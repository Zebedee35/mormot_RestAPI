unit Base.RestServer;

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
  mORMotService;

const
  HttpAuthenticationSalt = 'wRM6DTnrqXGkHBZabbs85hyWHnwmUG8m';
  HttpClientUserSalt = 'WNL5U36NtuqjRqVuq75QgZ87yjamU8km';

  SECRET_KEY = 'jsKkSFTxVtTegCUqmw4SRM7mQ6g86b3DQbVgpZPaYPc3a2xzEvqHxyY8DbcMRqsY';

type
  TBaseRestApiAuthorizationSetting = record
    MethodName: RawUTF8;
    AllowedGroups: array of RawUTF8;
    DeniedGroups: array of RawUTF8;
  end;

  TBaseRestPublicApi = class
  private
    fImplementationClass: TInterfacedClass;
    fInterfaceClass: TGUID;
  public
    constructor Create(aImplementationClass: TInterfacedClass; aInterfaceClass: TGUID); virtual;

    function ServiceName : RawUTF8;

    property ImplementationClass: TInterfacedClass read fImplementationClass;
    property InterfaceClass: TGUID read fInterfaceClass;
  end;

  TBaseRestPrivateApi = class(TBaseRestPublicApi)
  private
    fAuthorizations: TList<TBaseRestApiAuthorizationSetting>;
  public
    constructor Create(aImplementationClass: TInterfacedClass; aInterfaceClass: TGUID); override;
    destructor Destroy(); override;

    procedure AddAuthorization(MethodName, AllowedGroups, DeniedGroups : RawUTF8);
    property Authorizations: TList<TBaseRestApiAuthorizationSetting> read fAuthorizations;
  end;


  TAuthGroup = class(mORMot.TSQLAuthGroup);

  TAuthUser = class(mORMot.TSQLAuthUser)
  public
    class function ComputePasswordHexa(const PlainPassword: RawUTF8): RawUTF8;

    function CheckPlainPassword(const PlainPassword: RawUTF8): boolean; virtual;
    procedure SetPlainPassword(const PlainPassword: RawUTF8); virtual;
  end;


  TBaseRestServer = class(TSQLRestServerDB)
  private
    fAuthUserClass: TSQLAuthUserClass;
  public
    constructor Create(aAuthUserClass: TSQLAuthUserClass; aModel: TSQLModel; aHandleUserAuthentication: Boolean= False; aDBFileName: TFileName=''); reintroduce; virtual;

    procedure ClearGroups;
    procedure ClearUsers;

    procedure AddGroup(const Ident: RawUTF8; const SQLAccessRights: TSQLAccessRights; const SessionTimeOut: Integer = 60); virtual;
    procedure AddUser(const LogonName, DisplayName, PlainPassword, GroupIdent: RawUTF8; out ID: TID); virtual;

    procedure RemoveGroup(const Ident: RawUTF8);
    procedure RemoveUser(const LogonName: RawUTF8);

    procedure RegisterApi(PrivateApi: TBaseRestPrivateApi; const aInstanceCreation: TServiceInstanceImplementation;
                              const aContractExpected: RawUTF8 = ''; const ResultAsJSONWithoutResult: Boolean = True); overload;
    procedure RegisterApi(PublicApi : TBaseRestPublicApi; const aInstanceCreation: TServiceInstanceImplementation;
                              const aContractExpected: RawUTF8 = ''; const ResultAsJSONWithoutResult: Boolean = True); overload;
  end;

  TBaseJWTRestServer = class(TBaseRestServer)
  protected
    function GetSessionIndex: Integer;
  published
    function IsValidToken(aParams: TSQLRestServerURIContext): Integer;
    function RefreshToken(aParams: TSQLRestServerURIContext): Integer;
  public
    constructor Create(aAuthUserClass: TSQLAuthUserClass; aModel: TSQLModel; aHandleUserAuthentication: Boolean= False; aDBFileName: TFileName=''); override;

    procedure RegisterJWTAuthentication(aMethod: TSQLRestServerAuthenticationClass);
  end;

function NSplitStr(const Input: string; const LineBreak: string): TStringList;
function NGetAlgo(const Value: RawUTF8): TSignAlgo;
function NHeaderOnce(const Head: RawUTF8; upper: PAnsiChar): RawUTF8; {$ifdef HASINLINE}inline;{$endif}

implementation

uses Base.RestClient;

function NSplitStr(const Input: string; const LineBreak: string) : TStringList;
var
  P, Start, LB: PChar;
  S: string;
  LineBreakLen: Integer;
