{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit configuration;

interface

uses
   csvdocument, astronomy, clock, time;

const
   DynastyDataSubDirectory = 'dynasties/';
   SystemDataSubDirectory = 'systems/';
   LoginServerSubDirectory = 'login/';
   DynastyServersDirectory = DynastyDataSubDirectory;
   SystemServersDirectory = SystemDataSubDirectory;

   GalaxyBlobFilename = 'galaxy.dat';
   SystemsBlobFilename = 'systems.dat';
   OreRecordsFilename = 'ores.mrf'; // mrf = material record file
   TechnologyTreeFilename = 'base.tt'; // tt = technology tree

   ServerSettingsFilename = 'settings.csv';
   LoginServersListFilename = 'login-server.csv';
   DynastiesServersListFilename = 'dynasty-servers.csv';
   SystemsServersListFilename = 'systems-servers.csv';

   HomeSystemsDatabaseFilename = LoginServerSubDirectory + 'home-systems.db';
   SystemServerDatabaseFilename = LoginServerSubDirectory + 'system-servers.db';
   UserDatabaseFilename = LoginServerSubDirectory + 'users.db';

   DynastiesDatabaseFilename = 'dynasties.db';
   TokensDatabaseFilename = 'tokens.db';
   SettingsDatabaseFilename = 'settings.db';
   SystemsDatabaseFileName = 'systems.db';
   JournalDatabaseFileName = 'journal.db';
   SnapshotDatabaseFileName = 'snapshot.db';
   ScoresDatabaseFileName = '.scores.db';

   TemporaryExtension = '.$$$';

const
   ServerHostNameCell = 0;
   ServerWebSocketPortCell = 1;
   ServerDirectHostCell = 2;
   ServerDirectPortCell = 3;
   ServerDirectPasswordCell = 4;

function LoadServersConfiguration(const DataDirectory, ServersListFilename: UTF8String): TCSVDocument;

type
   PSettings = ^TSettings;
   TSettings = record
      HomeStarCategory: TStarCategory;
      HomeStarIndex: TStarIndex;
      GalaxyCategories: TStarCategories;
      StarCategories: TStarCategories;
      HomeCandidateCategories: TStarCategories;
      MinimumDistanceFromHome: Cardinal; // dword units
      LocalSpaceRadius: Cardinal; // dword units - distance from candidate home star within which we must find MaxStarsPerHomeSystem
      MaxStarsPerHomeSystem: Cardinal;
      GalaxyDiameter: Double; // meters
      StarGroupingThreshold: Double; // meters
      GravitionalInfluenceConstant: Double; // meters per kilogram (to compute default hill diameter of children of space features)
      DefaultTimeRate: TTimeFactor; // game seconds per TAI second
      ClockType: TRootClockClass;
   end;

const
   HomeStarCategorySetting = 'home star category';
   HomeStarIndexSetting = 'home star index';
   GalaxyCategoriesSetting = 'galaxy categories';
   StarCategoriesSetting = 'star categories';
   HomeCandidateCategoriesSetting = 'home candidate categories';
   MinimumDistanceFromHomeSetting = 'minimum distance from home'; // dword units
   LocalSpaceRadiusSetting = 'local space radius'; // dword units
   MaxStarsPerHomeSystemSetting = 'max stars per home system';
   GalaxyDiameterSetting = 'galaxy diameter'; // meters
   StarGroupingThresholdSetting = 'star grouping threshold'; // meters
   GravitionalInfluenceConstantSetting = 'gravitational influence constant'; // meters per kilogram
   DefaultTimeRateSetting = 'default time rate'; // game seconds per TAI second
   ClockTypeSetting = 'clock type'; // "mock" or "system"

function LoadSettingsConfiguration(const DataDirectory: UTF8String): PSettings;

procedure EnsureDirectoryExists(DirectoryName: UTF8String);

function GenerateScoreFilename(const DataDirectory: UTF8String; DynastyID: Cardinal): UTF8String;

implementation

uses
   sysutils, intutils, stringutils;

function LoadServersConfiguration(const DataDirectory, ServersListFilename: UTF8String): TCSVDocument;
begin
   Result := TCSVDocument.Create();
   Result.LoadFromFile(DataDirectory + ServersListFilename);
   if (Result.RowCount = 0) then
   begin
      raise Exception.CreateFmt('Configuration file "%s" has no servers specified.', [ServersListFilename]);
   end;
end;

function LoadSettingsConfiguration(const DataDirectory: UTF8String): PSettings;
var
   Settings: TCSVDocument;
   Index: Cardinal;
   Setting: UTF8String;

   function ReadCardinalSetting(Max: Cardinal): Cardinal;
   var
      Value: UTF8String;
      ParsedValue: Integer;
   begin
      Value := Settings.Cells[1, Index]; // $R-
      ParsedValue := ParseInt32(Value);
      if ((ParsedValue < 0) or (ParsedValue > Max)) then
         raise ERangeError.Create('Setting "' + Setting + '" out of range; got ' + Value + ' but range is 0..' + IntToStr(Max) + '.');
      Result := ParsedValue; // $R-
   end;

   function ReadDoubleSetting(): Double;
   var
      Value: UTF8String;
   begin
      Value := Settings.Cells[1, Index]; // $R-
      Result := StrToFloat(Value, FloatFormat); // $R-
   end;

   function ReadCategoriesSetting(): TStarCategories;
   var
      Value: UTF8String;
      Subindex: Cardinal;
      ParsedValue: Integer;
   begin
      Result := [];
      for Subindex := 1 to Settings.ColCount[Index] do // $R-
      begin
         Value := Settings.Cells[SubIndex, Index]; // $R-
         if (Value <> '') then
         begin
            ParsedValue := ParseInt32(Value);
            if ((ParsedValue < 0) or (ParsedValue > High(TStarCategory))) then
               raise ERangeError.Create('Setting "' + Setting + '" out of range; got ' + Value + ' but range is 0..' + IntToStr(High(TStarCategory)) + '.');
            Include(Result, ParsedValue); // $R-
         end;
      end;
   end;

begin
   New(Result);
   FillChar(Result^, SizeOf(Result^), 0);
   Settings := TCSVDocument.Create();
   Settings.LoadFromFile(DataDirectory + ServerSettingsFilename);
   try
      for Index := 0 to Settings.RowCount - 1 do // $R-
      begin
         if (Settings.ColCount[Index] >= 2) then // $R-
         begin
            Setting := Settings.Cells[0, Index]; // $R-
            if (Setting = HomeStarCategorySetting) then
            begin
               Result^.HomeStarCategory := ReadCardinalSetting(High(TStarCategory)); // $R-
            end
            else
            if (Setting = HomeStarIndexSetting) then
            begin
               Result^.HomeStarIndex := ReadCardinalSetting(High(TStarIndex)); // $R-
            end
            else
            if (Setting = GalaxyCategoriesSetting) then
            begin
               Result^.GalaxyCategories := ReadCategoriesSetting();
            end
            else
            if (Setting = StarCategoriesSetting) then
            begin
               Result^.StarCategories := ReadCategoriesSetting();
            end
            else
            if (Setting = HomeCandidateCategoriesSetting) then
            begin
               Result^.HomeCandidateCategories := ReadCategoriesSetting();
            end
            else
            if (Setting = MinimumDistanceFromHomeSetting) then
            begin
               Result^.MinimumDistanceFromHome := ReadCardinalSetting(High(Cardinal)); // $R-
            end
            else
            if (Setting = LocalSpaceRadiusSetting) then
            begin
               Result^.LocalSpaceRadius := ReadCardinalSetting(High(Cardinal)); // $R-
            end
            else
            if (Setting = MaxStarsPerHomeSystemSetting) then
            begin
               Result^.MaxStarsPerHomeSystem := ReadCardinalSetting(High(Cardinal)); // $R-
            end
            else
            if (Setting = GalaxyDiameterSetting) then
            begin
               Result^.GalaxyDiameter := ReadDoubleSetting(); // $R-
            end
            else
            if (Setting = StarGroupingThresholdSetting) then
            begin
               Result^.StarGroupingThreshold := ReadDoubleSetting(); // $R-
            end
            else
            if (Setting = GravitionalInfluenceConstantSetting) then
            begin
               Result^.GravitionalInfluenceConstant := ReadDoubleSetting(); // $R-
            end
            else
            if (Setting = DefaultTimeRateSetting) then
            begin
               Result^.DefaultTimeRate := TTimeFactor(ReadDoubleSetting()); // $R-
            end
            else
            if (Setting = ClockTypeSetting) then
            begin
               case (Settings.Cells[1, Index]) of // $R-
                  'mock': Result^.ClockType := TMockClock;
                  'system': Result^.ClockType := TSystemClock;
                else
                   raise Exception.Create('Unknown configuration value for key ' + ClockTypeSetting + ' in ' + DataDirectory + ServerSettingsFilename + ': "' + Settings.Cells[1, Index] + '"'); // $R-
               end;
            end
            else
            begin
               Writeln('Unknown configuration key in ', DataDirectory + ServerSettingsFilename, ': "', Setting, '"');
            end;
         end;
      end;
      if (not Assigned(Result^.ClockType)) then
      begin
         raise Exception.Create('Missing required configuration key in ' + DataDirectory + ServerSettingsFilename + ': "' + ClockTypeSetting + '"');
      end;
   except
      Dispose(Result);
      Settings.Free();
      raise;
   end;
   Settings.Free();
end;

procedure EnsureDirectoryExists(DirectoryName: UTF8String);
begin
   if (not DirectoryExists(DirectoryName)) then
      MkDir(DirectoryName);
end;

function GenerateScoreFilename(const DataDirectory: UTF8String; DynastyID: Cardinal): UTF8String;
begin
   Result := DataDirectory + IntToStr(DynastyID) + ScoresDatabaseFileName;
end;

end.
