{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit region;

interface

{$DEFINE VERBOSE}

uses
   systems, serverstream, techtree, materials, time, providers;

type
   TRegionFeatureNode = class;

   TRegionClientMode = (rcIdle, rcPending, rcActive, rcNoRegion);
   TRegionClientFields = packed record
      Region: TRegionFeatureNode; // 8 bytes
      Rate: TRate; // 8 bytes
      Enabled: Boolean;
      SourceLimiting, TargetLimiting: Boolean;
      Mode: TRegionClientMode;
   end;
   {$IF SIZEOF(TRegionClientMode) > 3*8} {$FATAL} {$ENDIF}
      
   IMiner = interface ['IMiner']
      function GetMinerMaxRate(): TRate; // kg per second
      function GetMinerCurrentRate(): TRate; // kg per second
      procedure StartMiner(Region: TRegionFeatureNode; Rate: TRate; SourceLimiting, TargetLimiting: Boolean);
      procedure StopMiner();
   end;
   TRegisterMinerBusMessage = specialize TRegisterProviderBusMessage<TPhysicalConnectionBusMessage, IMiner>;
   TMinerHashSet = specialize TProviderSet<IMiner>;

   IOrePile = interface ['IOrePile']
      function GetOrePileCapacity(): Double; // kg
      procedure StartOrePile(Region: TRegionFeatureNode);
      procedure StopOrePile();
   end;
   TRegisterOrePileBusMessage = specialize TRegisterProviderBusMessage<TPhysicalConnectionBusMessage, IOrePile>;
   TOrePileHashSet = specialize TProviderSet<IOrePile>;

   IRefinery = interface ['IRefinery']
      function GetRefineryOre(): TOres;
      function GetRefineryMaxRate(): TRate; // kg per second
      function GetRefineryCurrentRate(): TRate; // kg per second
      procedure StartRefinery(Region: TRegionFeatureNode; Rate: TRate; SourceLimiting, TargetLimiting: Boolean); // kg per second
      procedure StopRefinery();
   end;
   TRegisterRefineryBusMessage = specialize TRegisterProviderBusMessage<TPhysicalConnectionBusMessage, IRefinery>;
   TRefineryHashSet = specialize TProviderSet<IRefinery>;

   IMaterialPile = interface ['IMaterialPile']
      function GetMaterialPileMaterial(): TMaterial;
      function GetMaterialPileCapacity(): UInt64; // quantity
      procedure StartMaterialPile(Region: TRegionFeatureNode);
      procedure StopMaterialPile();
   end;
   TRegisterMaterialPileBusMessage = specialize TRegisterProviderBusMessage<TPhysicalConnectionBusMessage, IMaterialPile>;
   TMaterialPileHashSet = specialize TProviderSet<IMaterialPile>;

   TRegionFeatureClass = class(TFeatureClass)
   strict private
      FDepth: Cardinal;
      FTargetCount: Cardinal;
      FTargetQuantity: UInt64;
   strict protected
      function GetFeatureNodeClass(): FeatureNodeReference; override;
   public
      constructor Create(ADepth: Cardinal; ATargetCount: Cardinal; ATargetQuantity: UInt64);
      constructor CreateFromTechnologyTree(Reader: TTechTreeReader); override;
      function InitFeatureNode(): TFeatureNode; override;
      property Depth: Cardinal read FDepth;
      property TargetCount: Cardinal read FTargetCount;
      property TargetQuantity: UInt64 read FTargetQuantity;
   end;
   
   TRegionFeatureNode = class(TFeatureNode)
   private
      // The mass contained in FOrePileComposition is distributed
      // evenly to the FOrePiles (in the sense that each ore pile is
      // the same % full).
      // Ground truth:
      FGroundComposition: TOreQuantities;
      FOrePileComposition: TOreQuantities;
      FMaterialPileComposition: TMaterialQuantityHashTable;
      FAnchorTime: TTimeInMilliseconds; // set to Low(FAnchorTime) or Now when transfers are currently synced
      FAllocatedOres: Boolean; // TODO: find a way to make this bit cost 32 times less than it does now
      // Runtime admin variables:
      FFeatureClass: TRegionFeatureClass;
      FMiners: TMinerHashSet;
      FOrePiles: TOrePileHashSet;
      FRefineries: TRefineryHashSet;
      FMaterialPiles: TMaterialPileHashSet;
      FNextEvent: TSystemEvent; // set only when mass is moving
      FActive: Boolean; // set to true when transfers are set up, set to false when transfers need to be set up
      function GetTotalOrePileCapacity(): Double; // kg total for all piles
      function GetTotalOrePileMass(): Double; // kg total for all piles
      function GetTotalOrePileMassFlowRate(): TRate; // kg/s (total for all piles; total miner rate minus total refinery rate)
      function GetMinOreMassTransfer(CachedSystem: TSystem): Double; // kg mass that would need to be transferred to move at least one unit of quantity
      function GetTotalMaterialPileQuantity(Material: TMaterial): UInt64;
      function GetTotalMaterialPileQuantityFlowRate(Material: TMaterial): TRate; // units/s
      function GetTotalMaterialPileCapacity(Material: TMaterial): UInt64;
      function GetTotalMaterialPileMass(Material: TMaterial): Double; // kg
      function GetTotalMaterialPileMassFlowRate(Material: TMaterial): TRate; // kg/s
      procedure IncMaterialPile(Material: TMaterial; Delta: UInt64);
   protected
      constructor CreateFromJournal(Journal: TJournalReader; AFeatureClass: TFeatureClass; ASystem: TSystem); override;
      function GetMass(): Double; override;
      function GetMassFlowRate(): TRate; override;
      function ManageBusMessage(Message: TBusMessage): TBusMessageResult; override;
      procedure Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter; CachedSystem: TSystem); override;
      procedure Sync(); // move the ores around
      procedure Reset(); // tell our clients we're going to renegotiate the deal
      procedure Stop(); // cancel the current scheduled event, sync, and stop
      procedure HandleChanges(CachedSystem: TSystem); override;
      procedure ReconsiderEverything(var Data);
   public
      constructor Create(AFeatureClass: TRegionFeatureClass);
      destructor Destroy(); override;
      procedure UpdateJournal(Journal: TJournalWriter; CachedSystem: TSystem); override;
      procedure ApplyJournal(Journal: TJournalReader; CachedSystem: TSystem); override;
      procedure DescribeExistentiality(var IsDefinitelyReal, IsDefinitelyGhost: Boolean); override;
      procedure RemoveMiner(Miner: IMiner);
      procedure RemoveOrePile(OrePile: IOrePile);
      procedure RemoveRefinery(Refinery: IRefinery);
      procedure RemoveMaterialPile(MaterialPile: IMaterialPile);
      function GetOrePileMass(Pile: IOrePile): Double; // kg
      function GetOrePileMassFlowRate(Pile: IOrePile): TRate; // kg/s
      function GetOresPresent(): TOreFilter;
      function GetOresForPile(Pile: IOrePile): TOreQuantities;
      function GetMaterialPileMass(Pile: IMaterialPile): Double; // kg
      function GetMaterialPileMassFlowRate(Pile: IMaterialPile): TRate; // kg/s
      function GetMaterialPileQuantity(Pile: IMaterialPile): Int64; // units
      function GetMaterialPileQuantityFlowRate(Pile: IMaterialPile): TRate; // units/s
   end;
   
implementation

uses
   sysutils, planetary, exceptions, messages, isdprotocol, isdnumbers, math, hashfunctions;

constructor TRegionFeatureClass.Create(ADepth: Cardinal; ATargetCount: Cardinal; ATargetQuantity: UInt64);
begin
   inherited Create();
   FDepth := ADepth;
   FTargetCount := ATargetCount;
   FTargetQuantity := ATargetQuantity;
end;

