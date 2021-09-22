unit MyAPIService;

{$WARN IMPLICIT_STRING_CAST OFF}
{$WARN IMPLICIT_STRING_CAST_LOSS OFF}

interface

uses
  System.SysUtils,
  WinApi.Windows,
  SynCommons,
  SynTable,
  SynCrypto,
  SynLog,
  mORMot,
  mORMotDB,
  mORMotHTTPServer,
  mORMotService,

  Base.Service,
  Base.RestServer,
  Base.RestClient;


type
  TMyApiService = class(TBaseWinHttpJWTRestService)
  private
    procedure ReadConfiguration;
    procedure RegisterMethods;
    function OnRestServerAuthentication(Sender: TSQLRestServerAuthentication; Ctxt: TSQLRestServerURIContext; aUserID: TID; const aUserName: RawUTF8): TSQLAuthUser;
    procedure InitAuthentication;
    procedure CreateSQLConnection;
  public
    constructor Create; reintroduce;

    procedure DoStart(Sender: TService); override;
    procedure DoStop(Sender: TService); override;
  end;

  TMyApiRestServer = class(TBaseJWTRestServer)
  private
    function AllowedByPassAuthentication(var Call: TSQLRestURIParams): Boolean;
    procedure GetApiKeyOrEmpty(var Call: TSQLRestURIParams; out ApiKey: RawUTF8);
  protected
  public
    constructor Create(aAuthUserClass: TSQLAuthUserClass; aModel: TSQLModel; aHandleUserAuthentication: boolean=false; aDBFileName: TFileName=''); override;

    procedure URI(var Call: TSQLRestURIParams); override;
  published

  end;

  TMyApiAuthenticationJWT = class(TSQLRestServerAuthenticationJWT)
  public
    function Auth(Ctxt: TSQLRestServerURIContext): Boolean; override;
    function CheckPassword(Ctxt: TSQLRestServerURIContext; User: TSQLAuthUser; const aPassWord: RawUTF8): boolean; override;
  end;


const
  SERVICE_NAME        = 'MyApiService';
  SERVICE_DISPLAYNAME = 'My Api Service';
  SERVICE_DESCRIPTION = 'My Restful API Server running as service';

implementation

uses Base.SQLConnectionProp, MyAPIService.Interfaces, Constants, mORMotSQLite3;

{ TMyApiService }

constructor TMyApiService.Create;
begin
  inherited Create(SERVICE_NAME, SERVICE_DISPLAYNAME);
end;

procedure TMyApiService.CreateSQLConnection;
var fConnection : TSQLDatabaseConnection;
begin
  fConnection := TSQLDatabaseConnection.Create;
  with fConnection do
  begin
    Server    := cSERVER;
    UserName  := cUSERNAME;
    Password  := cPASSWORD;
    IsWinAuth := False;
    PortNo    := cPORTNO;
    Database  := cDATABASE;
  end;
  SQLClient := TSQLDBConnectionProp.CreateMSSQLConnection(fConnection);
  SQLClient.Connect;
end;

procedure TMyApiService.DoStart(Sender: TService);
var  Model: TSQLModel;
begin
  inherited;
  ReadConfiguration;
  CreateSQLConnection;

  Model := TSQLModel.Create([TAuthGroup, TAuthUser], API_ROOT);
  VirtualTableExternalRegisterAll(Model, SQLClient);

  RestServer := TMyApiRestServer.Create(TAuthUser, Model, True);
  RestServer.CreateMissingTables; // we need AuthGroup and AuthUser tables
  InitAuthentication;
  RestServer.OnAuthenticationUserRetrieve := OnRestServerAuthentication;
  RestServer.RegisterJWTAuthentication(TMyApiAuthenticationJWT);
  RegisterMethods;

  HttpServer := TSQLHttpServer.Create('8080', RestServer, '+', useHttpApiRegisteringURI, nil, 32, TSQLHttpServerSecurity.secSynShaAes);

//  THttpServer(HttpServer).ServerKeepAliveTimeOut := HttpServerKeepAliveTimeout;
  HTTPServer.AccessControlAllowCredential := true;
  HTTPServer.AccessControlAllowOrigin := '*';

  TSQLLog.Add.Log(sllInfo,'Server % started.',[HttpServer]);
end;

procedure TMyApiService.DoStop(Sender: TService);
begin
  inherited;

end;

function TMyApiService.OnRestServerAuthentication(Sender: TSQLRestServerAuthentication; Ctxt: TSQLRestServerURIContext; aUserID: TID; const aUserName: RawUTF8): TSQLAuthUser;
var vUser : TAuthUser;
   aID: TID;
begin
  vUser := TAuthUser.Create(RestServer, 'LogonName=?', [aUserName]);

  if vUser.ID > 0 then
  begin
    Result := vUser;
  end
  else
  begin
    vUser.LogonName := aUserName;
    aID := RestServer.Add(vUser, True);
    Result := vUser;
  end;
end;

procedure TMyApiService.ReadConfiguration;
begin
     //
end;

procedure TMyApiService.InitAuthentication;
var SQLAccessRights: TSQLAccessRights;
  fID: TID;
