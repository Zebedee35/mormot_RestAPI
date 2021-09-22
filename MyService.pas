unit MyService;

{$WARN IMPLICIT_STRING_CAST OFF}
{$WARN IMPLICIT_STRING_CAST_LOSS OFF}

interface

uses
  System.SysUtils,
  WinApi.Windows,
  SynCommons,
  SynTable,
  SynCrypto,
  mORMot,
  mORMotHTTPServer,
  mORMotService,
  Constants,
  MyService.Interfaces,
  MyService.Model;

type


  /// class implementing the background Service
  TMyWinService = class(TServiceSingle)
  public
    /// the associated database model
    Model: TSQLModel;
    /// the associated DB/
    Rest: TSQLRestServer;
    /// the background Server processing all requests
    Server: TSQLHttpServer;

    /// event triggered to start the service
    // - e.g. create the Server instance
    procedure DoStart(Sender: TService); virtual;

    /// event triggered to stop the service
    // - e.g. destroy the Server instance
    procedure DoStop(Sender: TService); virtual;

    constructor Create(const aServiceName, aDisplayName: String); reintroduce;
    constructor CreateAsConsole; reintroduce;

    destructor Destroy; override;

    class procedure WriteHelpContent;

  end;

function getAlgo(const Value: RawUTF8): TSignAlgo;

implementation

uses Base.RestServer;

function getAlgo(const Value: RawUTF8): TSignAlgo;
var i : TSignAlgo;
begin
  Result := saSha256;

  for i := low(JWT_TEXT) to High(JWT_TEXT) do
    if SameTextU(Value, JWT_TEXT[i]) then begin
      Result := i;
      Break;
    end;
end;


{ TMyWinService }

constructor TMyWinService.Create(const aServiceName, aDisplayName: String);
begin
  inherited Create(aServiceName, aDisplayName);

  OnStart := {$ifdef FPC}@{$endif}DoStart;
  OnStop := {$ifdef FPC}@{$endif}DoStop;
  OnResume := {$ifdef FPC}@{$endif}DoStart; // trivial Pause/Resume actions
  OnPause := {$ifdef FPC}@{$endif}DoStop;
end;

constructor TMyWinService.CreateAsConsole;
begin
  // manual switch to console mode
  AllocConsole;
end;

destructor TMyWinService.Destroy;
begin
  if Server<>nil then
    DoStop(nil); // should not happen

  inherited Destroy;
end;

procedure TMyWinService.DoStart(Sender: TService);
var SFS: TServiceFactoryServer;
begin
  if Server<>nil then
    DoStop(nil); // should never happen

  Model := TSQLModel.Create([]);

  Rest := TSQLRestServer.Create(Model, True);
  Rest.CreateMissingTables;

  SFS := Rest.ServiceDefine(TMyService, [IMyService], sicShared, SERVICE_CONTRACT_NONE_EXPECTED);
  SFS.ResultAsJSONObjectWithoutResult := True;
  SFS.ByPassAuthentication := True;
  SFS.SetOptions([], [optErrorOnMissingParam]);

  Server := TSQLHttpServer.Create('8080',[Rest],'+',useHttpApiRegisteringURI);
  Server.AccessControlAllowOrigin := '*';
end;

procedure TMyWinService.DoStop(Sender: TService);
begin

end;

class procedure TMyWinService.WriteHelpContent;
begin
  WriteLn('To install your service please type  /install');
  WriteLn('To uninstall your service please type  /uninstall');
  WriteLn('To start your service please type  /start');
  WriteLn('To stop your service please type  /stop');
  WriteLn('');
  WriteLn('For help please type  /? or /h');
end;

end.
