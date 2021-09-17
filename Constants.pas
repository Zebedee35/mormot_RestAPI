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

implementation

end.