constructor TRegionFeatureClass.CreateFromTechnologyTree(Reader: TTechTreeReader);
begin
   inherited Create();
   Reader.Tokens.ReadIdentifier('at');
   Reader.Tokens.ReadIdentifier('depth');
   FDepth := ReadNumber(Reader.Tokens, Low(FDepth), High(FDepth)); // $R-
   Reader.Tokens.ReadComma();
   FTargetCount := ReadNumber(Reader.Tokens, 1, 63); // $R-
   if (FTargetCount = 1) then
      Reader.Tokens.ReadIdentifier('material')
   else
      Reader.Tokens.ReadIdentifier('materials');
   if (Reader.Tokens.IsIdentifier('of')) then
   begin
      Reader.Tokens.ReadIdentifier('of');
      Reader.Tokens.ReadIdentifier('quantity');
      FTargetQuantity := ReadNumber(Reader.Tokens, 1, High(Int64)); // TODO: allow bigger numbers (up to UInt64) // $R-
   end
   else
      FTargetQuantity := High(FTargetQuantity);
end;

function TRegionFeatureClass.GetFeatureNodeClass(): FeatureNodeReference;
begin
   Result := TRegionFeatureNode;
end;

function TRegionFeatureClass.InitFeatureNode(): TFeatureNode;
begin
   Result := nil;
   raise Exception.Create('Cannot create a TRegionFeatureNode from a prototype, it must have an ore composition from an ancestor TPlanetaryBodyFeatureNode.');
end;


constructor TRegionFeatureNode.Create(AFeatureClass: TRegionFeatureClass);
begin
   inherited Create();
   FFeatureClass := AFeatureClass;
   FAnchorTime := TTimeInMilliseconds.NegInfinity;
end;

constructor TRegionFeatureNode.CreateFromJournal(Journal: TJournalReader; AFeatureClass: TFeatureClass; ASystem: TSystem);
begin
   inherited CreateFromJournal(Journal, AFeatureClass, ASystem);
   FFeatureClass := AFeatureClass as TRegionFeatureClass;
   Assert(Assigned(AFeatureClass));
   FAnchorTime := TTimeInMilliseconds.NegInfinity;
end;

destructor TRegionFeatureNode.Destroy();
begin
   if (FActive) then
   begin
      if (Assigned(FNextEvent)) then
      begin
         FNextEvent.Cancel();
         FNextEvent := nil;
      end;
      Reset();
   end;
   FMiners.Free();
   FOrePiles.Free();
   FRefineries.Free();
   FMaterialPiles.Free();
   FMaterialPileComposition.Free();
   inherited;
end;

function TRegionFeatureNode.GetMass(): Double;
var
   Ore: TOres;
   CachedSystem: TSystem;
   Encyclopedia: TEncyclopediaView;
begin
   CachedSystem := System;
   Encyclopedia := CachedSystem.Encyclopedia;
   Result := 0.0;
   Assert(Length(FGroundComposition) > 0);
   for Ore := Low(FGroundComposition) to High(FGroundComposition) do // $R-
      Result := Result + Encyclopedia.Materials[Ore].MassPerUnit * FGroundComposition[Ore];
   // The ore pile composition (see GetOrePileMass) and the material
   // pile composition are exposed on the various pile assets.
   if (Assigned(FNextEvent)) then
      Result := Result + (CachedSystem.Now - FAnchorTime) * MassFlowRate;
end;

function TRegionFeatureNode.GetMassFlowRate(): TRate;
var
   Miner: IMiner;
begin
   Result := TRate.Zero;
   if (Assigned(FMiners) and Assigned(FNextEvent)) then
   begin
      for Miner in FMiners do
      begin
         Result := Result - Miner.GetMinerCurrentRate();
      end;
   end;
   // Refineries, factories, and consumers affect the flow rates of
   // the pile assets (see e.g. GetOrePileMassFlowRate below).
end;

function TRegionFeatureNode.GetTotalOrePileCapacity(): Double; // kg total for all piles
var
   OrePile: IOrePile;
begin
   Result := 0.0;
   if (Assigned(FOrePiles)) then
   begin
      for OrePile in FOrePiles do
         Result := Result + OrePile.GetOrePileCapacity();
   end;
end;

function TRegionFeatureNode.GetTotalOrePileMass(): Double; // kg total for all piles
var
   Ore: TOres;
   CachedSystem: TSystem;
   Encyclopedia: TEncyclopediaView;
begin
   CachedSystem := System;
   Encyclopedia := CachedSystem.Encyclopedia;
   Result := 0.0;
   if (Length(FOrePileComposition) > 0) then
      for Ore := Low(FOrePileComposition) to High(FOrePileComposition) do // $R-
      begin
         Result := Result + Encyclopedia.Materials[Ore].MassPerUnit * FOrePileComposition[Ore];
      end;
   Assert(Result >= 0.0);
   if (Assigned(FNextEvent)) then
   begin
      Assert(not FAnchorTime.IsInfinite);
      Result := Result + (CachedSystem.Now - FAnchorTime) * GetTotalOrePileMassFlowRate();
   end;
   Assert(Result >= 0.0);
end;

function TRegionFeatureNode.GetTotalOrePileMassFlowRate(): TRate; // kg/s (miner rate minus refinery rate)
var
   Miner: IMiner;
   Refinery: IRefinery;
begin
   Result := TRate.Zero;
   if (Assigned(FMiners) and Assigned(FNextEvent)) then
   begin
      for Miner in FMiners do
         Result := Result + Miner.GetMinerCurrentRate();
   end;
   if (Assigned(FRefineries)) then
   begin
      for Refinery in FRefineries do
         Result := Result - Refinery.GetRefineryCurrentRate();
   end;
end;

function TRegionFeatureNode.GetOrePileMass(Pile: IOrePile): Double; // kg
var
   PileRatio: Double;
begin
   PileRatio := Pile.GetOrePileCapacity() / GetTotalOrePileCapacity();
   Result := GetTotalOrePileMass() * PileRatio;
end;

function TRegionFeatureNode.GetOrePileMassFlowRate(Pile: IOrePile): TRate; // kg/s
var
   RPileRatio: Double;
begin
   // We do it in this weird order to reduce the incidence of floating point error creep.
   // It's weird but fractions are bad, and doing it this way avoids fractions.
   // (I say this is a weird order because to me the intuitive way to do this is to get
   // the PileRation, Pile.GetOrePileCapacity() / GetTotalOrePileCapacity(), and then
   // multiply the GetTotalOrePileMassFlowRate() by that number.)
   RPileRatio := GetTotalOrePileCapacity() / Pile.GetOrePileCapacity();
   Result := GetTotalOrePileMassFlowRate() / RPileRatio;
end;

function TRegionFeatureNode.GetMinOreMassTransfer(CachedSystem: TSystem): Double;
var
   Ore: TOres;
   Quantity: UInt64;
   TransferMassPerUnit, Min: Double;
   Encyclopedia: TEncyclopediaView;
begin
   Encyclopedia := CachedSystem.Encyclopedia;
   Min := Encyclopedia.MinMassPerOreUnit;
   {$PUSH} {$IEEEERRORS-} Result := Infinity; {$POP}
   for Ore in TOres do
   begin
      Quantity := FGroundComposition[Ore];
      if (Quantity > 0) then
      begin
         TransferMassPerUnit := Encyclopedia.Materials[Ore].MassPerUnit;
         if (TransferMassPerUnit < Result) then
            Result := TransferMassPerUnit;
         if (Result <= Min) then
         begin
            exit;
         end;
      end;
   end;
end;

function TRegionFeatureNode.GetTotalMaterialPileQuantity(Material: TMaterial): UInt64;
begin
   if (not Assigned(FMaterialPileComposition)) then
   begin
      Result := 0;
   end
   else
   if (not FMaterialPileComposition.Has(Material)) then
   begin
      Result := 0;
   end
   else
   begin
      Result := FMaterialPileComposition[Material];
   end;
   if (Assigned(FNextEvent)) then
   begin
      Inc(Result, Round((System.Now - FAnchorTime) * GetTotalMaterialPileQuantityFlowRate(Material)));
   end;
end;

function TRegionFeatureNode.GetTotalMaterialPileQuantityFlowRate(Material: TMaterial): TRate; // units/s
var
   Refinery: IRefinery;
