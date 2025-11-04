{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit region;

interface

{$DEFINE VERBOSE}

uses
   systems, serverstream, techtree, materials, time, providers, isdprotocol, plasticarrays, genericutils;

type
   TRegionFeatureNode = class;

   TRegionClientMode = (rcIdle, rcPending, rcActive, rcNoRegion);
   TRegionClientFields = packed record
   strict private
      function GetEnabled(): Boolean; inline;
   public
      Region: TRegionFeatureNode; // 8 bytes
      Rate: TRate; // 8 bytes
      DisabledReasons: TDisabledReasons;
      SourceLimiting, TargetLimiting: Boolean;
      Mode: TRegionClientMode;
      procedure Enable();
      procedure Disable(Reasons: TDisabledReasons);
      property Enabled: Boolean read GetEnabled;
   end;
   {$IF SIZEOF(TRegionClientMode) > 3*8} {$FATAL} {$ENDIF}

   IMiner = interface ['IMiner']
      function GetMinerMaxRate(): TRate; // kg per second
      function GetMinerCurrentRate(): TRate; // kg per second
      procedure StartMiner(Region: TRegionFeatureNode; Rate: TRate; SourceLimiting, TargetLimiting: Boolean);
      procedure PauseMiner();
      procedure StopMiner();
   end;
   TRegisterMinerBusMessage = specialize TRegisterProviderBusMessage<TPhysicalConnectionBusMessage, IMiner>;
   TMinerList = specialize PlasticArray<IMiner, PointerUtils>;

   IOrePile = interface ['IOrePile']
      function GetOrePileCapacity(): Double; // kg
      procedure StartOrePile(Region: TRegionFeatureNode);
      procedure PauseOrePile();
      procedure StopOrePile();
   end;
   TRegisterOrePileBusMessage = specialize TRegisterProviderBusMessage<TPhysicalConnectionBusMessage, IOrePile>;
   TOrePileList = specialize PlasticArray<IOrePile, PointerUtils>;

   IRefinery = interface ['IRefinery']
      function GetRefineryOre(): TOres;
      function GetRefineryMaxRate(): TRate; // kg per second
      function GetRefineryCurrentRate(): TRate; // kg per second
      procedure StartRefinery(Region: TRegionFeatureNode; Rate: TRate; SourceLimiting, TargetLimiting: Boolean); // kg per second
      procedure PauseRefinery();
      procedure StopRefinery();
   end;
   TRegisterRefineryBusMessage = specialize TRegisterProviderBusMessage<TPhysicalConnectionBusMessage, IRefinery>;
   TRefineryList = specialize PlasticArray<IRefinery, PointerUtils>;

   IMaterialPile = interface ['IMaterialPile']
      function GetMaterialPileMaterial(): TMaterial;
      function GetMaterialPileCapacity(): UInt64; // quantity
      procedure StartMaterialPile(Region: TRegionFeatureNode);
      procedure PauseMaterialPile();
      procedure StopMaterialPile();
   end;
   TRegisterMaterialPileBusMessage = specialize TRegisterProviderBusMessage<TPhysicalConnectionBusMessage, IMaterialPile>;
   TMaterialPileList = specialize PlasticArray<IMaterialPile, PointerUtils>;

   // TODO: factories

   IMaterialConsumer = interface ['IMaterialConsumer']
      // Consumers grab material as far as possible, and only register when the piles are empty.
      // They might unregister a bit late, in which case GetMaterialConsumerMaterial() can return nil.
      function GetMaterialConsumerMaterial(): TMaterial;
      function GetMaterialConsumerMaxDelivery(): UInt64;
      function GetMaterialConsumerCurrentRate(): TRate; // returns the value set by StartMaterialConsumer
      procedure StartMaterialConsumer(Region: TRegionFeatureNode; ActualRate: TRate); // quantity per second; only called if GetMaterialConsumerMaterial returns non-nil
      procedure DeliverMaterialConsumer(Delivery: UInt64); // 0 <= Delivery <= GetMaterialConsumerMaxDelivery; will always be called when syncing if StartMaterialConsumer was called
      procedure PauseMaterialConsumer(); // will call StartMaterialConsumer again if necessary
      procedure StopMaterialConsumer(); // region is going away
   end;
   TRegisterMaterialConsumerBusMessage = specialize TRegisterProviderBusMessage<TPhysicalConnectionBusMessage, IMaterialConsumer>;
   TMaterialConsumerList = specialize PlasticArray<IMaterialConsumer, PointerUtils>;

   TObtainMaterialBusMessage = class(TPhysicalConnectionBusMessage)
   strict private
      FRequest: TMaterialQuantity;
      FDelivery: UInt64;
      function GetRemainingQuantity(): UInt64; inline;
      function GetFulfilled(): Boolean; inline;
      function GetTransferredManifest(): TMaterialQuantity; inline;
   public
      constructor Create(ARequest: TMaterialQuantity); overload;
      constructor Create(AMaterial: TMaterial; AQuantity: UInt64); overload;
      procedure Deliver(ADelivery: UInt64);
      property Material: TMaterial read FRequest.Material;
      property Quantity: UInt64 read GetRemainingQuantity;
      property Fulfilled: Boolean read GetFulfilled;
      property TransferredManifest: TMaterialQuantity read GetTransferredManifest;
   end;

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

   // TODO: Region logic for miners, piles, factories, and consumers needs to be per-dynasty (with a joint ground from which they mine).

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
      {$IFOPT C+} Busy: Boolean; {$ENDIF} // set to true while running our algorithms, to make sure nobody calls us reentrantly
      FFeatureClass: TRegionFeatureClass;
      FMiners: TMinerList;
      FOrePiles: TOrePileList;
      FRefineries: TRefineryList;
      FMaterialPiles: TMaterialPileList;
      FMaterialConsumers: TMaterialConsumerList;
      FNextEvent: TSystemEvent; // set only when mass is moving
      FActive: Boolean; // set to true when transfers are set up, set to false when transfers need to be set up
      FDynamic: Boolean; // set to true when the situation is dynamic (i.e. Sync() would do something)
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
      procedure DecMaterialPile(Material: TMaterial; Delta: UInt64);
      function ClampedDecMaterialPile(Material: TMaterial; Delta: UInt64): UInt64; // returns how much was actually transferred
      function GetIsMinable(): Boolean;
   protected
      constructor CreateFromJournal(Journal: TJournalReader; AFeatureClass: TFeatureClass; ASystem: TSystem); override;
      function GetMass(): Double; override;
      function GetMassFlowRate(): TRate; override;
      function ManageBusMessage(Message: TBusMessage): TBusMessageResult; override;
      function HandleBusMessage(Message: TBusMessage): Boolean; override;
      procedure Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter; CachedSystem: TSystem); override;
      procedure Sync(); // move the ores around (called by PrepareClientsForRenegotiation and ReconsiderEverything)
      procedure Pause(); // tell our clients we're going to renegotiate the deal (called by PrepareClientsForRenegotiation and ReconsiderEverything)
      procedure PrepareClientsForRenegotiation(); // sync, cancel the current scheduled event, and pause
      procedure ReconsiderEverything(var Data); // scheduled event handler: sync, pause (same as stop)
      procedure Reset(); // disconnect and forget all the clients (only called by Destroy)
      procedure HandleChanges(CachedSystem: TSystem); override;
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
      // TODO: RemoveFactory
      procedure RemoveMaterialConsumer(MaterialConsumer: IMaterialConsumer);
      procedure SyncForMaterialConsumer(); // call when a material consumer thinks it might be done
      procedure ReconsiderMaterialConsumer(MaterialConsumer: IMaterialConsumer); // call when a material consumer changes settings
      function GetOrePileMass(Pile: IOrePile): Double; // kg
      function GetOrePileMassFlowRate(Pile: IOrePile): TRate; // kg/s
      function GetOresPresent(): TOreFilter;
      function GetOresForPile(Pile: IOrePile): TOreQuantities;
      function GetMaterialPileMass(Pile: IMaterialPile): Double; // kg
      function GetMaterialPileMassFlowRate(Pile: IMaterialPile): TRate; // kg/s
      function GetMaterialPileQuantity(Pile: IMaterialPile): UInt64; // units
      function GetMaterialPileQuantityFlowRate(Pile: IMaterialPile): TRate; // units/s
      property IsMinable: Boolean read GetIsMinable;
   end;

