unit MyService.Model;

interface

uses
  Classes, SysUtils, SynCommons, mORMot
  , MyService.Interfaces
  ;

implementation

type
  TMyService = class(TInterfacedObject, IMyService)
  protected
    function Hello(Name: RawUTF8): RawUTF8;
  end;

{ TMyService }

function TMyService.Hello(Name: RawUTF8): RawUTF8;
var
  Greeting: RawUTF8;
begin
  Greeting := 'Hello!';
  if Name <> '' then
    Greeting := FormatUTF8('Hello, %s!', [Name]);
  Result := Greeting;
end;

end.

