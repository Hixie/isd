{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
program main;

uses sysutils, network, users, dynasty, servers, configuration, csvdocument, binaries, galaxy;

procedure CountDynastiesForServers(UserDatabase: TUserDatabase; ServerDatabase: TServerDatabase);
var
   Dynasty: TDynasty;
begin
   for Dynasty in UserDatabase.Dynasties do
   begin
      ServerDatabase.IncreaseLoadOnServer(Dynasty.ServerID);
   end;
end;

var
   Server: TServer;
   UserDatabase: TUserDatabase;
   UserDatabaseFile: File of TDynastyRecord;
   HomeSystemsDatabaseFile: THomeSystemsFile;
   SystemServerDatabaseFile: TSystemServerFile;
   DynastyServerDatabase, SystemServerDatabase: TServerDatabase;
   ServerFile: TCSVDocument;
   GalaxyData, SystemsData: TBinaryFile;
   GalaxyManager: TGalaxyManager;
   Settings: PSettings;
begin
   Writeln('Interstellar Dynasties - Login server');
   // configuration
   GalaxyData.Init(GalaxyBlobFilename);
   SystemsData.Init(SystemsBlobFilename);
   Settings := LoadSettingsConfiguration();
   // users and dynasties
   EnsureDirectoryExists(LoginServerDirectory);
   OpenUserDatabase(UserDatabaseFile, UserDatabaseFilename);
   UserDatabase := TUserDatabase.Create(UserDatabaseFile);
   ServerFile := LoadDynastiesServersConfiguration();
   DynastyServerDatabase := TServerDatabase.Create(ServerFile);
   FreeAndNil(ServerFile);
   CountDynastiesForServers(UserDatabase, DynastyServerDatabase);
   // systems
   OpenHomeSystemsDatabase(HomeSystemsDatabaseFile, HomeSystemsDatabaseFilename);
   OpenSystemServerDatabase(SystemServerDatabaseFile, SystemServerDatabaseFilename);
   ServerFile := LoadSystemsServersConfiguration();
   SystemServerDatabase := TServerDatabase.Create(ServerFile);
   FreeAndNil(ServerFile);
   GalaxyManager := TGalaxyManager.Create(GalaxyData, SystemsData, Settings, HomeSystemsDatabaseFile, SystemServerDatabaseFile);
   // server
   Server := TServer.Create(LoginServerPort, UserDatabase, DynastyServerDatabase, SystemServerDatabase, GalaxyManager);
   Server.Run();
   // shutdown
   Writeln('Exiting...');
   FreeAndNil(Server);
   FreeAndNil(GalaxyManager);
   FreeAndNil(SystemServerDatabase);
   FreeAndNil(DynastyServerDatabase);
   FreeAndNil(UserDatabase);
   Close(SystemServerDatabaseFile);
   Close(HomeSystemsDatabaseFile);
   Close(UserDatabaseFile);
   Dispose(Settings);
   SystemsData.Free();
   GalaxyData.Free();
end.