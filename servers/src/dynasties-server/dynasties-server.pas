{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
program main;

uses
   sysutils, intutils, dynastynetwork, configuration, csvdocument, servers, strutils, isdprotocol;

var
   Server: TServer;
   LoginServerDatabase, SystemServerDatabase: TServerDatabase;
   ServerFile: TCSVDocument;
   Port, ServerIndex, ServerCount: Integer;
   DataDirectory, Password: UTF8String;
begin
   if (ParamCount() <> 2) then
   begin
      Writeln('Usage: dynasties-server <configuration-path> <id>');
      Writeln('Expected 2 arguments, got ', ParamCount(), '.');
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
   ServerIndex := ParseInt32(ParamStr(2), -1);
   if (ServerIndex <= 0) then
   begin
      Writeln('Invalid dynasties server ID (', ServerIndex, '). Value must be an integer greater than zero.');
      exit;
   end;
   Dec(ServerIndex);
   ServerFile := LoadServersConfiguration(DataDirectory, DynastiesServersListFilename);
   try
      ServerCount := ServerFile.RowCount;
      if (ServerIndex >= ServerFile.RowCount) then
      begin
         Writeln('Invalid dynasties server ID (', ServerIndex+1, '). There are ', ServerCount, ' configured servers; valid range is 1..', ServerCount, '.');
         exit;
      end;
      Port := ParseInt32(ServerFile[ServerDirectPortCell, ServerIndex], -1);
      Password := ServerFile[ServerDirectPasswordCell, ServerIndex];
   finally
      FreeAndNil(ServerFile);
   end;
   Writeln('Interstellar Dynasties - Dynasties server ', ServerIndex+1, ' of ', ServerCount, ' on port ', Port);
   ServerFile := LoadServersConfiguration(DataDirectory, SystemsServersListFilename);
   SystemServerDatabase := TServerDatabase.Create(ServerFile);
   FreeAndNil(ServerFile);
   ServerFile := LoadServersConfiguration(DataDirectory, LoginServersListFilename);
   LoginServerDatabase := TServerDatabase.Create(ServerFile);
   FreeAndNil(ServerFile);
   EnsureDirectoryExists(DataDirectory + DynastyServersDirectory);
   Server := TServer.Create(Port, Password, LoginServerDatabase, SystemServerDatabase, DataDirectory + DynastyServersDirectory + IntToStr(ServerIndex) + '/'); // $R-
   Server.Run();
   Writeln('Exiting...');
   FreeAndNil(SystemServerDatabase);
   FreeAndNil(LoginServerDatabase);
   FreeAndNil(Server);
   {$IFOPT C+}
   Writeln('Done.', ControlEnd);
   GlobalSkipIfNoLeaks := True;
   {$ENDIF}
end.