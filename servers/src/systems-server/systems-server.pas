{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
program main;

uses
   sysutils, techtree, configuration, csvdocument, servers, materials, clock,
   exceptions, intutils, encyclopedia, systemnetwork, strutils, isdprotocol
   {$IFDEF DEBUG}, debug {$ENDIF};

{$IFNDEF TESTSUITE}
procedure AssertHandler(const Message: ShortString; const FileName: ShortString; LineNumber: LongInt; ErrorAddr: Pointer);
begin
   Writeln('Assertion: ', Message);
   Writeln(GetStackTrace());
end;
{$ENDIF}

var
   Server: TServer;
   DynastyServerDatabase: TServerDatabase;
   ServerFile: TCSVDocument;
   Port, ServerIndex, ServerCount: Integer;
   Password: UTF8String;
   Settings: PSettings;
   OreRecords: TMaterial.TArray;
   TechnologyTree: TTechnologyTree;
   SystemClock, MonotonicClock: TClock;
   GlobalEncyclopedia: TEncyclopedia;
   DataDirectory: UTF8String;
begin
   try
      try
         {$IFNDEF TESTSUITE}
         AssertErrorProc := @AssertHandler;
         {$ENDIF}
         if (ParamCount() <> 2) then
         begin
            Writeln('Usage: systems-server <configuration-path> <id>');
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
            Writeln('Invalid systems server ID. Value must be an integer greater than zero.');
            exit;
         end;
         Dec(ServerIndex);
         ServerFile := LoadServersConfiguration(DataDirectory, SystemsServersListFilename);
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
         Settings := LoadSettingsConfiguration(DataDirectory);
         Assert(Assigned(Settings^.ClockType));
         EnsureDirectoryExists(DataDirectory + SystemServersDirectory);
         ServerFile := LoadServersConfiguration(DataDirectory, DynastiesServersListFilename);
         DynastyServerDatabase := TServerDatabase.Create(ServerFile);
         FreeAndNil(ServerFile);
         OreRecords := LoadOres(DataDirectory + OreRecordsFilename);
         try
            TechnologyTree := LoadTechnologyTree(DataDirectory + TechnologyTreeFilename, OreRecords);
            GlobalEncyclopedia := TEncyclopedia.Create(Settings, OreRecords, TechnologyTree);
         finally
            FreeAndNil(TechnologyTree);
         end;
         SystemClock := Settings^.ClockType.Create();
         MonotonicClock := TMonotonicClock.Create(SystemClock);
         Server := TServer.Create(
            Port, // $R-
            MonotonicClock,
            Password,
            ServerIndex, // $R-
            Settings,
            GlobalEncyclopedia,
            DynastyServerDatabase,
            DataDirectory + SystemServersDirectory + IntToStr(ServerIndex) + '/'
         );
         Server.Run();
         Writeln('Exiting...');
         // TODO: have the servers write a last gasp update to their journal so we don't lose time
         // TODO: have the servers cleanly close their network sockets so that the clients know we're disconnected
      finally
         Writeln('Shutting down...');
         if (Assigned(RaiseList)) then
         begin
            Writeln('Shutdown caused by exception:');
            ReportCurrentException();
         end;
         FreeAndNil(Server);
         FreeAndNil(GlobalEncyclopedia);
         FreeAndNil(MonotonicClock);
         FreeAndNil(SystemClock);
         FreeAndNil(DynastyServerDatabase);
         Dispose(Settings);
      end;
   except
      on EAbort do
         Writeln('Aborted.');
      on TObject do
         ReportCurrentException();
   end;
   {$IFOPT C+}
   Writeln('Done.', ControlEnd);
   GlobalSkipIfNoLeaks := True;
   {$ENDIF}
end.