{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit configuration;

interface

uses csvdocument;

const
   LoginServerPort = 1024;
   DataDirectory = 'data/';
   GalaxyFilename = DataDirectory + 'galaxy.dat';
   UserDatabaseFilename = DataDirectory + 'users.db';
   DynastiesServersListFilename = DataDirectory + 'dynasty-servers.csv';
   SystemsServersListFilename = DataDirectory + 'systems-servers.csv';
   DynastiesServersDirectory = DataDirectory + 'dynasties/';
   DynastiesListFileName = 'dynasties.db';
   TemporaryExtension = '.$$$';

const
   DynastiesServerHostNameCell = 0;
   DynastiesServerWebSocketPortCell = 1;
   DynastiesServerDirectHostCell = 2;
   DynastiesServerDirectPortCell = 3;
   DynastiesServerDirectPasswordCell = 4;

function LoadDynastiesServersConfiguration(): TCSVDocument;
function LoadSystemsServersConfiguration(): TCSVDocument;
   
implementation

function LoadDynastiesServersConfiguration(): TCSVDocument;
begin
   Result := TCSVDocument.Create();
   Result.LoadFromFile(DynastiesServersListFilename);
end;

function LoadSystemsServersConfiguration(): TCSVDocument;
begin
   Result := TCSVDocument.Create();
   Result.LoadFromFile(SystemsServersListFilename);
end;

end.
