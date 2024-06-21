{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
program main;

uses sysutils, network, users, dynasty, servers, configuration, csvdocument, binaries;

procedure CountDynastiesForServers(UserDatabase: TUserDatabase; ServerDatabase: TServerDatabase);
var
   Dynasty: TDynasty;
begin
   for Dynasty in UserDatabase.Dynasties do
   begin
      ServerDatabase.AddDynastyToServer(Dynasty.ServerID);
   end;
end;

var
   Server: TServer;
   UserDatabase: TUserDatabase;
   UserDatabaseFile: File of TDynastyRecord;
   ServerDatabase: TServerDatabase;
   ServerFile: TCSVDocument;
   Galaxy: TBinaryFile;
begin
   Writeln('Interstellar Dynasties - Login server');
   Galaxy.Init(GalaxyFilename);
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
   ServerFile := LoadDynastiesServersConfiguration();
   ServerDatabase := TServerDatabase.Create(ServerFile);
   FreeAndNil(ServerFile);
   CountDynastiesForServers(UserDatabase, ServerDatabase);
   Server := TServer.Create(LoginServerPort, UserDatabase, ServerDatabase, Galaxy);
   Server.Run();
   Writeln('Exiting...');
   FreeAndNil(Server);
   FreeAndNil(UserDatabase);
   FreeAndNil(ServerDatabase);
   Close(UserDatabaseFile);
   Galaxy.Free();
end.