implementation

uses
   sysutils, planetary, exceptions, messages, isdnumbers, math, hashfunctions;

procedure TRegionClientFields.Disable(Reasons: TDisabledReasons);
begin
   Region := nil;
   Rate := TRate.Zero;
   DisabledReasons := Reasons;
   SourceLimiting := False;
   TargetLimiting := False;
   Mode := rcIdle;
end;

procedure TRegionClientFields.Enable();
begin
   DisabledReasons := [];
end;

function TRegionClientFields.GetEnabled(): Boolean;
begin
   Result := DisabledReasons = [];
end;


constructor TObtainMaterialBusMessage.Create(ARequest: TMaterialQuantity);
begin
   inherited Create();
   Assert(Assigned(ARequest.Material));
   FRequest := ARequest;
   Assert(not Fulfilled);
end;

constructor TObtainMaterialBusMessage.Create(AMaterial: TMaterial; AQuantity: UInt64);
begin
   inherited Create();
   Assert(Assigned(AMaterial));
   FRequest.Material := AMaterial;
   FRequest.Quantity := AQuantity;
   Assert(not Fulfilled);
end;

function TObtainMaterialBusMessage.GetRemainingQuantity(): UInt64;
begin
   Result := FRequest.Quantity - FDelivery; // $R-
end;

function TObtainMaterialBusMessage.GetFulfilled(): Boolean;
begin
   Result := FDelivery >= FRequest.Quantity;
end;

function TObtainMaterialBusMessage.GetTransferredManifest(): TMaterialQuantity;
begin
   if (FDelivery > 0) then
   begin
      Result.Material := FRequest.Material;
      Result.Quantity := FDelivery;
   end
   else
   begin
      Result.Material := nil;
      Result.Quantity := 0;
   end;
end;

procedure TObtainMaterialBusMessage.Deliver(ADelivery: UInt64);
begin
   Assert(FDelivery + ADelivery <= FRequest.Quantity);
   Inc(FDelivery, ADelivery);
end;


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
   Assert(not FDynamic);
end;

constructor TRegionFeatureNode.CreateFromJournal(Journal: TJournalReader; AFeatureClass: TFeatureClass; ASystem: TSystem);
begin
   FFeatureClass := AFeatureClass as TRegionFeatureClass;
   Assert(Assigned(AFeatureClass));
   inherited CreateFromJournal(Journal, AFeatureClass, ASystem);
   FAnchorTime := TTimeInMilliseconds.NegInfinity;
   Assert(not FDynamic);
end;

destructor TRegionFeatureNode.Destroy();
begin
   if (FActive) then
   begin
      if (Assigned(FNextEvent)) then
         CancelEvent(FNextEvent);
      FDynamic := False;
      Reset();
   end;
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
   if (FDynamic) then
      Result := Result + (CachedSystem.Now - FAnchorTime) * MassFlowRate;
end;

function TRegionFeatureNode.GetMassFlowRate(): TRate;
var
   Miner: IMiner;
begin
   Result := TRate.Zero;
   if (FDynamic and FMiners.IsNotEmpty) then
   begin
      for Miner in FMiners.Without(nil) do
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
   if (FOrePiles.IsNotEmpty) then
   begin
      for OrePile in FOrePiles.Without(nil) do
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
   if (FDynamic) then
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
   if (FDynamic) then
   begin
      if (FMiners.IsNotEmpty) then
      begin
         for Miner in FMiners.Without(nil) do
            Result := Result + Miner.GetMinerCurrentRate();
      end;
      if (FRefineries.IsNotEmpty) then
      begin
         for Refinery in FRefineries.Without(nil) do
            Result := Result - Refinery.GetRefineryCurrentRate();
      end;
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
   // the PileRatio, Pile.GetOrePileCapacity() / GetTotalOrePileCapacity(), and then
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
   if (FDynamic) then
   begin
      Inc(Result, RoundUInt64((System.Now - FAnchorTime) * GetTotalMaterialPileQuantityFlowRate(Material)));
   end;
end;

function TRegionFeatureNode.GetTotalMaterialPileQuantityFlowRate(Material: TMaterial): TRate; // units/s
var
   Refinery: IRefinery;
   Consumer: IMaterialConsumer;
begin
   Result := TRate.Zero;
   if (FRefineries.IsNotEmpty and Material.IsOre) then
   begin
      for Refinery in FRefineries.Without(nil) do
      begin
         if (Refinery.GetRefineryOre() = Material.ID) then
            Result := Result + Refinery.GetRefineryCurrentRate() / Material.MassPerUnit;
      end;
   end;
   // TODO: factories (consumption, generation)
   if (FMaterialConsumers.IsNotEmpty) then
   begin
      for Consumer in FMaterialConsumers.Without(nil) do
      begin
         if (Consumer.GetMaterialConsumerMaterial() = Material) then
            Result := Result - Consumer.GetMaterialConsumerCurrentRate();
      end;
   end;
end;

function TRegionFeatureNode.GetTotalMaterialPileCapacity(Material: TMaterial): UInt64;
var
   Pile: IMaterialPile;
begin
   Result := 0;
   if (FMaterialPiles.IsNotEmpty) then
   begin
      for Pile in FMaterialPiles.Without(nil) do
      begin
         if (Pile.GetMaterialPileMaterial() = Material) then
            Inc(Result, Pile.GetMaterialPileCapacity());
      end;
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
   if (FDynamic) then
   begin
      Result := Result + (System.Now - FAnchorTime) * GetTotalMaterialPileMassFlowRate(Material);
   end;
end;

function TRegionFeatureNode.GetTotalMaterialPileMassFlowRate(Material: TMaterial): TRate; // kg/s
var
   Refinery: IRefinery;
   Consumer: IMaterialConsumer;