begin
  fID := RestServer.OneFieldValueInt64(TAuthGroup, 'ID', 'Ident = '+ QuotedStr('SUPERADMIN'));
  if fID <= 0 then begin
    RestServer.ClearGroups;

    SQLAccessRights.AllowRemoteExecute := [reSQL, reService];
    RestServer.AddGroup('Admin', SQLAccessRights);
    SQLAccessRights.AllowRemoteExecute := [reSQL, reService];
    RestServer.AddGroup('SUPERADMIN', SQLAccessRights);
    SQLAccessRights.AllowRemoteExecute := [reService];
    RestServer.AddGroup('User', SQLAccessRights);

    RestServer.ClearUsers;

    RestServer.AddUser('tayfun', 'tayfun test', 'MySuperPass', 'Admin', fID);
  end;
end;

procedure TMyApiService.RegisterMethods;
var fPublicApi: TBaseRestPublicApi;
   fPrivateApi: TBaseRestPrivateApi;
begin
  fPublicApi := TBaseRestPublicApi.Create(TMyPublicApi, IMyPublicApi);
  try

    RestServer.RegisterApi(fPublicApi, sicShared, SERVICE_CONTRACT_NONE_EXPECTED);
  finally
    fPublicApi.Free;
  end;

  fPrivateApi := TBaseRestPrivateApi.Create(TMyPrivateApi, IMyPrivateApi);
  try
    fPrivateApi.AddAuthorization('allUsers', 'Admin', '');
    fPrivateApi.AddAuthorization('retrieve_User', 'Admin', '');
    RestServer.RegisterApi(fPrivateApi, sicPerSession, SERVICE_CONTRACT_NONE_EXPECTED);
  finally
    fPrivateApi.Free;
  end;

end;

{ TMyApiRestServer }

constructor TMyApiRestServer.Create(aAuthUserClass: TSQLAuthUserClass; aModel: TSQLModel; aHandleUserAuthentication: boolean;
  aDBFileName: TFileName);
begin
  inherited Create(aAuthUserClass, aModel, aHandleUserAuthentication, aDBFileName);

  SessionClass := TAuthSession;
end;

function TMyApiRestServer.AllowedByPassAuthentication(var Call: TSQLRestURIParams): Boolean;
  function getMethodName(const uri: RawUTF8): RawUTF8;
  var lastslash, paramstart: Integer;
  begin
    paramstart := FindDelimiter('?', uri);
    if paramstart > 0 then
      Result := Copy(uri, 1, paramstart-1);

    lastslash := LastDelimiter('/', Result);
    Result := Copy(Result, lastslash+1, Length(Result));
  end;

var methodName: RawUTF8;
begin
  methodName := getMethodName(Call.Url);
  Result := (fPublishedMethods.FindHashed(methodName) >= 0);
end;

procedure TMyApiRestServer.GetApiKeyOrEmpty(var Call: TSQLRestURIParams; out ApiKey: RawUTF8);
var header: RawUTF8;
  up: array[byte] of AnsiChar;
begin
  ApiKey := '';

  header := Call.InHead;

  if Pos('apikey', UTF8ToString(header)) < 0 then exit;

  PWord(UpperCopy255(up,'apikey'))^ := ord(':');
  FindNameValue(header,up,ApiKey);
end;

procedure TMyApiRestServer.URI(var Call: TSQLRestURIParams);
var Ctxt: TSQLRestServerURIContext;
  vApiKey: RawUTF8;
begin
  Call.OutStatus := HTTP_SUCCESS;
  GetApiKeyOrEmpty(Call, vApiKey);

  if not AllowedByPassAuthentication(Call) then begin
    Ctxt := ServicesRouting.Create(self,Call);

//   APIKEY has been canceled. (for temporarily)
//    try
//      if (vApiKey = '') then
//      begin
//        Call.OutStatus := HTTP_NOTFOUND;
//        Ctxt.Error('ApiKey unknown',Call.OutStatus);
//      end
//    except
//      on e: exception do begin
//        Call.OutStatus := HTTP_BADREQUEST;
//        Ctxt.Error(StringToUTF8(e.Message),Call.OutStatus);
//      end;
//    end;
  end;

  if Call.OutStatus = HTTP_SUCCESS then
    inherited URI(Call);
end;

{ TMyApiAuthenticationJWT }

function TMyApiAuthenticationJWT.Auth(Ctxt: TSQLRestServerURIContext): Boolean;
var aUserName, aPassWord : RawUTF8;
  User: TSQLAuthUser;
begin
  Result := False;

  if AuthSessionRelease(Ctxt) then
    Exit;

  if not Assigned(fServer.JWTForUnauthenticatedRequest) then begin
    AuthenticationFailed(Ctxt, afJWTRequired);
    Exit;
  end;

  aUserName := Ctxt.InputUTF8OrVoid['UserName'];
  aPassWord := Ctxt.InputUTF8OrVoid['Password'];

  JWTTimeout := JWTMaxTimeout;

  if (aUserName <> '') and (length(aPassWord) > 0) then
  begin
    User := GetUser(Ctxt, aUserName);
    try
      Result := (User <> nil);
      if Result then begin
        if CheckPassword(Ctxt, User, aPassWord) then
          SessionCreate(Ctxt, User)
        else
          AuthenticationFailed(Ctxt, afInvalidPassword);
      end else
        AuthenticationFailed(Ctxt, afUnknownUser);
    finally
      if Result then User.Free;
    end;
  end else
    AuthenticationFailed(Ctxt, afUnknownUser);
end;

function TMyApiAuthenticationJWT.CheckPassword(Ctxt: TSQLRestServerURIContext; User: TSQLAuthUser; const aPassWord: RawUTF8): boolean;
begin
  Result := TAuthUser(User).CheckPlainPassword(aPassWord);
end;

end.
