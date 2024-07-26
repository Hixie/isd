{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
program main;

uses sysutils, dynastynetwork, configuration, csvdocument, servers;

var
   Server: TServer;
   SystemServerDatabase: TServerDatabase;
   ServerFile: TCSVDocument;
   Port, ServerIndex, ServerCount: Integer;
   Password: UTF8String;
begin
   if (ParamCount() <> 1) then
   begin
      Writeln('Usage: dynasties-server <id>');
      exit;
   end;
   ServerIndex := StrToIntDef(ParamStr(1), -1);
   if (ServerIndex <= 0) then
   begin
      Writeln('Invalid dynasties server ID. Value must be an integer greater than zero.');
      exit;
   end;
   Dec(ServerIndex);
   ServerFile := LoadDynastiesServersConfiguration();
   try
      ServerCount := ServerFile.RowCount;
      if (ServerIndex >= ServerFile.RowCount) then
      begin
         Writeln('Invalid dynasties server ID. There are ', ServerCount, ' configured servers; valid range is 1..', ServerCount, '.');
         exit;
      end;
      Port := StrToIntDef(ServerFile[ServerDirectPortCell, ServerIndex], -1);
      Password := ServerFile[ServerDirectPasswordCell, ServerIndex];
   finally
      FreeAndNil(ServerFile);
   end;
   Writeln('Interstellar Dynasties - Dynasties server ', ServerIndex+1, ' of ', ServerCount, ' on port ', Port);
   ServerFile := LoadSystemsServersConfiguration();
   SystemServerDatabase := TServerDatabase.Create(ServerFile);
   FreeAndNil(ServerFile);
   EnsureDirectoryExists(DynastyServersDirectory);
   Server := TServer.Create(Port, Password, SystemServerDatabase, DynastyServersDirectory + IntToStr(ServerIndex) + '/'); // $R-
   Server.Run();
   Writeln('Exiting...');
   FreeAndNil(SystemServerDatabase);
   FreeAndNil(Server);
end.