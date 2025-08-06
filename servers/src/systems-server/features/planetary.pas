{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit planetary;

interface

uses
   systems, serverstream, materials, techtree, tttokenizer, isdnumbers;

type
   TAllocateOresBusMessage = class(TPhysicalConnectionBusMessage)
   strict private
      FDepth: Cardinal;
      FCachedSystem: TSystem;
      FTargetCount: Cardinal;
      FTargetQuantity: UInt64;
   public
      AssignedOres: TOreQuantities;
      constructor Create(ADepth: Cardinal; ATargetCount: Cardinal; ATargetQuantity: UInt64; ACachedSystem: TSystem);
      property Depth: Cardinal read FDepth;
      property TargetCount: Cardinal read FTargetCount;
      property TargetQuantity: UInt64 read FTargetQuantity;
      property CachedSystem: TSystem read FCachedSystem;
   end;

   TPlanetaryBodyFeatureClass = class(TFeatureClass)
   strict protected
      function GetFeatureNodeClass(): FeatureNodeReference; override;
   public
      constructor CreateFromTechnologyTree(Reader: TTechTreeReader); override;
      function InitFeatureNode(): TFeatureNode; override;
   end;

   TPlanetaryBodyFeatureNode = class(TFeatureNode)
   strict private
      FComposition: TOreFractions;
      FMass: Int256; // kg
      FDiameter: Double; // m
      FConsiderForDynastyStart: Boolean;
      FTemperature: Double; // K
      function GetBondAlbedo(): Double;
   protected
      constructor CreateFromJournal(Journal: TJournalReader; AFeatureClass: TFeatureClass; ASystem: TSystem); override;
      function GetMass(): Double; override; // kg
      function GetSize(): Double; override; // m
      function ManageBusMessage(Message: TBusMessage): TBusMessageResult; override;
      function HandleBusMessage(Message: TBusMessage): Boolean; override;
      procedure Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter; CachedSystem: TSystem); override;
   public
      constructor Create(ADiameter, ATemperature: Double; AComposition: TOreFractions; AMass: Double; AConsiderForDynastyStart: Boolean);
      destructor Destroy(); override;
      procedure UpdateJournal(Journal: TJournalWriter; CachedSystem: TSystem); override;
      procedure ApplyJournal(Journal: TJournalReader; CachedSystem: TSystem); override;
      procedure SetTemperature(ATemperature: Double);
      procedure DescribeExistentiality(var IsDefinitelyReal, IsDefinitelyGhost: Boolean); override;
      property ConsiderForDynastyStart: Boolean read FConsiderForDynastyStart;
      property BondAlbedo: Double read GetBondAlbedo;
      property Temperature: Double read FTemperature; // K
   end;

implementation

uses
   isdprotocol, sysutils, exceptions, math, rubble;

constructor TAllocateOresBusMessage.Create(ADepth: Cardinal; ATargetCount: Cardinal; ATargetQuantity: UInt64; ACachedSystem: TSystem);
begin
   inherited Create();
   FDepth := ADepth;
   FTargetCount := ATargetCount;
   FTargetQuantity := ATargetQuantity;
   FCachedSystem := ACachedSystem;
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


constructor TPlanetaryBodyFeatureNode.Create(ADiameter, ATemperature: Double; AComposition: TOreFractions; AMass: Double; AConsiderForDynastyStart: Boolean);
begin
   inherited Create();
   FDiameter := ADiameter;
   FTemperature := ATemperature;
   FComposition := AComposition;
   FMass := Int256.FromDouble(AMass);
   FConsiderForDynastyStart := AConsiderForDynastyStart;
end;

constructor TPlanetaryBodyFeatureNode.CreateFromJournal(Journal: TJournalReader; AFeatureClass: TFeatureClass; ASystem: TSystem);
begin
   inherited;
end;

destructor TPlanetaryBodyFeatureNode.Destroy();
begin
   inherited;
end;

function TPlanetaryBodyFeatureNode.GetMass(): Double; // kg
begin
   Result := FMass.ToDouble();
end;

function TPlanetaryBodyFeatureNode.GetSize(): Double;
begin
   Result := FDiameter;
end;