begin
   Result := TRate.Zero;
   if (Assigned(FRefineries) and Material.IsOre) then
   begin
      for Refinery in FRefineries do
      begin
         if (Refinery.GetRefineryOre() = Material.ID) then
            Result := Result + Refinery.GetRefineryCurrentRate() / Material.MassPerUnit;
      end;
   end;
   // TODO: factories (consumption, generation)
   // TODO: consumers (structures, etc)
end;

function TRegionFeatureNode.GetTotalMaterialPileCapacity(Material: TMaterial): UInt64;
var
   Pile: IMaterialPile;
begin
   Result := 0;
   if (Assigned(FMaterialPiles)) then
   begin
      for Pile in FMaterialPiles do
         Inc(Result, Pile.GetMaterialPileCapacity());
   end;
end;

function TRegionFeatureNode.GetTotalMaterialPileMass(Material: TMaterial): Double; // kg
begin
   if (not Assigned(FMaterialPileComposition)) then
   begin
      Result := 0;
   end
   else
   if (not FMaterialPileComposition.Has(Material)) then
   begin
      Result := 0;
   end
   else
   begin
      Result := FMaterialPileComposition[Material] * Material.MassPerUnit;
   end;
   if (Assigned(FNextEvent)) then
   begin
      Result := Result + (System.Now - FAnchorTime) * GetTotalMaterialPileMassFlowRate(Material);
   end;
end;

function TRegionFeatureNode.GetTotalMaterialPileMassFlowRate(Material: TMaterial): TRate; // kg/s
var
   Refinery: IRefinery;
begin
   Result := TRate.Zero;
   if (Assigned(FRefineries) and Material.IsOre) then
   begin
      for Refinery in FRefineries do
      begin
         if (Refinery.GetRefineryOre() = Material.ID) then
            Result := Result + Refinery.GetRefineryCurrentRate();
      end;
   end;
   // TODO: factories (consumption, generation)
   // TODO: consumers (structures, etc)
end;

procedure TRegionFeatureNode.IncMaterialPile(Material: TMaterial; Delta: UInt64);
begin
   Assert(Assigned(Material));
   Assert(Delta <> 0);
   if (not Assigned(FMaterialPileComposition)) then
   begin
      FMaterialPileComposition := TMaterialQuantityHashTable.Create(1);
   end;
   FMaterialPileComposition.Inc(Material, Delta);
end;

function TRegionFeatureNode.ManageBusMessage(Message: TBusMessage): TBusMessageResult;
var
   CachedSystem: TSystem;

   procedure CacheSystem(); inline;
   begin
      if (not Assigned(CachedSystem)) then
         CachedSystem := System;
   end;

var
   MinerMessage: TRegisterMinerBusMessage;
   OrePileMessage: TRegisterOrePileBusMessage;
   RefineryMessage: TRegisterRefineryBusMessage;
   MaterialPileMessage: TRegisterMaterialPileBusMessage;
begin
   if (Message is TRegisterMinerBusMessage) then
   begin
      if (FActive) then
         Stop();
      MinerMessage := Message as TRegisterMinerBusMessage;
      if (not Assigned(FMiners)) then
         FMiners := TMinerHashSet.Create();
      Assert(not FMiners.Has(MinerMessage.Provider));
      FMiners.Add(MinerMessage.Provider);
      MarkAsDirty([dkUpdateClients, dkUpdateJournal, dkNeedsHandleChanges]);
      Result := mrHandled;
      Writeln('  ', Parent.DebugName, ': Registered a new miner, now ', FMiners.Count, ' miners');
   end
   else
   if (Message is TRegisterOrePileBusMessage) then
   begin
      if (FActive) then
         Stop();
      OrePileMessage := Message as TRegisterOrePileBusMessage;
      if (not Assigned(FOrePiles)) then
         FOrePiles := TOrePileHashSet.Create();
      Assert(not FOrePiles.Has(OrePileMessage.Provider));
      FOrePiles.Add(OrePileMessage.Provider);
      MarkAsDirty([dkUpdateClients, dkUpdateJournal, dkNeedsHandleChanges]);
      Result := mrHandled;
      Writeln('  ', Parent.DebugName, ': Registered a new ore pile, now ', FOrePiles.Count, ' ore piles');
   end
   else
   if (Message is TRegisterRefineryBusMessage) then
   begin
      if (FActive) then
         Stop();
      RefineryMessage := Message as TRegisterRefineryBusMessage;
      if (not Assigned(FRefineries)) then
         FRefineries := TRefineryHashSet.Create();
      Assert(not FRefineries.Has(RefineryMessage.Provider));
      FRefineries.Add(RefineryMessage.Provider);
      MarkAsDirty([dkUpdateClients, dkUpdateJournal, dkNeedsHandleChanges]);
      Result := mrHandled;
      Writeln('  ', Parent.DebugName, ': Registered a new refinery, now ', FRefineries.Count, ' refineries');
   end
   else
   if (Message is TRegisterMaterialPileBusMessage) then
   begin
      if (FActive) then
         Stop();
      MaterialPileMessage := Message as TRegisterMaterialPileBusMessage;
      if (not Assigned(FMaterialPiles)) then
         FMaterialPiles := TMaterialPileHashSet.Create();
      Assert(not FMaterialPiles.Has(MaterialPileMessage.Provider));
      FMaterialPiles.Add(MaterialPileMessage.Provider);
      MarkAsDirty([dkUpdateClients, dkUpdateJournal, dkNeedsHandleChanges]);
      Result := mrHandled;
      Writeln('  ', Parent.DebugName, ': Registered a new material pile, now ', FMaterialPiles.Count, ' material piles');
   end
   else
      Result := mrDeferred;
end;

procedure TRegionFeatureNode.Sync();
var
   Miner: IMiner;
   OrePile: IOrePile;
   Refinery: IRefinery;
   Rate: TRate;
   TotalCompositionMass, TotalTransferMass, ApproximateTransferQuantity, ActualTransfer, CurrentOrePileMass, OrePileCapacity: Double;
   {$IFDEF DEBUG}
   OrePileRecordedMass: Double;
   FlowRate: TRate;
   {$ENDIF}
   SyncDuration: TMillisecondsDuration;
   Ore: TOres;
   Material: TMaterial;
   CachedSystem: TSystem;
   Encyclopedia: TEncyclopediaView;
   Quantity: UInt64;
   TransferQuantity: UInt64;
   Distribution: TOreFractions;
   RefinedOreMasses: array[TOres] of Double;
