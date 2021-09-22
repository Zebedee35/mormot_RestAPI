unit Base.SQLConnectionProp;

{$WARN IMPLICIT_STRING_CAST OFF}
{$WARN IMPLICIT_STRING_CAST_LOSS OFF}

interface

uses
  Classes, SysUtils, SynCommons, SynDB, SynOleDB, mORMot;

type
  TSQLDatabaseConnection = class(TSQLRecord)
  private
    fUserName: RawUTF8;
    fPassword: RawUTF8;
    fServer: RawUTF8;
    fIsWinAuth: Boolean;
    fPortNo: Integer;
    fDataBase: RawUTF8;
  public
    function FullServerName : RawUTF8;
  published
    property Server: RawUTF8 read fServer write fServer;
    property UserName: RawUTF8 read fUserName write fUserName;
    property Password: RawUTF8 read fPassword write fPassword;
    property IsWinAuth: Boolean read fIsWinAuth write fIsWinAuth;
    property PortNo: Integer read fPortNo write fPortNo;
    property Database: RawUTF8 read fDataBase write fDataBase;
  end;


  TSQLDBConnectionProp = class(TSQLDBConnectionProperties)
  private
    function GetConnected: Boolean;
  public
    class function CreateMSSQLConnection(const ADatabaseConnection: TSQLDatabaseConnection): TSQLDBConnectionProp; static;

    procedure Connect;
    procedure Disconnect;

    function ExecuteJSON(const CommandText: RawUTF8): RawUTF8;
    function ExecuteTableJSON(const CommandText: RawUTF8): TSQLTableJSON;

//    function GetValue(const CommandText, ValueField : RawUTF8) : Variant;
//    function GetIntValue(const CommandText, ValueField : RawUTF8) : Integer;
//    function GetInt64Value(const CommandText, ValueField: RawUTF8): Int64;
//    function GetStrValue(const CommandText, ValueField : RawUTF8) : RawUTF8;
//    function GetBoolValue(const CommandText, ValueField : RawUTF8) : Boolean;
//    function GetFloatValue(const CommandText, ValueField: RawUTF8): Double;

//    function CheckColumnExists(ATableName, AColumnName: RawUTF8): Boolean;
//    function CheckFunctionExists(AFunctionName: RawUTF8): Boolean;
//    function CheckProcedureExists(AProcedureName: RawUTF8): Boolean;
//    function CheckTableExists(ATableName: RawUTF8): Boolean;
//    function CheckViewExists(AViewName: RawUTF8): Boolean;
//    function CheckDefaultValueExists(ATableName, AColumnName: RawUTF8): Boolean;

    property Connected: Boolean read GetConnected;
  end;

implementation


{ TSQLDatabaseConnection }

function TSQLDatabaseConnection.FullServerName: RawUTF8;
begin
  if fPortNo >  0
    then Result := fServer + ',' + IntToStr(fPortNo)
    else Result := fServer;
end;

{ TSQLDBConnectionProp }

class function TSQLDBConnectionProp.CreateMSSQLConnection(const ADatabaseConnection: TSQLDatabaseConnection): TSQLDBConnectionProp;
type
  TMSSQLConnectionType = (msctGeneric, msct2005, msct2008, msct2012);

  function CreateConnection(aType: TMSSQLConnectionType; bIfFailSetNil: Boolean) : TSQLDBConnectionProp;
  begin
    Result := nil;

    with ADatabaseConnection do
    case aType of
      msctGeneric: TSQLDBConnectionProperties(Result) := TOleDBMSSQLConnectionProperties    .Create(FullServerName, Database, UserName, Password);
         msct2005: TSQLDBConnectionProperties(Result) := TOleDBMSSQL2005ConnectionProperties.Create(FullServerName, Database, UserName, Password);
         msct2008: TSQLDBConnectionProperties(Result) := TOleDBMSSQL2008ConnectionProperties.Create(FullServerName, Database, UserName, Password);
         msct2012: TSQLDBConnectionProperties(Result) := TOleDBMSSQL2012ConnectionProperties.Create(FullServerName, Database, UserName, Password);
    end;

    try
      Result.Connect;
    except
      on e:Exception do
      begin
        if SameText(E.ClassName, 'EOleSysError') then
          if bIfFailSetNil then
            Result := nil;
      end;
    end;

  end;

begin
  Result := CreateConnection(msct2012, True);
  if not Assigned(Result) then Result := CreateConnection(msct2008, True);
  if not Assigned(Result) then Result := CreateConnection(msct2005, True);
  if not Assigned(Result) then Result := CreateConnection(msctGeneric, False);

  Result.ConnectionTimeOutMinutes := 60;
  Result.ReconnectAfterConnectionError := True;
  Result.UseCache := False;
end;

procedure TSQLDBConnectionProp.Connect;
begin
  ThreadSafeConnection.Connect;
end;

procedure TSQLDBConnectionProp.Disconnect;
begin
  ThreadSafeConnection.Disconnect;
end;

function TSQLDBConnectionProp.ExecuteJSON(const CommandText: RawUTF8): RawUTF8;

  procedure GetResult;
  var RowCount: PPtrInt;
  var I: ISQLDBRows;
  begin
    try
      I := Execute(CommandText, []);
      try
        Result := I.FetchAllAsJSON(True, @RowCount);
        if Integer(Pointer(RowCount)) = 0
          then Result := ''
          else Result := StringToUTF8(UTF8ToString(Result));  // tr karakter problemini çözmek için
      finally
        I := nil;
      end;
    except
      on e:Exception do begin
        Result := '';
        TSQLLog.Add.Log(sllError,'An error occured inside TSQLDBConnectionProp.ExecuteJSON. SqlText: ?, Message: ?', [CommandText, e.Message]);
      end;
    end;
  end;

begin
  if not ThreadSafeConnection.IsConnected then
    ThreadSafeConnection.Connect;

  GetResult;
end;

function TSQLDBConnectionProp.ExecuteTableJSON(const CommandText: RawUTF8): TSQLTableJSON;
var fResultJSON: RawUTF8;
begin
  fResultJSON := ExecuteJSON(CommandText);
  Result := TSQLTableJSON.Create(CommandText,pointer(fResultJSON),Length(fResultJSON));
end;

function TSQLDBConnectionProp.GetConnected: Boolean;
begin
  Result := ThreadSafeConnection.Connected;
end;

end.

