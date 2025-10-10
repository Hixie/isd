{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
program main;

uses
   sysutils, loginnetwork, users, logindynasty, servers,
   configuration, csvdocument, binaries, galaxy, strutils, isdprotocol;

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
   DataDirectory: UTF8String;
begin
   if (ParamCount() <> 1) then
   begin
      Writeln('Usage: login-server <configuration-path>');
      Writeln('Expected 1 argument, got ', ParamCount(), '.');
      exit;
   end;
   DataDirectory := ParamStr(1);
   if (not EndsStr('/', DataDirectory)) then
   begin
      Writeln('Configuration path must end with a slash.');
      exit;
   end;
   if (not DirectoryExists(DataDirectory)) then
   begin
      Writeln('Specified configuration path does not exist.');
      exit;
   end;
   Writeln('Interstellar Dynasties - Login server');
   // configuration
   GalaxyData.Init(DataDirectory + GalaxyBlobFilename);
   SystemsData.Init(DataDirectory + SystemsBlobFilename);
   Settings := LoadSettingsConfiguration(DataDirectory);
   // users and dynasties
   EnsureDirectoryExists(DataDirectory + LoginServerDirectory);
   OpenUserDatabase(UserDatabaseFile, DataDirectory + UserDatabaseFilename);
   UserDatabase := TUserDatabase.Create(UserDatabaseFile);
   ServerFile := LoadServersConfiguration(DataDirectory, DynastiesServersListFilename);
   DynastyServerDatabase := TServerDatabase.Create(ServerFile);
   FreeAndNil(ServerFile);
   CountDynastiesForServers(UserDatabase, DynastyServerDatabase);
   // systems
   OpenHomeSystemsDatabase(HomeSystemsDatabaseFile, DataDirectory + HomeSystemsDatabaseFilename);
   OpenSystemServerDatabase(SystemServerDatabaseFile, DataDirectory + SystemServerDatabaseFilename);
   ServerFile := LoadServersConfiguration(DataDirectory, SystemsServersListFilename);
   SystemServerDatabase := TServerDatabase.Create(ServerFile);
   FreeAndNil(ServerFile);
   GalaxyManager := TGalaxyManager.Create(GalaxyData, SystemsData, Settings, HomeSystemsDatabaseFile, SystemServerDatabaseFile);
   // server
   Server := TServer.Create(Settings^.LoginServerPort, UserDatabase, DynastyServerDatabase, SystemServerDatabase, GalaxyManager);
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
   {$IFOPT C+}
   Writeln('Done.', ControlEnd);
   GlobalSkipIfNoLeaks := True;
   {$ENDIF}
end.