begin
   Writeln('  ', Parent.DebugName, ': SYNCHRONIZING FOR ', Parent.DebugName);
   Assert(Assigned(FNextEvent));
   CachedSystem := System;
   Encyclopedia := CachedSystem.Encyclopedia;
   SyncDuration := CachedSystem.Now - FAnchorTime;
   Writeln('    duration: ', SyncDuration.ToString(), ' (Now=', CachedSystem.Now.ToString(), ', anchor time=', FAnchorTime.ToString(), ')');

   OrePileCapacity := 0.0;
   if (Assigned(FOrePiles)) then
   begin
      for OrePile in FOrePiles do
      begin
         OrePileCapacity := OrePileCapacity + OrePile.GetOrePileCapacity();
      end;
   end;
   
   {$IFDEF DEBUG}
   if (Assigned(FOrePiles)) then
   begin
      FlowRate := GetTotalOrePileMassFlowRate();
      CurrentOrePileMass := GetTotalOrePileMass();
      OrePileRecordedMass := 0.0;
      if (Length(FOrePileComposition) > 0) then
         for Ore := Low(FOrePileComposition) to High(FOrePileComposition) do // $R-
         begin
            OrePileRecordedMass := OrePileRecordedMass + Encyclopedia.Materials[Ore].MassPerUnit * FOrePileComposition[Ore];
         end;
      Writeln('    we started with ', OrePileCapacity:0:1, 'kg ore pile capacity and ', CurrentOrePileMass:0:1, 'kg in ', FOrePiles.Count, ' ore piles (of which ', OrePileRecordedMass:0:1, 'kg is recorded)');
      Assert(CurrentOrePileMass <= OrePileCapacity, 'already over capacity');
      Writeln('    we get to that by multiplying the total ore pile mass flow rate, ', FlowRate.ToString('kg'), ', by the elapsed time, ', SyncDuration.ToString());
   end;
   {$ENDIF}

   if (Assigned(FMiners)) then
   begin
      TotalCompositionMass := 0.0;
      Assert(Length(FGroundComposition) > 0);
      for Ore := Low(FGroundComposition) to High(FGroundComposition) do // $R-
         TotalCompositionMass := TotalCompositionMass + Encyclopedia.Materials[Ore].MassPerUnit * FGroundComposition[Ore];
      TotalTransferMass := 0.0;
      for Miner in FMiners do
      begin
         Rate := Miner.GetMinerMaxRate(); // Not the current rate; the difference is handled by us dumping excess back into the ground.
         TotalTransferMass := TotalTransferMass + SyncDuration * Rate;
         Writeln('    transfer mass for this miner (rate ', Rate.ToString('kg'), ') is ', (SyncDuration * Rate):0:1, 'kg; TotalCompositionMass is ', TotalCompositionMass:0:1);
      end;
      Writeln('    total ideal mass transfer: ', TotalTransferMass:0:1, 'kg');
      ActualTransfer := 0.0;
      for Ore in TOres do
      begin
         Quantity := FGroundComposition[Ore];
         if (Quantity > 0) then
         begin
            Assert(TotalTransferMass >= 0);
            Assert(Encyclopedia.Materials[Ore].MassPerUnit > 0);
            Assert(TotalTransferMass * Encyclopedia.Materials[Ore].MassPerUnit < High(TransferQuantity));
            // The actual transferred quantity is:
            //   ThisOreMass := Quantity * Encyclopedia.Materials[Ore].MassPerUnit;
            //   ThisTransferMass := ThisOreMass * (TotalTransferMass / TotalCompositionMass);
            //   ApproximateTransferQuantity := ThisTransferMass / Encyclopedia.Materials[Ore].MassPerUnit;
            // which simplifies to:
            ApproximateTransferQuantity := Quantity * (TotalTransferMass / TotalCompositionMass);
            TransferQuantity := TruncUInt64(ApproximateTransferQuantity);
            Assert(TransferQuantity <= Quantity, 'region composition underflow');
            Dec(FGroundComposition[Ore], TransferQuantity);
            Assert(High(FOrePileComposition[Ore]) - FOrePileComposition[Ore] >= TransferQuantity);
            Writeln('      moving ', TransferQuantity, ' units of ore ', Ore, ', ', Encyclopedia.Materials[Ore].Name, ' (', Encyclopedia.Materials[Ore].MassPerUnit:0:1, 'kg/unit) into piles (out of ', Quantity, ' units of that ore remaining, ', HexStr(Quantity, 16), ') (should be approximately ', ApproximateTransferQuantity:0:1, ') - high-quantity=', HexStr(High(FOrePileComposition[Ore]) - Quantity, 16), ' [', High(FOrePileComposition[Ore]) - Quantity >= TransferQuantity, ']');
            ActualTransfer := ActualTransfer + TransferQuantity * Encyclopedia.Materials[Ore].MassPerUnit;
            Inc(FOrePileComposition[Ore], TransferQuantity);
         end;
      end;
      if (ActualTransfer < TotalTransferMass) then
      begin
         Writeln('      final cleanup:');
         Fraction32.InitArray(@Distribution[Low(TOres)], Length(Distribution));
         for Ore in TOres do
         begin
            Writeln('        Ore ', Ore, ' has ', FGroundComposition[Ore], ' units in ground, out of total ', TotalCompositionMass:0:1, 'kg (', Encyclopedia.Materials[Ore].MassPerUnit:0:1, 'kg/unit)');
            Distribution[Ore] := Fraction32.FromDouble(FGroundComposition[Ore] * Encyclopedia.Materials[Ore].MassPerUnit / TotalCompositionMass);
         end;
         Fraction32.NormalizeArray(@Distribution[Low(TOres)], Length(Distribution));
         Ore := TOres(Fraction32.ChooseFrom(@Distribution[Low(TOres)], Length(Distribution), CachedSystem.RandomNumberGenerator) + Low(TOres));
         Writeln('        selected ore ', Ore, ' with quantity ', FGroundComposition[Ore]);
         Quantity := FGroundComposition[Ore];
         Assert(Quantity > 0);
         TransferQuantity := RoundUInt64((TotalTransferMass - ActualTransfer) / Encyclopedia.Materials[Ore].MassPerUnit);
         Dec(FGroundComposition[Ore], TransferQuantity);
         Writeln('      moving ', TransferQuantity, ' units of ore ', Ore, ', ', Encyclopedia.Materials[Ore].Name, ' (', Encyclopedia.Materials[Ore].MassPerUnit:0:1, 'kg/unit) into piles (final cleanup move with randomly-selected ore)');
         ActualTransfer := ActualTransfer + TransferQuantity * Encyclopedia.Materials[Ore].MassPerUnit;
         Inc(FOrePileComposition[Ore], TransferQuantity);
      end;
      Writeln('    total actual mass transfer: ', ActualTransfer:0:1, 'kg');
   end;
   if (Assigned(FRefineries)) then
   begin
      Writeln('    refineries:');
      for Ore in TOres do
         RefinedOreMasses[Ore] := 0.0;
      for Refinery in FRefineries do
      begin
         Rate := Refinery.GetRefineryCurrentRate();
         Ore := Refinery.GetRefineryOre();
         Writeln('    - refining ', Encyclopedia.Materials[Ore].Name, ' at ', Rate.ToString('kg'));
         if (Rate.IsNotZero) then
         begin
            TotalTransferMass := SyncDuration * Rate;
            Assert(TotalTransferMass >= 0);
            RefinedOreMasses[Ore] := RefinedOreMasses[Ore] + TotalTransferMass;
            Writeln('      total mass to transfer: ', TotalTransferMass:0:9, ' kg');
         end;
      end;
      Writeln('    ore refining summary:');
      for Ore in TOres do
      begin
         TotalTransferMass := RefinedOreMasses[Ore];
         if (TotalTransferMass > 0.0) then
         begin
            Material := Encyclopedia.Materials[Ore];
            Writeln('    - refining ', TotalTransferMass:0:9, ' kg of ', Material.Name);
            Assert(Material.MassPerUnit > 0);
            Assert(TotalTransferMass * Material.MassPerUnit < High(TransferQuantity));
            TransferQuantity := RoundUInt64(TotalTransferMass / Material.MassPerUnit);
            Writeln('      mass per unit: ', Material.MassPerUnit:0:9);
            Writeln('      transferring ', TransferQuantity);
            if (TransferQuantity > 0) then
            begin
               if (TransferQuantity > FOrePileComposition[Ore]) then
                  TransferQuantity := FOrePileComposition[Ore];
               Dec(FOrePileComposition[Ore], TransferQuantity);
               IncMaterialPile(Material, TransferQuantity);
            end;
         end;
      end;
   end;

   // Can't use GetTotalOrePileMass() because FNextEvent is not nil so it
   // would attempt to re-apply the mass flow rate from before the sync.
   CurrentOrePileMass := 0.0;
   if (Length(FOrePileComposition) > 0) then
      for Ore := Low(FOrePileComposition) to High(FOrePileComposition) do // $R-
      begin
         CurrentOrePileMass := CurrentOrePileMass + Encyclopedia.Materials[Ore].MassPerUnit * FOrePileComposition[Ore];
      end;
   if (CurrentOrePileMass > OrePileCapacity) then
   begin
      Writeln('    dumping excesses back into the ground:');
      Writeln('      CurrentOrePileMass=', CurrentOrePileMass:0:9, ' kg');
      Writeln('      OrePileCapacity=', OrePileCapacity:0:9, ' kg (which is not enough)');
      TotalTransferMass := CurrentOrePileMass - OrePileCapacity;
      Writeln('      Transferring ', TotalTransferMass:0:9, ' kg');
      Assert(TotalTransferMass >= 0);
      ActualTransfer := 0.0;
      for Ore in TOres do
      begin
         TransferQuantity := RoundUInt64(FOrePileComposition[Ore] * TotalTransferMass / CurrentOrePileMass);
         if (TransferQuantity > 0) then
         begin
            Dec(FOrePileComposition[Ore], TransferQuantity);
            Inc(FGroundComposition[Ore], TransferQuantity);
            Writeln('      removing ', TransferQuantity, ' units of ore ', Ore, ', ', Encyclopedia.Materials[Ore].Name, ' (', Encyclopedia.Materials[Ore].MassPerUnit:0:1, 'kg/unit) from ore piles (leaving ', FOrePileComposition[Ore], ' units of that ore in piles)');
            ActualTransfer := ActualTransfer + TransferQuantity * Encyclopedia.Materials[Ore].MassPerUnit;
         end;
      end;

      if (ActualTransfer < TotalTransferMass) then
      begin
         Writeln('      final cleanup:');
         Fraction32.InitArray(@Distribution[Low(TOres)], Length(Distribution));
         for Ore in TOres do
         begin
            Writeln('        Ore ', Ore, ' has ', FOrePileComposition[Ore], ' units in piles, out of total ', CurrentOrePileMass:0:1, 'kg (', Encyclopedia.Materials[Ore].MassPerUnit:0:1, 'kg/unit)');
            Distribution[Ore] := Fraction32.FromDouble(FOrePileComposition[Ore] * Encyclopedia.Materials[Ore].MassPerUnit / CurrentOrePileMass);
         end;
         Fraction32.NormalizeArray(@Distribution[Low(TOres)], Length(Distribution));
         Ore := TOres(Fraction32.ChooseFrom(@Distribution[Low(TOres)], Length(Distribution), CachedSystem.RandomNumberGenerator) + Low(TOres));
         Writeln('        selected ore ', Ore, ' with quantity ', FOrePileComposition[Ore]);
         Quantity := FOrePileComposition[Ore];
         Assert(Quantity > 0);
         TransferQuantity := RoundUInt64((TotalTransferMass - ActualTransfer) / Encyclopedia.Materials[Ore].MassPerUnit);
         Dec(FOrePileComposition[Ore], TransferQuantity);
         Writeln('      moving ', TransferQuantity, ' units of ore ', Ore, ', ', Encyclopedia.Materials[Ore].Name, ' (', Encyclopedia.Materials[Ore].MassPerUnit:0:1, 'kg/unit) into ground (final cleanup move with randomly-selected ore)');
         ActualTransfer := ActualTransfer + TransferQuantity * Encyclopedia.Materials[Ore].MassPerUnit;
         Inc(FGroundComposition[Ore], TransferQuantity);
      end;

   end;
   
   FAnchorTime := CachedSystem.Now;
   Writeln('    Sync() reset FAnchorTime to ', FAnchorTime.ToString());

   {$IFDEF DEBUG}
   if (Assigned(FOrePiles)) then
   begin
      CurrentOrePileMass := GetTotalOrePileMass();
      Writeln('    we ended with ', OrePileCapacity:0:1, 'kg ore pile capacity and ', CurrentOrePileMass:0:1, 'kg in ', FOrePiles.Count, ' ore piles');
      Assert(CurrentOrePileMass <= OrePileCapacity, 'now over capacity');
   end;
   {$ENDIF}
