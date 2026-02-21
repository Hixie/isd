{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit planetary;

interface

uses
   systems, internals, serverstream, materials, tttokenizer, isdnumbers, masses;

type
   TAllocateOresBusMessage = class(TPhysicalConnectionBusMessage)
   strict private
      FDepth: Cardinal;
      FTargetCount: Cardinal;
   public
      AssignedOres: TOreQuantities;
      constructor Create(ADepth: Cardinal; ATargetCount: Cardinal);
      property Depth: Cardinal read FDepth;
      property TargetCount: Cardinal read FTargetCount;
   end;

   TPlanetaryBodyFeatureClass = class(TFeatureClass)
   strict protected
      FSeed: Cardinal;
      FDiameter: Double; // m
      FTemperature: Double; // K
      FComposition: TOreFractions; // fractions of total _mass_ (not units)
      FMass: Int256; // kg
      FConsiderForDynastyStart: Boolean;
      function GetFeatureNodeClass(): FeatureNodeReference; override;
   public
      constructor CreateFromTechnologyTree(const Reader: TTechTreeReader); override;
      function InitFeatureNode(ASystem: TSystem): TFeatureNode; override;
   end;

   TPlanetaryBodyFeatureNode = class(TFeatureNode)
   strict private
      FSeed: Cardinal;
      FDiameter: Double; // m
      FTemperature: Double; // K
      FComposition: TOreFractions; // fractions of total mass (not units)
      FMass: Int256; // kg
      FConsiderForDynastyStart: Boolean;
      function GetBondAlbedo(): Double;
   protected
      constructor CreateFromJournal(Journal: TJournalReader; AFeatureClass: TFeatureClass; ASystem: TSystem); override;
      function GetMass(): TMass; override; // kg
      function GetSize(): Double; override; // m
      function ManageBusMessage(Message: TBusMessage): TInjectBusMessageResult; override;
      function HandleBusMessage(Message: TBusMessage): THandleBusMessageResult; override;
      procedure Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter); override;
   public
      constructor Create(ASystem: TSystem; ASeed: Cardinal; ADiameter, ATemperature: Double; AComposition: TOreFractions; AMass: TMass; AConsiderForDynastyStart: Boolean); overload;
      constructor Create(ASystem: TSystem; ASeed: Cardinal; ADiameter, ATemperature: Double; AComposition: TOreFractions; AMass: Int256; AConsiderForDynastyStart: Boolean); overload;
      destructor Destroy(); override;
      procedure UpdateJournal(Journal: TJournalWriter); override;
      procedure ApplyJournal(Journal: TJournalReader); override;
      procedure SetTemperature(ATemperature: Double);
      procedure DescribeExistentiality(var IsDefinitelyReal, IsDefinitelyGhost: Boolean); override;
      property ConsiderForDynastyStart: Boolean read FConsiderForDynastyStart;
      property BondAlbedo: Double read GetBondAlbedo;
      property Temperature: Double read FTemperature; // K
   end;

const
   MaxUnitsPerOre = 1 << 62; // the actual max would be 2^63-1 but having some headroom for floating point approximation when converting to and from doubles avoids some confusion

implementation

uses
   isdprotocol, sysutils, exceptions, math, rubble, commonbuses, ttparser;

constructor TAllocateOresBusMessage.Create(ADepth: Cardinal; ATargetCount: Cardinal);
begin
   inherited Create();
   FDepth := ADepth;
   FTargetCount := ATargetCount;
end;

constructor TPlanetaryBodyFeatureClass.CreateFromTechnologyTree(const Reader: TTechTreeReader);
var
   Material: TMaterial;
   WeightValue: Cardinal;
   PlanetMass: TMass;
begin
   inherited Create();
   if (Reader.Tokens.IsIdentifier()) then
   begin
      Reader.Tokens.ReadIdentifier('seed');
      FSeed := ReadNumber(Reader.Tokens, Low(Cardinal), High(Cardinal)); // $R-
      Reader.Tokens.ReadComma();
      Reader.Tokens.ReadIdentifier('diameter');
      FDiameter := ReadLength(Reader.Tokens);
      if (FDiameter <= 0.0) then
         Reader.Tokens.Error('Diameter must be greater than zero', []);
      Reader.Tokens.ReadComma();
      Reader.Tokens.ReadIdentifier('temperature');
      FTemperature := ReadNumber(Reader.Tokens, 0, High(Int64));
      Reader.Tokens.ReadIdentifier('K');
      Reader.Tokens.ReadComma();
      Reader.Tokens.ReadIdentifier('mass');
      PlanetMass := ReadMass(Reader.Tokens);
      FMass := Int256.FromDouble(PlanetMass.AsDouble);
      Reader.Tokens.ReadOpenParenthesis();
      repeat
         Material := ReadMaterial(Reader);
         if ((Material.ID < Low(TOres)) or (Material.ID > High(TOres))) then
            Reader.Tokens.Error('Material "%s" is not an ore and cannot be used in a planetary body composition', [Material.Name]);
         WeightValue := ReadNumber(Reader.Tokens, Low(Cardinal), High(Cardinal)); // $R-
         if (WeightValue <= 0) then
            Reader.Tokens.Error('Composition weights must be greater than zero', []);
         FComposition[Material.ID] := Fraction32.FromCardinal(WeightValue);
         if (Reader.Tokens.IsCloseParenthesis()) then
            break;
         Reader.Tokens.ReadComma();
      until False;
      Reader.Tokens.ReadCloseParenthesis();
      Fraction32.NormalizeArray(@FComposition[Low(FComposition)], Length(FComposition));
      if (Reader.Tokens.IsComma()) then
      begin
         Reader.Tokens.ReadComma();
         Reader.Tokens.ReadIdentifier('can-be-dynasty-start');
         FConsiderForDynastyStart := True;
      end;
   end;