function TPlanetaryBodyFeatureNode.GetBondAlbedo(): Double;
// This function should remain equivalent to the GetBondAlbedo function in protoplanetary.pas
var
   Index: TOres;
   Factor, Numerator, Denominator: Double;
   Material: TMaterial;
   Encyclopedia: TEncyclopediaView;
begin
   Encyclopedia := System.Encyclopedia;
   Numerator := 0.0;
   Denominator := 0.0;
   Assert(Length(FComposition) > 0);
   for Index := Low(FComposition) to High(FComposition) do // $R-
   begin
      Material := Encyclopedia.Materials[Index];
      if (Assigned(Material) and not IsNaN(Material.BondAlbedo)) then
      begin
         Factor := FComposition[Index] / Material.Density;
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

function TPlanetaryBodyFeatureNode.ManageBusMessage(Message: TBusMessage): TBusMessageResult;
var
   AllocateResourcesMessage: TAllocateOresBusMessage;
   OreIndex: TOres;
   Encyclopedia: TEncyclopediaView;
   Material: TMaterial;
   ConsiderOre, IncludeOre: Boolean;
   TargetCount, RemainingCount, Index: Cardinal;
   CurrentFraction, IncludedFraction: Fraction32;
   ApproximateMass, CandidateMass, MaxMass: Double;
   SelectedOres: TOreFilter;
   CachedSystem: TSystem;
begin
   if (Message is TAllocateOresBusMessage) then
   begin
      AllocateResourcesMessage := Message as TAllocateOresBusMessage;
      CachedSystem := System;
      Encyclopedia := AllocateResourcesMessage.CachedSystem.Encyclopedia;
      TargetCount := AllocateResourcesMessage.TargetCount;
      Assert(TargetCount > 0);
      SelectedOres.Clear();
      ApproximateMass := FMass.ToDouble();
      RemainingCount := 0;
      for OreIndex in TOres do
      begin
         Material := Encyclopedia.Materials[OreIndex];
         if ((FComposition[OreIndex].IsNotZero) and
             (mtSolid in Material.Tags) and
             ((mtEvenlyDistributed in Material.Tags) or
              ((mtDepth2 in Material.Tags) and (AllocateResourcesMessage.Depth >= 2)) or
              ((mtDepth3 in Material.Tags) and (AllocateResourcesMessage.Depth >= 3)) or
              (Material.Tags * [mtDepth2, mtDepth3] = []))) then
            Inc(RemainingCount);
      end;
      Index := 0;
      IncludedFraction := Fraction32.Zero;
      for OreIndex in TOres do
      begin
         if (FComposition[OreIndex].IsNotZero) then
         begin
            Material := Encyclopedia.Materials[OreIndex];
            if (mtSolid in Material.Tags) then
            begin
               ConsiderOre := False;
               if (mtEvenlyDistributed in Material.Tags) then
               begin
                  ConsiderOre := True;
                  IncludeOre := True;
               end
               else
               begin
                  if (mtDepth2 in Material.Tags) then
                  begin
                     ConsiderOre := AllocateResourcesMessage.Depth >= 2;
                  end
                  else
                  if (mtDepth3 in Material.Tags) then
                  begin
                     ConsiderOre := AllocateResourcesMessage.Depth >= 3;
                  end
                  else
                  begin
                     ConsiderOre := True;
                  end;
                  IncludeOre := ConsiderOre and AllocateResourcesMessage.CachedSystem.RandomNumberGenerator.GetBoolean(TargetCount / RemainingCount);
               end;
               if (IncludeOre) then
               begin
                  SelectedOres.Enable(OreIndex);
                  CurrentFraction := FComposition[OreIndex];
                  IncludedFraction := IncludedFraction + CurrentFraction;
                  Inc(Index);
                  Dec(TargetCount);
                  if (TargetCount = 0) then
                     break;
               end;
               if (ConsiderOre) then
                  Dec(RemainingCount);
            end;
         end;
      end;
      Assert((RemainingCount = 0) or (TargetCount = 0));
      Writeln('ALLOCATING ORES FROM ', Parent.DebugName);
      for OreIndex in TOres do
      begin
         if (SelectedOres[OreIndex]) then
         begin
            Material := CachedSystem.Encyclopedia.Materials[OreIndex];
            CandidateMass := (FComposition[OreIndex] / IncludedFraction) * (AllocateResourcesMessage.TargetQuantity * Material.MassPerUnit);
            MaxMass := FComposition[OreIndex] * ApproximateMass; // the amount of material that's left
            if (CandidateMass > MaxMass) then
            begin
               // finish it off
               FComposition[OreIndex].ResetToZero();
               AllocateResourcesMessage.AssignedOres[OreIndex] := Round(MaxMass / Material.MassPerUnit); // $R-
            end
            else
            begin
               // extract a little
               FComposition[OreIndex].Subtract(CandidateMass / ApproximateMass);
               AllocateResourcesMessage.AssignedOres[OreIndex] := RoundUInt64(CandidateMass / Material.MassPerUnit); // $R-
            end;
            FMass.Subtract(Int256.FromDouble(Material.MassPerUnit * AllocateResourcesMessage.AssignedOres[OreIndex]));
         end
         else
         begin
            AllocateResourcesMessage.AssignedOres[OreIndex] := 0;
         end;
         Writeln('  Ore #', OreIndex, ': ', AllocateResourcesMessage.AssignedOres[OreIndex]);
      end;
      Fraction32.NormalizeArray(@FComposition[Low(FComposition)], Length(FComposition)); // renormalize our composition
      MarkAsDirty([dkUpdateClients, dkUpdateJournal]);
      Result := mrHandled;
   end
   else
      Result := inherited;
