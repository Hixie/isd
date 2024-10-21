{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
program main;

uses sysutils, systemnetwork, configuration, csvdocument, servers, materials;

var
   Server: TServer;
   DynastyServerDatabase: TServerDatabase;
   ServerFile: TCSVDocument;
   Port, ServerIndex, ServerCount: Integer;
   Password: UTF8String;
   Settings: PSettings;
   MaterialRecords: TMaterialHashSet;
   Material: TMaterial;
begin
   if (ParamCount() <> 1) then
   begin
      Writeln('Usage: systems-server <id>');
      exit;
   end;
   ServerIndex := StrToIntDef(ParamStr(1), -1);
   if (ServerIndex <= 0) then
   begin
      Writeln('Invalid systems server ID. Value must be an integer greater than zero.');
      exit;
   end;
   Dec(ServerIndex);
   ServerFile := LoadSystemsServersConfiguration();
   try
      ServerCount := ServerFile.RowCount;
      if (ServerIndex >= ServerFile.RowCount) then
      begin
         Writeln('Invalid systems server ID. There are ', ServerCount, ' configured servers; valid range is 1..', ServerCount, '.');
         exit;
      end;
      Port := StrToIntDef(ServerFile[ServerDirectPortCell, ServerIndex], -1);
      Password := ServerFile[ServerDirectPasswordCell, ServerIndex];
   finally
      FreeAndNil(ServerFile);
   end;
   Writeln('Interstellar Dynasties - Systems server ', ServerIndex+1, ' of ', ServerCount, ' on port ', Port);
   Settings := LoadSettingsConfiguration();
   EnsureDirectoryExists(SystemServersDirectory);
   ServerFile := LoadDynastiesServersConfiguration();
   DynastyServerDatabase := TServerDatabase.Create(ServerFile);
   FreeAndNil(ServerFile);
   MaterialRecords := LoadMaterialRecords(MaterialRecordsFilename);
   Server := TServer.Create(Port, Password, ServerIndex, Settings, MaterialRecords, DynastyServerDatabase, SystemServersDirectory + IntToStr(ServerIndex) + '/'); // $R-
   Server.Run();
   Writeln('Exiting...');
   for Material in MaterialRecords do
      Material.Free();
   FreeAndNil(MaterialRecords);
   FreeAndNil(Server);
   FreeAndNil(DynastyServerDatabase);
   Dispose(Settings);
end.