end;

function TPlanetaryBodyFeatureClass.GetFeatureNodeClass(): FeatureNodeReference;
begin
   Result := TPlanetaryBodyFeatureNode;
end;

function TPlanetaryBodyFeatureClass.InitFeatureNode(ASystem: TSystem): TFeatureNode;
begin
   Result := TPlanetaryBodyFeatureNode.Create(ASystem, FSeed, FDiameter, FTemperature, FComposition, FMass, FConsiderForDynastyStart);
end;


constructor TPlanetaryBodyFeatureNode.Create(ASystem: TSystem; ASeed: Cardinal; ADiameter, ATemperature: Double; AComposition: TOreFractions; AMass: TMass; AConsiderForDynastyStart: Boolean);
begin
   inherited Create(ASystem);
   FSeed := ASeed;
   FDiameter := ADiameter;
   FTemperature := ATemperature;
   FComposition := AComposition;
   FMass := Int256.FromDouble(AMass.AsDouble);
   FConsiderForDynastyStart := AConsiderForDynastyStart;
end;

constructor TPlanetaryBodyFeatureNode.Create(ASystem: TSystem; ASeed: Cardinal; ADiameter, ATemperature: Double; AComposition: TOreFractions; AMass: Int256; AConsiderForDynastyStart: Boolean);
begin
   inherited Create(ASystem);
   FSeed := ASeed;
   FDiameter := ADiameter;
   FTemperature := ATemperature;
   FComposition := AComposition;
   FMass := AMass;
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

function TPlanetaryBodyFeatureNode.GetMass(): TMass; // kg
begin
   Result := TMass.FromKg(FMass);
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

function TPlanetaryBodyFeatureNode.ManageBusMessage(Message: TBusMessage): TInjectBusMessageResult;
var
   AllocateResourcesMessage: TAllocateOresBusMessage;
   LimitingOre: TOres;
   LimitingQuantity, LimitingQuantityCandidate: Double;
   LimitingMass: TMass;
   OreIndex: TOres;
   Material: TMaterial;
   ConsiderOre, IncludeOre: Boolean;
   TargetCount, RemainingCount, Index: Cardinal;
   IncludedFraction: Fraction32;
   ApproximateMass, CandidateMass: TMass;
   SelectedOres: TOreFilter;
   CandidateQuantity: TQuantity64;