end;

procedure TRegionFeatureNode.Reset();
var
   Miner: IMiner;
   OrePile: IOrePile;
   Refinery: IRefinery;
   MaterialPile: IMaterialPile;
begin
   Writeln('  ', Parent.DebugName, ': Reset for ', Parent.DebugName);
   Assert(not Assigned(FNextEvent));
   Assert(FActive);
   if (Assigned(FMiners)) then
   begin
      for Miner in FMiners do
         Miner.StopMiner();
      FMiners.Reset();
   end;
   if (Assigned(FOrePiles)) then
   begin
      for OrePile in FOrePiles do
         OrePile.StopOrePile();
      FOrePiles.Reset();
   end;
   if (Assigned(FRefineries)) then
   begin
      for Refinery in FRefineries do
         Refinery.StopRefinery();
      FRefineries.Reset();
   end;
   if (Assigned(FMaterialPiles)) then
   begin
      for MaterialPile in FMaterialPiles do
         MaterialPile.StopMaterialPile();
      FMaterialPiles.Reset();
   end;
   // TODO: factories, consumers
   FActive := False;
   FAnchorTime := TTimeInMilliseconds.NegInfinity;
   Writeln('    Reset() reset FAnchorTime to ', FAnchorTime.ToString());
end;

procedure TRegionFeatureNode.Stop();
begin
   Assert(FActive);
   if (Assigned(FNextEvent)) then
   begin
      Sync();
      FNextEvent.Cancel();
      FNextEvent := nil;
   end;
   Reset();
   Assert(not FActive);
end;

procedure TRegionFeatureNode.HandleChanges(CachedSystem: TSystem);

   procedure AllocateOres();
   var
      Message: TAllocateOresBusMessage;
   begin
      Assert(not FAllocatedOres);
      Message := TAllocateOresBusMessage.Create(FFeatureClass.Depth, FFeatureClass.TargetCount, FFeatureClass.TargetQuantity, CachedSystem);
      if (InjectBusMessage(Message) = mrHandled) then
         FGroundComposition := Message.AssignedOres;
      FreeAndNil(Message);
      FAllocatedOres := True;
   end;
   
var
   OrePileCapacity, RemainingOrePileCapacity: Double;
   CurrentGroundMass, CurrentOrePileMass, MinMassTransfer: Double;
   Rate, TotalMinerMaxRate, TotalMiningToRefineryRate, RefiningRate, MaterialFactoryRate: TRate;
   TimeUntilGroundEmpty, TimeUntilOrePilesFull, TimeUntilAnyOrePileEmpty, TimeUntilThisOrePileEmpty,
   TimeUntilAnyMaterialPileFull, TimeUntilThisMaterialPileFull, TimeUntilAnyMaterialPileEmpty, TimeUntilNextEvent: TMillisecondsDuration;
   Composition: UInt64;
   Ore: TOres;
   Material: TMaterial;
   OreMiningRates, OreRefiningRates: TOreRates;
   MaterialCapacities: TMaterialQuantityHashTable;
   MaterialFactoryRates: TMaterialRateHashTable;
   Encyclopedia: TEncyclopediaView;
   Ratio: Double;
   Miner: IMiner;
   OrePile: IOrePile;
   Refinery: IRefinery;
   Pile: IMaterialPile;
   MaterialPileFull, OrePileEmpty: Boolean;
   SourceLimiting, TargetLimiting: Boolean;
   Count: THashTableSizeInt;