begin
   Result := TRate.Zero;
   if (FRefineries.IsNotEmpty and Material.IsOre) then
   begin
      for Refinery in FRefineries.Without(nil) do
      begin
         if (Refinery.GetRefineryOre() = Material.ID) then
            Result := Result + Refinery.GetRefineryCurrentRate();
      end;
   end;
   // TODO: factories (consumption, generation)
   if (FMaterialConsumers.IsNotEmpty) then
   begin
      for Consumer in FMaterialConsumers.Without(nil) do
      begin
         if (Consumer.GetMaterialConsumerMaterial() = Material) then
            Result := Result - Consumer.GetMaterialConsumerCurrentRate() * Material.MassPerUnit;
      end;
   end;
end;

procedure TRegionFeatureNode.IncMaterialPile(Material: TMaterial; Delta: UInt64);
begin
   Assert(Assigned(Material));
   Assert(Delta > 0);
   if (not Assigned(FMaterialPileComposition)) then
   begin
      FMaterialPileComposition := TMaterialQuantityHashTable.Create(1);
   end;
   FMaterialPileComposition.Inc(Material, Delta);
end;

procedure TRegionFeatureNode.DecMaterialPile(Material: TMaterial; Delta: UInt64);
begin
   Assert(Assigned(Material));
   Assert(Delta > 0);
   Assert(Assigned(FMaterialPileComposition));
   FMaterialPileComposition.Dec(Material, Delta);
end;

function TRegionFeatureNode.ClampedDecMaterialPile(Material: TMaterial; Delta: UInt64): UInt64;
begin
   // We return how much was _actually_ transferred.
   Assert(Assigned(Material));
   Assert(Delta > 0);
   if (Assigned(FMaterialPileComposition)) then
   begin
      Result := FMaterialPileComposition.ClampedDec(Material, Delta);
   end
   else
   begin
      Result := 0;
   end;
end;

function TRegionFeatureNode.GetIsMinable(): Boolean;
var
   Ore: TOres;
begin
   Result := False;
   for Ore := Low(FGroundComposition) to High(FGroundComposition) do // $R-
   begin
      if (FGroundComposition[Ore] > 0) then
      begin
         Result := True;
         break;
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
   MaterialPileMessage: TRegisterMaterialPileBusMessage;
   MaterialConsumerMessage: TRegisterMaterialConsumerBusMessage;
begin
   Writeln(DebugName, ' received ', Message.ClassName);
   {$IFOPT C+} Assert(not Busy); {$ENDIF}
   if (Message is TRegisterMinerBusMessage) then
   begin
      if (FActive) then
         PrepareClientsForRenegotiation();
      MinerMessage := Message as TRegisterMinerBusMessage;
      Assert(not FMiners.Contains(MinerMessage.Provider));
      FMiners.Push(MinerMessage.Provider);
      MarkAsDirty([dkNeedsHandleChanges]);
      Result := mrHandled;
      Writeln(DebugName, ': Registered a new miner, now ', FMiners.Length, ' miners');
   end
   else
   if (Message is TRegisterOrePileBusMessage) then
   begin
      if (FActive) then
         PrepareClientsForRenegotiation();
      OrePileMessage := Message as TRegisterOrePileBusMessage;
      Assert(not FOrePiles.Contains(OrePileMessage.Provider));
      FOrePiles.Push(OrePileMessage.Provider);
      MarkAsDirty([dkNeedsHandleChanges]);
      Result := mrHandled;
      Writeln(DebugName, ': Registered a new ore pile, now ', FOrePiles.Length, ' ore piles');
   end
   else
   if (Message is TRegisterRefineryBusMessage) then
   begin
      if (FActive) then
         PrepareClientsForRenegotiation();
      RefineryMessage := Message as TRegisterRefineryBusMessage;
      Assert(not FRefineries.Contains(RefineryMessage.Provider));
      FRefineries.Push(RefineryMessage.Provider);
      MarkAsDirty([dkNeedsHandleChanges]);
      Result := mrHandled;
      Writeln(DebugName, ': Registered a new refinery, now ', FRefineries.Length, ' refineries');
   end
   else
   if (Message is TRegisterMaterialPileBusMessage) then
   begin
      if (FActive) then
         PrepareClientsForRenegotiation();
      MaterialPileMessage := Message as TRegisterMaterialPileBusMessage;
      Assert(not FMaterialPiles.Contains(MaterialPileMessage.Provider));
      FMaterialPiles.Push(MaterialPileMessage.Provider);
      MarkAsDirty([dkNeedsHandleChanges]);
      Result := mrHandled;
      Writeln(DebugName, ': Registered a new material pile, now ', FMaterialPiles.Length, ' material piles');
   end
   // TODO: factories
   else
   if (Message is TRegisterMaterialConsumerBusMessage) then
   begin
      if (FActive) then
         PrepareClientsForRenegotiation();
      MaterialConsumerMessage := Message as TRegisterMaterialConsumerBusMessage;
      Assert(not FMaterialConsumers.Contains(MaterialConsumerMessage.Provider));
      FMaterialConsumers.Push(MaterialConsumerMessage.Provider);
      MarkAsDirty([dkNeedsHandleChanges]);
      Result := mrHandled;
      Writeln(DebugName, ': Registered a new material consumer, now ', FMaterialConsumers.Length, ' material consumers');
   end
   else
   if (Message is TObtainMaterialBusMessage) then
   begin
      Result := DeferOrManageBusMessage(Message);
   end
   else
      Result := mrDeferred;
end;

function TRegionFeatureNode.HandleBusMessage(Message: TBusMessage): Boolean;
var
   Obtain: TObtainMaterialBusMessage;
   DeliverySize: UInt64;
   Changes: TDirtyKinds;
begin
   {$IFOPT C+} Assert(not Busy); {$ENDIF}
   if (Message is TObtainMaterialBusMessage) then
   begin
      Obtain := Message as TObtainMaterialBusMessage;
      Assert(Obtain.Quantity > 0);
      if (FActive) then
         PrepareClientsForRenegotiation();
      Changes := [dkNeedsHandleChanges];
      if (Assigned(FMaterialPileComposition) and FMaterialPileComposition.Has(Obtain.Material)) then
      begin
         DeliverySize := FMaterialPileComposition[Obtain.Material];
         if (DeliverySize > 0) then
         begin
            if (DeliverySize > Obtain.Quantity) then
               DeliverySize := Obtain.Quantity;
            Obtain.Deliver(DeliverySize);
            FMaterialPileComposition.Dec(Obtain.Material, DeliverySize);
            Include(Changes, dkUpdateJournal);
         end;
      end;
      MarkAsDirty(Changes);
      Result := Obtain.Fulfilled;
   end
   else
      Result := inherited;
end;

procedure TRegionFeatureNode.Sync();
var
   Miner: IMiner;
   OrePile: IOrePile;
   Refinery: IRefinery;
   Consumer: IMaterialConsumer;
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
   TransferQuantity, ActualTransferQuantity, DesiredTransferQuantity: UInt64;
   Distribution: TOreFractions;
   RefinedOreMasses: array[TOres] of Double;
   GroundChanged, GroundWasMinable: Boolean;