begin
   if (Message is TAllocateOresBusMessage) then
   begin
      Writeln('ALLOCATING ORES FROM ', Parent.DebugName);
      AllocateResourcesMessage := Message as TAllocateOresBusMessage;
      TargetCount := AllocateResourcesMessage.TargetCount;
      Assert(TargetCount > 0);
      SelectedOres.Clear();
      ApproximateMass := TMass.FromKg(FMass);
      RemainingCount := 0;
      // FComposition[Ore] is the fraction of the mass of the planet that is of that ore
      // ApproximateMass is the mass of the planet (as a double)
      for OreIndex in TOres do
      begin
         Material := System.Encyclopedia.Materials[OreIndex];
         if ((FComposition[OreIndex].IsNotZero) and
             (mtSolid in Material.Tags) and
             ((mtEvenlyDistributed in Material.Tags) or
              ((mtDepth2 in Material.Tags) and (AllocateResourcesMessage.Depth >= 2)) or
              ((mtDepth3 in Material.Tags) and (AllocateResourcesMessage.Depth >= 3)) or
              (Material.Tags * [mtDepth2, mtDepth3] = []))) then
            Inc(RemainingCount);
      end;
      Index := 0;
      IncludedFraction := Fraction32.Zero; // fraction of planet mass that we are considering including in the region
      for OreIndex in TOres do
      begin
         if (FComposition[OreIndex].IsNotZero) then
         begin
            Material := System.Encyclopedia.Materials[OreIndex];
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
                  IncludeOre := ConsiderOre and System.RandomNumberGenerator.GetBoolean(TargetCount / RemainingCount);
               end;
               if (IncludeOre) then
               begin
                  SelectedOres.Enable(OreIndex);
                  IncludedFraction := IncludedFraction + FComposition[OreIndex]; // fraction of mass
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

      // first determine the limiting ore
      // this is the one where the included fraction results in the largest quantity
      LimitingQuantity := 0.0;
      LimitingOre := Low(TOres); // this line should not matter
      for OreIndex in TOres do
      begin
         if (SelectedOres[OreIndex]) then
         begin
            Material := System.Encyclopedia.Materials[OreIndex];
            LimitingQuantityCandidate := FComposition[OreIndex] / Material.MassPerUnit.AsDouble;
            Assert(LimitingQuantityCandidate > 0);
            if (LimitingQuantityCandidate > LimitingQuantity) then
            begin
               LimitingOre := OreIndex;
               LimitingQuantity := LimitingQuantityCandidate;
            end;
         end;
      end;

      // now compute the fraction we want to include
      // the goal is to max out the LimitingOre
      Material := System.Encyclopedia.Materials[LimitingOre];
      LimitingMass := (TQuantity64.FromUnits(MaxUnitsPerOre) * Material.MassPerUnit) / FComposition[LimitingOre]; // TQuantity64.Max is the most we could put in
      if (LimitingMass > FComposition[LimitingOre] * ApproximateMass) then
         LimitingMass := FComposition[LimitingOre] * ApproximateMass;

      // actually assign the ores, in quantities
      for OreIndex in TOres do
      begin
         if (SelectedOres[OreIndex]) then
         begin
            Material := System.Encyclopedia.Materials[OreIndex];
            CandidateMass := FComposition[OreIndex] * LimitingMass;
            CandidateQuantity := CandidateMass div Material.MassPerUnit;
            CandidateMass := CandidateQuantity * Material.MassPerUnit;
            FComposition[OreIndex].ReduceBy(Fraction32.FromDouble(CandidateMass / ApproximateMass));
            AllocateResourcesMessage.AssignedOres[OreIndex] := CandidateQuantity;
            FMass.Subtract(Int256.FromDouble(CandidateMass.AsDouble));
            Writeln('  ', Material.Name, ' (ore #', OreIndex, '): ', AllocateResourcesMessage.AssignedOres[OreIndex].ToString(), ' (', (AllocateResourcesMessage.AssignedOres[OreIndex] * Material.MassPerUnit).ToString(), ')');
         end
         else
         begin
            AllocateResourcesMessage.AssignedOres[OreIndex] := TQuantity64.Zero;
         end;
      end;
      Fraction32.NormalizeArray(@FComposition[Low(FComposition)], Length(FComposition)); // renormalize our composition
      MarkAsDirty([dkUpdateClients, dkUpdateJournal]);
      Result := irHandled;
   end
   else
      Result := inherited;
end;

function TPlanetaryBodyFeatureNode.HandleBusMessage(Message: TBusMessage): THandleBusMessageResult;
begin
   Assert(not ((Message is TRubbleCollectionMessage) or (Message is TDismantleMessage)), ClassName + ' should never see ' + Message.ClassName);
   Result := inherited;
end;

procedure TPlanetaryBodyFeatureNode.Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter);
var
   Visibility: TVisibility;
begin
   Visibility := Parent.ReadVisibilityFor(DynastyIndex);
   if (dmDetectable * Visibility <> []) then
   begin
      Writer.WriteCardinal(fcPlanetaryBody);
      Writer.WriteCardinal(FSeed);
   end;
end;

procedure TPlanetaryBodyFeatureNode.UpdateJournal(Journal: TJournalWriter);
var
   QuadIndex: Int256.TQuadIndex;
   OreIndex: TOres;
begin
   Journal.WriteCardinal(FSeed);
   Journal.WriteDouble(FDiameter);
   Journal.WriteDouble(FTemperature);
   for QuadIndex in Int256.TQuadIndex do
      Journal.WriteUInt64(FMass.AsQWords[QuadIndex]);
   Journal.WriteCardinal(Length(FComposition));
   Assert(Length(FComposition) > 0);
   for OreIndex := Low(FComposition) to High(FComposition) do // $R-
   begin
      Journal.WriteMaterialReference(System.Encyclopedia.Materials[OreIndex]);
      Journal.WriteCardinal(FComposition[OreIndex].AsCardinal);
   end;
   Journal.WriteBoolean(FConsiderForDynastyStart);
end;

procedure TPlanetaryBodyFeatureNode.ApplyJournal(Journal: TJournalReader);
var
   QuadIndex: Int256.TQuadIndex;
   Index, Count: Cardinal;
   Material: TMaterial;
begin
   FSeed := Journal.ReadCardinal();
   FDiameter := Journal.ReadDouble();
   FTemperature := Journal.ReadDouble();
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