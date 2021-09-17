unit MyService.Interfaces;

interface

uses
  Classes, SysUtils, SynCommons, mORMot;

type
  IMyService = interface(IInvokable)
  ['{17ED3792-B6B8-4B69-AE45-3EBF7A6F08C9}']
    function Hello(Name: RawUTF8): RawUTF8;
    function allUsers: RawJSON;
    function retrieve_User(RecID: Integer): RawJSON;
  end;

implementation

initialization
  TInterfaceFactory.RegisterInterfaces([TypeInfo(IMyService)]);


end.
