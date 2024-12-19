{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit materials;

interface

uses
   hashtable, hashset, genericutils, icons;

type
   TMaterial = class;

   TMaterialID = LongInt; // signed because negative values are built-in, and positive values are in tech tree
   
   TMaterialColor = $000000..$FFFFFF;

   TMaterialHashSet = class(specialize THashSet<TMaterial, TObjectUtils>)
      constructor Create();
   end;

   TMaterialHashMap = class(specialize THashTable<TMaterialID, TMaterial, LongIntUtils>)
      constructor Create();
   end;
   
   TUnitKind = (
      ukBulkResource, // UI shows it in kilograms
      ukComponent // UI shows it as number of units
   );

   TMaterialTag = (
      mtTerrestrial, // must be abundant on a planet for the planet to be considered a terrestrial planet during planet generation
      mtSystemUnique, // TODO: marks a material as being from the groups of materials where only one is allowed to spawn per system
      mtStarFuel, // TODO: marks the material as the one that stars are made of
      mtPressurized, // TODO: marks a material that is under high pressure (e.g. core of Jupiter)
      mtSolid, // TODO: indicates the material can be carried on belts and so forth
      mtFluid, // TODO: indicates the material is handled by pipes (if we even implement pipes, which we really should probably not)
      mtAtmospheric // TODO: indicates that the material would be available in the atmosphere, if any
   );
   TMaterialTags = set of TMaterialTag;
   
   TMaterialAbundanceParameters = record
      Distance: Double;
      RelativeVolume: Double;
   end;

   TMaterialAbundance = array of TMaterialAbundanceParameters;
   
   TMaterial = class
   protected
      FID: TMaterialID;
      FName, FAmbiguousName, FDescription: UTF8String;
      FIcon: TIcon;
      FColor: TMaterialColor;
      FUnitKind: TUnitKind;
      FMassPerUnit: Double; // kg
      FDensity: Double; // m^3
      FBondAlbedo: Double;
      FTags: TMaterialTags;
      FAbundance: TMaterialAbundance;
   public
      constructor Create(AID: TMaterialID; AName, AAmbiguousName, ADescription: UTF8String; AIcon: TIcon; AColor: TMaterialColor; AUnitKind: TUnitKind; AMassPerUnit, ADensity, ABondAlbedo: Double; ATags: TMaterialTags; AAbundance: TMaterialAbundance);
      property ID: TMaterialID read FID;
      property AmbiguousName: UTF8String read FAmbiguousName;
      property Name: UTF8String read FName;
      property Description: UTF8String read FDescription;
      property Icon: TIcon read FIcon;
      property Color: TMaterialColor read FColor;
      property UnitKind: TUnitKind read FUnitKind;
      property MassPerUnit: Double read FMassPerUnit; // kg
      property Density: Double read FDensity; // kg/m^3
      property BondAlbedo: Double read FBondAlbedo;
      property Tags: TMaterialTags read FTags;
      property Abundance: TMaterialAbundance read FAbundance;
   end;

const
   ZeroAbundance: TMaterialAbundance = ((Distance: 0.0; RelativeVolume: 0.0));

function LoadMaterialRecords(Filename: RawByteString): TMaterialHashSet;

implementation

uses
   hashfunctions, sysutils, strutils, math;

function MaterialHash32(const Key: TMaterial): DWord;
begin
   Result := PtrUIntHash32(PtrUInt(Key));
end;

constructor TMaterialHashSet.Create();
begin
   inherited Create(@MaterialHash32);
end;

constructor TMaterialHashMap.Create();
begin
   inherited Create(@LongIntHash32);
end;

constructor TMaterial.Create(AID: TMaterialID; AName, AAmbiguousName, ADescription: UTF8String; AIcon: TIcon; AColor: TMaterialColor; AUnitKind: TUnitKind; AMassPerUnit, ADensity, ABondAlbedo: Double; ATags: TMaterialTags; AAbundance: TMaterialAbundance);
begin
   inherited Create();
   Assert(AID <> 0); // zero means "not recognized"
   FID := AID;
   FName := AName;
   Assert(FName <> '');
   FAmbiguousName := AAmbiguousName;
   Assert(FAmbiguousName <> '');
   FDescription := ADescription;
   Assert(FDescription <> '');
   FIcon := AIcon;
   FColor := AColor;
   Assert(FIcon <> '');
   FUnitKind := AUnitKind;
   FMassPerUnit := AMassPerUnit;
   FDensity := ADensity;
   FBondAlbedo := ABondAlbedo;
   FTags := ATags;
   FAbundance := AAbundance;
end;

function LoadMaterialRecords(Filename: RawByteString): TMaterialHashSet;

   function ParseDouble(Value: UTF8String): Double;
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
   begin
      Result := StrToFloat(Value, FloatFormat); // $R-
   end;

var
   F: Text;
   IDLine, ColorLine, TagsLine, DensityLine, BondAlbedoLine, AbundanceLine: UTF8String;
   Tag: UTF8String;
   TagList: array of UTF8String;
   Index: SizeInt;
   MaterialID: TMaterialID;
   MaterialName, MaterialAmbiguousName, MaterialDescription: UTF8String;
   MaterialIcon: TIcon;
   MaterialColor: TMaterialColor;
   MaterialTags: TMaterialTags;
   MaterialDensity, MaterialBondAlbedo, MaterialDistance, MaterialAbundance: Double;
   MaterialAbundances: array of TMaterialAbundanceParameters;
   Material: TMaterial;
begin
   Result := TMaterialHashSet.Create();
   Assign(F, Filename);
   Reset(F);
   while (not EOF(F)) do
   begin
      Readln(F, IDLine);
      MaterialID := StrToInt(IDLine); // TODO: make this strictly support only 0-9 // $R-
      Readln(F, MaterialName);
      Readln(F, MaterialAmbiguousName);
      Readln(F, MaterialDescription);
      Readln(F, ColorLine); // hex integer
      MaterialColor := Hex2Dec(ColorLine); // $R- (range errors on this line are indicative of bad data input and we want an exception to fire)
      MaterialIcon := 'material' + IntToHex(MaterialColor, 6);
      Readln(F, TagsLine); // comma-separated strings
      TagList := SplitString(TagsLine, ',');
      MaterialTags := [];
      for Tag in TagList do
      begin
         case Tag of
            'solid': Include(MaterialTags, mtSolid);
            'fluid': Include(MaterialTags, mtFluid);
            'pressurized': Include(MaterialTags, mtPressurized);
            'terrestrial': Include(MaterialTags, mtTerrestrial);
            'system-unique': Include(MaterialTags, mtSystemUnique);
            'star-fuel': Include(MaterialTags, mtStarFuel);
            'atmospheric': Include(MaterialTags, mtAtmospheric);
         else
            raise EConvertError.Create('Unknown material tag "' + Tag + '"');
         end;
      end;
      Readln(F, DensityLine); // floating point number
      MaterialDensity := ParseDouble(DensityLine);
      Readln(F, BondAlbedoLine); // floating point number
      if (BondAlbedoLine = 'n/a') then
      begin
         MaterialBondAlbedo := NaN;
      end
      else
      begin
         MaterialBondAlbedo := ParseDouble(BondAlbedoLine);
      end;
      SetLength(MaterialAbundances, 0); {BOGUS Hint: Local variable "MaterialAbundances" does not seem to be initialized}
      repeat
         Readln(F, AbundanceLine); // two comma-separated floating-point numbers
         if (AbundanceLine <> '') then
         begin
            Index := Pos(',', AbundanceLine);
            if (Index < 1) then
               raise EConvertError.Create('Invalid abundance line (no comma): "' + AbundanceLine + '"');
            MaterialDistance := ParseDouble(Copy(AbundanceLine, 1, Index - 1));
            MaterialAbundance := ParseDouble(Copy(AbundanceLine, Index + 1, Length(AbundanceLine) - Index));
            if ((Length(MaterialAbundances) = 0) and (MaterialDistance > 0)) then
            begin
               SetLength(MaterialAbundances, 2);
               MaterialAbundances[0].Distance := 0.0;
               MaterialAbundances[0].RelativeVolume := MaterialAbundance;
            end
            else
            begin
               SetLength(MaterialAbundances, Length(MaterialAbundances) + 1); // TODO: this is a lot of copies!
            end;
            MaterialAbundances[High(MaterialAbundances)].Distance := MaterialDistance;
            MaterialAbundances[High(MaterialAbundances)].RelativeVolume := MaterialAbundance;
         end;
      until AbundanceLine = '';
      Material := TMaterial.Create(
         MaterialID,
         MaterialName,
         MaterialAmbiguousName,
         MaterialDescription,
         MaterialIcon,
         MaterialColor,
         ukBulkResource,
         0.001,
         MaterialDensity,
         MaterialBondAlbedo,
         MaterialTags,
         MaterialAbundances
      );
      Result.Add(Material);
   end;
   Close(F);
end;

end.