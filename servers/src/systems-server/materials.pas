{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit materials;

interface

uses
   hashtable, hashset, hashfunctions, genericutils, stringutils, icons, isdnumbers, time;

type
   TMaterial = class;

   TMaterialID = LongInt; // signed because negative values are built-in, and positive values are in tech tree and ores.mrf

   TOres = 1..22; // IDs that are valid in the ores.mrf file (but not the tech tree)
   
   TMaterialHashSet = class(specialize THashSet<TMaterial, TObjectUtils>)
      constructor Create();
   end;

   TMaterialIDHashTable = class(specialize THashTable<TMaterialID, TMaterial, LongIntUtils>)
      constructor Create(ACount: THashTableSizeInt = 8);
   end;
   
   TMaterialNameHashTable = class(specialize THashTable<UTF8String, TMaterial, UTF8StringUtils>)
      constructor Create(ACount: THashTableSizeInt = 8);
   end;

   TMaterialQuantity = record
      Material: TMaterial;
      Quantity: UInt64;
   end;
   
   TMaterialQuantityHashTable = class(specialize THashTable<TMaterial, UInt64, TObjectUtils>)
      constructor Create(ACount: THashTableSizeInt = 2);
      procedure Inc(Material: TMaterial; Delta: UInt64);
      procedure Inc(Material: TMaterial; Delta: Int64);
   end;
   
   TMaterialRateHashTable = class(specialize THashTable<TMaterial, TRate, TObjectUtils>)
      constructor Create(ACount: THashTableSizeInt = 2);
      procedure Inc(Material: TMaterial; Delta: TRate);
      procedure RemoveZeroes(); // removes entries whose rate is zero
   end;
   
   PMaterialQuantityArray = ^TMaterialQuantityArray;
   TMaterialQuantityArray = array of TMaterialQuantity;

   PQuantityArray = ^TQuantityArray;
   TQuantityArray = array of UInt64;

   TOreQuantities = array[TOres] of UInt64;
   TOreFractions = array[TOres] of Fraction32;
   TOreRates = array[TOres] of TRate;
   TOreMasses = array[TOres] of Double;
   
   TMaterialAbundanceParameters = record
      Distance: Double;
      RelativeVolume: Double;
   end;

   TMaterialAbundance = array of TMaterialAbundanceParameters;

   TUnitKind = (
      ukBulkResource, // UI shows it in kilograms (solids) or liters (fluids)
      ukComponent // UI shows it as number of units
   );

   TMaterialTag = (
      mtTerrestrial, // must be abundant on a planet for the planet to be considered a terrestrial planet during planet generation
      mtSystemUnique, // TODO: marks a material as being from the groups of materials where only one is allowed to spawn per system
      mtStarFuel, // TODO: marks the material as the one that stars are made of
      mtPressurized, // TODO: marks a material that is under high pressure (e.g. core of Jupiter)
      mtSolid, // TODO: indicates the material can be carried on belts and so forth
      mtFluid, // TODO: indicates the material is handled by pipes (if we even implement pipes, which we really should probably not)
      mtAtmospheric, // TODO: indicates that the material would be available in the atmosphere, if any
      mtEvenlyDistributed, // always available wherever you mine
      mtDepth2, // only available at secondary mining depths/regions
      mtDepth3 // only available at tertiary mining depths/regions
   );
   TMaterialTags = set of TMaterialTag;
   
   TMaterial = class sealed
   public
      type
         TArray = array of TMaterial;
   protected
      FID: TMaterialID;
      FName, FAmbiguousName, FDescription: UTF8String;
      FIcon: TIcon;
      FUnitKind: TUnitKind;
      FMassPerUnit: Double; // kg
      FDensity: Double; // m^3
      FBondAlbedo: Double;
      FTags: TMaterialTags;
      FAbundance: TMaterialAbundance;
   public
      constructor Create(AID: TMaterialID; AName, AAmbiguousName, ADescription: UTF8String; AIcon: TIcon; AUnitKind: TUnitKind; AMassPerUnit, ADensity, ABondAlbedo: Double; ATags: TMaterialTags; AAbundance: TMaterialAbundance);
      property ID: TMaterialID read FID; // negative numbers for built-in materials, TOres range for ores, positive numbers above TOres for tech tree components. Never zero.
      property AmbiguousName: UTF8String read FAmbiguousName;
      property Name: UTF8String read FName;
      property Description: UTF8String read FDescription;
      property Icon: TIcon read FIcon;
      property UnitKind: TUnitKind read FUnitKind;
      property MassPerUnit: Double read FMassPerUnit; // kg
      property Density: Double read FDensity; // kg/m^3
      property BondAlbedo: Double read FBondAlbedo;
      property Tags: TMaterialTags read FTags;
      property Abundance: TMaterialAbundance read FAbundance;
   end;

   TMaterialEncyclopedia = class
   protected
      function GetMaterial(ID: TMaterialID): TMaterial; virtual; abstract;
   public
      property Materials[ID: TMaterialID]: TMaterial read GetMaterial;
   end;

   POreFilter = ^TOreFilter;
   TOreFilter = record
   strict private
      const
         kAllDisabled = QWord($0000000000000001);
         kAllEnabled = QWord($FFFFFFFFFFFFFFFF);
      function GetActive(): Boolean; inline;
      function GetOres(Index: TOres): Boolean; inline;
      function GetIsFiltered(): Boolean; inline;
      function GetEnabledCount(): Cardinal;
   public
      procedure Clear(); inline; // sets all flags to disabled
      procedure EnableAll(); inline; // sets all flags to enabled
      procedure Disable(Index: TOres); inline;
      procedure Enable(Index: TOres); inline;
      procedure EnableMaterialIfOre(Material: TMaterial); inline; // silently ignores non-ores
      procedure Add(B: TOreFilter); inline;
      class operator and(A, B: TOreFilter): TOreFilter;
      class operator or(A, B: TOreFilter): TOreFilter;
      class operator xor(A, B: TOreFilter): TOreFilter;
      class operator not(A: TOreFilter): TOreFilter;
      property Ores[Index: TOres]: Boolean read GetOres; default;
      property IsFiltered: Boolean read GetIsFiltered; // if false, every bit is true
      property EnabledCount: Cardinal read GetEnabledCount; // number of bits that are set (from 0 to the number of values in TOres)
      property Active: Boolean read GetActive; // whether the first bit is set (it is always set, unless the memory is location is actually a pointer)
   strict private
      case Integer of
         0: (FFilterArray: bitpacked array[0..63] of Boolean); // slot 0 is reserved (and must always be set)
         1: (FFilterQuad: QWord);
   end;
   {$IF SIZEOF(TOreFilter) <> SIZEOF(Pointer)} {$FATAL This platform is not yet supported.} {$ENDIF}

const
   ZeroAbundance: TMaterialAbundance = ((Distance: 0.0; RelativeVolume: 0.0));

function LoadOres(Filename: RawByteString): TMaterialHashSet;

implementation

uses
   sysutils, strutils, intutils, math;

function MaterialHash32(const Key: TMaterial): DWord;
begin
   Result := PtrUIntHash32(PtrUInt(Key));
end;

constructor TMaterialHashSet.Create();
begin
   inherited Create(@MaterialHash32);
end;

constructor TMaterialIDHashTable.Create(ACount: THashTableSizeInt = 8);
begin
   inherited Create(@LongIntHash32, ACount);
end;

constructor TMaterialNameHashTable.Create(ACount: THashTableSizeInt = 8);
begin
   inherited Create(@UTF8StringHash32, ACount);
end;


constructor TMaterialQuantityHashTable.Create(ACount: THashTableSizeInt = 2);
begin
   inherited Create(@MaterialHash32, ACount);
end;

procedure TMaterialQuantityHashTable.Inc(Material: TMaterial; Delta: UInt64);
var
   Value: UInt64;
begin
   Assert(Delta <> 0);
   if (Has(Material)) then
   begin
      if (Delta > High(UInt64) - Self[Material]) then
      begin
         raise EOverflow.Create('Overflowed TMaterialQuantityHashTable value');
      end;
      Value := Self[Material] + Delta; // $R-
   end
   else
   begin
      Value := Delta; // $R-
   end;
   Self[Material] := Value;
end; 

procedure TMaterialQuantityHashTable.Inc(Material: TMaterial; Delta: Int64);
var
   Value: UInt64;
begin
   Assert(Delta <> 0);
   if (Has(Material)) then
   begin
      Assert((Delta > 0) or (Self[Material] + Delta >= 0));
      if (Delta > High(UInt64) - Self[Material]) then
      begin
         raise EOverflow.Create('Overflowed TMaterialQuantityHashTable value');
      end;
      Value := Self[Material] + Delta; // $R-
   end
   else
   begin
      Assert(Delta > 0);
      Value := Delta; // $R-
   end;
   Self[Material] := Value;
end; 

      
constructor TMaterialRateHashTable.Create(ACount: THashTableSizeInt = 2);
begin
   inherited Create(@MaterialHash32, ACount);
end;

procedure TMaterialRateHashTable.Inc(Material: TMaterial; Delta: TRate);
var
   Value: TRate;
begin
   if (Has(Material)) then
   begin
      Value := Self[Material] + Delta;
   end
   else
   begin
      Value := Delta;
   end;
   Self[Material] := Value;
end;

procedure TMaterialRateHashTable.RemoveZeroes();
var
   Index: Cardinal;
   Entry: PHashTableEntry;
   LastEntry: PPHashTableEntry;
   NextEntry: PHashTableEntry;
begin
   if (Length(FTable) > 0) then
   begin
      for Index := Low(FTable) to High(FTable) do // $R-
      begin
         LastEntry := @FTable[Index];
         Entry := LastEntry^;
         while (Assigned(Entry)) do
         begin
            NextEntry := Entry^.Next;
            if (Entry^.Value.IsZero) then
            begin
               LastEntry^ := Entry^.Next;
               Dispose(Entry);
               Dec(FCount);
            end
            else
            begin
               LastEntry := @Entry^.Next;
            end;
            Entry := NextEntry;
         end;
      end;
   end;
end;


constructor TMaterial.Create(AID: TMaterialID; AName, AAmbiguousName, ADescription: UTF8String; AIcon: TIcon; AUnitKind: TUnitKind; AMassPerUnit, ADensity, ABondAlbedo: Double; ATags: TMaterialTags; AAbundance: TMaterialAbundance);
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
   Assert(FIcon <> '');
   FUnitKind := AUnitKind;
   FMassPerUnit := AMassPerUnit;
   FDensity := ADensity;
   FBondAlbedo := ABondAlbedo;
   FTags := ATags;
   FAbundance := AAbundance;
end;


function TOreFilter.GetActive(): Boolean;
begin
   Result := FFilterArray[0];
end;
   
procedure TOreFilter.Clear();
begin
   FFilterQuad := kAllDisabled;
end;

procedure TOreFilter.EnableAll();
begin
   FFilterQuad := kAllEnabled;
end;
   
procedure TOreFilter.Disable(Index: TOres);
begin
   FFilterArray[Index] := False;
end;

procedure TOreFilter.Enable(Index: TOres);
begin
   FFilterArray[Index] := True;
end;

procedure TOreFilter.EnableMaterialIfOre(Material: TMaterial);
begin
   Assert(Assigned(Material));
   if ((Material.ID >= Low(TOres)) and (Material.ID <= High(TOres))) then
      FFilterArray[Material.ID] := True;
end;

procedure TOreFilter.Add(B: TOreFilter);
begin
   FFilterQuad := FFilterQuad or B.FFilterQuad;
end;

class operator TOreFilter.and(A, B: TOreFilter): TOreFilter;
begin
   Result.FFilterQuad := A.FFilterQuad and B.FFilterQuad;
end;
   
class operator TOreFilter.or(A, B: TOreFilter): TOreFilter;
begin
   Result.FFilterQuad := A.FFilterQuad or B.FFilterQuad;
end;

class operator TOreFilter.xor(A, B: TOreFilter): TOreFilter;
begin
   Result.FFilterQuad := (A.FFilterQuad xor B.FFilterQuad) or kAllDisabled;
end;

class operator TOreFilter.not(A: TOreFilter): TOreFilter;
begin
   Result.FFilterQuad := (not A.FFilterQuad) or kAllDisabled;
end;
   
function TOreFilter.GetOres(Index: TOres): Boolean;
begin
   Assert(Index > 0);
   Assert(Index < High(FFilterArray));
   Result := FFilterArray[Index];
end;

function TOreFilter.GetIsFiltered(): Boolean;
begin
   Result := FFilterQuad = kAllEnabled;
end;

function TOreFilter.GetEnabledCount(): Cardinal;
var
   Mask: QWord;
begin
   Mask := kAllEnabled;
   Mask := Mask >> High(TOres);
   Mask := Mask << High(TOres);
   Mask := Mask << 1; // Active bit
   Mask := not Mask;
   Result := PopCnt(FFilterQuad and Mask); // $R- (no idea why it's defined to return a QWord, when the range is 0..64)
end;
   

function LoadOres(Filename: RawByteString): TMaterialHashSet;

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

type
   TMaterialColor = $000000..$FFFFFF;
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
      Assert(Low(MaterialID) < Low(TOres));
      MaterialID := ParseInt32(IDLine, Low(MaterialID)); // $R-
      if ((MaterialID < Low(TOres)) or (MaterialID > High(TOres))) then
         raise EConvertError.CreateFmt('Invalid material ID ("%s"); must be in range %d..%d', [IDLine, Low(TOres), High(TOres)]);
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
            'evenly-distributed': Include(MaterialTags, mtEvenlyDistributed);
            'depth2': Include(MaterialTags, mtDepth2);
            'depth3': Include(MaterialTags, mtDepth3);
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
         ukBulkResource,
         1000.0, // MassPerUnit for ores is always 1 metric ton
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