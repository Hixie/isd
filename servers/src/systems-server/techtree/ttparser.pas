{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit ttparser;

//{$DEFINE VERBOSE}

interface

uses
   sysutils, time, systems, internals, tttokenizer, materials, masses;

procedure RegisterFeatureClass(FeatureClass: FeatureClassReference);
function RegisterSituation(Name: UTF8String): TSituation;

function ReadBuildEnvironment(Tokens: TTokenizer): TBuildEnvironment;
function ReadAssetClass(Reader: TTechTreeReader): TAssetClass;
function ReadFeatureClass(Reader: TTechTreeReader): TFeatureClass;
function ReadMaterial(Reader: TTechTreeReader): TMaterial;
function ReadSituationName(Reader: TTechTreeReader): UTF8String;
function ReadSituation(Reader: TTechTreeReader): TSituation;
function ReadNumber(Tokens: TTokenizer; Min, Max: Int64): Int64; // integer only
function ReadPerTime(Tokens: TTokenizer): TIterationsRate;
function ReadLength(Tokens: TTokenizer): Double;
function ReadTime(Tokens: TTokenizer): TTimeInMilliseconds;
function ReadMass(Tokens: TTokenizer): TMass;
function ReadMassPerTime(Tokens: TTokenizer): TMassRate;
function ReadQuantity64(Tokens: TTokenizer; Material: TMaterial): TQuantity64;
function ReadQuantity32(Tokens: TTokenizer; Material: TMaterial): TQuantity32;
function ReadQuantityPerTime(Tokens: TTokenizer; Material: TMaterial): TQuantityRate;
function ReadKeywordPerTime(Tokens: TTokenizer; Keyword: UTF8String): TRate;
function ReadComma(Tokens: TTokenizer): Boolean;

function ExtractSituationRegistry(): TSituationHashTable;

implementation

uses
   {$IFDEF VERBOSE} unicode, {$ENDIF}
   typedump, exceptions, rtlutils, stringutils, hashtable,
   hashfunctions, astronomy;

// FEATURE CLASSES

type
   TFeatureClassHashTable = class(specialize THashTable<UTF8String, FeatureClassReference, UTF8StringUtils>)
      constructor Create();
   end;

   constructor TFeatureClassHashTable.Create();
   begin
      inherited Create(@UTF8StringHash32);
   end;

var
   FeatureClasses: TFeatureClassHashTable = nil;

procedure RegisterFeatureClass(FeatureClass: FeatureClassReference);
begin
   if (not Assigned(FeatureClasses)) then
      FeatureClasses := TFeatureClassHashTable.Create();
   Assert(not FeatureClasses.Has(FeatureClass.ClassName));
   FeatureClasses[FeatureClass.ClassName] := FeatureClass;
end;


// INTRINSIC SITUATION NAMES

var
   RegistryOpen: Boolean = True;
   IntrinsicSituations: TSituationHashTable = nil;

function RegisterSituation(Name: UTF8String): TSituation;
begin
   Assert(RegistryOpen, 'RegisterSituation called after parsing tech tree');
   if (not Assigned(IntrinsicSituations)) then
      IntrinsicSituations := TSituationHashTable.Create();
   Assert(not IntrinsicSituations.Has(Name));
   Assert(IntrinsicSituations.Count < High(TSituation));
   IntrinsicSituations[Name] := IntrinsicSituations.Count + 1; // $R-
   Result := IntrinsicSituations.Count; // $R-
end;

function ExtractSituationRegistry(): TSituationHashTable;
begin
   Assert(RegistryOpen, 'ExtractSituationRegistry called twice');
   Assert(Assigned(IntrinsicSituations), 'ExtractSituationRegistry called before registering ores');
   RegistryOpen := False;
   Result := IntrinsicSituations;
   IntrinsicSituations := nil;
end;


// PARSER SHORTHANDS

function ReadBuildEnvironment(Tokens: TTokenizer): TBuildEnvironment;
var
   Keyword: UTF8String;
begin
   Keyword := Tokens.ReadIdentifier();
   case Keyword of
      'land': Result := bePlanetRegion;
      'spacedock': Result := beSpaceDock;
   else
      Tokens.Error('Unknown build environment "%s"', [Keyword]);
   end;
end;

function ReadAssetClass(Reader: TTechTreeReader): TAssetClass;
var
   Name: UTF8String;
begin
   Name := Reader.Tokens.ReadString();
   Result := Reader.AssetClasses[Name];
   if (not Assigned(Result)) then
      Reader.Tokens.Error('Unknown asset class "%s"', [Name]);
end;

function ReadFeatureClass(Reader: TTechTreeReader): TFeatureClass;
var
   FeatureClassName: UTF8String;
begin
   FeatureClassName := 'T' + Reader.Tokens.ReadIdentifier() + 'FeatureClass';
   if (not FeatureClasses.Has(FeatureClassName)) then
      Reader.Tokens.Error('Unknown feature class "%s"', [FeatureClassName]);
   Result := FeatureClasses[FeatureClassName].CreateFromTechnologyTree(Reader);
end;

function ReadMaterial(Reader: TTechTreeReader): TMaterial;
var
   Value: UTF8String;
begin
   Value := Reader.Tokens.ReadString();
   Result := Reader.Materials[Value];
   if (not Assigned(Result)) then
      Reader.Tokens.Error('Unknown material "%s"', [Value]);
   Assert(Result.Name = Value);
end;

function ReadNumber(Tokens: TTokenizer; Min, Max: Int64): Int64;
begin
   Result := Tokens.ReadNumber();
   if (Result < Min) then
      Tokens.Error('Invalid value %d; must be greater than or equal to %d', [Result, Min]);
   if (Result > Max) then
      Tokens.Error('Invalid value %d; must be less than or equal to %d', [Result, Max]);
end;

function ReadSituationName(Reader: TTechTreeReader): UTF8String;
var
   Category: UTF8String;
begin
   if (Reader.Tokens.IsAt()) then
   begin
      Reader.Tokens.ReadAt();
      Category := Reader.Tokens.ReadIdentifier();
      if (Reader.Tokens.IsAt()) then
      begin
         Reader.Tokens.ReadAt();
         Result := '@' + Category + ' @' + Reader.Tokens.ReadIdentifier();
      end
      else
      begin
         Result := '@' + Category + ' ' + Reader.Tokens.ReadString();
      end;
   end
   else
      Result := Reader.Tokens.ReadIdentifier();
end;

function ReadSituation(Reader: TTechTreeReader): TSituation;
var
   Value: UTF8String;
begin
   Value := ReadSituationName(Reader);
   Result := Reader.Situations[Value];
   if (Result = 0) then
      Reader.Tokens.Error('Unknown situation "%s"', [Value]);
end;

function ReadLength(Tokens: TTokenizer): Double;
var
   Value: Double;
   Keyword: UTF8String;
begin
   Value := Tokens.ReadDouble();
   if (Value <= 0) then
      Tokens.Error('Invalid length "%d"; must be greater than zero', [Value]);
   Keyword := Tokens.ReadIdentifier();
   case Keyword of
      'LY': Result := Value * LY;
      'AU': Result := Value * AU;
      'km': Result := Value * 1000.0;
      'm': Result := Value;
      'cm': Result := Value / 100.0;
      'mm': Result := Value / 1000.0;
   else
      Tokens.Error('Unknown unit for length "%s"', [Keyword]);
   end;
end;

function ReadTime(Tokens: TTokenizer): TTimeInMilliseconds;
var
   Value: Double;
   Keyword: UTF8String;
begin
   Value := Tokens.ReadDouble();
   Keyword := Tokens.ReadIdentifier();
   case Keyword of
      'decades': Result := TTimeInMilliseconds.FromMilliseconds(Value * 10.0 * 365.0 * 24.0 * 60.0 * 60.0 * 1000.0);
      'years': Result := TTimeInMilliseconds.FromMilliseconds(Value * 365.0 * 24.0 * 60.0 * 60.0 * 1000.0);
      'w': Result := TTimeInMilliseconds.FromMilliseconds(Value * 7.0 * 24.0 * 60.0 * 60.0 * 1000.0);
      'd': Result := TTimeInMilliseconds.FromMilliseconds(Value * 24.0 * 60.0 * 60.0 * 1000.0);
      'h': Result := TTimeInMilliseconds.FromMilliseconds(Value * 60.0 * 60.0 * 1000.0);
      'min': Result := TTimeInMilliseconds.FromMilliseconds(Value * 60.0 * 1000.0);
      's': Result := TTimeInMilliseconds.FromMilliseconds(Value * 1000.0);
      'ms': Result := TTimeInMilliseconds.FromMilliseconds(Value * 1.0);
   else
      Tokens.Error('Unknown unit for time "%s"', [Keyword]);
   end;
end;

function ReadTimeDenominator(Tokens: TTokenizer): TMillisecondsDuration;
var
   Keyword: UTF8String;
begin
   Tokens.ReadSlash();
   Keyword := Tokens.ReadIdentifier();
   case Keyword of
      'decade': Result := TMillisecondsDuration.FromMilliseconds(10.0 * 365.0 * 24.0 * 60.0 * 60.0 * 1000.0);
      'year': Result := TMillisecondsDuration.FromMilliseconds(365.0 * 24.0 * 60.0 * 60.0 * 1000.0);
      'w': Result := TMillisecondsDuration.FromMilliseconds(7.0 * 24.0 * 60.0 * 60.0 * 1000.0);
      'd': Result := TMillisecondsDuration.FromMilliseconds(24.0 * 60.0 * 60.0 * 1000.0);
      'h': Result := TMillisecondsDuration.FromMilliseconds(60.0 * 60.0 * 1000.0);
      'min': Result := TMillisecondsDuration.FromMilliseconds(60.0 * 1000.0);
      's': Result := TMillisecondsDuration.FromMilliseconds(1000.0);
      'ms': Result := TMillisecondsDuration.FromMilliseconds(1.0);
   else
      Tokens.Error('Unknown unit for time "%s"', [Keyword]);
   end;
end;

function ReadMass(Tokens: TTokenizer): TMass;
var
   Value: Double;
   Keyword: UTF8String;
begin
   Value := Tokens.ReadDouble();
   if (Value <= 0) then
      Tokens.Error('Invalid mass "%d"; must be greater than zero', [Value]);
   Keyword := Tokens.ReadIdentifier();
   case Keyword of
      't', 'Mg': Result := TMass.FromKg(Value * 1000.0);
      'kg': Result := TMass.FromKg(Value);
      'g': Result := TMass.FromG(Value);
      'mg': Result := TMass.FromMg(Value);
   else
      Tokens.Error('Unknown unit for mass "%s"', [Keyword]);
   end;
end;

function ReadQuantity64(Tokens: TTokenizer; Material: TMaterial): TQuantity64;
var
   Value: Int64;
   Mass: TMass;
   Keyword: UTF8String;
begin
   if (Tokens.IsNumber) then
   begin
      Value := Tokens.ReadNumber();
      if (Value <= 0) then
         Tokens.Error('Invalid quantity "%d"; must be greater than zero', [Value]);
      Keyword := Tokens.ReadIdentifier();
      case Keyword of
         't', 'Mg': Result := TMass.FromKg(Value * 1000.0) / Material.MassPerUnit;
         'kg': Result := TMass.FromKg(Value) / Material.MassPerUnit;
         'g': Result := TMass.FromG(Value) / Material.MassPerUnit;
         'mg': Result := TMass.FromMg(Value) / Material.MassPerUnit;
         'unit':
            begin
               if (Value = 1) then
                  Result := TQuantity64.FromUnits(Value) // $R-
               else
                  Tokens.Error('Expected plural "units" for non-1 value, got singular "unit"', []);
            end;     
         'units':
            begin
               if (Value <> 1) then
                  Result := TQuantity64.FromUnits(Value) // $R-
               else
                  Tokens.Error('Expected singular "unit" for value 1, got plural "units"', []);
            end;     
      else
         Tokens.Error('Unknown unit for quantity "%s"', [Keyword]);
      end;
   end
   else
   begin
      Mass := ReadMass(Tokens);
      Result := Mass / Material.MassPerUnit;
   end;
   if (not Result.IsPositive) then
   begin
      Assert(Result.IsZero);
      Tokens.Error('Given mass rounds to zero quantity; quantity must be greater than zero', []);
   end;
end;

function ReadQuantity32(Tokens: TTokenizer; Material: TMaterial): TQuantity32;
var
   Value: TQuantity64;
begin
   Value := ReadQuantity64(Tokens, Material);
   if (Value.AsInt64 > TQuantity32.Max.AsCardinal) then
      Tokens.Error('Invalid quantity, must be no more than %s or %s', [TQuantity32.Max.ToString(), (TQuantity32.Max * Material.MassPerUnit).ToString()]);
   Result := TQuantity32.FromQuantity64(Value);
end;

function ReadPerTime(Tokens: TTokenizer): TIterationsRate;
var
   Value: Double;
begin
   Value := Tokens.ReadDouble();
   Result := TIterationsRate.FromPeriod(ReadTimeDenominator(Tokens), Value);
end;

function ReadMassPerTime(Tokens: TTokenizer): TMassRate;
var
   Value: TMass;
   Period: TMillisecondsDuration;
begin
   Value := ReadMass(Tokens);
   if (Value.IsNegative) then
      Tokens.Error('Invalid throughput "%s"; must be positive', [Value.ToString()]);
   Period := ReadTimeDenominator(Tokens);
   Result := Value / Period;
end;

function ReadQuantityPerTime(Tokens: TTokenizer; Material: TMaterial): TQuantityRate;
var
   Value: TQuantity64;
begin
   Value := ReadQuantity64(Tokens, Material);
   if (Value.IsNegative) then
      Tokens.Error('Invalid throughput "%s"; must be positive', [Value.ToString()]);
   Result := Value / ReadTimeDenominator(Tokens);
end;

function ReadKeywordPerTime(Tokens: TTokenizer; Keyword: UTF8String): TRate;
var
   Value: Double;
begin
   Value := Tokens.ReadDouble();
   Tokens.ReadIdentifier(Keyword);
   Result := Value / ReadTimeDenominator(Tokens);
end;

function ReadComma(Tokens: TTokenizer): Boolean;
begin
   Result := Tokens.IsComma();
   if (Result) then
      Tokens.ReadComma();
end;

finalization
   FreeAndNil(FeatureClasses);
   if (RegistryOpen) then
      FreeAndNil(IntrinsicSituations);
end.