begin
   inherited;
   if (not FAllocatedOres) then
      AllocateOres();
   Writeln('  ', Parent.DebugName, ': Region considering next move.');
   if (not FActive) then
   begin
      Assert(not Assigned(FNextEvent)); // so all the "get current mass" etc getters won't be affected by mass flow
      Encyclopedia := CachedSystem.Encyclopedia;
      CurrentGroundMass := Mass;
      CurrentOrePileMass := GetTotalOrePileMass();
      MaterialCapacities := nil;
      MaterialFactoryRates := nil;
      Writeln('    CurrentGroundMass = ', CurrentGroundMass:0:1, ' kg');

      // COMPUTE MAX RATES AND CAPACITIES
      // Total mining rate
      TotalMinerMaxRate := TRate.Zero;
      if (Assigned(FMiners)) then
      begin
         for Miner in FMiners do
            TotalMinerMaxRate := TotalMinerMaxRate + Miner.GetMinerMaxRate();
         Writeln('    ', FMiners.Count, ' miners, total mining rate ', TotalMinerMaxRate.ToString('kg'));
      end;
      // Per-ore mining rates
      for Ore in TOres do
      begin
         if (CurrentGroundMass > 0) then
         begin
            OreMiningRates[Ore] := TotalMinerMaxRate * (FGroundComposition[Ore] * Encyclopedia.Materials[Ore].MassPerUnit / CurrentGroundMass);
         end
         else
         begin
            OreMiningRates[Ore] := TRate.Zero;
         end;
         OreRefiningRates[Ore] := TRate.Zero;
      end;
      // Ore pile capacities
      OrePileCapacity := 0.0;
      if (Assigned(FOrePiles)) then
      begin
         Writeln('    ', FOrePiles.Count, ' ore piles');
         for OrePile in FOrePiles do
         begin
            OrePileCapacity := OrePileCapacity + OrePile.GetOrePileCapacity();
            OrePile.StartOrePile(Self);
         end;
         if (OrePileCapacity > 0) then
            Writeln('    Ore piles are at ', CurrentOrePileMass:0:1, ' kg of ', OrePileCapacity:0:1, ' kg (', (100 * CurrentOrePileMass/OrePileCapacity):0:1, '%)')
      end;
      {$IFOPT C+}
         for Ore in TOres do
         begin
            Assert(OrePileCapacity / Encyclopedia.Materials[Ore].MassPerUnit < Double(High(FOrePileComposition[Ore])), 'Ore pile capacity exceeds maximum individual max ore quantity for ' + Encyclopedia.Materials[Ore].Name);
         end;
      {$ENDIF}
      // Refinery rates
      if (Assigned(FRefineries)) then
      begin
         Writeln('    ', FRefineries.Count, ' refineries');
         for Refinery in FRefineries do
         begin
            Ore := Refinery.GetRefineryOre();
            Rate := Refinery.GetRefineryMaxRate();
            OreRefiningRates[Ore] := OreRefiningRates[Ore] + Rate;
         end;
      end;
      for Ore in TOres do
      begin
         Composition := 0;
         if (Assigned(FMaterialPileComposition)) then
            Composition := FMaterialPileComposition[Encyclopedia.Materials[Ore]];
         Writeln('    ', Encyclopedia.Materials[Ore].Name:20, ' mining at ', OreMiningRates[Ore].ToString('kg'), ', refining at ', OreRefiningRates[Ore].ToString('kg'), ', ', FGroundComposition[Ore], '/', FOrePileComposition[Ore], '/', Composition);
      end;
      // Material pile capacity
      if (Assigned(FMaterialPiles)) then
      begin
         Writeln('    ', FMaterialPiles.Count, ' material piles');
         Count := FMaterialPiles.Count;
         if (Count < 1) then
            Count := 1;
         MaterialCapacities := TMaterialQuantityHashTable.Create(Count);
         for Pile in FMaterialPiles do
         begin
            MaterialCapacities.Inc(Pile.GetMaterialPileMaterial(), Pile.GetMaterialPileCapacity());
            Pile.StartMaterialPile(Self);
         end;
      end;
      if (Assigned(MaterialCapacities)) then
      begin
         for Material in MaterialCapacities do
            Writeln('    MaterialCapacities[', Material.Name, '] = ', MaterialCapacities[Material], ' units, ', MaterialCapacities[Material] * Material.MassPerUnit:0:1, ' kg');
      end;
      // Factories and consumers
      // TODO: factories, consumers
      // if (Assigned(FFactories) or Assigned(FConsumers)) then
      // begin
      //    Count := FFactories.Count;
      //    if (Count < 1) then
      //       Count := 1;
      //    MaterialFactoryRates := TMaterialRateHashTable.Create(Count);
      // end;
      // TODO: factories need to affect MaterialFactoryRates
      // TODO: consumers need to affect MaterialFactoryRates (e.g. structure feature)

      // COMPUTE ACTUAL RATES

      // Consumers and factories
      // TODO: Turn on consumers and factories that can operate
      // without running out of source materials or storage for
      // output, and turn off those that cannot.
      TimeUntilAnyMaterialPileEmpty := TMillisecondsDuration.Infinity;

      // Refineries
      TimeUntilAnyOrePileEmpty := TMillisecondsDuration.Infinity;
      TimeUntilAnyMaterialPileFull := TMillisecondsDuration.Infinity;
      TotalMiningToRefineryRate := TRate.Zero;
      for Ore in TOres do
      begin
         Material := Encyclopedia.Materials[Ore];
         RefiningRate := OreRefiningRates[Ore];
         if (RefiningRate.IsZero) then
            continue; // no refineries for this ore, skip the whole exercise
         Writeln('    Refining ', Encyclopedia.Materials[Ore].Name, ', max rate ', RefiningRate.ToString('kg'));
         if (Assigned(MaterialFactoryRates)) then
         begin
            MaterialFactoryRate := MaterialFactoryRates[Material];
         end
         else
         begin
            MaterialFactoryRate := TRate.Zero;
         end;
         OrePileEmpty := (OreMiningRates[Ore] < RefiningRate) and (FOrePileComposition[Ore] = 0.0);
         Writeln('      OrePileEmpty = ', OrePileEmpty);
         if (Assigned(MaterialCapacities)) then
         begin
            if (Assigned(FMaterialPileComposition)) then
            begin
               Composition := FMaterialPileComposition[Material];
            end
            else
            begin
               Composition := 0;
            end;
            MaterialPileFull := (MaterialFactoryRate < RefiningRate) and (Composition >= MaterialCapacities[Material]);
            Writeln('      MaterialPileComposition = ', Composition);
            Writeln('      MaterialCapacities = ', MaterialCapacities[Material]);
         end
         else
         begin
            MaterialPileFull := True;
         end;
         Writeln('      MaterialPileFull = ', MaterialPileFull, ' (', Assigned(MaterialCapacities), '/', Assigned(FMaterialPileComposition), ')');
         SourceLimiting := False;
         TargetLimiting := False;
         if (OrePileEmpty) then
         begin
            SourceLimiting := True;
            if (MaterialPileFull) then
            begin
               TargetLimiting := True;
               if (OreMiningRates[Ore] < MaterialFactoryRate) then
               begin
                  Ratio := OreMiningRates[Ore] / RefiningRate;
               end
               else
               begin
                  Ratio := MaterialFactoryRate / RefiningRate;
               end;
               TimeUntilThisMaterialPileFull := TMillisecondsDuration.Infinity;
            end
            else 
            begin
               Writeln('      Refining of ', Encyclopedia.Materials[Ore].Name, ' is limited by incoming ore (mining at ', OreMiningRates[Ore].ToString('kg'), ' vs refining at ', RefiningRate.ToString('kg'), ')');
               if ((OreMiningRates[Ore].IsPositive) and (RefiningRate > MaterialFactoryRate)) then
               begin
                  Ratio := OreMiningRates[Ore] / RefiningRate;
                  TimeUntilThisMaterialPileFull := (MaterialCapacities[Material] - GetTotalMaterialPileQuantity(Material)) * Material.MassPerUnit / (RefiningRate * Ratio - MaterialFactoryRate);
                  Assert(TimeUntilThisMaterialPileFull.IsPositive);
               end
               else
               begin
                  Ratio := 0.0;
                  TimeUntilThisMaterialPileFull := TMillisecondsDuration.Infinity;
               end;
            end;
            TimeUntilThisOrePileEmpty := TMillisecondsDuration.Infinity;
         end
         else
         begin
            if (MaterialPileFull) then
            begin
               TargetLimiting := True;
               Ratio := MaterialFactoryRate / RefiningRate;
               TimeUntilThisMaterialPileFull := TMillisecondsDuration.Infinity;
            end
            else
            begin
               Ratio := 1.0;
               Writeln('      Full rate refining accepted. Capacity=', MaterialCapacities[Material], '; Current=', GetTotalMaterialPileQuantity(Material));
               Writeln('      Refining rate = ', RefiningRate.ToString('kg'), '; factory rate = ', MaterialFactoryRate.ToString('kg'));
               TimeUntilThisMaterialPileFull := (MaterialCapacities[Material] - GetTotalMaterialPileQuantity(Material)) * Material.MassPerUnit / (RefiningRate * Ratio - MaterialFactoryRate);
               Writeln('      Remaining time: ', TimeUntilThisMaterialPileFull.ToString());
               Assert(TimeUntilThisMaterialPileFull.IsPositive);
            end;
            if (OreMiningRates[Ore] < RefiningRate * Ratio) then
            begin
               TimeUntilThisOrePileEmpty := FOrePileComposition[Ore] * Encyclopedia.Materials[Ore].MassPerUnit / (RefiningRate * Ratio - OreMiningRates[Ore]);
               Assert(TimeUntilThisOrePileEmpty.IsPositive);
            end
            else
               TimeUntilThisOrePileEmpty := TMillisecondsDuration.Infinity;
         end;
         for Refinery in FRefineries do
         begin
            if (Refinery.GetRefineryOre() = Ore) then
            begin
               Refinery.StartRefinery(Self, Refinery.GetRefineryMaxRate() * Ratio, SourceLimiting, TargetLimiting);
            end;
         end;
         OreRefiningRates[Ore] := RefiningRate * Ratio;
         Assert(TimeUntilThisOrePileEmpty.IsNotZero);
         if (TimeUntilThisOrePileEmpty < TimeUntilAnyOrePileEmpty) then
         begin
            TimeUntilAnyOrePileEmpty := TimeUntilThisOrePileEmpty;
            Assert(TimeUntilAnyOrePileEmpty.IsPositive);
         end;
         Assert(TimeUntilThisMaterialPileFull.IsNotZero);
         if (TimeUntilThisMaterialPileFull < TimeUntilAnyMaterialPileFull) then
         begin
            TimeUntilAnyMaterialPileFull := TimeUntilThisMaterialPileFull;
            Assert(TimeUntilAnyMaterialPileFull.IsPositive);
         end;
         if (FGroundComposition[Ore] > 0) then
            TotalMiningToRefineryRate := TotalMiningToRefineryRate + OreRefiningRates[Ore];
      end;

      // Miners
      RemainingOrePileCapacity := OrePileCapacity - CurrentOrePileMass;
      MinMassTransfer := GetMinOreMassTransfer(CachedSystem);
      Writeln('    Remaining ore pile capacity: ', RemainingOrePileCapacity:0:1, ' kg, min mass transfer: ', MinMassTransfer:0:1, ' kg.');
      TimeUntilOrePilesFull := TMillisecondsDuration.Infinity;
      TimeUntilGroundEmpty := TMillisecondsDuration.Infinity;
      if (CurrentGroundMass > 0) then
      begin
         if (RemainingOrePileCapacity >= MinMassTransfer) then
         begin
            if (TotalMinerMaxRate > TotalMiningToRefineryRate) then
            begin
               TimeUntilOrePilesFull := RemainingOrePileCapacity / (TotalMinerMaxRate - TotalMiningToRefineryRate);
               Writeln('    TimeUntilOrePilesFull:');
               Writeln('      RemainingOrePileCapacity = ', RemainingOrePileCapacity:0:9);
               Writeln('      TotalMinerMaxRate = ', TotalMinerMaxRate.AsDouble:0:9);
               Writeln('      TotalMiningToRefineryRate = ', TotalMiningToRefineryRate.AsDouble:0:9);
               Assert(TimeUntilOrePilesFull.IsPositive);
            end;
            if (TotalMinerMaxRate > TRate.Zero) then
            begin
               TimeUntilGroundEmpty := CurrentGroundMass / TotalMinerMaxRate;
               Assert(TimeUntilGroundEmpty.IsPositive);
            end;
            // ready to go, start the miners!
            if (Assigned(FMiners)) then
            begin
               for Miner in FMiners do
                  Miner.StartMiner(Self, Miner.GetMinerMaxRate(), False, False);
            end;
         end
         else
         if (TotalMiningToRefineryRate > TRate.Zero) then
         begin
            // piles are full, but we are refining, so there is room being made
            if (Assigned(FMiners)) then
            begin
               for Miner in FMiners do
                  Miner.StartMiner(Self, TotalMiningToRefineryRate * (Miner.GetMinerMaxRate() / TotalMinerMaxRate), False, True);
            end;
         end
         else
         begin
            // piles are full, stop the miners
            if (Assigned(FMiners)) then
            begin
               for Miner in FMiners do
                  Miner.StartMiner(Self, TRate.Zero, False, True);
            end;
         end;
      end
      else
      begin
         // ground is empty, stop the miners
         if (Assigned(FMiners)) then
         begin
            for Miner in FMiners do
               Miner.StartMiner(Self, TRate.Zero, True, False);
         end;
      end;
      TimeUntilNextEvent := TimeUntilGroundEmpty;
      if (TimeUntilNextEvent > TimeUntilOrePilesFull) then
         TimeUntilNextEvent := TimeUntilOrePilesFull;
      if (TimeUntilNextEvent > TimeUntilAnyOrePileEmpty) then
         TimeUntilNextEvent := TimeUntilAnyOrePileEmpty;
      if (TimeUntilNextEvent > TimeUntilAnyMaterialPileFull) then
         TimeUntilNextEvent := TimeUntilAnyMaterialPileFull;
      if (TimeUntilNextEvent > TimeUntilAnyMaterialPileEmpty) then
         TimeUntilNextEvent := TimeUntilAnyMaterialPileEmpty;
      if (not TimeUntilNextEvent.IsInfinite) then
      begin
         Assert(TimeUntilNextEvent.IsPositive);
         Assert(not Assigned(FNextEvent));
         {$IFDEF VERBOSE}
         if (TimeUntilNextEvent = TimeUntilGroundEmpty) then
            Writeln('    Scheduling event for when ground will be empty: T-', TimeUntilNextEvent.ToString());
         if (TimeUntilNextEvent = TimeUntilOrePilesFull) then
            Writeln('    Scheduling event for when ore piles will be full: T-', TimeUntilNextEvent.ToString());
         if (TimeUntilNextEvent = TimeUntilAnyOrePileEmpty) then
            Writeln('    Scheduling event for when an ore pile will be empty: T-', TimeUntilNextEvent.ToString());
         if (TimeUntilNextEvent = TimeUntilAnyMaterialPileFull) then
            Writeln('    Scheduling event for when material piles will be full: T-', TimeUntilNextEvent.ToString());
         if (TimeUntilNextEvent = TimeUntilAnyMaterialPileEmpty) then
            Writeln('    Scheduling event for when an material pile will be empty: T-', TimeUntilNextEvent.ToString());
         {$ENDIF}
         FNextEvent := CachedSystem.ScheduleEvent(TimeUntilNextEvent, @ReconsiderEverything, Self);
         if (FAnchorTime.IsInfinite) then
         begin
            FAnchorTime := CachedSystem.Now;
            Writeln('    Anchoring time at ', FAnchorTime.ToString(), ' (now)');
         end
         else
         begin
            Writeln('    Anchoring time at ', FAnchorTime.ToString(), ' (', (FAnchorTime - CachedSystem.Now).ToString(), ' ago)');
         end;
         Writeln('    Next sync should be at ', (FAnchorTime + TimeUntilNextEvent).ToString());
      end
      else
      begin
         Writeln('    Situation is static, not scheduling an event.');
         Assert(FAnchorTime.IsInfinite);
      end;
      FActive := True;
      FreeAndNil(MaterialFactoryRates);
      FreeAndNil(MaterialCapacities);
   end;
