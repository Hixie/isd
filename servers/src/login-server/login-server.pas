{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
program main;

uses
   sysutils, loginnetwork, users, logindynasty, servers, clock,
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
   LoginServerDatabase, DynastyServerDatabase, SystemServerDatabase: TServerDatabase;
   ServerFile: TCSVDocument;
   GalaxyData, SystemsData: TBinaryFile;
   GalaxyManager: TGalaxyManager;
   Settings: PSettings;
   SystemClock, MonotonicClock: TClock;
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
   ServerFile := LoadServersConfiguration(DataDirectory, LoginServersListFilename);
   LoginServerDatabase := TServerDatabase.Create(ServerFile);
   FreeAndNil(ServerFile);
   // clock
   SystemClock := Settings^.ClockType.Create();
   MonotonicClock := TMonotonicClock.Create(SystemClock);
   // users and dynasties
   EnsureDirectoryExists(DataDirectory + LoginServerSubDirectory);
   EnsureDirectoryExists(DataDirectory + LoginServerSubDirectory + DynastyDataSubDirectory);
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
   Server := TServer.Create(
      LoginServerDatabase[0]^.DirectPort,
      LoginServerDatabase[0]^.DirectPassword,
      MonotonicClock,
      DataDirectory + LoginServerSubDirectory,
      UserDatabase,
      DynastyServerDatabase,
      SystemServerDatabase,
      GalaxyManager
   );
   Server.Run();
   // shutdown
   Writeln('Exiting...');
   FreeAndNil(Server);
   FreeAndNil(GalaxyManager);
   FreeAndNil(SystemServerDatabase);
   FreeAndNil(DynastyServerDatabase);
   FreeAndNil(LoginServerDatabase);
   FreeAndNil(UserDatabase);
   Close(SystemServerDatabaseFile);
   Close(HomeSystemsDatabaseFile);
   Close(UserDatabaseFile);
   FreeAndNil(MonotonicClock);
   FreeAndNil(SystemClock);
   Dispose(Settings);
   SystemsData.Free();
   GalaxyData.Free();
   {$IFOPT C+}
   Writeln('Done.', ControlEnd);
   GlobalSkipIfNoLeaks := True;
   {$ENDIF}
end.