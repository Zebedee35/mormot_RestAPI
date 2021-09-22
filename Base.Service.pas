unit Base.Service;

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
  mORMotHTTPServer,
  mORMotService,

  Base.RestServer,
  Base.SQLConnectionProp;


type
  TBaseWinService = class(TServiceSingle)
  private
    fLogFolder: TFileName;
  protected
    function GetLogFolder: TFileName;
  public
    procedure DoStart(Sender: TService); virtual;
    procedure DoStop(Sender: TService); virtual;

    constructor Create(const aServiceName, aDisplayName: String); reintroduce;
    constructor CreateAsConsole; reintroduce;

    destructor Destroy; override;

    class procedure WriteHelpContent;
    property LogFolder: TFileName read GetLogFolder;
  end;


  TBaseWinHttpService = class(TBaseWinService)
  private
  public
    HttpServer: TSQLHttpServer;

    procedure DoStart(Sender: TService); override;
    procedure DoStop(Sender: TService); override;
  end;

  TBaseWinHttpSQLService = class(TBaseWinHttpService)
  public
    SQLClient: TSQLDBConnectionProp;
    procedure DoStop(Sender: TService); override;
  end;

  TBaseWinHttpJWTRestService = class(TBaseWinHttpSQLService)
  public
    RestServer: TBaseJWTRestServer;
  end;


implementation

{ TBaseWinService }

constructor TBaseWinService.Create(const aServiceName, aDisplayName: String);
begin
  inherited Create(aServiceName, aDisplayName);

  OnStart := {$ifdef FPC}@{$endif}DoStart;
  OnStop := {$ifdef FPC}@{$endif}DoStop;
  OnResume := {$ifdef FPC}@{$endif}DoStart; // trivial Pause/Resume actions
  OnPause := {$ifdef FPC}@{$endif}DoStop;
end;

constructor TBaseWinService.CreateAsConsole;
begin
  // manual switch to console mode
  AllocConsole;
end;

destructor TBaseWinService.Destroy;
begin

  inherited Destroy;
end;

procedure TBaseWinService.DoStart(Sender: TService);
const
  LogLevel: TSynLogInfos =
    {$ifdef DEBUG} [sllDebug, sllTrace, sllError, sllLastError, sllException, sllExceptionOS, sllMemory, sllStackTrace, sllFail, sllClient, sllServer, sllServiceCall, sllServiceReturn, sllDDDError]
          {$else}  [sllError, sllLastError, sllException, sllExceptionOS, sllFail, sllDDDError]
    {$endif};

begin
  ServiceLog := TSQLLog; // explicitely enable logging
  ServiceLog.Family.Level := LogLevel;

  // define the log level
  with TSQLLog.Family do begin
    DestinationPath := LogFolder;
    Level := LogLevel;
    PerThreadLog := ptIdentifiedInOnFile;
  end;

  if Sender = nil then
    TSQLLog.Family.EchoToConsole := LOG_STACKTRACE;

  TSQLLog.Enter(self);
end;

procedure TBaseWinService.DoStop(Sender: TService);
begin
  TSQLLog.Add.Log(sllInfo,'Service stopped.')
end;

function TBaseWinService.GetLogFolder: TFileName;
begin
  if fLogFolder = '' then begin
    fLogFolder := ExeVersion.ProgramFilePath + 'logs\' + ExeVersion.ProgramName;
    fLogFolder := IncludeTrailingPathDelimiter(fLogFolder);

    ForceDirectories(fLogFolder);
  end;

  Result := fLogFolder;
end;

class procedure TBaseWinService.WriteHelpContent;
begin
  WriteLn('To install your service please type  /install');
  WriteLn('To uninstall your service please type  /uninstall');
  WriteLn('To start your service please type  /start');
  WriteLn('To stop your service please type  /stop');
  WriteLn('');
  WriteLn('For help please type  /? or /h');
end;

{ TBaseWinHttpService }

procedure TBaseWinHttpService.DoStart(Sender: TService);
begin
  inherited;

  if HttpServer <> nil then DoStop(nil); // should never happen
end;

procedure TBaseWinHttpService.DoStop(Sender: TService);
begin
  if HttpServer = nil then Exit;

  inherited;
end;

{ TBaseWinHttpSQLService }

procedure TBaseWinHttpSQLService.DoStop(Sender: TService);
begin
  if Assigned(SQLClient) then
    try
      if SQLClient.Connected then
      SQLClient.Disconnect;
    finally
      FreeAndNil(SQLClient);
    end;

  inherited;
end;

end.