begin
   Writeln('  ', DebugName, ' SYNCHRONIZING');
   Assert(FDynamic);
   CachedSystem := System;
   SyncDuration := CachedSystem.Now - FAnchorTime;
   Writeln('    duration: ', SyncDuration.ToString(), ' (Now=', CachedSystem.Now.ToString(), ', anchor time=', FAnchorTime.ToString(), ')');

   if (SyncDuration.IsZero) then
   begin
      Writeln('    skipping sync; nothing to do');
      exit;
   end;
   Assert(SyncDuration.IsPositive);

   {$IFOPT C+}
   Assert(not Busy);
   Busy := true;
   {$ENDIF}

   Encyclopedia := CachedSystem.Encyclopedia;

   GroundChanged := False;
   GroundWasMinable := IsMinable;

   OrePileCapacity := 0.0;
   if (FOrePiles.IsNotEmpty) then
   begin
      for OrePile in FOrePiles.Without(nil) do
      begin
         OrePileCapacity := OrePileCapacity + OrePile.GetOrePileCapacity();
      end;
   end;

   {$IFDEF DEBUG}
   if (FOrePiles.IsNotEmpty) then
   begin
      FlowRate := GetTotalOrePileMassFlowRate();
      CurrentOrePileMass := GetTotalOrePileMass();
      OrePileRecordedMass := 0.0;
      if (Length(FOrePileComposition) > 0) then
         for Ore := Low(FOrePileComposition) to High(FOrePileComposition) do // $R-
         begin
            OrePileRecordedMass := OrePileRecordedMass + Encyclopedia.Materials[Ore].MassPerUnit * FOrePileComposition[Ore];
         end;
      Writeln('    we started with ', OrePileCapacity:0:1, 'kg ore pile capacity and ', CurrentOrePileMass:0:1, 'kg in ', FOrePiles.Length, ' ore piles (of which ', OrePileRecordedMass:0:1, 'kg is recorded)');
      Assert(CurrentOrePileMass <= OrePileCapacity + 0.00001, 'already over capacity');
      Writeln('    we get to that by multiplying the total ore pile mass flow rate, ', FlowRate.ToString('kg'), ', by the elapsed time, ', SyncDuration.ToString());
   end;
   {$ENDIF}

   if (FMiners.IsNotEmpty) then
   begin
      TotalCompositionMass := 0.0;
      Assert(Length(FGroundComposition) > 0);
      for Ore := Low(FGroundComposition) to High(FGroundComposition) do // $R-
         TotalCompositionMass := TotalCompositionMass + Encyclopedia.Materials[Ore].MassPerUnit * FGroundComposition[Ore];
      TotalTransferMass := 0.0;
      for Miner in FMiners.Without(nil) do
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
            GroundChanged := True;
            Assert(High(FOrePileComposition[Ore]) - FOrePileComposition[Ore] >= TransferQuantity);
            Writeln('      moving ', TransferQuantity, ' units of ore ', Ore, ', ', Encyclopedia.Materials[Ore].Name, ' (', Encyclopedia.Materials[Ore].MassPerUnit:0:1, 'kg/unit) into piles (out of ', Quantity, ' units of that ore remaining, ', HexStr(Quantity, 16), ') (should be approximately ', ApproximateTransferQuantity:0:5, ') - high-quantity=', HexStr(High(FOrePileComposition[Ore]) - Quantity, 16), ' [', High(FOrePileComposition[Ore]) - Quantity >= TransferQuantity, ']');
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
         // TODO: consider truncating and remembering how much is left over for next time
         TransferQuantity := RoundUInt64((TotalTransferMass - ActualTransfer) / Encyclopedia.Materials[Ore].MassPerUnit);
         Dec(FGroundComposition[Ore], TransferQuantity);
         GroundChanged := True;
         Writeln('      moving ', TransferQuantity, ' units of ore ', Ore, ', ', Encyclopedia.Materials[Ore].Name, ' (', Encyclopedia.Materials[Ore].MassPerUnit:0:1, 'kg/unit) into piles (final cleanup move with randomly-selected ore)');
         ActualTransfer := ActualTransfer + TransferQuantity * Encyclopedia.Materials[Ore].MassPerUnit;
         Inc(FOrePileComposition[Ore], TransferQuantity);
      end;
      Writeln('    total actual mass transfer: ', ActualTransfer:0:1, 'kg');
   end;
   if (FRefineries.IsNotEmpty) then
   begin
      Writeln('    refineries:');
      for Ore in TOres do
         RefinedOreMasses[Ore] := 0.0;
      for Refinery in FRefineries.Without(nil) do
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
            // TODO: consider truncating here and keeping track of how much to add next time
            TransferQuantity := RoundUInt64(TotalTransferMass / Material.MassPerUnit);
            Writeln('      mass per unit: ', Material.MassPerUnit:0:9);
            if (TransferQuantity > FOrePileComposition[Ore]) then
            begin
               Writeln('      limiting transfer to ore pile composition');
               TransferQuantity := FOrePileComposition[Ore];
            end;
            if (TransferQuantity > 0) then
            begin
               Writeln('      transferring ', TransferQuantity);
               Dec(FOrePileComposition[Ore], TransferQuantity);
               IncMaterialPile(Material, TransferQuantity);
            end
            else
               Writeln('      transferring nothing');
         end;
      end;
   end;
   if (FMaterialConsumers.IsNotEmpty) then
   begin
      Writeln('    consumers:');
      for Consumer in FMaterialConsumers.Without(nil) do
      begin
         Rate := Consumer.GetMaterialConsumerCurrentRate();
         Material := Consumer.GetMaterialConsumerMaterial();
         if (Assigned(Material)) then
         begin
            // we truncate here because otherwise we might end up using more material than we have
            // (consider two consumers who have both reached 0.5, when the total material refined is 1.0)
            TransferQuantity := CeilUInt64(SyncDuration * Rate);
            DesiredTransferQuantity := Consumer.GetMaterialConsumerMaxDelivery();
            Writeln('    - ', HexStr(Consumer), ' consuming ', Material.Name, ' at ', Rate.ToString('units'), ' (targeting ', TransferQuantity, ' units, max ', DesiredTransferQuantity, ' units)');
            if (TransferQuantity > DesiredTransferQuantity) then
               TransferQuantity := DesiredTransferQuantity;
            if (TransferQuantity > 0) then
            begin
               ActualTransferQuantity := ClampedDecMaterialPile(Material, TransferQuantity);
            end
            else
            begin
               ActualTransferQuantity := 0;
            end;
            Writeln('      Transferring ', ActualTransferQuantity);
            Consumer.DeliverMaterialConsumer(ActualTransferQuantity);
         end
         else
            Writeln('    - ', HexStr(Consumer), ' not consuming anything');
      end;
   end;

   // Can't use GetTotalOrePileMass() because FNextEvent might not be nil so it
   // might attempt to re-apply the mass flow rate from before the sync.
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
            GroundChanged := True;
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
         GroundChanged := True;
      end;
   end;

   if (GroundChanged) then
   begin
      if (IsMinable <> GroundWasMinable) then
      begin
         MarkAsDirty([dkUpdateJournal, dkUpdateClients]);
      end
      else
      begin
         MarkAsDirty([dkUpdateJournal]);
      end;
   end;

   FAnchorTime := CachedSystem.Now;
   Writeln('    Sync() reset FAnchorTime to ', FAnchorTime.ToString());

   {$IFDEF DEBUG}
   if (FOrePiles.IsNotEmpty) then
   begin
      CurrentOrePileMass := GetTotalOrePileMass();
      Writeln('    we ended with ', OrePileCapacity:0:1, 'kg ore pile capacity and ', CurrentOrePileMass:0:1, 'kg in ', FOrePiles.Length, ' ore piles');
      Assert(CurrentOrePileMass <= OrePileCapacity, 'now over capacity');
   end;
   {$ENDIF}

   {$IFOPT C+} Assert(Busy); Busy := False; {$ENDIF}
