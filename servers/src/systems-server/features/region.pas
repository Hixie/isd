{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit region;

interface

{$DEFINE VERBOSE}

uses
   systems, serverstream, techtree, materials, time, providers;

type
   TRegionFeatureNode = class;

   TMinerBlockage = (mbNone, mbPilesFull, mbMinesEmpty, mbNoRegion, mbPending = 254, mbDisabled = 255);
   
   IMiner = interface ['IMiner']
      function GetMinerRate(): TRate; // kg per second
      procedure StartMiner(Region: TRegionFeatureNode);
      procedure StartMinerBlocked(Region: TRegionFeatureNode; Blockage: TMinerBlockage); // called when we would call StartMiner but there's some problem (must mbPilesFull or mbMinesEmpty)
      procedure StopMiner();
   end;
   TRegisterMinerBusMessage = specialize TRegisterProviderBusMessage<TPhysicalConnectionBusMessage, IMiner>;
   TMinerHashSet = specialize TProviderSet<IMiner>;

   IOrePile = interface ['IPile']
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
      procedure StartRefinery(Region: TRegionFeatureNode; Rate: TRate); // kg per second
      procedure SyncRefinery(Quantity: UInt64);
      procedure StopRefinery();
   end;
   TRegisterRefineryBusMessage = specialize TRegisterProviderBusMessage<TPhysicalConnectionBusMessage, IRefinery>;
   TRefineryHashSet = specialize TProviderSet<IRefinery>;

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
      FAnchorTime: TTimeInMilliseconds; // set to Low(FAnchorTime) or Now when transfers are currently synced
      FAllocatedOres: Boolean; // TODO: find a way to make this bit cost 32 times less than it does now
      // Runtime admin variables:
      FFeatureClass: TRegionFeatureClass;
      FMiners: TMinerHashSet;
      FOrePiles: TOrePileHashSet;
      FRefineries: TRefineryHashSet;
      FNextEvent: TSystemEvent; // set only when mass is moving
      FActive: Boolean; // set to true when transfers are set up, set to false when transfers need to be set up
      function GetTotalOrePileCapacity(): Double; // kg total for all piles
      function GetTotalOrePileMass(): Double; // kg total for all piles
      function GetTotalOrePileMassFlowRate(): TRate; // kg/s (total for all piles; total miner rate minus total refinery rate)
      function GetMinMassTransfer(CachedSystem: TSystem): Double; // kg mass that would need to be transferred to move at least one unit of quantity
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
      function GetOrePileMass(Pile: IOrePile): Double; // kg
      function GetOrePileMassFlowRate(Pile: IOrePile): TRate; // kg/s
      function GetOresPresent(): TOreFilter;
      function GetOresForPile(Pile: IOrePile): TOreQuantities;
   end;
   
implementation

uses
   sysutils, planetary, exceptions, messages, isdprotocol, isdnumbers, math;

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
   // The ore pile composition contributes to GetOrePileMass below.
   if (Assigned(FNextEvent)) then
      Result := Result + (CachedSystem.Now - FAnchorTime) * MassFlowRate;
end;

function TRegionFeatureNode.GetMassFlowRate(): TRate;
var
   Miner: IMiner;
begin
   Result := TRate.FromPerMillisecond(0.0);
   if (Assigned(FMiners) and Assigned(FNextEvent)) then
   begin
      for Miner in FMiners do
         Result := Result - Miner.GetMinerRate();
   end;
   // Refineries affect GetOrePileMassFlowRate below.
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
   Result := TRate.FromPerMillisecond(0.0);
   if (Assigned(FMiners) and Assigned(FNextEvent)) then
   begin
      for Miner in FMiners do
         Result := Result + Miner.GetMinerRate();
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
   PileRatio: Double;
begin
   PileRatio := Pile.GetOrePileCapacity() / GetTotalOrePileCapacity();
   Result := GetTotalOrePileMassFlowRate() * PileRatio;
end;

function TRegionFeatureNode.GetMinMassTransfer(CachedSystem: TSystem): Double;
var
   Ore: TOres;
   TotalComposition, Quantity: UInt64;
   TransferMassPerUnit: Double;
   Encyclopedia: TEncyclopediaView;
begin
   Encyclopedia := CachedSystem.Encyclopedia;
   TotalComposition := 0;
   for Ore in TOres do
      Inc(TotalComposition, FGroundComposition[Ore]);
   {$PUSH} {$IEEEERRORS-} Result := Infinity; {$POP}
   for Ore in TOres do
   begin
      Quantity := FGroundComposition[Ore];
      if (Quantity > 0) then
      begin
         TransferMassPerUnit := Encyclopedia.Materials[Ore].MassPerUnit / Ceil(Quantity / TotalComposition);
         if (TransferMassPerUnit < Result) then
            Result := TransferMassPerUnit;
      end;
   end;
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
      Result := mrDeferred;
end;

procedure TRegionFeatureNode.Sync();
var
   Miner: IMiner;
   Refinery: IRefinery;
   Rate: TRate;
   TransferMass, ApproximateTransferQuantity: Double;
   {$IFDEF DEBUG}
   CurrentOrePileMass, OrePileRecordedMass, OrePileCapacity, ActualTransfer: Double;
   OrePile: IOrePile;
   {$ENDIF}
   SyncDuration: TMillisecondsDuration;
   Ore: TOres;
   Material: TMaterial;
   CachedSystem: TSystem;
   Encyclopedia: TEncyclopediaView;
   Quantity, TotalComposition: UInt64;
   TransferQuantity: UInt64;
   Distribution: TOreFractions;
begin
   Writeln('  ', Parent.DebugName, ': SYNCHRONIZING FOR ', Parent.DebugName);
   Assert(Assigned(FNextEvent));
   CachedSystem := System;
   Encyclopedia := CachedSystem.Encyclopedia;
   SyncDuration := CachedSystem.Now - FAnchorTime;
   Writeln('    duration: ', SyncDuration.ToString(), ' (Now=', CachedSystem.Now.ToString(), ', anchor time=', FAnchorTime.ToString(), ')');

   {$IFDEF DEBUG}
   if (Assigned(FOrePiles)) then
   begin
      CurrentOrePileMass := GetTotalOrePileMass();
      OrePileRecordedMass := 0.0;
      if (Length(FOrePileComposition) > 0) then
         for Ore := Low(FOrePileComposition) to High(FOrePileComposition) do // $R-
         begin
            OrePileRecordedMass := OrePileRecordedMass + Encyclopedia.Materials[Ore].MassPerUnit * FOrePileComposition[Ore];
         end;
      OrePileCapacity := 0.0;
      for OrePile in FOrePiles do
      begin
         OrePileCapacity := OrePileCapacity + OrePile.GetOrePileCapacity();
      end;
      Writeln('    we started with ', OrePileCapacity:0:1, 'kg pile capacity and ', CurrentOrePileMass:0:1, 'kg in ', FOrePiles.Count, ' ore piles (of which ', OrePileRecordedMass:0:1, 'kg is recorded)');
      Assert(CurrentOrePileMass < OrePileCapacity, 'already over capacity');
   end;
   {$ENDIF}

   if (Assigned(FMiners)) then
   begin
      TotalComposition := 0;
      for Ore in TOres do
      begin
         Inc(TotalComposition, FGroundComposition[Ore]);
      end;
      TransferMass := 0.0;
      for Miner in FMiners do
      begin
         Rate := Miner.GetMinerRate();
         TransferMass := TransferMass + SyncDuration * Rate;
         Writeln('    transfer mass for this miner (rate ', Rate.ToString('kg'), ') is ', (SyncDuration * Rate):0:1, 'kg; TotalComposition is ', TotalComposition:0);
      end;
      Writeln('    total ideal mass transfer: ', TransferMass:0:1, 'kg');
      ActualTransfer := 0.0;
      for Ore in TOres do
      begin
         Quantity := FGroundComposition[Ore];
         if (Quantity > 0) then
         begin
            Assert(TransferMass >= 0);
            Assert(Encyclopedia.Materials[Ore].MassPerUnit > 0);
            Assert(TransferMass * Encyclopedia.Materials[Ore].MassPerUnit < High(TransferQuantity));
            ApproximateTransferQuantity := (Quantity / TotalComposition) * (TransferMass / Encyclopedia.Materials[Ore].MassPerUnit); 
            TransferQuantity := TruncUInt64(ApproximateTransferQuantity);
            Assert(TransferQuantity <= Quantity, 'region composition underflow');
            Dec(FGroundComposition[Ore], TransferQuantity);
            Assert(High(FOrePileComposition[Ore]) - Quantity >= TransferQuantity);
            Writeln('      moving ', TransferQuantity, ' units of ore ', Ore, ', ', Encyclopedia.Materials[Ore].Name, ' (', Encyclopedia.Materials[Ore].MassPerUnit:0:1, 'kg/unit) into piles (out of ', Quantity, ' units of that ore remaining) (should be approximately ', ApproximateTransferQuantity:0:1, ')');
            ActualTransfer := ActualTransfer + TransferQuantity * Encyclopedia.Materials[Ore].MassPerUnit;
            Inc(FOrePileComposition[Ore], TransferQuantity);
         end;
      end;
      if (ActualTransfer < TransferMass) then
      begin
         Fraction32.InitArray(@Distribution[Low(TOres)], Length(Distribution));
         for Ore in TOres do
            Distribution[Ore] := Fraction32.FromDouble(FGroundComposition[Ore] / TotalComposition);
         Fraction32.NormalizeArray(@Distribution[Low(TOres)], Length(Distribution));
         Ore := TOres(Fraction32.ChooseFrom(@Distribution[Low(TOres)], Length(Distribution), CachedSystem.RandomNumberGenerator));
         Quantity := FGroundComposition[Ore];
         Assert(Quantity > 0);
         TransferQuantity := RoundUInt64((TransferMass - ActualTransfer) / Encyclopedia.Materials[Ore].MassPerUnit);
         Dec(FGroundComposition[Ore], TransferQuantity);
         Writeln('      moving ', TransferQuantity, ' units of ore ', Ore, ', ', Encyclopedia.Materials[Ore].Name, ' (', Encyclopedia.Materials[Ore].MassPerUnit:0:1, 'kg/unit) into piles (final cleanup move with randomly-selected ore)');
         ActualTransfer := ActualTransfer + TransferQuantity * Encyclopedia.Materials[Ore].MassPerUnit;
         Inc(FOrePileComposition[Ore], TransferQuantity);
      end;
      Writeln('    total actual mass transfer: ', ActualTransfer:0:1, 'kg');
   end;
   if (Assigned(FRefineries)) then
   begin
      for Refinery in FRefineries do
      begin
         Rate := Refinery.GetRefineryCurrentRate();
         TransferMass := SyncDuration * Rate;
         Material := Encyclopedia.Materials[Refinery.GetRefineryOre()];
         Assert(Material.ID >= Low(TOres));
         Assert(Material.ID <= High(TOres));
         Assert(TransferMass >= 0);
         Assert(Material.MassPerUnit > 0);
         Assert(TransferMass * Material.MassPerUnit < High(TransferQuantity));
         TransferQuantity := RoundUInt64(TransferMass / Material.MassPerUnit);
         Assert(TransferQuantity <= FOrePileComposition[Ore]); // TODO: this doesn't seem guaranteed
         Dec(FOrePileComposition[Ore], TransferQuantity);
         Refinery.SyncRefinery(TransferQuantity);
      end;
   end;
   FAnchorTime := CachedSystem.Now;
   Writeln('    Sync() reset FAnchorTime to ', FAnchorTime.ToString());

   {$IFDEF DEBUG}
   if (Assigned(FOrePiles)) then
   begin
      CurrentOrePileMass := GetTotalOrePileMass();
      OrePileCapacity := 0.0;
      for OrePile in FOrePiles do
      begin
         OrePileCapacity := OrePileCapacity + OrePile.GetOrePileCapacity();
      end;
      Writeln('    we ended with ', OrePileCapacity:0:1, 'kg pile capacity and ', CurrentOrePileMass:0:1, 'kg in ', FOrePiles.Count, ' ore piles');
      Assert(CurrentOrePileMass < OrePileCapacity, 'now over capacity');
   end;
   {$ENDIF}
end;

procedure TRegionFeatureNode.Reset();
var
   Miner: IMiner;
   OrePile: IOrePile;
   Refinery: IRefinery;
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
      Message := TAllocateOresBusMessage.Create(FFeatureClass.Depth, FFeatureClass.TargetCount, FFeatureClass.TargetQuantity, CachedSystem);
      if (InjectBusMessage(Message) = mrHandled) then
         FGroundComposition := Message.AssignedOres;
      FreeAndNil(Message);
      FAllocatedOres := True;
   end;
   
var
   OrePileCapacity, RemainingOrePileCapacity: Double;
   CurrentGroundMass, CurrentOrePileMass, MinMassTransfer: Double;
   TotalMinerRate, TotalRefineryRate: TRate;
   TimeUntilGroundEmpty, TimeUntilOrePilesFull, TimeUntilAnyOrePileEmpty, TimeUntilThisOrePileEmpty, TimeUntilNextEvent: TMillisecondsDuration;
   Ore: TOres;
   OreMiningRates, OreRefiningRates: TOreRates;
   Encyclopedia: TEncyclopediaView;
   Ratio: Double;
   Miner: IMiner;
   OrePile: IOrePile;
   Refinery: IRefinery;
begin
   inherited;
   if (not FAllocatedOres) then
      AllocateOres();
   Writeln('  ', Parent.DebugName, ': Region considering next move.');
   if (not FActive) then
   begin
      Encyclopedia := CachedSystem.Encyclopedia;
      CurrentOrePileMass := GetTotalOrePileMass();
      OrePileCapacity := 0.0;
      if (Assigned(FOrePiles)) then
      begin
         Writeln('    we have ', FOrePiles.Count, ' ore piles');
         for OrePile in FOrePiles do
         begin
            OrePileCapacity := OrePileCapacity + OrePile.GetOrePileCapacity();
            OrePile.StartOrePile(Self);
         end;
      end;
      TotalMinerRate := TRate.FromPerMillisecond(0.0);
      if (Assigned(FMiners)) then
      begin
         Writeln('    we have ', FMiners.Count, ' miners');
         for Miner in FMiners do
            TotalMinerRate := TotalMinerRate + Miner.GetMinerRate();
      end;
      CurrentGroundMass := Mass;
      Writeln('    we have ', CurrentGroundMass:0:1, ' kg of mass');
      for Ore in TOres do
      begin
         if (CurrentGroundMass > 0) then
         begin
            OreMiningRates[Ore] := TotalMinerRate * (FGroundComposition[Ore] * Encyclopedia.Materials[Ore].MassPerUnit / CurrentGroundMass);
         end
         else
         begin
            OreMiningRates[Ore] := TRate.FromPerMillisecond(0.0);
         end;
         OreRefiningRates[Ore] := TRate.FromPerMillisecond(0.0);
         Assert(OrePileCapacity / Encyclopedia.Materials[Ore].MassPerUnit < Double(High(FOrePileComposition[Ore])), 'Pile capacity exceeds maximum individual max ore quantity for ' + Encyclopedia.Materials[Ore].Name);
      end;
      if (Assigned(FRefineries)) then
      begin
         Writeln('    we have ', FRefineries.Count, ' refineries');
         for Refinery in FRefineries do
         begin
            Ore := Refinery.GetRefineryOre();
            OreRefiningRates[Ore] := OreRefiningRates[Ore] - Refinery.GetRefineryMaxRate();
         end;
      end;
      TimeUntilAnyOrePileEmpty := TMillisecondsDuration.Infinity;
      TotalRefineryRate := TRate.FromPerMillisecond(0.0);
      for Ore in TOres do
      begin
         if (OreMiningRates[Ore] < OreRefiningRates[Ore]) then
         begin
            // eventually we're going to run out. did we already?
            if (FOrePileComposition[Ore] > 0) then
            begin
               // if we're above zero quantity, then figure out when we'll run out, and enable refineries at full rate
               TimeUntilThisOrePileEmpty := FOrePileComposition[Ore] * Encyclopedia.Materials[Ore].MassPerUnit / (OreRefiningRates[Ore] - OreMiningRates[Ore]);
               if (TimeUntilThisOrePileEmpty < TimeUntilAnyOrePileEmpty) then
                  TimeUntilAnyOrePileEmpty := TimeUntilThisOrePileEmpty;
               for Refinery in FRefineries do
               begin
                  if (Refinery.GetRefineryOre() = Ore) then
                  begin
                     Refinery.StartRefinery(Self, Refinery.GetRefineryMaxRate());
                  end;
               end;
            end
            else
            begin
               // if we're at zero quantity, then set the refineries to a sustainable rate
               Ratio := OreMiningRates[Ore] / OreRefiningRates[Ore];
               for Refinery in FRefineries do
               begin
                  if (Refinery.GetRefineryOre() = Ore) then
                  begin
                     Refinery.StartRefinery(Self, Refinery.GetRefineryMaxRate() * Ratio);
                  end;
               end;
               OreRefiningRates[Ore] := OreRefiningRates[Ore] * Ratio;
            end;
         end;
         TotalRefineryRate := TotalRefineryRate + OreRefiningRates[Ore];
      end;
      Writeln('    we have ', OrePileCapacity:0:1, 'kg pile capacity and ', CurrentOrePileMass:0:1, 'kg in piles');
      RemainingOrePileCapacity := OrePileCapacity - CurrentOrePileMass;
      MinMassTransfer := GetMinMassTransfer(CachedSystem);
      TimeUntilOrePilesFull := TMillisecondsDuration.Infinity;
      TimeUntilGroundEmpty := TMillisecondsDuration.Infinity;
      if (CurrentGroundMass > 0) then
      begin
         if (RemainingOrePileCapacity >= MinMassTransfer) then
         begin
            Writeln('    should still be able to move ', MinMassTransfer:0:1, 'kg');
            if (TotalMinerRate > TotalRefineryRate) then
               TimeUntilOrePilesFull := TMillisecondsDuration(RemainingOrePileCapacity / (TotalMinerRate - TotalRefineryRate));
            if (TotalMinerRate > TRate.FromPerMillisecond(0)) then
               TimeUntilGroundEmpty := TMillisecondsDuration(CurrentGroundMass / TotalMinerRate);
            // ready to go, start the miners!
            if (Assigned(FMiners)) then
            begin
               for Miner in FMiners do
                  Miner.StartMiner(Self);
            end;
         end
         else
         begin
            Writeln('    cannot move any more, min transfer is ', MinMassTransfer:0:1, 'kg');
            // piles are full, stop the miners
            if (Assigned(FMiners)) then
            begin
               for Miner in FMiners do
                  Miner.StartMinerBlocked(Self, mbPilesFull);
            end;
         end;
      end
      else
      begin
         Writeln('    ground is empty');
         // ground is empty, stop the miners
         if (Assigned(FMiners)) then
         begin
            for Miner in FMiners do
               Miner.StartMinerBlocked(Self, mbMinesEmpty);
         end;
      end;
      TimeUntilNextEvent := TimeUntilGroundEmpty;
      if (TimeUntilNextEvent > TimeUntilOrePilesFull) then
         TimeUntilNextEvent := TimeUntilOrePilesFull;
      if (TimeUntilNextEvent > TimeUntilAnyOrePileEmpty) then
         TimeUntilNextEvent := TimeUntilAnyOrePileEmpty;
      if (not TimeUntilNextEvent.IsInfinite) then
      begin
         Assert(not TimeUntilNextEvent.IsZero);
         Assert(not Assigned(FNextEvent));
         {$IFDEF VERBOSE}
         if (TimeUntilNextEvent = TimeUntilGroundEmpty) then
            Writeln('    Scheduling event for when ground will be empty: T-', TimeUntilNextEvent.ToString());
         if (TimeUntilNextEvent = TimeUntilOrePilesFull) then
            Writeln('    Scheduling event for when ore piles will be full: T-', TimeUntilNextEvent.ToString());
         if (TimeUntilNextEvent = TimeUntilAnyOrePileEmpty) then
            Writeln('    Scheduling event for when an ore pile will be empty: T-', TimeUntilNextEvent.ToString());
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
      end;
      FActive := True;
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
   Journal.WriteInt64(FAnchorTime.AsInt64);
end;

procedure TRegionFeatureNode.ApplyJournal(Journal: TJournalReader; CachedSystem: TSystem);

   procedure ReadMaterials(var Composition: TOreQuantities);
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
   
begin
   FAllocatedOres := Journal.ReadBoolean();
   ReadMaterials(FGroundComposition);
   ReadMaterials(FOrePileComposition);
   FAnchorTime := TTimeInMilliseconds.FromMilliseconds(Journal.ReadInt64());
end;

procedure TRegionFeatureNode.DescribeExistentiality(var IsDefinitelyReal, IsDefinitelyGhost: Boolean);
begin
   IsDefinitelyReal := True;
end;

initialization
   RegisterFeatureClass(TRegionFeatureClass);
end.