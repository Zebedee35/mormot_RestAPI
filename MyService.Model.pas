unit MyService.Model;

{$WARN IMPLICIT_STRING_CAST OFF}
{$WARN IMPLICIT_STRING_CAST_LOSS OFF}

interface

uses
  Classes, SysUtils, SynCommons, mORMot,
  MyService.Interfaces, MyService.DataModel;

type
  TMyService = class(TInterfacedObject, IMyService)
  private
    fConnection: TSQLDatabaseConnection;
    function GetServerConnection: TSQLDatabaseConnection;

    property Connection: TSQLDatabaseConnection read GetServerConnection;
  protected
    function Hello(Name: RawUTF8): RawUTF8;
    function allUsers: RawJSON;
    function retrieve_User(RecID: Integer): RawJSON;
  end;

implementation

uses Constants;

{ TMyService }

function TMyService.GetServerConnection: TSQLDatabaseConnection;
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

function TMyService.Hello(Name: RawUTF8): RawUTF8;
var
  Greeting: RawUTF8;
begin
  Greeting := 'Hello!';
  if Name <> '' then
    Greeting := Format('Hello, %s!', [Name]);
  Result := Greeting;
end;

function TMyService.allUsers: RawJSON;
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

function TMyService.retrieve_User(RecID: Integer): RawJSON;
var Greeting: RawJSON;
    fDB: TSQLDBConnectionProp;
begin
  Greeting := 'Hello!';
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

end.

