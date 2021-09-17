unit MyService.Model;

{$WARN IMPLICIT_STRING_CAST OFF}
{$WARN IMPLICIT_STRING_CAST_LOSS OFF}

interface

uses
  Classes, SysUtils, SynCommons, mORMot, MyService.Interfaces;

type
  TMyService = class(TInterfacedObject, IMyService)
  protected
    function Hello(Name: RawUTF8): RawUTF8;
  end;

implementation

{ TMyService }

function TMyService.Hello(Name: RawUTF8): RawUTF8;
var
  Greeting: RawUTF8;
begin
  Greeting := 'Hello!';
  if Name <> '' then
    Greeting := Format('Hello, %s!', [Name]);
  Result := Greeting;
end;

end.

