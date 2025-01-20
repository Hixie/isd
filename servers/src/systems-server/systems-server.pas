{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
program main;

uses
   sysutils, systemnetwork, configuration, csvdocument, servers,
   materials, clock, exceptions, intutils, techtree, encyclopedia;

procedure AssertHandler(const Message: ShortString; const FileName: ShortString; LineNumber: LongInt; ErrorAddr: Pointer);
begin
   Writeln('Assertion: ', Message);
   Writeln(GetStackTrace());
end;

var
   Server: TServer;
   DynastyServerDatabase: TServerDatabase;
   ServerFile: TCSVDocument;
   Port, ServerIndex, ServerCount: Integer;
   Password: UTF8String;
   Settings: PSettings;
   MaterialRecords: TMaterialHashSet;
   TechnologyTree: TTechnologyTree;
   SystemClock: TClock;
   GlobalEncyclopedia: TEncyclopedia;
begin
   try
      try
         AssertErrorProc := @AssertHandler;
         if (ParamCount() <> 1) then
         begin
            Writeln('Usage: systems-server <id>');
            exit;
         end;
         ServerIndex := ParseInt32(ParamStr(1), -1);
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
         try
            TechnologyTree := LoadTechnologyTree(TechnologyTreeFilename, MaterialRecords);
            GlobalEncyclopedia := TEncyclopedia.Create(Settings, MaterialRecords, TechnologyTree);
         finally
            FreeAndNil(TechnologyTree);
         end;
         SystemClock := TSystemClock.Create();
         Server := TServer.Create(Port, SystemClock, Password, ServerIndex, Settings, GlobalEncyclopedia, DynastyServerDatabase, SystemServersDirectory + IntToStr(ServerIndex) + '/'); // $R-
         Writeln('Ready');
         Server.Run();
         Writeln('Exiting...');
      finally
         FreeAndNil(Server);
         FreeAndNil(SystemClock);
         FreeAndNil(DynastyServerDatabase);
         FreeAndNil(MaterialRecords);
         Dispose(Settings);
      end;
   except
      on EAbort do
         Writeln('Aborted.');
      on TObject do
         ReportCurrentException();
   end;
end.