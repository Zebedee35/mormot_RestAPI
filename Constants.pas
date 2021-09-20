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

  cSQL_ALLUSER = 'SELECT FullName FROM User ';
  cSQL_RETRIEVEUSER = 'SELECT RecID, UserName, FullName FROM User where RecID= %d';

  cALLOW_API = '111222333';

  JWTDefaultTimeout: Integer = 10;
  JWTMaxTimeout: Integer = 2600000;

implementation

end.
