{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit configuration;

interface

uses
   csvdocument, astronomy;

const
   LoginServerPort = 1024;
   DataDirectory = 'data/';
   DynastyDataSubDirectory = 'dynasties/';
   SystemDataSubDirectory = 'systems/';
   LoginServerDirectory = DataDirectory + 'login/';
   DynastyServersDirectory = DataDirectory + DynastyDataSubDirectory;
   SystemServersDirectory = DataDirectory + SystemDataSubDirectory;

   GalaxyBlobFilename = DataDirectory + 'galaxy.dat';
   SystemsBlobFilename = DataDirectory + 'systems.dat';

   ServerSettingsFilename = DataDirectory + 'settings.csv';
   DynastiesServersListFilename = DataDirectory + 'dynasty-servers.csv';
   SystemsServersListFilename = DataDirectory + 'systems-servers.csv';

   HomeSystemsDatabaseFilename = LoginServerDirectory + 'home-systems.db';
   SystemServerDatabaseFilename = LoginServerDirectory + 'system-servers.db';
   UserDatabaseFilename = LoginServerDirectory + 'users.db';

   DynastiesDatabaseFilename = 'dynasties.db';
   TokensDatabaseFilename = 'tokens.db';
   SettingsDatabaseFilename = 'settings.db';
   SystemsDatabaseFileName = 'systems.db';
   JournalDatabaseFileName = 'journal.db';
   SnapshotDatabaseFileName = 'snapshot.db';

   TemporaryExtension = '.$$$';

const
   ServerHostNameCell = 0;
   ServerWebSocketPortCell = 1;
   ServerDirectHostCell = 2;
   ServerDirectPortCell = 3;
   ServerDirectPasswordCell = 4;

function LoadDynastiesServersConfiguration(): TCSVDocument;
function LoadSystemsServersConfiguration(): TCSVDocument;

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
      DefaultTimeRate: Double; // game seconds per TAI second
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

function LoadSettingsConfiguration(): PSettings;

procedure EnsureDirectoryExists(DirectoryName: UTF8String);

implementation

uses
   sysutils;

function LoadDynastiesServersConfiguration(): TCSVDocument;
begin
   Result := TCSVDocument.Create();
   Result.LoadFromFile(DynastiesServersListFilename);
end;

function LoadSystemsServersConfiguration(): TCSVDocument;
begin
   Result := TCSVDocument.Create();
   Result.LoadFromFile(SystemsServersListFilename);
end;

function LoadSettingsConfiguration(): PSettings;
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
      ParsedValue := StrToInt(Value);
      if ((ParsedValue < 0) or (ParsedValue > Max)) then
         raise ERangeError.Create('Setting "' + Setting + '" out of range; got ' + Value + ' but range is 0..' + IntToStr(Max) + '.');
      Result := ParsedValue; // $R-
   end;

   function ReadDoubleSetting(): Double;
   const
      FloatFormat: TFormatSettings = (
         CurrencyFormat: 1;
         NegCurrFormat: 1;
         ThousandSeparator: ',';
         DecimalSeparator: '.';
         CurrencyDecimals: 2;
         DateSeparator: '-';
         TimeSeparator: ':';
         ListSeparator: ',';
         CurrencyString: '$';
         ShortDateFormat: 'yyyy-mm-dd';
         LongDateFormat: 'dd" "mmmm" "yyyy';
         TimeAMString: 'AM';
         TimePMString: 'PM';
         ShortTimeFormat: 'hh:nn';
         LongTimeFormat: 'hh:nn:ss';
         ShortMonthNames: ('Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec');
         LongMonthNames: ('January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December');
         ShortDayNames: ('Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat');
         LongDayNames: ('Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday');
         TwoDigitYearCenturyWindow: 50
      );
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
            ParsedValue := StrToInt(Value);
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
   Settings.LoadFromFile(ServerSettingsFilename);
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
               Result^.DefaultTimeRate := ReadDoubleSetting(); // $R-
            end
            else
            begin
               Writeln('Unknown configuration key in ', ServerSettingsFilename, ': "', Setting, '"');
            end;
         end;
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

end.
