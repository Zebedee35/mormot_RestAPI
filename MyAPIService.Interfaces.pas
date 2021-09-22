unit MyAPIService.Interfaces;

interface

uses
  Classes, SysUtils, SynCommons, mORMot,

  Base.SQLConnectionProp;

type
  IMyPublicApi = interface(IInvokable)
  ['{17ED3792-B6B8-4B69-AE45-3EBF7A6F08C9}']
    function Hello(Name: RawUTF8): RawUTF8;
  end;

  IMyPrivateApi = interface(IInvokable)
  ['{C0F0330F-9AA5-4BE6-B1E9-5E94DF3D7E43}']
    function allUsers: RawJSON;
    function retrieve_User(RecID: Integer): RawJSON;
  end;

  TMyPublicApi = class(TInjectableObjectRest, IMyPublicApi)
  public
    function Hello(Name: RawUTF8): RawUTF8;
  end;

  TMyPrivateApi = class(TInterfacedObject, IMyPrivateApi)
  private
    fConnection: TSQLDatabaseConnection;
    function GetServerConnection: TSQLDatabaseConnection;

    property Connection: TSQLDatabaseConnection read GetServerConnection;
  public
    function allUsers: RawJSON;
    function retrieve_User(RecID: Integer): RawJSON;
  end;

implementation

uses Constants;

{ TMyPublicApi }

function TMyPublicApi.Hello(Name: RawUTF8): RawUTF8;
var Greeting: RawUTF8;
begin
  Greeting := 'Hello!';
  if Name <> '' then
    Greeting := Format('Hello, %s!', [Name]);
  Result := Greeting;
end;

{ TMyPrivateApi }

function TMyPrivateApi.allUsers: RawJSON;
var fDB: TSQLDBConnectionProp;
begin
  fDB := TSQLDBConnectionProp.CreateMSSQLConnection(Connection);
  try
    fDB.Connect;
    Result :=
      fDB.ExecuteJSON(cSQL_ALLUSER);
  finally
    fDB.Disconnect;
    FreeAndNil(fDB);
  end;
end;

function TMyPrivateApi.GetServerConnection: TSQLDatabaseConnection;
begin
  if not Assigned(fConnection) then
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
  end;

  Result := fConnection;
end;

function TMyPrivateApi.retrieve_User(RecID: Integer): RawJSON;
var Greeting: RawJSON;
    fDB: TSQLDBConnectionProp;
begin
  Greeting := '';
  fDB := TSQLDBConnectionProp.CreateMSSQLConnection(Connection);
  try
    fDB.Connect;
    Greeting :=
      fDB.ExecuteJSON(Format(cSQL_RETRIEVEUSER, [RecID]));
  finally
    fDB.Disconnect;
    FreeAndNil(fDB);
  end;

  Result := Greeting;
end;

initialization
  TInterfaceFactory.RegisterInterfaces([TypeInfo(IMyPublicApi)]);
  TInterfaceFactory.RegisterInterfaces([TypeInfo(IMyPrivateApi)]);

end.
