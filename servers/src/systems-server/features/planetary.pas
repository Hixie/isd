{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit planetary;

interface

uses
   systems, serverstream, materials;

type
   TPlanetaryCompositionEntry = record
      Material: TMaterial;
      Mass: Double;
      constructor Create(AMaterial: TMaterial; AMass: Double);
   end;

   TPlanetaryComposition = array of TPlanetaryCompositionEntry;

   TPlanetaryBodyFeatureClass = class(TFeatureClass)
   strict protected
      function GetFeatureNodeClass(): FeatureNodeReference; override;
   public
      function InitFeatureNode(): TFeatureNode; override;
   end;

   TPlanetaryBodyFeatureNode = class(TFeatureNode)
   strict private
      FComposition: TPlanetaryComposition;
      FStructuralIntegrity: Cardinal;
      FDiameter: Double; // m
      FConsiderForDynastyStart: Boolean;
      FTemperature: Double; // K
      function GetBondAlbedo(): Double;
   protected
      function GetMass(): Double; override; // kg
      function GetSize(): Double; override; // m
      function GetFeatureName(): UTF8String; override;
      procedure Walk(PreCallback: TPreWalkCallback; PostCallback: TPostWalkCallback); override;
      function HandleBusMessage(Message: TBusMessage): Boolean; override;
      procedure Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter; CachedSystem: TSystem); override;
   public
      constructor Create(ADiameter, ATemperature: Double; AComposition: TPlanetaryComposition; AStructuralIntegrity: Cardinal; AConsiderForDynastyStart: Boolean);
      procedure UpdateJournal(Journal: TJournalWriter); override;
      procedure ApplyJournal(Journal: TJournalReader; CachedSystem: TSystem); override;
      procedure SetTemperature(ATemperature: Double); // stores a computed temperature
      property StructuralIntegrity: Cardinal read FStructuralIntegrity;
      property ConsiderForDynastyStart: Boolean read FConsiderForDynastyStart;
      property BondAlbedo: Double read GetBondAlbedo;
      property Temperature: Double read FTemperature; // K
   end;

implementation

uses
   isdprotocol, sysutils, exceptions, math;

constructor TPlanetaryCompositionEntry.Create(AMaterial: TMaterial; AMass: Double);
begin
   Material := AMaterial;
   Mass := AMass;
end;


function TPlanetaryBodyFeatureClass.GetFeatureNodeClass(): FeatureNodeReference;
begin
   Result := TPlanetaryBodyFeatureNode;
end;

function TPlanetaryBodyFeatureClass.InitFeatureNode(): TFeatureNode;
begin
   Result := nil;
   // TODO: create a technology that knows how to create a planet from a mass of material
   raise Exception.Create('Cannot create a TPlanetaryBodyFeatureNode from a prototype; it must have a unique composition.');
end;


constructor TPlanetaryBodyFeatureNode.Create(ADiameter, ATemperature: Double; AComposition: TPlanetaryComposition; AStructuralIntegrity: Cardinal; AConsiderForDynastyStart: Boolean);
begin
   inherited Create();
   FDiameter := ADiameter;
   FTemperature := ATemperature;
   FComposition := AComposition;
   FStructuralIntegrity := AStructuralIntegrity;
   FConsiderForDynastyStart := AConsiderForDynastyStart;
end;

function TPlanetaryBodyFeatureNode.GetMass(): Double; // kg
var
   CompositionEntry: TPlanetaryCompositionEntry;
begin
   Result := 0.0;
   for CompositionEntry in FComposition do
      Result := Result + CompositionEntry.Mass;
end;

function TPlanetaryBodyFeatureNode.GetSize(): Double;
begin
   Result := FDiameter;
end;

function TPlanetaryBodyFeatureNode.GetBondAlbedo(): Double;
// This function should remain equivalent to the GetBondAlbedo function in protoplanetary.pas
var
   Index: Cardinal;
   Weight, Numerator, Denominator: Double;
   Material: TMaterial;
begin
   Numerator := 0.0;
   Denominator := 0.0;
   Assert(Length(FComposition) > 0);
   for Index := Low(FComposition) to High(FComposition) do // $R-
   begin
      Material := FComposition[Index].Material;
      if (not IsNaN(Material.BondAlbedo)) then
      begin
         Weight := FComposition[Index].Mass / Material.Density;
         Numerator := Numerator + Material.BondAlbedo * Weight;
         Denominator := Denominator + Weight;
      end;
   end;
   Result := Numerator / Denominator;
   if (IsNan(Result)) then
      Result := 1.0;
   Assert(Result >= 0.0);
   Assert(Result <= 1.0);
end;

function TPlanetaryBodyFeatureNode.GetFeatureName(): UTF8String;
begin
   Result := '';
end;

procedure TPlanetaryBodyFeatureNode.Walk(PreCallback: TPreWalkCallback; PostCallback: TPostWalkCallback);
begin
end;

function TPlanetaryBodyFeatureNode.HandleBusMessage(Message: TBusMessage): Boolean;
begin
   Result := False;
end;

procedure TPlanetaryBodyFeatureNode.Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter; CachedSystem: TSystem);
begin
   Writer.WriteCardinal(fcPlanetaryBody);
   Writer.WriteCardinal(FStructuralIntegrity);
end;

procedure TPlanetaryBodyFeatureNode.UpdateJournal(Journal: TJournalWriter);
var
   Index: Cardinal;
begin
   Journal.WriteDouble(FDiameter);
   Journal.WriteCardinal(Length(FComposition));
   Assert(Length(FComposition) > 0);
   for Index := Low(FComposition) to High(FComposition) do // $R-
   begin
      Journal.WriteMaterialReference(FComposition[Index].Material);
      Journal.WriteDouble(FComposition[Index].Mass);
   end;
   Journal.WriteCardinal(FStructuralIntegrity);
   Journal.WriteBoolean(FConsiderForDynastyStart);
   Journal.WriteDouble(FTemperature);
end;

procedure TPlanetaryBodyFeatureNode.ApplyJournal(Journal: TJournalReader; CachedSystem: TSystem);
var
   Index: Cardinal;
begin
   FDiameter := Journal.ReadDouble();
   SetLength(FComposition, Journal.ReadCardinal());
   Assert(Length(FComposition) > 0);
   for Index := Low(FComposition) to High(FComposition) do // $R-
   begin
      FComposition[Index].Material := Journal.ReadMaterialReference();
      FComposition[Index].Mass := Journal.ReadDouble();
   end;
   FStructuralIntegrity := Journal.ReadCardinal();
   FConsiderForDynastyStart := Journal.ReadBoolean();
   FTemperature := Journal.ReadDouble();
end;

procedure TPlanetaryBodyFeatureNode.SetTemperature(ATemperature: Double);
begin
   FTemperature := ATemperature;
   Writeln('Setting temperature of ', Parent.DebugName, ' to ', ATemperature:0:2, 'K (', ConsiderForDynastyStart, ')');
end;

end.