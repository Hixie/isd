{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
program main;

uses sysutils, network, configuration, csvdocument;

var
   Server: TServer;
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
      if ((ServerIndex < 0) or (ServerIndex >= ServerFile.RowCount)) then
      begin
         Writeln('Invalid dynasties server ID. There are ', ServerCount, ' configured servers; valid range is 1..', ServerCount, '.');
         exit;
      end;
      Port := StrToIntDef(ServerFile[DynastiesServerDirectPortCell, ServerIndex], -1);
      Password := ServerFile[DynastiesServerDirectPasswordCell, ServerIndex];
   finally
      FreeAndNil(ServerFile);
   end;
   Writeln('Interstellar Dynasties - dynasties server ', ServerIndex+1, ' of ', ServerCount, ' on port ', Port);
   Server := TServer.Create(Port, Password, DynastiesServersDirectory + IntToStr(ServerIndex) + '/'); // $R-
   Server.Run();
   Writeln('Exiting...');
   FreeAndNil(Server);
end.