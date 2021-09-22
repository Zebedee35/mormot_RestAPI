unit Base.RestClient;

{$WARN IMPLICIT_STRING_CAST OFF}
{$WARN IMPLICIT_STRING_CAST_LOSS OFF}

interface

uses
  System.SysUtils,
  WinApi.Windows,
  System.Generics.Collections,
  System.Classes,
  SynCommons,
  SynTable,
  SynCrypto,
  SynLog,
  mORMot,
  mORMotSQLite3,
  mORMotHTTPServer,
  mORMotService,
  mORMotHttpClient;  // TSQLHttpClientRequest

type
  TSQLRestRoutingREST_JWT = class(TSQLRestRoutingREST)
  protected
    procedure AuthenticationFailed(Reason: TNotifyAuthenticationFailedReason); override;
  end;

  TSQLHttpClientJWT = class(TSQLHttpClientRequest)
  private
    fJWT: RawUTF8;
  protected
    procedure InternalSetClass; override;
    function InternalRequest(const url, method: RawUTF8; var Header, Data, DataType: RawUTF8): Int64Rec; override;
  public
    function SetUser(const aUserName, aPassword: RawUTF8; aHashedPassword: Boolean = false): Boolean; virtual;

    property jwt: RawUTF8 read fJWT write fJWT;
  end;

  TSQLRestServerAuthenticationJWT = class(TSQLRestServerAuthenticationHttpBasic)
  protected
    procedure SessionCreate(Ctxt: TSQLRestServerURIContext; var User: TSQLAuthUser); override;
    procedure AuthenticationFailed(Ctxt: TSQLRestServerURIContext; Reason: TNotifyAuthenticationFailedReason);

    class function ClientGetSessionKey(Sender: TSQLRestClientURI; User: TSQLAuthUser; const aNameValueParameters: array of const): RawUTF8; override;
  public
    constructor Create(aServer: TSQLRestServer); override;

    function Auth(Ctxt: TSQLRestServerURIContext): Boolean; override;

    function CheckPassword(Ctxt: TSQLRestServerURIContext; User: TSQLAuthUser; const aPassWord: RawUTF8): boolean; override;
    function RetrieveSession(Ctxt: TSQLRestServerURIContext): mORMot.TAuthSession; override;

    class function ClientSetUser(Sender: TSQLRestClientURI; const aUserName, aPassword: RawUTF8;
      aPasswordKind: TSQLRestServerAuthenticationClientSetUserPassword = passClear;
      const aHashSalt: RawUTF8=''; aHashRound: Integer = 20000): Boolean; override;
  end;


const
  HttpServerKeepAliveTimeout  = 3000;
  JWTDefaultTimeout: Integer = 10;
  JWTMaxTimeout: Integer = 2600000;
  JWTDefaultRefreshTimeOut : Cardinal = (SecsPerDay div 3 + UnixDateDelta);

  API_ROOT = 'a';
  DEFAULT_ROOT = 'r';

var
  JWTTimeout: Integer;

implementation

uses Base.RestServer, SynCrtSock;

{ TSQLRestRoutingREST_JWT }

procedure TSQLRestRoutingREST_JWT.AuthenticationFailed(Reason: TNotifyAuthenticationFailedReason);
begin
  inherited;
  inherited AuthenticationFailed(Reason);
end;

{ TSQLRestServerAuthenticationJWT }

function TSQLRestServerAuthenticationJWT.Auth(Ctxt: TSQLRestServerURIContext): Boolean;
var aUserName, aPassWord, aKeepAlive : RawUTF8;
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
  aKeepAlive := Ctxt.InputUTF8OrVoid['KeepAlive'];

  if not SameTextU(aKeepAlive, 'YES') then
    JWTTimeout := JWTDefaultTimeout
  else
    JWTTimeout := JWTMaxTimeout;

  if (aUserName<>'') and (length(aPassWord)>0) then begin
    User := GetUser(Ctxt,aUserName);
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

