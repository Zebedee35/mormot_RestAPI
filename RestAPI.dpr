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
  SynCrypto,
  mORMot,
  mORMotHTTPServer,
  mORMotService,
  SynSQLite3Static,
  Constants in 'Constants.pas',
  MyService.Interfaces in 'MyService.Interfaces.pas',
  MyService.Model in 'MyService.Model.pas',
  Base.SQLConnectionProp in 'Base.SQLConnectionProp.pas',
  MyService in 'MyService.pas',
  Base.Service in 'Base.Service.pas',
  Base.RestServer in 'Base.RestServer.pas',
  Base.RestClient in 'Base.RestClient.pas',
  MyAPIService in 'MyAPIService.pas',
  MyAPIService.Interfaces in 'MyAPIService.Interfaces.pas';

const
  SERVICE_Name = 'MyRestAPI_Service';
  SERVICE_DESCRIPTION = 'MyRestAPI Service With Mormot';

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
        with TMyApiService.CreateAsConsole do
          try
            DoStart(nil);

            writeln(#10);
            ConsoleWrite('Service is running: PORT:8080', ccLightGreen);
            ConsoleWrite('FULL_URL: http://localhost:8080/a/', ccLightGray);
            ConsoleWrite('', ccLightGray);
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
