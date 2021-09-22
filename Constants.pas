unit Constants;

interface

uses
  SynCommons;

const
  cSERVER   = '127.0.01';
  cUSERNAME = 'sa';
  cPASSWORD = 'sapass';
  cPORTNO   = 1433;
  cDATABASE = 'TESTDB';


  cSQL_ALLUSER = 'SELECT LogonName FROM AuthUser ';
  cSQL_RETRIEVEUSER = 'SELECT ID, LogonName, DisplayName FROM AuthUser where ID= %d';

  cALLOW_API = '111222333';

  JWTDefaultTimeout: Integer = 10;
  JWTMaxTimeout: Integer = 2600000;

implementation

end.
