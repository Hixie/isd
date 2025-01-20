{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit planetary;

interface

uses
   systems, serverstream, materials, techtree, tttokenizer;

type
   TPlanetaryCompositionEntry = record
      Material: TMaterial;
      Quantity: Double; // TODO: how are we going to handle small changes to such large numbers?
      constructor Create(AMaterial: TMaterial; AQuantity: Double);
   end;

   TPlanetaryComposition = array of TPlanetaryCompositionEntry;

   TPlanetaryBodyFeatureClass = class(TFeatureClass)
   strict protected
      function GetFeatureNodeClass(): FeatureNodeReference; override;
   public
      constructor CreateFromTechnologyTree(Reader: TTechTreeReader); override;
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
      function HandleBusMessage(Message: TBusMessage): Boolean; override;
      procedure Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter; CachedSystem: TSystem); override;
   public
      constructor Create(ADiameter, ATemperature: Double; AComposition: TPlanetaryComposition; AStructuralIntegrity: Cardinal; AConsiderForDynastyStart: Boolean);
      procedure UpdateJournal(Journal: TJournalWriter; CachedSystem: TSystem); override;
      procedure ApplyJournal(Journal: TJournalReader; CachedSystem: TSystem); override;
      procedure SetTemperature(ATemperature: Double); // stores a computed temperature
      procedure DescribeExistentiality(var IsDefinitelyReal, IsDefinitelyGhost: Boolean); override;
      property StructuralIntegrity: Cardinal read FStructuralIntegrity;
      property ConsiderForDynastyStart: Boolean read FConsiderForDynastyStart;
      property BondAlbedo: Double read GetBondAlbedo;
      property Temperature: Double read FTemperature; // K
   end;

implementation

uses
   isdprotocol, sysutils, exceptions, math, rubble;

constructor TPlanetaryCompositionEntry.Create(AMaterial: TMaterial; AQuantity: Double);
begin
   Material := AMaterial;
   Quantity := AQuantity;
end;


constructor TPlanetaryBodyFeatureClass.CreateFromTechnologyTree(Reader: TTechTreeReader);
begin
   Reader.Tokens.Error('Feature class %s is reserved for internal asset classes', [ClassName]);
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
      Result := Result + CompositionEntry.Material.MassPerUnit * CompositionEntry.Quantity;
end;

function TPlanetaryBodyFeatureNode.GetSize(): Double;
begin
   Result := FDiameter;
end;

function TPlanetaryBodyFeatureNode.GetBondAlbedo(): Double;
// This function should remain equivalent to the GetBondAlbedo function in protoplanetary.pas
var
   Index: Cardinal;
   Factor, Numerator, Denominator: Double;
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
         Factor := FComposition[Index].Quantity * Material.MassPerUnit / Material.Density;
         Numerator := Numerator + Material.BondAlbedo * Factor;
         Denominator := Denominator + Factor;
      end;
   end;
   Result := Numerator / Denominator;
   if (IsNan(Result)) then
      Result := 1.0;
   Assert(Result >= 0.0);
   Assert(Result <= 1.0);
end;

function TPlanetaryBodyFeatureNode.HandleBusMessage(Message: TBusMessage): Boolean;
var
   RubbleMessage: TRubbleCollectionMessage;
   Entry: TPlanetaryCompositionEntry;
begin
   Result := False;
   if (Message is TRubbleCollectionMessage) then
   begin
      RubbleMessage := Message as TRubbleCollectionMessage;
      RubbleMessage.Grow(Length(FComposition)); // $R-
      for Entry in FComposition do
      begin
         if (Entry.Quantity <= High(Int64)) then
         begin
            RubbleMessage.AddMaterial(Entry.Material, Round(Entry.Quantity));
         end
         else
         begin
            // now what
            Assert(False, 'Could not convert plantery body ' + Entry.Material.Name + ' to rubble (quantity too high).');
         end;
      end;
      exit;
   end;
end;

procedure TPlanetaryBodyFeatureNode.Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter; CachedSystem: TSystem);
begin
   Writer.WriteCardinal(fcPlanetaryBody);
   Writer.WriteCardinal(FStructuralIntegrity);
end;

procedure TPlanetaryBodyFeatureNode.UpdateJournal(Journal: TJournalWriter; CachedSystem: TSystem);
var
   Index: Cardinal;
begin
   Journal.WriteDouble(FDiameter);
   Journal.WriteCardinal(Length(FComposition));
   Assert(Length(FComposition) > 0);
   for Index := Low(FComposition) to High(FComposition) do // $R-
   begin
      Journal.WriteMaterialReference(FComposition[Index].Material);
      Journal.WriteDouble(FComposition[Index].Quantity);
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
      FComposition[Index].Quantity := Journal.ReadDouble();
   end;
   FStructuralIntegrity := Journal.ReadCardinal();
   FConsiderForDynastyStart := Journal.ReadBoolean();
   FTemperature := Journal.ReadDouble();
end;

procedure TPlanetaryBodyFeatureNode.SetTemperature(ATemperature: Double);
begin
   FTemperature := ATemperature;
   // Writeln('Setting temperature of ', Parent.DebugName, ' to ', ATemperature:0:2, 'K (', ConsiderForDynastyStart, ')');
end;

procedure TPlanetaryBodyFeatureNode.DescribeExistentiality(var IsDefinitelyReal, IsDefinitelyGhost: Boolean);
begin
   IsDefinitelyReal := True;
end;

initialization
   RegisterFeatureClass(TPlanetaryBodyFeatureClass);
end.