end;

procedure TRegionFeatureNode.ReconsiderEverything(var Data);
begin
   Writeln('  ', Parent.DebugName, ': Reconsidering everything for ', Parent.DebugName, '...');
   Assert(Assigned(FNextEvent));
   Sync();
   FNextEvent := nil;
   Reset();
   MarkAsDirty([dkUpdateClients, dkUpdateJournal, dkNeedsHandleChanges]);
end;

procedure TRegionFeatureNode.RemoveMiner(Miner: IMiner);
begin
   if (FActive) then
      Stop();
   Assert(Assigned(FMiners));
   FMiners.Remove(Miner);
   MarkAsDirty([dkUpdateClients, dkUpdateJournal, dkNeedsHandleChanges]);
end;

procedure TRegionFeatureNode.RemoveOrePile(OrePile: IOrePile);
begin
   if (FActive) then
      Stop();
   Assert(Assigned(FOrePiles));
   FOrePiles.Remove(OrePile);
   MarkAsDirty([dkUpdateClients, dkUpdateJournal, dkNeedsHandleChanges]);
end;

procedure TRegionFeatureNode.RemoveRefinery(Refinery: IRefinery);
begin
   if (FActive) then
      Stop();
   Assert(Assigned(FRefineries));
   FRefineries.Remove(Refinery);
   MarkAsDirty([dkUpdateClients, dkUpdateJournal, dkNeedsHandleChanges]);