end;

procedure TRegionFeatureNode.Pause();
var
   Miner: IMiner;
   OrePile: IOrePile;
   Refinery: IRefinery;
   MaterialPile: IMaterialPile;
   MaterialConsumer: IMaterialConsumer;
begin
   Writeln(DebugName, ': Pause for ', Parent.DebugName);
   Assert(not Assigned(FNextEvent));
   if (FActive) then
   begin
      if (FMiners).IsNotEmpty then
      begin
         for Miner in FMiners.Without(nil) do
            Miner.PauseMiner();
      end;
      if (FOrePiles).IsNotEmpty then
      begin
         for OrePile in FOrePiles.Without(nil) do
            OrePile.PauseOrePile();
      end;
      if (FRefineries).IsNotEmpty then
      begin
         for Refinery in FRefineries.Without(nil) do
            Refinery.PauseRefinery();
      end;
      if (FMaterialPiles).IsNotEmpty then
      begin
         for MaterialPile in FMaterialPiles.Without(nil) do
            MaterialPile.PauseMaterialPile();
      end;
      // TODO: factories
      if (FMaterialConsumers).IsNotEmpty then
      begin
         for MaterialConsumer in FMaterialConsumers.Without(nil) do
            MaterialConsumer.PauseMaterialConsumer();
      end;
      FActive := False;
   end;
   FDynamic := False;
   FAnchorTime := TTimeInMilliseconds.NegInfinity;
   Writeln('    Pause() reset FAnchorTime to ', FAnchorTime.ToString());
end;

procedure TRegionFeatureNode.PrepareClientsForRenegotiation();
begin
   Assert(FActive); // callers are responsible for checking this first
   if (FDynamic) then
   begin
      Sync();
      if (Assigned(FNextEvent)) then
         CancelEvent(FNextEvent);
   end;
   Pause();
   Assert(not FActive);
end;

procedure TRegionFeatureNode.ReconsiderEverything(var Data);
begin
   Writeln(DebugName, ': Reconsidering everything for ', Parent.DebugName, '...');
   Assert(Assigned(FNextEvent));
   Assert(FDynamic);
   FNextEvent := nil; // important to do this before anything that might crash, otherwise we try to free it on exit
   Sync();
   Pause();
   Assert(not FDynamic);
   MarkAsDirty([dkUpdateJournal, dkNeedsHandleChanges]);
end;

procedure TRegionFeatureNode.Reset();
var
   Miner: IMiner;
   OrePile: IOrePile;
   Refinery: IRefinery;
   MaterialPile: IMaterialPile;
   MaterialConsumer: IMaterialConsumer;
begin
   Writeln(DebugName, ': Reset for ', Parent.DebugName);
   Assert(not Assigned(FNextEvent));
   Assert(not FDynamic);
   Assert(FActive);
   if (FMiners).IsNotEmpty then
   begin
      for Miner in FMiners.Without(nil) do
         Miner.StopMiner();
      FMiners.Empty();
   end;
   if (FOrePiles).IsNotEmpty then
   begin
      for OrePile in FOrePiles.Without(nil) do
         OrePile.StopOrePile();
      FOrePiles.Empty();
   end;
   if (FRefineries).IsNotEmpty then
   begin
      for Refinery in FRefineries.Without(nil) do
         Refinery.StopRefinery();
      FRefineries.Empty();
   end;
   if (FMaterialPiles).IsNotEmpty then
   begin
      for MaterialPile in FMaterialPiles.Without(nil) do
         MaterialPile.StopMaterialPile();
      FMaterialPiles.Empty();
   end;
   // TODO: factories
   if (FMaterialConsumers).IsNotEmpty then
   begin
      for MaterialConsumer in FMaterialConsumers.Without(nil) do
         MaterialConsumer.StopMaterialConsumer();
      FMaterialConsumers.Empty();
   end;
   FActive := False;
   FAnchorTime := TTimeInMilliseconds.NegInfinity;
   Writeln('    Reset() reset FAnchorTime to ', FAnchorTime.ToString());
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
   Rate, TotalMinerMaxRate, TotalMiningToRefineryRate, RefiningRate, MaterialConsumptionRate: TRate;
   TimeUntilGroundEmpty, TimeUntilOrePilesFull, TimeUntilAnyOrePileEmpty, TimeUntilThisOrePileEmpty,
   TimeUntilAnyMaterialPileFull, TimeUntilThisMaterialPileFull, TimeUntilAnyMaterialPileEmpty, TimeUntilNextEvent: TMillisecondsDuration;
   Composition: UInt64;
   Ore: TOres;
   Material: TMaterial;
   OreMiningRates, OreRefiningRates: TOreRates;
   MaterialCapacities, MaterialConsumerCounts: TMaterialQuantityHashTable;
   MaterialFactoryRates: TMaterialRateHashTable;
   Encyclopedia: TEncyclopediaView;
   Ratio: Double;
   Miner: IMiner;
   OrePile: IOrePile;
   Refinery: IRefinery;
   Pile: IMaterialPile;
   MaterialConsumer: IMaterialConsumer;
   MaterialPileFull, OrePileEmpty: Boolean;
   SourceLimiting, TargetLimiting: Boolean;
   Count: THashTableSizeInt;