begin
  Result := TStringList.Create;
  Result.Duplicates := dupIgnore;

  Result.BeginUpdate;
  try
    Result.Clear;
    LineBreakLen := Length(LineBreak);
    P := PChar(Input);
    while P^ <> #0 do
    begin
      Start := P;
      LB := AnsiStrPos(P, PChar(LineBreak));
      while (P^ <> #0) and (P <> LB) do Inc(P);
      SetString(S, Start, P - Start);
      Result.Add(S);
      if P = LB then
        Inc(P, LineBreakLen);
    end;
  finally
    Result.EndUpdate;
  end;
end;

function NGetAlgo(const Value: RawUTF8): TSignAlgo;
var i : TSignAlgo;
begin
  Result := saSha256;

  for i := low(JWT_TEXT) to High(JWT_TEXT) do
    if SameTextU(Value, JWT_TEXT[i]) then begin
      Result := i;
      Break;
    end;
end;

function NHeaderOnce(const Head: RawUTF8; upper: PAnsiChar): RawUTF8; {$ifdef HASINLINE}inline;{$endif}
begin
  if (Head <> '') then
    Result := FindIniNameValue(pointer(Head),upper)
  else
    Result := '';
end;

{ TBaseRestPublicApi }

constructor TBaseRestPublicApi.Create(aImplementationClass: TInterfacedClass; aInterfaceClass: TGUID);
begin
  inherited Create;

  fImplementationClass := aImplementationClass;
  fInterfaceClass := aInterfaceClass;
end;

function TBaseRestPublicApi.ServiceName: RawUTF8;
begin
  Result := Copy(fImplementationClass.ClassName, 2, Length(fImplementationClass.ClassName));
end;

{ TBaseRestPrivateApi }

constructor TBaseRestPrivateApi.Create(aImplementationClass: TInterfacedClass; aInterfaceClass: TGUID);
begin
  inherited Create(aImplementationClass, aInterfaceClass);

  fAuthorizations := TList<TBaseRestApiAuthorizationSetting>.Create();
end;

destructor TBaseRestPrivateApi.Destroy;
begin
  fAuthorizations.Free;

  inherited;
end;

procedure TBaseRestPrivateApi.AddAuthorization(MethodName, AllowedGroups, DeniedGroups: RawUTF8);
var I : Integer;
  SL : TStringList;
  ApiAuthorizationSettings: TBaseRestApiAuthorizationSetting;
begin
  ApiAuthorizationSettings.MethodName := MethodName;

  SetLength(ApiAuthorizationSettings.AllowedGroups, 0);
  SetLength(ApiAuthorizationSettings.DeniedGroups, 0);

  SL := NSplitStr(AllowedGroups, ';');
  try
    for I := 0 to SL.Count - 1 do begin
      SetLength(ApiAuthorizationSettings.AllowedGroups, Length(ApiAuthorizationSettings.AllowedGroups) + 1);
      ApiAuthorizationSettings.AllowedGroups[Length(ApiAuthorizationSettings.AllowedGroups) - 1] := StringToUTF8(SL[I]);
    end;
  finally
    SL.Free;
  end;

  SL := NSplitStr(DeniedGroups, ';');
  try
    for I := 0 to SL.Count - 1 do begin
      SetLength(ApiAuthorizationSettings.DeniedGroups, Length(ApiAuthorizationSettings.DeniedGroups) + 1);
      ApiAuthorizationSettings.DeniedGroups[Length(ApiAuthorizationSettings.DeniedGroups) - 1] := StringToUTF8(SL[I]);
    end;
  finally
    SL.Free;
  end;

  fAuthorizations.Add(ApiAuthorizationSettings);
end;

{ TBaseRestServer }

procedure TBaseRestServer.AddGroup(const Ident: RawUTF8; const SQLAccessRights: TSQLAccessRights; const SessionTimeOut: Integer);
var fGroup: TAuthGroup;
begin
  fGroup := TAuthGroup.Create(Self, 'Ident = ?', [Ident]);
  try
    fGroup.Ident := Ident;
    fGroup.SQLAccessRights := SQLAccessRights;
    fGroup.SessionTimeout := SessionTimeOut;

    if fGroup.ID = 0 then
      Add(fGroup, True);
  finally
    fGroup.Free;
  end;
end;

procedure TBaseRestServer.AddUser(const LogonName, DisplayName, PlainPassword, GroupIdent: RawUTF8; out ID: TID);
var fUser: TSQLAuthUser;
  fGroupID: TID;
begin
  ID := 0;

  fUser := fAuthUserClass.Create(Self, 'LogonName = ?', [LogonName]);
  try
    fUser.LogonName := LogonName;
    fUser.DisplayName := AnsiUpperCase(DisplayName);
    fUser.PasswordHashHexa := TAuthUser.ComputePasswordHexa(PlainPassword);

    if GroupIdent <> '' then
      begin
        fGroupID := MainFieldID(TAuthGroup, GroupIdent);
        fUser.GroupRights := pointer(fGroupID);
      end;

    if fUser.ID = 0 then
      ID := Add(fUser, True);
  finally
    fUser.Free;
  end;
end;

procedure TBaseRestServer.ClearGroups;
begin
  Delete(TAuthGroup, '');
end;

procedure TBaseRestServer.ClearUsers;
begin
  Delete(fAuthUserClass, '');
end;

constructor TBaseRestServer.Create(aAuthUserClass: TSQLAuthUserClass; aModel: TSQLModel; aHandleUserAuthentication: Boolean; aDBFileName: TFileName);
begin
  if aDBFileName <> ''
    then inherited Create(aModel, aDBFileName, aHandleUserAuthentication)
    else inherited Create(aModel, aHandleUserAuthentication);
  fAuthUserClass := aAuthUserClass;
end;

procedure TBaseRestServer.RegisterApi(PrivateApi: TBaseRestPrivateApi; const aInstanceCreation: TServiceInstanceImplementation;
  const aContractExpected: RawUTF8; const ResultAsJSONWithoutResult: Boolean);
var i, j : Integer;
  SFS: TServiceFactoryServer;
  AAS: TBaseRestApiAuthorizationSetting;
begin
  SFS := ServiceDefine(PrivateApi.ImplementationClass, PrivateApi.InterfaceClass, aInstanceCreation, aContractExpected);
  SFS.ResultAsJSONObjectWithoutResult := ResultAsJSONWithoutResult;

  for i := 0 to PrivateApi.Authorizations.Count - 1 do
    begin
      AAS := PrivateApi.Authorizations.Items[i];

      for j := 0 to Length(AAS.AllowedGroups) - 1 do
        SFS.AllowByName([AAS.MethodName], AAS.AllowedGroups[j]);

      for j := 0 to Length(AAS.DeniedGroups) - 1 do
        SFS.DenyByName([AAS.MethodName], AAS.DeniedGroups[j]);
    end;

  SFS.SetOptions([], [optErrorOnMissingParam]);
end;

procedure TBaseRestServer.RegisterApi(PublicApi: TBaseRestPublicApi; const aInstanceCreation: TServiceInstanceImplementation;
  const aContractExpected: RawUTF8; const ResultAsJSONWithoutResult: Boolean);
var SFS: TServiceFactoryServer;
begin
  SFS := ServiceDefine(PublicApi.ImplementationClass, PublicApi.InterfaceClass, aInstanceCreation, aContractExpected);
  SFS.ResultAsJSONObjectWithoutResult := ResultAsJSONWithoutResult;
  SFS.ByPassAuthentication := True;
  SFS.SetOptions([], [optErrorOnMissingParam]);
end;

procedure TBaseRestServer.RemoveGroup(const Ident: RawUTF8);
begin
  Delete(TAuthGroup, 'Ident = ?', [Ident]);
end;

procedure TBaseRestServer.RemoveUser(const LogonName: RawUTF8);
begin
  Delete(fAuthUserClass, 'LogonName = ?', [LogonName]);
end;

{ TAuthUser }

function TAuthUser.CheckPlainPassword(const PlainPassword: RawUTF8): boolean;
begin
  Result := PasswordHashHexa = TAuthUser.ComputePasswordHexa(PlainPassword);
end;

class function TAuthUser.ComputePasswordHexa(const PlainPassword: RawUTF8): RawUTF8;
begin
  Result := SHA256( HttpAuthenticationSalt + PlainPassword);
end;

procedure TAuthUser.SetPlainPassword(const PlainPassword: RawUTF8);
begin
  PasswordHashHexa := TAuthUser.ComputePasswordHexa(PlainPassword);
end;

{ TBaseJWTRestServer }

constructor TBaseJWTRestServer.Create(aAuthUserClass: TSQLAuthUserClass; aModel: TSQLModel; aHandleUserAuthentication: Boolean;
  aDBFileName: TFileName);
begin
  inherited Create(aAuthUserClass, aModel, aHandleUserAuthentication, aDBFileName);

  NoAJAXJSON := False;
  Options := Options + [rsoCookieIncludeRootPath];
end;

function TBaseJWTRestServer.GetSessionIndex: Integer;
var jWtClass : TJWTSynSignerAbstractClass;
  TokenSesID : Cardinal;
  i : Integer;
begin
  Result := -1;

  try
    if not Assigned(JWTForUnauthenticatedRequest) then
      Exit;

    jwtClass := JWT_CLASS[NGetAlgo(JWTForUnauthenticatedRequest.Algorithm)];
    if not CurrentServiceContext.Request.AuthenticationCheck((JWTForUnauthenticatedRequest as jwtClass))
    then exit
    else
      if Sessions <> nil then
      begin
        TokenSesID := GetCardinal(Pointer(CurrentServiceContext.Request.JWTContent.data.U['sessionkey']));
        if TokenSesID > 0 then
          for i := 0 to pred(Sessions.Count) do
            if (TAuthSession(Sessions[i]).IDCardinal = TokenSesID) then begin
              Result := i;
              Break;
            end;
      end;
  except
  end;
end;

function TBaseJWTRestServer.IsValidToken(aParams: TSQLRestServerURIContext): Integer;
var vResult: TDocVariantData;
  nowunix: TUnixTime;
  unix: Cardinal;
  vExpired: TDateTime;
  TokenSesID: Cardinal;
  SessionExist: Boolean;
  i: Integer;
begin
  Result := HTTP_UNAVAILABLE;

  TokenSesID := aParams.InputIntOrVoid['sessionkey'];
  if TokenSesID=0 then begin
    aParams.Returns('Session unknown', HTTP_FORBIDDEN);
    Exit;
  end;

  try
    SessionExist := False;

    if Sessions <> nil then begin
      TokenSesID := aParams.InputIntOrVoid['sessionkey'];
      if TokenSesID > 0 then
        for i := 0 to pred(Sessions.Count) do begin
          if (TAuthSession(Sessions[i]).IDCardinal = TokenSesID) then begin
            SessionExist := True;
            Break;
          end;
        end;
    end;

    if SessionExist then begin
      vResult.InitFast;
      if jrcExpirationTime in CurrentServiceContext.Request.JWTContent.claims then
         if ToCardinal(CurrentServiceContext.Request.JWTContent.reg[jrcExpirationTime],unix) then begin
           nowunix := UnixTimeUTC;
           vExpired := UnixTimeToDateTime(unix - nowunix);
           vResult.AddValue('ExpiredIn', FormatDateTime('hh:nn:ss', vExpired));
         end
         else vResult.AddValue('ExpiredIn','');
      aParams.Returns(Variant(vResult), HTTP_SUCCESS);
    end
    else aParams.Returns('Session unknown', HTTP_FORBIDDEN);
  except
    on e: exception do
     aParams.Returns(StringToUTF8(e.Message), HTTP_NOTFOUND);
  end;
end;

function TBaseJWTRestServer.RefreshToken(aParams: TSQLRestServerURIContext): Integer;
var Token, vUserName, vPassword, signat : RawUTF8;
  vResult : TDocVariantData;
  jWtClass : TJWTSynSignerAbstractClass;
  User : TSQLAuthUser;
  i : Integer;
  TokenSesID : Cardinal;
  SessionExist : Boolean;
  NewSession : mORMot.TAuthSession;
  nowunix : TUnixTime;
  unix : Cardinal;
begin
  Result := HTTP_UNAVAILABLE;

  try
    if not Assigned(JWTForUnauthenticatedRequest) then begin
      aParams.Returns('TSQLRestServerAuthenticationJWT not initialized', HTTP_NOTFOUND);
      Exit;
    end;

    if UrlDecodeNeedParameters(aParams.Parameters, 'USERNAME,PASSWORD') then begin
      while aParams.Parameters<>nil do begin
        UrlDecodeValue(aParams.Parameters,'USERNAME=',    vUserName,   @aParams.Parameters);
        UrlDecodeValue(aParams.Parameters,'PASSWORD=',    vPassword,   @aParams.Parameters);
      end;

      vResult.InitFast;

      jwtClass := JWT_CLASS[NGetAlgo(JWTForUnauthenticatedRequest.Algorithm)];
      Token := CurrentServiceContext.Request.AuthenticationBearerToken;

      CurrentServiceContext.Request.AuthenticationCheck((JWTForUnauthenticatedRequest as jwtClass));

      if CurrentServiceContext.Request.JWTContent.result in [jwtValid, jwtExpired] then begin
        User := fAuthUserClass.Create(Self, 'LogonName=?', [vUserName]);
        if Assigned(User) then
          try
            if User.ID <= 0 then
              aParams.Returns('Unknown user', HTTP_FORBIDDEN)
            else if SameTextU(User.PasswordHashHexa, TAuthUser.ComputePasswordHexa(vPassword)) or SameTextU(User.PasswordHashHexa, vPassword) then begin
              SessionExist := False;
              if Sessions <> nil then begin
                TokenSesID := GetCardinal(Pointer(CurrentServiceContext.Request.JWTContent.data.U['sessionkey']));
                if TokenSesID > 0 then
                  for i := 0 to pred(Sessions.Count) do begin
                    if (TAuthSession(Sessions[i]).UserID = User.ID) and
                       (TAuthSession(Sessions[i]).IDCardinal = TokenSesID) then begin
                      SessionExist := True;
                      Break;
                    end;
                  end;
              end;

              if SessionExist and (CurrentServiceContext.Request.JWTContent.result = jwtValid) then begin // return current Token
                vResult.AddValue('jwt', Token);
                aParams.Returns(Variant(vResult), HTTP_SUCCESS);
              end else begin
                if (CurrentServiceContext.Request.JWTContent.result = jwtExpired) then
                  if jrcExpirationTime in CurrentServiceContext.Request.JWTContent.claims then
                    if ToCardinal(CurrentServiceContext.Request.JWTContent.reg[jrcExpirationTime],unix) then begin
                      nowunix := UnixTimeUTC;
                      if UnixTimeToDateTime(nowunix - unix) > JWTDefaultRefreshTimeOut then begin
                        aParams.Returns('jwt : expiration time to long', HTTP_FORBIDDEN);
                        Exit;
                      end;
                    end;

                jwtClass := JWT_CLASS[NGetAlgo(JWTForUnauthenticatedRequest.Algorithm)];
                if SessionExist then
                  Token := (JWTForUnauthenticatedRequest as jwtClass)
                               .Compute(['sessionkey', Variant(CurrentServiceContext.Request.JWTContent.data.U['sessionkey'])],
                                         vUserName,
                                         'jwt.access',
                                         '',0,JWTTimeout, @Signat)
                else begin
                  SessionCreate(TSQLAuthUser(User), CurrentServiceContext.Request, NewSession);

                  if NewSession <> nil then
                    Token := (JWTForUnauthenticatedRequest as jwtClass)
                                 .Compute(['sessionkey', NewSession.ID + '+' + NewSession.PrivateKey],
                                           vUserName,
                                           'jwt.access',
                                           '',0,JWTTimeout, @Signat)
                  else begin
                    aParams.Returns('Invalid sessionCreate result', HTTP_FORBIDDEN);
                    Exit;
                  end;
                end;

                vResult.AddValue('jwt', Token);
                aParams.Returns(Variant(vResult), HTTP_SUCCESS);
              end;
            end
            else
              aParams.Returns('Invalid password', HTTP_FORBIDDEN);
          finally
            User.Free;
          end
        else
          aParams.Returns('User incorrect', HTTP_FORBIDDEN);
      end else
        aParams.Returns(synCrypto.ToText(CurrentServiceContext.Request.JWTContent.result)^, HTTP_FORBIDDEN)
    end else begin
      aParams.Returns('Parameters incorrect', HTTP_NOTFOUND);
      Exit;
    end;
  except
    on e: exception do
     aParams.Returns(StringToUTF8(e.Message), HTTP_NOTFOUND);
  end;end;

procedure TBaseJWTRestServer.RegisterJWTAuthentication(aMethod: TSQLRestServerAuthenticationClass);
var vGUID : TGUID;
begin
  AuthenticationUnregisterAll;
  AuthenticationRegister(aMethod);

  ServicesRouting := TSQLRestRoutingREST_JWT;
  CreateGUID(vGUID);
  JWTForUnauthenticatedRequest := JWT_CLASS[saSha256].Create(SHA256(GUIDToRawUTF8(vGUID)), 0, [jrcIssuer, jrcSubject], [], JWTDefaultTimeout);

  Self.ServiceMethodByPassAuthentication('IsValidToken');
  Self.ServiceMethodByPassAuthentication('RefreshToken');
end;

end.
