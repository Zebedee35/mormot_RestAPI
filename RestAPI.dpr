program RestAPI;

{$APPTYPE CONSOLE}
{$WARN IMPLICIT_STRING_CAST OFF}
{$WARN IMPLICIT_STRING_CAST_LOSS OFF}

{$R *.res}

uses
  System.SysUtils,
  WinApi.Windows,
  SynCommons,
  SynTable,
  mORMot,
  mORMotHTTPServer,
  mORMotService,
  MyService.Interfaces in 'MyService.Interfaces.pas',
  MyService.Model in 'MyService.Model.pas',
  Constants in 'Constants.pas';

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

const
  SERVICE_Name = 'MyRestAPI_Service';
  SERVICE_DESCRIPTION = 'MyRestAPI Service With Mormot';

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

  Rest := TSQLRestServer.Create(Model, false);
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

var Param1: String;
begin
  try
    ConsoleWrite('Service starting...', ccYellow);

    if (ParamCount<>0) then
    begin
      Param1 := ParamStr(1);
      if (Param1 <> '') and (Param1[1] = '-') then
        Param1[1] := '/';

      if (SameText(Param1,'/h') or SameText(Param1,'/?')) then begin
        TMyWinService.WriteHelpContent;
      end
      else
      if (SameText(Param1,'/install') or SameText(Param1,'/uninstall') or SameText(Param1,'/start') or SameText(Param1,'/stop')) then
      begin
        TServiceController.CheckParameters(ExeVersion.ProgramFileName, ExeVersion.ProgramName, SERVICE_DESCRIPTION, SERVICE_DESCRIPTION);
        with TServiceController.CreateOpenService('', '', ExeVersion.ProgramName) do
        try
          State; // just to log the service state after handling the /parameters
        finally
          Free;
        end;
      end
      else
      if SameText(Param1,'/c') then
        with TMyWinService.CreateAsConsole do
          try
            DoStart(nil);

            writeln(#10);
            ConsoleWrite('Service is running', ccLightGreen);
            ConsoleWrite('Press [Enter] to close the server', ccLightGray);
            ConsoleWaitForEnterKey; // ReadLn if you do not use main thread execution

            Exit;
          finally
            Free;
          end;
    end
    else
    begin
      with TMyWinService.Create(ExeVersion.ProgramName, SERVICE_DESCRIPTION) do
        try
          ServicesRun;
        finally
          Free;
        end;
    end;

  except
    on E: Exception do
      Writeln(E.ClassName, ': ', E.Message);
  end;
end.