begin
   inherited;
   if (not FAllocatedOres) then
      AllocateOres();
   {$IFOPT C+} Assert(not Busy); Busy := True; {$ENDIF}
   Writeln('==', Parent.DebugName, ': Region considering next move.');
   if (not FActive) then
   begin
      FMiners.RemoveAll(nil);
      FOrePiles.RemoveAll(nil);
      FRefineries.RemoveAll(nil);
      FMaterialPiles.RemoveAll(nil);
      FMaterialConsumers.RemoveAll(nil);
      Assert(not Assigned(FNextEvent));
      Assert(not FDynamic); // so all the "get current mass" etc getters won't be affected by mass flow
      Encyclopedia := CachedSystem.Encyclopedia;
      CurrentGroundMass := Mass;
      CurrentOrePileMass := GetTotalOrePileMass();
      MaterialCapacities := nil;
      MaterialFactoryRates := nil;
      MaterialConsumerCounts := nil;
      Writeln('    CurrentGroundMass = ', CurrentGroundMass:0:1, ' kg');

      // COMPUTE MAX RATES AND CAPACITIES
      // Total mining rate
      TotalMinerMaxRate := TRate.Zero;
      if (FMiners).IsNotEmpty then
      begin
         for Miner in FMiners.Without(nil) do
            TotalMinerMaxRate := TotalMinerMaxRate + Miner.GetMinerMaxRate();
         Writeln('    ', FMiners.Length, ' miners, total mining rate ', TotalMinerMaxRate.ToString('kg'));
         Assert(FMiners.IsEmpty or TotalMinerMaxRate.IsPositive);
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
      if (FOrePiles).IsNotEmpty then
      begin
         Writeln('    ', FOrePiles.Length, ' ore piles');
         for OrePile in FOrePiles.Without(nil) do
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
      if (FRefineries).IsNotEmpty then
      begin
         Writeln('    ', FRefineries.Length, ' refineries');
         for Refinery in FRefineries.Without(nil) do
         begin
            Ore := Refinery.GetRefineryOre();
            Rate := Refinery.GetRefineryMaxRate();
            OreRefiningRates[Ore] := OreRefiningRates[Ore] + Rate;
         end;
      end;
      for Ore in TOres do
      begin
         if (Assigned(FMaterialPileComposition)) then
         begin
            Composition := FMaterialPileComposition[Encyclopedia.Materials[Ore]];
         end
         else
         begin
            Composition := 0;
         end;
         Writeln('    ', Encyclopedia.Materials[Ore].Name:20, ' mining at ', OreMiningRates[Ore].ToString('kg'), ', refining at max ', OreRefiningRates[Ore].ToString('kg'), ', ', FGroundComposition[Ore], '/', FOrePileComposition[Ore], '/', Composition);
      end;
      // Material pile capacity
      if (FMaterialPiles).IsNotEmpty then
      begin
         Writeln('    ', FMaterialPiles.Length, ' material piles');
         Count := FMaterialPiles.Length;
         if (Count < 1) then
            Count := 1;
         MaterialCapacities := TMaterialQuantityHashTable.Create(Count);
         for Pile in FMaterialPiles.Without(nil) do
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

      // Factories
      // TODO: factories
      // if (FFactories).IsNotEmpty then
      // begin
      //    Count := FFactories.Length;
      //    if (Count < 1) then
      //       Count := 1;
      //    MaterialFactoryRates := TMaterialRateHashTable.Create(Count);
      // end;
      // TODO: factories need to affect MaterialFactoryRates

      if (FMaterialConsumers).IsNotEmpty then
      begin
         Writeln('    Consumers: ', FMaterialConsumers.Length);
         Count := FMaterialConsumers.Length;
         if (Count < 1) then
            Count := 1;
         MaterialConsumerCounts := TMaterialQuantityHashTable.Create(Count);
         for MaterialConsumer in FMaterialConsumers.Without(nil) do
         begin
            Material := MaterialConsumer.GetMaterialConsumerMaterial();
            if (Assigned(Material)) then
            begin
               MaterialConsumerCounts.Inc(Material, 1);
               Assert((not Assigned(FMaterialPileComposition)) or (not FMaterialPileComposition.Has(Material)) or (FMaterialPileComposition[Material] = 0));
               Writeln('       + ', HexStr(MaterialConsumer), ' consuming ', HexStr(Material), ': ', Material.Name)
            end
            else
               Writeln('       + ', HexStr(MaterialConsumer), ' consuming ', HexStr(Material), ': nil');
         end;
      end;

      // COMPUTE ACTUAL RATES

      TimeUntilAnyMaterialPileEmpty := TMillisecondsDuration.Infinity;

      // TODO: Consumers that aren't dealing with ores.

      // Refineries
      TimeUntilAnyOrePileEmpty := TMillisecondsDuration.Infinity;
      TimeUntilAnyMaterialPileFull := TMillisecondsDuration.Infinity;
      TotalMiningToRefineryRate := TRate.Zero;
      for Ore in TOres do
      begin
         Material := Encyclopedia.Materials[Ore];
         RefiningRate := OreRefiningRates[Ore];
         if (RefiningRate.IsZero) then
         begin
            // TODO: handle factories when relevant material pile is not empty
            if (FMaterialConsumers).IsNotEmpty then
            begin
               for MaterialConsumer in FMaterialConsumers.Without(nil) do
               begin
                  if (MaterialConsumer.GetMaterialConsumerMaterial() = Material) then
                  begin
                     // If we have consumers who want this, then by definition there's none of that material in
                     // our piles (because they would have taken that first before calling us).
                     Assert((not Assigned(FMaterialPileComposition)) or (not FMaterialPileComposition.Has(Material)) or (FMaterialPileComposition[Material] = 0));
                     MaterialConsumer.StartMaterialConsumer(Self, TRate.Zero);
                  end;
               end;
            end;
            continue;
         end;
         Writeln('    Refining ', Encyclopedia.Materials[Ore].Name, ', max rate ', RefiningRate.ToString('kg'));
         MaterialConsumptionRate := TRate.Zero;
         if (Assigned(MaterialConsumerCounts) and MaterialConsumerCounts.Has(Material)) then
         begin
            Assert((not Assigned(FMaterialPileComposition)) or (not FMaterialPileComposition.Has(Material)) or (FMaterialPileComposition[Material] = 0));
            MaterialConsumptionRate := TRate.Infinity;
         end
         else
         if (Assigned(MaterialFactoryRates) and MaterialFactoryRates.Has(Material)) then
         begin
            MaterialConsumptionRate := MaterialFactoryRates[Material];
         end;
         Writeln('      MaterialConsumptionRate = ', MaterialConsumptionRate.ToString('units'));
         OrePileEmpty := (OreMiningRates[Ore] < RefiningRate) and (FOrePileComposition[Ore] = 0.0);
         Writeln('      OreMiningRates = ', OreMiningRates[Ore].ToString('kg'));
         Writeln('      FOrePileComposition = ', FOrePileComposition[Ore], ' units');
         Writeln('      OrePileEmpty = ', OrePileEmpty);
         if (Assigned(MaterialCapacities)) then
         begin
            if (Assigned(FMaterialPileComposition) and FMaterialPileComposition.Has(Material)) then
            begin
               Composition := FMaterialPileComposition[Material];
            end
            else
            begin
               Composition := 0;
            end;
            MaterialPileFull := (MaterialConsumptionRate < RefiningRate) and (Composition >= MaterialCapacities[Material]);
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
               if (OreMiningRates[Ore] < MaterialConsumptionRate) then
               begin
                  Ratio := OreMiningRates[Ore] / RefiningRate;
               end
               else
               begin
                  Assert(MaterialConsumptionRate.IsFinite);
                  Ratio := MaterialConsumptionRate / RefiningRate;
               end;
               TimeUntilThisMaterialPileFull := TMillisecondsDuration.Infinity;
            end
            else
            begin
               Writeln('      Refining of ', Encyclopedia.Materials[Ore].Name, ' is limited by incoming ore (mining at ', OreMiningRates[Ore].ToString('kg'), ' vs refining at ', RefiningRate.ToString('kg'), ')');
               Ratio := OreMiningRates[Ore] / RefiningRate;
               if ((OreMiningRates[Ore].IsPositive) and (RefiningRate > MaterialConsumptionRate)) then
               begin
                  TimeUntilThisMaterialPileFull := (MaterialCapacities[Material] - GetTotalMaterialPileQuantity(Material)) * Material.MassPerUnit / (RefiningRate * Ratio - MaterialConsumptionRate);
                  Assert(TimeUntilThisMaterialPileFull.IsPositive);
               end
               else
               begin
                  // we're mining then immediately refining then immediately consuming
                  TimeUntilThisMaterialPileFull := TMillisecondsDuration.Infinity;
               end;
            end;
            TimeUntilThisOrePileEmpty := TMillisecondsDuration.Infinity;
         end
         else
         begin
            if (MaterialPileFull) then
            begin
               Assert(MaterialConsumptionRate.IsFinite);
               TargetLimiting := True;
               Ratio := MaterialConsumptionRate / RefiningRate;
               TimeUntilThisMaterialPileFull := TMillisecondsDuration.Infinity;
            end
            else
            begin
               Ratio := 1.0;
               Writeln('      Full rate refining accepted. Capacity=', MaterialCapacities[Material], '; Current=', GetTotalMaterialPileQuantity(Material));
               Writeln('      Refining rate = ', RefiningRate.ToString('kg'), '; consumption rate = ', MaterialConsumptionRate.ToString('kg'));
               if (RefiningRate * Ratio > MaterialConsumptionRate) then
               begin
                  TimeUntilThisMaterialPileFull := (MaterialCapacities[Material] - GetTotalMaterialPileQuantity(Material)) * Material.MassPerUnit / (RefiningRate * Ratio - MaterialConsumptionRate);
                  Writeln('      Remaining time until material pile is full: ', TimeUntilThisMaterialPileFull.ToString());
                  Assert(TimeUntilThisMaterialPileFull.IsPositive);
               end
               else // we're consuming everything immediately
                  TimeUntilThisMaterialPileFull := TMillisecondsDuration.Infinity;
            end;
            if (OreMiningRates[Ore] < RefiningRate * Ratio) then
            begin
               TimeUntilThisOrePileEmpty := FOrePileComposition[Ore] * Encyclopedia.Materials[Ore].MassPerUnit / (RefiningRate * Ratio - OreMiningRates[Ore]);
               Assert(TimeUntilThisOrePileEmpty.IsPositive);
               Writeln('      Remaining time until ore piles are empty of this ore: ', TimeUntilThisOrePileEmpty.ToString());
            end
            else
               TimeUntilThisOrePileEmpty := TMillisecondsDuration.Infinity;
         end;
         Writeln('      Refining ratio: ', Ratio:0:5, ' (i.e. ', Refinery.GetRefineryMaxRate().ToString('kg'), ' * ', Ratio:0:5, ' => ', (Refinery.GetRefineryMaxRate() * Ratio).ToString('kg'), ')');
         for Refinery in FRefineries.Without(nil) do
         begin
            if (Refinery.GetRefineryOre() = Ore) then
            begin
               Refinery.StartRefinery(Self, Refinery.GetRefineryMaxRate() * Ratio, SourceLimiting, TargetLimiting);
            end;
         end;
         // TODO: Turn on factories that can operate without running out
         // of source materials or storage for output, and turn off those
         // that cannot; adjust MaterialFactoryRates accordingly.
         if (Assigned(MaterialConsumerCounts) and MaterialConsumerCounts.Has(Material)) then
         begin
            Writeln('     Consumers: ', MaterialConsumerCounts[Material]);
            Assert(MaterialConsumerCounts[Material] > 0);
            Assert(MaterialConsumptionRate.IsInfinite);
            if (Assigned(MaterialFactoryRates) and MaterialFactoryRates.Has(Material)) then
               MaterialConsumptionRate := MaterialFactoryRates[Material]
            else
               MaterialConsumptionRate := TRate.Zero;
            MaterialConsumptionRate := ((RefiningRate / Material.MassPerUnit) * Ratio - MaterialConsumptionRate) / MaterialConsumerCounts[Material];
            Writeln('     consumer rate: ', MaterialConsumptionRate.ToString('units'));
            Assert(MaterialConsumptionRate.IsZero or MaterialConsumptionRate.IsPositive);
            for MaterialConsumer in FMaterialConsumers.Without(nil) do
            begin
               if (MaterialConsumer.GetMaterialConsumerMaterial() = Material) then
               begin
                  Writeln('       - starting ', HexStr(MaterialConsumer));
                  MaterialConsumer.StartMaterialConsumer(Self, MaterialConsumptionRate);
               end;
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
         Writeln('    Considering mining options...');
         if ((TotalMinerMaxRate.IsPositive) and ((RemainingOrePileCapacity >= MinMassTransfer) or (TotalMinerMaxRate <= TotalMiningToRefineryRate))) then
         begin
            Writeln('     Mining at max rate.');
            if (TotalMinerMaxRate > TotalMiningToRefineryRate) then
            begin
               TimeUntilOrePilesFull := RemainingOrePileCapacity / (TotalMinerMaxRate - TotalMiningToRefineryRate);
               Writeln('     TimeUntilOrePilesFull:');
               Writeln('       RemainingOrePileCapacity = ', RemainingOrePileCapacity:0:9);
               Writeln('       TotalMinerMaxRate = ', TotalMinerMaxRate.AsDouble:0:9);
               Writeln('       TotalMiningToRefineryRate = ', TotalMiningToRefineryRate.AsDouble:0:9);
               Assert(TimeUntilOrePilesFull.IsPositive);
            end;
            TimeUntilGroundEmpty := CurrentGroundMass / TotalMinerMaxRate;
            Assert(TimeUntilGroundEmpty.IsPositive);
            // ready to go, start the miners!
            if (FMiners.IsNotEmpty) then
            begin
               for Miner in FMiners.Without(nil) do
                  Miner.StartMiner(Self, Miner.GetMinerMaxRate(), False, False);
            end;
            FDynamic := True;
         end
         else
         if ((TotalMinerMaxRate.IsPositive) and (TotalMiningToRefineryRate.IsPositive)) then
         begin
            // piles are full, but we are refining, so there is room being made
            Writeln('      Mining for refineries.');
            Writeln('        CurrentGroundMass: ', CurrentGroundMass:0:2);
            Writeln('        TotalMinerMaxRate: ', TotalMinerMaxRate.ToString('kg'));
            Writeln('        TotalMiningToRefineryRate: ', TotalMiningToRefineryRate.ToString('kg'));
            Assert(TotalMiningToRefineryRate < TotalMinerMaxRate);
            if (FMiners.IsNotEmpty) then
            begin
               for Miner in FMiners.Without(nil) do
                  Miner.StartMiner(Self, TotalMiningToRefineryRate * (Miner.GetMinerMaxRate() / TotalMinerMaxRate), False, True);
            end;
            TimeUntilGroundEmpty := CurrentGroundMass / TotalMiningToRefineryRate;
            Assert(TimeUntilGroundEmpty.IsPositive);
            Writeln('        TimeUntilGroundEmpty: ', TimeUntilGroundEmpty.ToString());
            FDynamic := True;
         end
         else
         begin
            // piles are full, stop the miners
            Writeln('      Not mining; nowhere to mine to.');
            Writeln('        TotalMinerMaxRate: ', TotalMinerMaxRate.ToString('kg'));
            Writeln('        TotalMiningToRefineryRate: ', TotalMiningToRefineryRate.ToString('kg'));
            if (FMiners.IsNotEmpty) then
            begin
               for Miner in FMiners.Without(nil) do
                  Miner.StartMiner(Self, TRate.Zero, False, True);
            end;
         end;
      end
      else
      begin
         // ground is empty, stop the miners
         Writeln('    Ground is empty; no mining.');
         if (FMiners.IsNotEmpty) then
         begin
            for Miner in FMiners.Without(nil) do
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
         FDynamic := True;
      end
      else
      begin
         if (FDynamic) then
         begin
            Writeln('    Situation is pseudo-static, not scheduling an event.');
         end
         else
         begin
            Writeln('    Situation is static, not scheduling an event.');
         end;
         Assert(FAnchorTime.IsInfinite);
      end;
      FActive := True;
      if (FDynamic) then
      begin
         if (FAnchorTime.IsInfinite) then
         begin
            FAnchorTime := CachedSystem.Now;
            Writeln('    Anchoring time at ', FAnchorTime.ToString(), ' (now)');
         end
         else
         begin
            Writeln('    Anchoring time at ', FAnchorTime.ToString(), ' (', (FAnchorTime - CachedSystem.Now).ToString(), ' ago)');
         end;
         if (Assigned(FNextEvent)) then
            Writeln('    Situation is dynamic, next sync should be at ', (FAnchorTime + TimeUntilNextEvent).ToString());
      end
      else
      begin
         Assert(FAnchorTime.IsInfinite);
      end;
      FreeAndNil(MaterialFactoryRates);
      FreeAndNil(MaterialCapacities);
      FreeAndNil(MaterialConsumerCounts);
   end;
   {$IFOPT C+}
   Rate := Parent.MassFlowRate;
   Assert(Rate.IsNearZero, '  Ended with non-zero mass flow rate: ' + Rate.ToString('kg'));
   {$ENDIF}
   {$IFOPT C+} Assert(Busy); Busy := False; {$ENDIF}
   Assert(FDynamic = not FAnchorTime.IsInfinite);
   Writeln('== END OF ', Parent.DebugName);