procedure TSQLRestServerAuthenticationJWT.AuthenticationFailed(Ctxt: TSQLRestServerURIContext; Reason: TNotifyAuthenticationFailedReason);
begin
  if Ctxt is TSQLRestRoutingREST_JWT then
    TSQLRestRoutingREST_JWT(Ctxt).AuthenticationFailed(Reason);
end;

function TSQLRestServerAuthenticationJWT.CheckPassword(Ctxt: TSQLRestServerURIContext; User: TSQLAuthUser;
  const aPassWord: RawUTF8): boolean;
begin
  Result := (User.PasswordHashHexa = TAuthUser.ComputePasswordHexa(aPassWord));
end;

class function TSQLRestServerAuthenticationJWT.ClientGetSessionKey(Sender: TSQLRestClientURI; User: TSQLAuthUser;
  const aNameValueParameters: array of const): RawUTF8;
var resp: RawUTF8;
  a: integer;
  algo: TSQLRestServerAuthenticationSignedURIAlgo absolute a;
begin
  Result := '';

  if (Sender.CallBackGet('Auth',aNameValueParameters, resp) = HTTP_SUCCESS) then
    Result := resp;
end;

class function TSQLRestServerAuthenticationJWT.ClientSetUser(Sender: TSQLRestClientURI; const aUserName, aPassword: RawUTF8;
  aPasswordKind: TSQLRestServerAuthenticationClientSetUserPassword; const aHashSalt: RawUTF8; aHashRound: Integer): Boolean;
var res: RawUTF8;
  U: TSQLAuthUser;
  vTmp : Variant;
begin
  Result := False;

  if (aUserName = '') or (Sender = nil) then
    Exit;

  if not Sender.InheritsFrom(TSQLHttpClientJWT) then
    Exit;

  Sender.SessionClose; // to make Sender.SessionUser = nil

  try
    ClientSetUserHttpOnly(Sender, aUserName, aPassword);
    TSQLHttpClientJWT(Sender).jwt := '';

    U := TSQLAuthUser(Sender.Model.GetTableInherited(TSQLAuthUser).Create);
    try
      U.LogonName := trim(aUserName);

      res := ClientGetSessionKey(Sender, U, ['Username', aUserName, 'password', aPassword, 'passwordKind', Ord(aPasswordKind)]);

      if res<>'' then begin
        vTmp := _JsonFast(res);
        if DocVariantType.IsOfType(vTmp) then begin
          Result := TSQLHttpClientJWT(Sender).SessionCreate(self,U,TDocvariantData(vTmp).U['result']);
          if Result then TSQLHttpClientJWT(Sender).jwt := TDocvariantData(vTmp).U['jwt'];
        end;
      end;
    finally
      U.Free;
    end;
  finally
    if not Result then begin
      TSQLHttpClientJWT(Sender).jwt := '';
    end;

    if Assigned(Sender.OnSetUser) then
      Sender.OnSetUser(Sender); // always notify of user change, even if failed
  end;
end;

constructor TSQLRestServerAuthenticationJWT.Create(aServer: TSQLRestServer);
begin
  inherited Create(aServer);
end;

function TSQLRestServerAuthenticationJWT.RetrieveSession(Ctxt: TSQLRestServerURIContext): mORMot.TAuthSession;
var aUserName: RawUTF8;
  User: TSQLAuthUser;
  i: Integer;
  vSessionPrivateSalt: RawUTF8;