end;

function TPlanetaryBodyFeatureNode.HandleBusMessage(Message: TBusMessage): Boolean;
begin
   if (Message is TRubbleCollectionMessage) then
   begin
      Assert(False, 'TPlanetaryBodyFeatureNode should never see TRubbleCollectionMessage');
   end;
   Result := False;
end;

procedure TPlanetaryBodyFeatureNode.Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter; CachedSystem: TSystem);
var
   Visibility: TVisibility;
begin
   Visibility := Parent.ReadVisibilityFor(DynastyIndex, CachedSystem);
   if ((dmDetectable * Visibility <> []) and (dmClassKnown in Visibility)) then
   begin
      Writer.WriteCardinal(fcPlanetaryBody);
   end;
end;

procedure TPlanetaryBodyFeatureNode.UpdateJournal(Journal: TJournalWriter; CachedSystem: TSystem);
var
   QuadIndex: Int256.TQuadIndex;
   OreIndex: TOres;
begin
   Journal.WriteDouble(FDiameter);
   for QuadIndex in Int256.TQuadIndex do
      Journal.WriteUInt64(FMass.AsQWords[QuadIndex]);
   Journal.WriteCardinal(Length(FComposition));
   Assert(Length(FComposition) > 0);
   for OreIndex := Low(FComposition) to High(FComposition) do // $R-
   begin
      Journal.WriteMaterialReference(CachedSystem.Encyclopedia.Materials[OreIndex]);
      Journal.WriteCardinal(FComposition[OreIndex].AsCardinal);
   end;
   Journal.WriteBoolean(FConsiderForDynastyStart);
   Journal.WriteDouble(FTemperature);
end;

procedure TPlanetaryBodyFeatureNode.ApplyJournal(Journal: TJournalReader; CachedSystem: TSystem);
var
   QuadIndex: Int256.TQuadIndex;
   Index, Count: Cardinal;
   Material: TMaterial;
begin
   FDiameter := Journal.ReadDouble();
   for QuadIndex in Int256.TQuadIndex do
      FMass.AsQWords[QuadIndex] := Journal.ReadUInt64();
   Count := Journal.ReadCardinal();
   Assert(Count <= Length(FComposition));
   Assert(Count > 0);
   Assert(SizeOf(DWord) = SizeOf(Fraction32));
   FillDWord(FComposition, Length(FComposition), 0);
   for Index := 0 to Count - 1 do // $R-
   begin
      Material := Journal.ReadMaterialReference();
      Assert(Material.ID >= Low(TOres));
      Assert(Material.ID <= High(TOres));
      FComposition[Material.ID].AsCardinal := Journal.ReadCardinal();
   end;
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
   Assert(FMass.IsNotZero);
   IsDefinitelyReal := True;
end;

initialization
   RegisterFeatureClass(TPlanetaryBodyFeatureClass);
end.