end;


procedure TRegionFeatureNode.RemoveMiner(Miner: IMiner);
begin
   if (FDynamic) then
   begin
      Sync();
      if (Assigned(FNextEvent)) then
         CancelEvent(FNextEvent);
   end;
   Assert(not Assigned(FNextEvent));
   FMiners.Replace(Miner, nil);
   Pause();
   Assert(not FActive);
   Assert(not FDynamic);
   MarkAsDirty([dkNeedsHandleChanges]);
end;

procedure TRegionFeatureNode.RemoveOrePile(OrePile: IOrePile);
begin
   if (FDynamic) then
   begin
      Sync();
      if (Assigned(FNextEvent)) then
         CancelEvent(FNextEvent);
   end;
   Assert(not Assigned(FNextEvent));
   FOrePiles.Replace(OrePile, nil);
   Pause();
   Assert(not FActive);
   Assert(not FDynamic);
   MarkAsDirty([dkNeedsHandleChanges]);
end;

procedure TRegionFeatureNode.RemoveRefinery(Refinery: IRefinery);
begin
   if (FDynamic) then
   begin
      Sync();
      if (Assigned(FNextEvent)) then
         CancelEvent(FNextEvent);
   end;
   Assert(not Assigned(FNextEvent));
   FRefineries.Replace(Refinery, nil);
   Pause();
   Assert(not FActive);
   Assert(not FDynamic);
   MarkAsDirty([dkNeedsHandleChanges]);