begin
  Result := inherited RetrieveSession(Ctxt);

  if Result <> nil then
    Exit;

  if not Assigned(fServer.JWTForUnauthenticatedRequest) then
    Exit;

  vSessionPrivateSalt := '';

  if Ctxt.AuthenticationBearerToken <> '' then begin
    if Ctxt.AuthenticationCheck(fServer.JWTForUnauthenticatedRequest) then begin
      aUserName := Ctxt.JWTContent.reg[jrcIssuer];

      User := GetUser(Ctxt,aUserName);
      try
        if User <> nil then begin
          if Ctxt.Server.Sessions <> nil then begin
            if Ctxt.JWTContent.data.GetValueIndex('sessionkey') >= 0 then
              vSessionPrivateSalt := Ctxt.JWTContent.data.U['sessionkey'];

            Ctxt.Server.Sessions.Safe.Lock;
            try
              // Search session for User
              if (reOneSessionPerUser in Ctxt.Call^.RestAccessRights^.AllowRemoteExecute) and (Ctxt.Server.Sessions<>nil) then
                for i := 0 to Pred(Ctxt.Server.Sessions.Count) do
                  if TAuthSession(Ctxt.Server.Sessions[i]).User.ID = User.ID then begin
                    Result := TAuthSession(Ctxt.Server.Sessions[i]);

                    Ctxt.Session := Result.IDCardinal;

                    Break;
                  end;

              // Search session by privatesalt
              if Result = nil then
                for i := 0 to Pred(Ctxt.Server.Sessions.Count) do
                  if SameTextU(vSessionPrivateSalt, TAuthSession(Ctxt.Server.Sessions[i]).ID + '+' + TAuthSession(Ctxt.Server.Sessions[i]).PrivateKey) then begin
                    Result := TAuthSession(Ctxt.Server.Sessions[i]);

                    Ctxt.Session := Result.IDCardinal;

                    Break;
                  end;

            finally
              Ctxt.Server.Sessions.Safe.UnLock;
            end;
           end;
        end;
      finally
        User.free;
      end;
    end;
  end;
end;

procedure TSQLRestServerAuthenticationJWT.SessionCreate(Ctxt: TSQLRestServerURIContext; var User: TSQLAuthUser);
var Token : RawUTF8;
  jWtClass : TJWTSynSignerAbstractClass;
  vPass, vUser, Signat, vSessionKey : RawUTF8;
  vTmp : TDocVariantData;
begin
  vUser := User.LogonName;
  vPass := User.PasswordHashHexa;

  inherited SessionCreate(Ctxt, User);

  if Ctxt.Call^.OutStatus = HTTP_SUCCESS then begin
    vTmp.InitJSON(Ctxt.Call^.OutBody);

    if vTmp.Kind <> dvUndefined then
      if fServer.JWTForUnauthenticatedRequest <> nil then begin
        jwtClass := JWT_CLASS[NGetAlgo(fServer.JWTForUnauthenticatedRequest.Algorithm)];
        vSessionKey := vTmp.U['result'];
        Token := (fServer.JWTForUnauthenticatedRequest as jwtClass).Compute([ 'sessionkey', vSessionKey],
                                                                           vUser,
                                                                           'jwt.access',
                                                                           '', 0, JWTTimeout, @Signat);

        Ctxt.Call^.OutBody := _Obj(['result', vTmp.U['result'], 'jwt', Token]);
      end;
  end;
end;

{ TSQLHttpClientJWT }

function TSQLHttpClientJWT.InternalRequest(const url, method: RawUTF8; var Header, Data, DataType: RawUTF8): Int64Rec;
var vBasic : RawUTF8;
    h : Integer;
begin
  if fjwt <> '' then begin // Change Header if jwt exist
    vBasic := NHeaderOnce(Header, 'AUTHORIZATION: BASIC ');
    if vBasic <> '' then begin
      h := PosEx(vBasic, Header);
      if h = 22 then
        header := copy(Header, h + Length(vBasic), Length(header))
      else header := copy(Header, 1, h - 21) + copy(Header, h + Length(vBasic), Length(header));
      header := Trim(header);
    end;
    Header := trim(HEADER_BEARER_UPPER + fJWT + #13#10 + Header);
  end;
  result := inherited InternalRequest(url, method, Header, Data, DataType);
end;

procedure TSQLHttpClientJWT.InternalSetClass;
begin
  fRequestClass := TWinHTTP;

  inherited;
end;

function TSQLHttpClientJWT.SetUser(const aUserName, aPassword: RawUTF8; aHashedPassword: Boolean): Boolean;
const HASH: array[boolean] of TSQLRestServerAuthenticationClientSetUserPassword = (passClear, passHashed);
begin
  if self=nil then begin
    Result := false;
    Exit;
  end;

  Result := TSQLRestServerAuthenticationJWT.ClientSetUser(self,aUserName,aPassword,HASH[aHashedPassword]);
end;

end.
