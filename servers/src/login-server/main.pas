{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
program main;
uses sysutils, sigint, network, users, dynasty;

const
   UserDatabaseFilename = 'users.db';
var
   Server: TServer;
   UserDatabase: TUserDatabase;
   UserDatabaseFile: File of TDynastyRecord;
begin
   InstallSigIntHandler();
   Writeln('Interstellar Dynasties - Login server');
   Assign(UserDatabaseFile, UserDatabaseFilename);
   FileMode := 2;
   if (not FileExists(UserDatabaseFilename)) then
   begin
      Rewrite(UserDatabaseFile);
   end
   else
   begin
      Reset(UserDatabaseFile);
   end;
   UserDatabase := TUserDatabase.Create(UserDatabaseFile);
   Server := TServer.Create(1024, UserDatabase);
   repeat
      Server.Select(-1);
   until Aborted;
   FreeAndNil(Server);
   FreeAndNil(UserDatabase);
   Close(UserDatabaseFile);
   Writeln('Exiting...');
end.