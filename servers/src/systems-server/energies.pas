{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit energies;

interface

uses
   hashtable, hashfunctions, stringutils, plasticarrays, genericutils, time;

type
   TEnergy = class
   public
      type
         TArray = array of TEnergy;
         TPlasticArray = specialize PlasticArray<TEnergy, TObjectUtils>;
   strict private
      FName, FUnits, FDescription: UTF8String;
   public
      constructor Create(const AName, AUnits, ADescription: UTF8String);
      property Name: UTF8String read FName write FName;
      property Units: UTF8String read FUnits write FUnits;
      property Description: UTF8String read FDescription write FDescription;
   end;

   TEnergyNameHashTable = class(specialize THashTable<UTF8String, TEnergy, UTF8StringUtils>)
      constructor Create(ACount: THashTableSizeInt = 8);
   end;

   TEnergyUnitsHashTable = class(specialize THashTable<UTF8String, TEnergy, UTF8StringUtils>)
      constructor Create(ACount: THashTableSizeInt = 8);
   end;

   TEnergyRateHashTable = class(specialize THashTable<TEnergy, TRate, TObjectUtils>)
      constructor Create(ACount: THashTableSizeInt = 8);
   end;

function EnergyHash32(const Key: TEnergy): DWord;

implementation

function EnergyHash32(const Key: TEnergy): DWord;
begin
   Result := PtrUIntHash32(PtrUInt(Key));
end;

constructor TEnergy.Create(const AName, AUnits, ADescription: UTF8String);
begin
   inherited Create;
   FName := AName;
   FUnits := AUnits;
   FDescription := ADescription;
end;


constructor TEnergyNameHashTable.Create(ACount: THashTableSizeInt = 8);
begin
   inherited Create(@UTF8StringHash32, ACount);
end;


constructor TEnergyUnitsHashTable.Create(ACount: THashTableSizeInt = 8);
begin
   inherited Create(@UTF8StringHash32, ACount);
end;


constructor TEnergyRateHashTable.Create(ACount: THashTableSizeInt = 8);
begin
   inherited Create(@EnergyHash32, ACount);
end;

end.