end;

procedure TRegionFeatureNode.RemoveMaterialPile(MaterialPile: IMaterialPile);
begin
   if (FDynamic) then
   begin
      Sync();
      if (Assigned(FNextEvent)) then
         CancelEvent(FNextEvent);
   end;
   Assert(not Assigned(FNextEvent));
   FMaterialPiles.Replace(MaterialPile, nil);
   Pause();
   Assert(not FActive);
   Assert(not FDynamic);
   MarkAsDirty([dkNeedsHandleChanges]);
end;

// TODO: factories

procedure TRegionFeatureNode.RemoveMaterialConsumer(MaterialConsumer: IMaterialConsumer);
begin
   Writeln(DebugName, ' :: RemoveMaterialConsumer(', HexStr(MaterialConsumer), ')');
   if (FDynamic) then
   begin
      Sync();
      if (Assigned(FNextEvent)) then
         CancelEvent(FNextEvent);
   end;
   Assert(not Assigned(FNextEvent));
   FMaterialConsumers.Replace(MaterialConsumer, nil);
   Pause();
   Assert(not FActive);
   Assert(not FDynamic);
   MarkAsDirty([dkNeedsHandleChanges]);
end;

procedure TRegionFeatureNode.SyncForMaterialConsumer();
{$IFOPT C+}
var
   HadEvent: Boolean;
{$ENDIF}
begin
   Writeln(DebugName, ' :: SyncForMaterialConsumer()');
   {$IFOPT C+} HadEvent := Assigned(FNextEvent); {$ENDIF}
   Assert(FDynamic);
   Sync();
   Assert(FDynamic);
   {$IFOPT C+} Assert(HadEvent = Assigned(FNextEvent)); {$ENDIF}
end;

procedure TRegionFeatureNode.ReconsiderMaterialConsumer(MaterialConsumer: IMaterialConsumer);
begin
   Writeln(DebugName, ' :: ReconsiderMaterialConsumer(', HexStr(MaterialConsumer), ')');
   Assert(FMaterialConsumers.Contains(MaterialConsumer));
   if (FDynamic) then
   begin
      Sync();
      if (Assigned(FNextEvent)) then
         CancelEvent(FNextEvent);
   end;
   Assert(not Assigned(FNextEvent));
   Pause();
   Assert(not FActive);
   Assert(not FDynamic);
   MarkAsDirty([dkNeedsHandleChanges]);
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
   Assert(FOrePiles.Contains(Pile));
   if (FDynamic) then
      Sync(); // TODO: mark all the assets as needing client updates
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

function TRegionFeatureNode.GetMaterialPileQuantity(Pile: IMaterialPile): UInt64; // units
var
   Material: TMaterial;
   PileRatio: Double;
begin
   Material := Pile.GetMaterialPileMaterial();
   PileRatio := Pile.GetMaterialPileCapacity() / GetTotalMaterialPileCapacity(Material);
   Result := RoundUInt64(GetTotalMaterialPileQuantity(Material) * PileRatio);
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
begin
   Visibility := Parent.ReadVisibilityFor(DynastyIndex, CachedSystem);
   if ((dmDetectable * Visibility <> []) and (dmClassKnown in Visibility)) then
   begin
      Writer.WriteCardinal(fcRegion);
      Assert(Length(FGroundComposition) > 0);
      Writer.WriteBoolean(IsMinable); // if we add more flags, they should go into this byte
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
end;

procedure TRegionFeatureNode.DescribeExistentiality(var IsDefinitelyReal, IsDefinitelyGhost: Boolean);
begin
   IsDefinitelyReal := True;
end;

initialization
   RegisterFeatureClass(TRegionFeatureClass);
end.