end;

procedure TRegionFeatureNode.RemoveMaterialPile(MaterialPile: IMaterialPile);
begin
   if (FActive) then
      Stop();
   Assert(Assigned(FMaterialPiles));
   FMaterialPiles.Remove(MaterialPile);
   MarkAsDirty([dkUpdateClients, dkUpdateJournal, dkNeedsHandleChanges]);
end;

// TODO: factories, consumers

function TRegionFeatureNode.GetOresPresent(): TOreFilter;
var
   Ore: TOres;
begin
   Result.Clear();
   for Ore in TOres do
   begin
      if (FOrePileComposition[Ore] > 0) then
         Result.Enable(Ore);
   end;
end;

function TRegionFeatureNode.GetOresForPile(Pile: IOrePile): TOreQuantities;
var
   PileRatio: Double;
   Ore: TOres;
   TotalCapacity: Double;
begin
   Assert(Assigned(FOrePiles));
   Assert(FOrePiles.Has(Pile));
   TotalCapacity := GetTotalOrePileCapacity();
   if (TotalCapacity > 0) then
   begin
      PileRatio := Pile.GetOrePileCapacity() / TotalCapacity;
      Assert(PileRatio > 0.0);
      Assert(PileRatio <= 1.0);
      for Ore in TOres do
         Result[Ore] := RoundUInt64(FOrePileComposition[Ore] * PileRatio);
   end
   else
   begin
      Assert(SizeOf(Result[Low(Result)]) = SizeOf(QWord));
      FillQWord(Result[Low(TOres)], High(TOres) - Low(TOres), 0);
   end;
end;

function TRegionFeatureNode.GetMaterialPileMass(Pile: IMaterialPile): Double; // kg
var
   Material: TMaterial;
   PileRatio: Double;
begin
   Material := Pile.GetMaterialPileMaterial();
   PileRatio := Pile.GetMaterialPileCapacity() / GetTotalMaterialPileCapacity(Material);
   Result := GetTotalMaterialPileMass(Material) * PileRatio;
end;

function TRegionFeatureNode.GetMaterialPileMassFlowRate(Pile: IMaterialPile): TRate; // kg/s
var
   Material: TMaterial;
   PileRatio: Double;
begin
   Material := Pile.GetMaterialPileMaterial();
   PileRatio := Pile.GetMaterialPileCapacity() / GetTotalMaterialPileCapacity(Material);
   Result := GetTotalMaterialPileMassFlowRate(Material) * PileRatio;
end;

function TRegionFeatureNode.GetMaterialPileQuantity(Pile: IMaterialPile): Int64; // units
var
   Material: TMaterial;
   PileRatio: Double;
begin
   Material := Pile.GetMaterialPileMaterial();
   PileRatio := Pile.GetMaterialPileCapacity() / GetTotalMaterialPileCapacity(Material);
   Result := Round(GetTotalMaterialPileQuantity(Material) * PileRatio);
end;

function TRegionFeatureNode.GetMaterialPileQuantityFlowRate(Pile: IMaterialPile): TRate; // units/s
var
   Material: TMaterial;
   PileRatio: Double;
begin
   Material := Pile.GetMaterialPileMaterial();
   PileRatio := Pile.GetMaterialPileCapacity() / GetTotalMaterialPileCapacity(Material);
   Result := GetTotalMaterialPileQuantityFlowRate(Material) * PileRatio;
end;

procedure TRegionFeatureNode.Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter; CachedSystem: TSystem);
var
   Visibility: TVisibility;
   Ore: TOres;
   Minable: Boolean;
begin
   Visibility := Parent.ReadVisibilityFor(DynastyIndex, CachedSystem);
   if ((dmDetectable * Visibility <> []) and (dmClassKnown in Visibility)) then
   begin
      Writer.WriteCardinal(fcRegion);
      Assert(Length(FGroundComposition) > 0);
      Minable := False;
      for Ore := Low(FGroundComposition) to High(FGroundComposition) do // $R-
      begin
         if (FGroundComposition[Ore] > 0) then
         begin
            Minable := True;
            break;
         end;
      end;
      Writer.WriteBoolean(Minable); // if we add more flags, they should go into this byte
   end;
end;

procedure TRegionFeatureNode.UpdateJournal(Journal: TJournalWriter; CachedSystem: TSystem);
var
   Ore: TOres;
   Material: TMaterial;
begin
   Journal.WriteBoolean(FAllocatedOres);
   Assert(Length(FGroundComposition) > 0);
   for Ore := Low(FGroundComposition) to High(FGroundComposition) do
   begin
      if (FGroundComposition[Ore] > 0) then
      begin
         Journal.WriteMaterialReference(CachedSystem.Encyclopedia.Materials[Ore]);
         Journal.WriteUInt64(FGroundComposition[Ore]);
      end;
   end;
   Journal.WriteCardinal(0);
   Assert(Length(FOrePileComposition) > 0);
   for Ore := Low(FOrePileComposition) to High(FOrePileComposition) do
   begin
      if (FOrePileComposition[Ore] > 0) then
      begin
         Journal.WriteMaterialReference(CachedSystem.Encyclopedia.Materials[Ore]);
         Journal.WriteUInt64(FOrePileComposition[Ore]);
      end;
   end;
   Journal.WriteCardinal(0);
   if (Assigned(FMaterialPileComposition)) then
   begin
      for Material in FMaterialPileComposition do
      begin
         Journal.WriteMaterialReference(Material);
         Journal.WriteUInt64(FMaterialPileComposition[Material]);
      end;
   end;
   Journal.WriteCardinal(0);
   Journal.WriteInt64(FAnchorTime.AsInt64);
end;

procedure TRegionFeatureNode.ApplyJournal(Journal: TJournalReader; CachedSystem: TSystem);

   procedure ReadOres(var Composition: TOreQuantities);
   var
      Material: TMaterial;
      OreID: TOres;
   begin
      Assert(SizeOf(Composition[Low(TOres)]) = SizeOf(QWord));
      FillQWord(Composition[Low(TOres)], High(TOres) - Low(TOres), 0);
      repeat
         Material := Journal.ReadMaterialReference();
         if (Assigned(Material)) then
         begin
            Assert(Material.ID >= Low(TOres));
            Assert(Material.ID <= High(TOres));
            OreID := TOres(Material.ID);
            Composition[OreID] := Journal.ReadUInt64();
         end;
      until not Assigned(Material);
   end;

   procedure ReadMaterials(var Materials: TMaterialQuantityHashTable);
   var
      Material: TMaterial;
   begin
      repeat
         Material := Journal.ReadMaterialReference();
         if (Assigned(Material)) then
         begin
            if (not Assigned(Materials)) then
               Materials := TMaterialQuantityHashTable.Create();
            Materials[Material] := Journal.ReadUInt64();
         end;
      until not Assigned(Material);
   end;
   
begin
   FAllocatedOres := Journal.ReadBoolean();
   ReadOres(FGroundComposition);
   ReadOres(FOrePileComposition);
   ReadMaterials(FMaterialPileComposition);
   FAnchorTime := TTimeInMilliseconds.FromMilliseconds(Journal.ReadInt64());
end;

procedure TRegionFeatureNode.DescribeExistentiality(var IsDefinitelyReal, IsDefinitelyGhost: Boolean);
begin
   IsDefinitelyReal := True;
end;

initialization
   RegisterFeatureClass(TRegionFeatureClass);
end.