{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit region;

interface

{$DEFINE VERBOSE}

uses
   systems, internals, serverstream, materials, time,
   hashtable, genericutils, isdprotocol, plasticarrays,
   commonbuses, systemdynasty, masses, isdnumbers, annotatedpointer;

type
   TRegionFeatureNode = class;

   TStallReason = (srInput, srOutput);
   
   generic TRegionClientFields <R> = packed record // used by miners and refineries
   private
      type
         TClientLimits = (clNoRegion, clSourceLimited, clTargetLimited);
   strict private
      FRegion: specialize TAnnotatedPointer<TRegionFeatureNode, TClientLimits>; // 8 bytes
      FRateLimit: Double; // 8 bytes
      FRate: R; // 8 bytes
      FDisabledReasons: TDisabledReasons; // 4 bytes
      FPendingFraction: Fraction32; // 4 bytes;
      function GetRegion(): TRegionFeatureNode; inline;
      function GetNeedsConnection(): Boolean; inline;
      function GetConnected(): Boolean; inline;
      function GetSourceLimiting(): Boolean; inline;
      function GetTargetLimiting(): Boolean; inline;
      function GetDisabledReasons(): TDisabledReasons;
   public
      property DisabledReasons: TDisabledReasons read GetDisabledReasons; // intended for Serialize, may not match value given to SetDisabledReasons
      property RateLimit: Double read FRateLimit;
      property NeedsConnection: Boolean read GetNeedsConnection;
      property Connected: Boolean read GetConnected;
      property Region: TRegionFeatureNode read GetRegion;
      property Rate: R read FRate;
      property SourceLimiting: Boolean read GetSourceLimiting;
      property TargetLimiting: Boolean read GetTargetLimiting;
      function GetPendingFraction(): PFraction32;
   public
      procedure SetDisabledReasons(Value: TDisabledReasons; ARateLimit: Double);
      procedure SetRegion(ARegion: TRegionFeatureNode);
      function Update(ARate: R; ASourceLimiting, ATargetLimiting: Boolean): Boolean; // returns whether anything changed
      procedure SetNoRegion(); inline;
      procedure Reset();
   end;
   {$IF SIZEOF(TRegionClientFields) > 4*8} {$FATAL} {$ENDIF}

   IMiner = interface ['IMiner']
      function GetMinerMaxRate(): TMassRate; // kg per second
      function GetMinerCurrentRate(): TMassRate; // kg per second
      procedure SetMinerRegion(Region: TRegionFeatureNode);
      procedure StartMiner(Rate: TMassRate; SourceLimiting, TargetLimiting: Boolean);
      procedure DisconnectMiner();
      function GetDynasty(): TDynasty;
   end;
   TRegisterMinerBusMessage = specialize TRegisterProviderBusMessage<TPhysicalConnectionBusMessage, IMiner>;
   TMinerList = specialize PlasticArray<IMiner, PointerUtils>;

   IOrePile = interface ['IOrePile']
      function GetOrePileCapacity(): TMass;
      procedure SetOrePileRegion(Region: TRegionFeatureNode);
      procedure RegionAdjustedOrePiles();
      procedure DisconnectOrePile();
      function GetDynasty(): TDynasty;
   end;
   TRegisterOrePileBusMessage = specialize TRegisterProviderBusMessage<TPhysicalConnectionBusMessage, IOrePile>;
   TOrePileList = specialize PlasticArray<IOrePile, PointerUtils>;

   IRefinery = interface ['IRefinery']
      function GetRefineryOre(): TOres;
      function GetRefineryMaxRate(): TQuantityRate;
      function GetRefineryCurrentRate(): TQuantityRate;
      procedure SetRefineryRegion(Region: TRegionFeatureNode);
      procedure StartRefinery(Rate: TQuantityRate; SourceLimiting, TargetLimiting: Boolean);
      procedure DisconnectRefinery();
      function GetDynasty(): TDynasty;
      function GetPendingFraction(): PFraction32;
   end;
   TRegisterRefineryBusMessage = specialize TRegisterProviderBusMessage<TPhysicalConnectionBusMessage, IRefinery>;
   TRefineryList = specialize PlasticArray<IRefinery, PointerUtils>;

   IMaterialPile = interface ['IMaterialPile']
      function GetMaterialPileMaterial(): TMaterial;
      function GetMaterialPileCapacity(): TQuantity64; // quantity
      procedure SetMaterialPileRegion(Region: TRegionFeatureNode);
      procedure RegionAdjustedMaterialPiles();
      procedure DisconnectMaterialPile();
      function GetDynasty(): TDynasty;
   end;
   TRegisterMaterialPileBusMessage = specialize TRegisterProviderBusMessage<TPhysicalConnectionBusMessage, IMaterialPile>;
   TMaterialPileList = specialize PlasticArray<IMaterialPile, PointerUtils>;

   IFactory = interface ['IFactory']
      function GetFactoryInputs(): TMaterialQuantity32Array;
      function GetFactoryOutputs(): TMaterialQuantity32Array;
      function GetFactoryRate(): TIterationsRate; // instances (not units!) per second; starts returning zero if stalled
      procedure SetFactoryRegion(Region: TRegionFeatureNode);
      procedure StartFactory();
      procedure StallFactory(Reason: TStallReason); // disconnects the factory as well
      procedure DisconnectFactory();
      function GetDynasty(): TDynasty;
      function GetPendingFraction(): PFraction32;
      procedure IncBacklog();
      function GetBacklog(): Cardinal;
      procedure ResetBacklog();
   end;
   FactoryUtils = specialize DefaultUnorderedUtils<IFactory>;
   TRegisterFactoryBusMessage = specialize TRegisterProviderBusMessage<TPhysicalConnectionBusMessage, IFactory>;
   TFactoryList = specialize PlasticArray<IFactory, PointerUtils>;
   
   IMaterialConsumer = interface ['IMaterialConsumer']
      // Consumers grab material as far as possible, and only register when the piles are empty.
      // They might unregister a bit late, in which case GetMaterialConsumerMaterial() can return nil.
      function GetMaterialConsumerMaterial(): TMaterial;
      function GetMaterialConsumerMaxDelivery(): TQuantity32;
      function GetMaterialConsumerCurrentRate(): TQuantityRate; // returns the value set by StartMaterialConsumer
      procedure SetMaterialConsumerRegion(Region: TRegionFeatureNode);
      procedure StartMaterialConsumer(ActualRate: TQuantityRate); // quantity per second; only called if GetMaterialConsumerMaterial returns non-nil
      procedure DeliverMaterialConsumer(Delivery: TQuantity32); // 0 <= Delivery <= GetMaterialConsumerMaxDelivery; will always be called when syncing if StartMaterialConsumer was called
      procedure DisconnectMaterialConsumer(); // region is going away
      function GetDynasty(): TDynasty;
      function GetPendingFraction(): PFraction32;
      {$IFOPT C+} function GetAsset(): TAssetNode; {$ENDIF}
   end;
   TRegisterMaterialConsumerBusMessage = specialize TRegisterProviderBusMessage<TPhysicalConnectionBusMessage, IMaterialConsumer>;
   TMaterialConsumerList = specialize PlasticArray<IMaterialConsumer, PointerUtils>;

   TObtainMaterialBusMessage = class(TPhysicalConnectionBusMessage)
   strict private
      FDynasty: TDynasty;
      FRequest: TMaterialQuantity64;
      FDelivery: TQuantity32;
      function GetRemainingQuantity(): TQuantity32; inline;
      function GetFulfilled(): Boolean; inline;
      function GetTransferredManifest(): TMaterialQuantity64; inline;
   public
      constructor Create(ADynasty: TDynasty; ARequest: TMaterialQuantity64); overload;
      constructor Create(ADynasty: TDynasty; AMaterial: TMaterial; AQuantity: TQuantity32); overload;
      procedure Deliver(ADelivery: TQuantity32);
      property Dynasty: TDynasty read FDynasty;
      property Material: TMaterial read FRequest.Material;
      property Quantity: TQuantity32 read GetRemainingQuantity;
      property Fulfilled: Boolean read GetFulfilled;
      property TransferredManifest: TMaterialQuantity64 read GetTransferredManifest;
   end;

   TStoreMaterialBusMessage = class(TPhysicalConnectionWithExclusionBusMessage)
   strict private
      FDynasty: TDynasty;
      FRequest: TMaterialQuantity64;
      FStored: TQuantity64;
      function GetRemainingQuantity(): TQuantity64; inline;
      function GetFulfilled(): Boolean; inline;
      function GetTransferredManifest(): TMaterialQuantity64; inline;
   public
      constructor Create(AAsset: TAssetNode; ADynasty: TDynasty; ARequest: TMaterialQuantity64); overload;
      constructor Create(AAsset: TAssetNode; ADynasty: TDynasty; AMaterial: TMaterial; AQuantity: TQuantity64); overload;
      procedure Store(ADelivery: TQuantity64);
      property Dynasty: TDynasty read FDynasty;
      property Material: TMaterial read FRequest.Material;
      property RemainingQuantity: TQuantity64 read GetRemainingQuantity;
      property Fulfilled: Boolean read GetFulfilled;
      property TransferredManifest: TMaterialQuantity64 read GetTransferredManifest;
   end;

   TSampleOreBusMessage = class(TPhysicalConnectionBusMessage)
   strict private
      FDynasty: TDynasty;
      FSize: Double;
      FMaterial: TMaterial;
      FQuantity: TQuantity64;
   public
      constructor Create(ADynasty: TDynasty; ASize: Double);
      destructor Destroy(); override;
      property Dynasty: TDynasty read FDynasty;
      property Size: Double read FSize;
      procedure Provide(AMaterial: TMaterial; AQuantity: TQuantity64);
      function Accept(): TMaterialQuantity64;
   end;

   TStoreOreBusMessage = class(TPhysicalConnectionBusMessage)
   strict private
      FDynasty: TDynasty;
      FOre: TOres;
      FQuantity: TQuantity64;
   public
      constructor Create(ADynasty: TDynasty; AOre: TOres; AQuantity: TQuantity64);
      destructor Destroy(); override;
      property Dynasty: TDynasty read FDynasty;
      function Accept(): TOreQuantity64;
   end;

   TDumpOreBusMessage = class(TPhysicalConnectionBusMessage)
   strict private
      FOre: TOres;
      FQuantity: TQuantity64;
   public
      constructor Create(AOre: TOres; AQuantity: TQuantity64);
      destructor Destroy(); override;
      function Accept(): TOreQuantity64;
   end;

type
   TRegionFeatureClass = class(TFeatureClass)
   strict private
      FDepth: Cardinal;
      FTargetCount: Cardinal;
   strict protected
      function GetFeatureNodeClass(): FeatureNodeReference; override;
   public
      constructor Create(ADepth: Cardinal; ATargetCount: Cardinal);
      constructor CreateFromTechnologyTree(const Reader: TTechTreeReader); override;
      function InitFeatureNode(ASystem: TSystem): TFeatureNode; override;
      property Depth: Cardinal read FDepth;
      property TargetCount: Cardinal read FTargetCount;
   end;

   TRegionFeatureNode = class(TFeatureNode)
   private
      type
         PPerDynastyData = ^TPerDynastyData;
         TPerDynastyData = record
            // The mass contained in FOrePileComposition is distributed
            // evenly to the FOrePiles (in the sense that each ore pile is
            // the same % full).
            FOrePileComposition: TOreQuantities;
            FMaterialPileComposition: TMaterialQuantityHashTable; // allocated on demand
            FMiners: TMinerList;
            FOrePiles: TOrePileList;
            FRefineries: TRefineryList;
            FMaterialPiles: TMaterialPileList;
            FFactories: TFactoryList;
            FMaterialConsumers: TMaterialConsumerList;
            FOrePileMassFlowRate: TMassRate;
            FPendingMiningDebt: TMass;
            class operator Initialize(var Rec: TPerDynastyData); // fills the record with zeroes
            class operator Finalize(var Rec: TPerDynastyData); // frees the allocated substructures
            procedure IncMaterialPile(Material: TMaterial; Delta: TQuantity64);
            procedure DecMaterialPile(Material: TMaterial; Delta: TQuantity64);
            function ClampedDecMaterialPile(Material: TMaterial; Delta: TQuantity64): TQuantity64; // returns how much was actually transferred
         end;
         TDynastyTable = specialize THashTable<TDynasty, TPerDynastyData, PointerUtils>;
         TRegionData = record
         strict private
            class operator Initialize(var Rec: TRegionData);
            class operator Finalize(var Rec: TRegionData);
            function GetData(Dynasty: TDynasty): PPerDynastyData;
         public
            type
               TDynastyMode = (dmNone, dmOne, dmMany);
               TDynastyEnumerator = class
               private
                  FDynasty: TDynasty;
                  FEnumerator: TDynastyTable.TKeyEnumerator;
                  FStarted: Boolean;
                  function GetCurrent(): TDynasty;
               public
                  destructor Destroy(); override;
                  function MoveNext(): Boolean;
                  property Current: TDynasty read GetCurrent;
                  function GetEnumerator(): TDynastyEnumerator; inline;
               end;
         private
            function GetDynastyEnumerator(): TDynastyEnumerator;
            function GetDynastyMode(): TDynastyMode; inline;
            function GetSingleDynastyData(): PPerDynastyData; inline;
         public
            function HasDynasty(Dynasty: TDynasty): Boolean; inline;
            property Data[Dynasty: TDynasty]: PPerDynastyData read GetData; default;
            property Dynasties: TDynastyEnumerator read GetDynastyEnumerator;
            property DynastyMode: TDynastyMode read GetDynastyMode;
            property SingleDynastyData: PPerDynastyData read GetSingleDynastyData;
         strict private
            const
               MultiDynastyMarker = $0001;
            var
               FDynasty: TDynasty;
               case TDynastyMode of
                  dmNone: (FNil: Pointer); // no dynasty (FDynasty is nil)
                  dmOne: (FSingleDynastyData: PPerDynastyData); // (FDynasty is a pointer)
                  dmMany: (FDynastyTable: TDynastyTable); // (FDynasty = MultiDynastyMarker)
         end; // {$IF SIZEOF(TRegionData) <> SIZEOF(Pointer) * 2} {$FATAL} {$ENDIF}
   private
      FFeatureClass: TRegionFeatureClass;
      FGroundComposition: TOreQuantities;
      FAnchorTime: TTimeInMilliseconds; // set to Low(FAnchorTime) or Now when transfers are currently synced
      FNextEvent: TSystemEvent; // set only when mass is moving
      FAllocatedOres: Boolean; // TODO: we shouldn't have to store this forever just to track if we've initialized correctly
      FActive: Boolean; // set to true when transfers are set up, set to false when transfers need to be set up
      FDynamic: Boolean; // set to true when the situation is dynamic (i.e. Sync() would do something)
      FData: TRegionData;
      FNetMiningRate: TMassRate;
      {$IFOPT C+} Busy: Boolean; {$ENDIF} // set to true while running our algorithms, to make sure nobody calls us reentrantly
      function GetTotalOrePileCapacity(Dynasty: TDynasty): TMass; // kg total for all piles
      function GetTotalOrePileMass(Dynasty: TDynasty): TMass; // total for all piles
      function GetTotalOrePileMassFlowRate(Dynasty: TDynasty): TMassRate; // kg/s (total for all piles; actual miner rate minus total refinery rate)
      function GetMaxUnitOreMassTransfer(): TMass; // kg mass of largest single quantity we could mine
      function GetTotalMaterialPileQuantity(Dynasty: TDynasty; Material: TMaterial): TQuantity64;
      function GetTotalMaterialPileQuantityFlowRate(Dynasty: TDynasty; Material: TMaterial): TQuantityRate; // units/s
      function GetTotalMaterialPileCapacity(Dynasty: TDynasty; Material: TMaterial): TQuantity64;
      function GetTotalMaterialPileMass(Dynasty: TDynasty; Material: TMaterial): TMass; // kg
      function GetTotalMaterialPileMassFlowRate(Dynasty: TDynasty; Material: TMaterial): TMassRate; // kg/s
      function GetIsMinable(): Boolean;
      procedure ReturnOreToGround(DynastyData: PPerDynastyData; TotalOrePileMass, TotalTransferMass: TMass);
   protected
      constructor CreateFromJournal(Journal: TJournalReader; AFeatureClass: TFeatureClass; ASystem: TSystem); override;
      function GetMass(): TMass; override;
      function GetMassFlowRate(): TMassRate; override;
      function ManageBusMessage(Message: TBusMessage): TInjectBusMessageResult; override;
      function HandleBusMessage(Message: TBusMessage): THandleBusMessageResult; override;
      procedure Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter); override;
      procedure Sync(); // move the ores around
      procedure SyncAndReconsider(); // sync, cancel the current scheduled event, schedule HandleChanges
      procedure HandleScheduledEvent(var Data); // same as SyncAndReconsider, but used as event handler
      procedure Reset(); // disconnect and forget all the clients (only called by Destroy)
      procedure HandleChanges(); override;
   public
      constructor Create(ASystem: TSystem; AFeatureClass: TRegionFeatureClass);
      destructor Destroy(); override;
      procedure UpdateJournal(Journal: TJournalWriter); override;
      procedure ApplyJournal(Journal: TJournalReader); override;
      procedure DescribeExistentiality(var IsDefinitelyReal, IsDefinitelyGhost: Boolean); override;
      procedure RemoveMiner(Miner: IMiner);
      procedure RemoveOrePile(OrePile: IOrePile);
      procedure RemoveRefinery(Refinery: IRefinery);
      procedure RemoveMaterialPile(MaterialPile: IMaterialPile);
      procedure RemoveFactory(Factory: IFactory);
      procedure RemoveMaterialConsumer(MaterialConsumer: IMaterialConsumer);
      procedure ClientChanged(); inline; // call when a material consumer thinks it might be done, or another client has changed rate; marks the region as dirty so everything gets recomputed
      procedure RehomeOreForPile(OrePile: IOrePile); // removes the pile, and if there isn't enough remaining capacity, puts some back in the ground.
      procedure FlattenOrePileIntoGround(OrePile: IOrePile); // removes the pile, and moves all of its contents into the ground
      function ExtractMaterialPile(MaterialPile: IMaterialPile): TQuantity64; // removes the pile and its contents; returns the quantity of material the pile had.
      function RehomeMaterialPile(MaterialPile: IMaterialPile): TQuantity64; // removes the pile, and if there isn't enough remaining capacity, returns the quantity remaining.
      function GetOrePileMass(Pile: IOrePile): TMass;
      function GetOrePileMassFlowRate(Pile: IOrePile): TMassRate; // kg/s
      function GetOresPresentForPile(Pile: IOrePile): TOreFilter;
      function GetOresForPile(Pile: IOrePile): TOreQuantities;
      function GetMaterialPileMass(Pile: IMaterialPile): TMass;
      function GetMaterialPileMassFlowRate(Pile: IMaterialPile): TMassRate; // kg/s
      function GetMaterialPileQuantity(Pile: IMaterialPile): TQuantity64;
      function GetMaterialPileQuantityFlowRate(Pile: IMaterialPile): TQuantityRate; // units/s
      property IsMinable: Boolean read GetIsMinable;
   end;

implementation

uses
   sysutils, planetary, exceptions, hashfunctions, rubble, knowledge, ttparser;

function FactoryHash32(const Key: IFactory): DWord;
begin
   Result := PtrUIntHash32(PtrUInt(Key));
end;

function TRegionClientFields.GetRegion(): TRegionFeatureNode;
begin
   Result := FRegion.Unwrap();
end;

function TRegionClientFields.GetNeedsConnection(): Boolean;
begin
   Result := (not FRegion.Assigned) and (FRegion.IsFlagClear(clNoRegion)) and (FRateLimit > 0.0);
end;

function TRegionClientFields.GetConnected(): Boolean;
begin
   Result := FRegion.Assigned;
end;

function TRegionClientFields.GetSourceLimiting(): Boolean;
begin
   Result := FRegion.IsFlagSet(clSourceLimited);
end;

function TRegionClientFields.GetTargetLimiting(): Boolean;
begin
   Result := FRegion.IsFlagSet(clTargetLimited);
end;

function TRegionClientFields.GetDisabledReasons(): TDisabledReasons;
begin
   Result := FDisabledReasons;
   if (FRegion.IsFlagSet(clNoRegion)) then
      Include(Result, drNoBus);
   if (SourceLimiting) then
      Include(Result, drSourceLimited);
   if (TargetLimiting) then
      Include(Result, drTargetLimited);
end;

function TRegionClientFields.GetPendingFraction(): PFraction32;
begin
   Result := @FPendingFraction;
end;

procedure TRegionClientFields.SetDisabledReasons(Value: TDisabledReasons; ARateLimit: Double);
begin
   FDisabledReasons := Value;
   FRateLimit := ARateLimit;
   FRate.Reset;
end;

procedure TRegionClientFields.SetRegion(ARegion: TRegionFeatureNode);
begin
   Assert(Assigned(ARegion));
   Assert(FDisabledReasons = []);
   FRegion.Wrap(ARegion);
   FRegion.ClearFlag(clNoRegion);
end;

function TRegionClientFields.Update(ARate: R; ASourceLimiting, ATargetLimiting: Boolean): Boolean;
begin
   Assert(FRegion.Assigned);
   Assert(FDisabledReasons = []);
   Result := (Rate <> ARate) or
             (SourceLimiting <> ASourceLimiting) or
             (TargetLimiting <> ATargetLimiting);
   if (Result) then
   begin
      FRate := ARate;
      FRegion.ConfigureFlag(clSourceLimited, ASourceLimiting);
      FRegion.ConfigureFlag(clTargetLimited, ATargetLimiting);
   end;
end;

procedure TRegionClientFields.SetNoRegion();
begin
   Assert(not FRegion.Assigned);
   Assert(FDisabledReasons = []);
   Assert(Rate.IsExactZero);
   Assert(not SourceLimiting);
   Assert(not TargetLimiting);
   FRegion.SetFlag(clNoRegion);
end;

procedure TRegionClientFields.Reset();
begin
   FRegion.Clear();
   FRate.Reset;
end;


constructor TObtainMaterialBusMessage.Create(ADynasty: TDynasty; ARequest: TMaterialQuantity64);
begin
   inherited Create();
   Assert(Assigned(ADynasty));
   Assert(Assigned(ARequest.Material));
   FDynasty := ADynasty;
   FRequest := ARequest;
   Assert(not Fulfilled);
end;

constructor TObtainMaterialBusMessage.Create(ADynasty: TDynasty; AMaterial: TMaterial; AQuantity: TQuantity32);
begin
   inherited Create();
   Assert(Assigned(ADynasty));
   Assert(Assigned(AMaterial));
   FDynasty := ADynasty;
   FRequest.Material := AMaterial;
   FRequest.Quantity := AQuantity;
   Assert(not Fulfilled);
end;

function TObtainMaterialBusMessage.GetRemainingQuantity(): TQuantity32;
begin
   Result := TQuantity32.FromQuantity64(FRequest.Quantity - FDelivery); // $R-
end;

function TObtainMaterialBusMessage.GetFulfilled(): Boolean;
begin
   Result := FDelivery >= FRequest.Quantity;
end;

function TObtainMaterialBusMessage.GetTransferredManifest(): TMaterialQuantity64;
begin
   if (FDelivery.IsPositive) then
   begin
      Result.Material := FRequest.Material;
      Result.Quantity := FDelivery;
   end
   else
   begin
      Result.Material := nil;
      Result.Quantity := TQuantity64.Zero;
   end;
end;

procedure TObtainMaterialBusMessage.Deliver(ADelivery: TQuantity32);
begin
   Assert(FDelivery + ADelivery <= FRequest.Quantity);
   FDelivery := FDelivery + ADelivery;
end;


constructor TStoreMaterialBusMessage.Create(AAsset: TAssetNode; ADynasty: TDynasty; ARequest: TMaterialQuantity64);
begin
   inherited Create(AAsset);
   Assert(Assigned(ADynasty));
   Assert(Assigned(ARequest.Material));
   FDynasty := ADynasty;
   FRequest := ARequest;
   Assert(FRequest.Quantity.IsPositive);
   Assert(not Fulfilled);
end;

constructor TStoreMaterialBusMessage.Create(AAsset: TAssetNode; ADynasty: TDynasty; AMaterial: TMaterial; AQuantity: TQuantity64);
begin
   inherited Create(AAsset);
   Assert(Assigned(ADynasty));
   Assert(Assigned(AMaterial));
   FDynasty := ADynasty;
   FRequest.Material := AMaterial;
   FRequest.Quantity := AQuantity;
   Assert(FRequest.Quantity.IsPositive);
   Assert(not Fulfilled);
end;

function TStoreMaterialBusMessage.GetRemainingQuantity(): TQuantity64;
begin
   Result := FRequest.Quantity - FStored; // $R-
end;

function TStoreMaterialBusMessage.GetFulfilled(): Boolean;
begin
   Result := FStored >= FRequest.Quantity;
end;

function TStoreMaterialBusMessage.GetTransferredManifest(): TMaterialQuantity64;
begin
   if (FStored.IsPositive) then
   begin
      Result.Material := FRequest.Material;
      Result.Quantity := FStored;
   end
   else
   begin
      Result.Material := nil;
      Result.Quantity := TQuantity64.Zero;
   end;
end;

procedure TStoreMaterialBusMessage.Store(ADelivery: TQuantity64);
begin
   Assert(FStored + ADelivery <= FRequest.Quantity);
   FStored := FStored + ADelivery;
end;


constructor TSampleOreBusMessage.Create(ADynasty: TDynasty; ASize: Double);
begin
   inherited Create();
   Assert(Assigned(ADynasty));
   FDynasty := ADynasty;
   FSize := ASize;
end;

destructor TSampleOreBusMessage.Destroy();
begin
   Assert(not Assigned(FMaterial));
   Assert(FQuantity.IsZero);
   inherited;
end;

procedure TSampleOreBusMessage.Provide(AMaterial: TMaterial; AQuantity: TQuantity64);
begin
   Assert(not Assigned(FMaterial));
   Assert(FQuantity.IsZero);
   Assert(Assigned(AMaterial));
   FMaterial := AMaterial;
   Assert(AQuantity <= TMass.FromKg(Size * Size * Size * FMaterial.Density) div FMaterial.MassPerUnit);
   FQuantity := AQuantity;
end;
   
function TSampleOreBusMessage.Accept(): TMaterialQuantity64;
begin
   Assert(Assigned(FMaterial));
   Assert(FQuantity.IsNotZero);
   Result.Material := FMaterial;
   Result.Quantity := FQuantity;
   FMaterial := nil;
   FQuantity := TQuantity64.Zero;
end;


constructor TStoreOreBusMessage.Create(ADynasty: TDynasty; AOre: TOres; AQuantity: TQuantity64);
begin
   inherited Create();
   Assert(Assigned(ADynasty));
   FDynasty := ADynasty;
   FOre := AOre;
   FQuantity := AQuantity;
end;

destructor TStoreOreBusMessage.Destroy();
begin
   Assert(FQuantity.IsZero);
end;
      
function TStoreOreBusMessage.Accept(): TOreQuantity64;
begin
   Assert(FQuantity.IsNotZero);
   Result.Ore := FOre;
   Result.Quantity := FQuantity;
   FQuantity := TQuantity64.Zero;
end;


constructor TDumpOreBusMessage.Create(AOre: TOres; AQuantity: TQuantity64);
begin
   inherited Create();
   FOre := AOre;
   FQuantity := AQuantity;
end;

destructor TDumpOreBusMessage.Destroy();
begin
   Assert(FQuantity.IsZero);
end;
      
function TDumpOreBusMessage.Accept(): TOreQuantity64;
begin
   Assert(FQuantity.IsNotZero);
   Result.Ore := FOre;
   Result.Quantity := FQuantity;
   FQuantity := TQuantity64.Zero;
end;


constructor TRegionFeatureClass.Create(ADepth: Cardinal; ATargetCount: Cardinal);
begin
   inherited Create();
   FDepth := ADepth;
   FTargetCount := ATargetCount;
end;

constructor TRegionFeatureClass.CreateFromTechnologyTree(const Reader: TTechTreeReader);
begin
   inherited Create();
   Reader.Tokens.ReadIdentifier('at');
   Reader.Tokens.ReadIdentifier('depth');
   FDepth := ReadNumber(Reader.Tokens, 1, 3); // $R- // hard-coded, assumes existence of mtDepth2 and mtDepth3 and no other depths
   Reader.Tokens.ReadComma();
   FTargetCount := ReadNumber(Reader.Tokens, 1, 63); // $R-
   if (FTargetCount = 1) then
      Reader.Tokens.ReadIdentifier('material')
   else
      Reader.Tokens.ReadIdentifier('materials');
end;

function TRegionFeatureClass.GetFeatureNodeClass(): FeatureNodeReference;
begin
   Result := TRegionFeatureNode;
end;

function TRegionFeatureClass.InitFeatureNode(ASystem: TSystem): TFeatureNode;
begin
   Result := TRegionFeatureNode.Create(ASystem, Self);
end;


class operator TRegionFeatureNode.TPerDynastyData.Initialize(var Rec: TPerDynastyData);
begin
   FillChar(Rec, SizeOf(Rec), 0);
   Assert(not Assigned(Rec.FMaterialPileComposition));
   Assert(PPtrUInt(@Rec.FMiners)^ = 0);
   Assert(PPtrUInt(@Rec.FOrePiles)^ = 0);
   Assert(PPtrUInt(@Rec.FRefineries)^ = 0);
   Assert(PPtrUInt(@Rec.FMaterialPiles)^ = 0);
   Assert(PPtrUInt(@Rec.FMaterialConsumers)^ = 0);
   Assert(Rec.FOrePileMassFlowRate.IsExactZero);
   Assert(Rec.FPendingMiningDebt.IsZero);
   // if we do anything else here, see GetData below
end;

class operator TRegionFeatureNode.TPerDynastyData.Finalize(var Rec: TPerDynastyData);
begin
   FreeAndNil(Rec.FMaterialPileComposition);
end;

procedure TRegionFeatureNode.TPerDynastyData.IncMaterialPile(Material: TMaterial; Delta: TQuantity64);
begin
   Assert(Assigned(Material));
   Assert(Delta.IsPositive);
   if (not Assigned(FMaterialPileComposition)) then
   begin
      FMaterialPileComposition := TMaterialQuantityHashTable.Create(1);
   end;
   FMaterialPileComposition.Inc(Material, Delta);
end;

procedure TRegionFeatureNode.TPerDynastyData.DecMaterialPile(Material: TMaterial; Delta: TQuantity64);
begin
   Assert(Assigned(Material));
   Assert(Delta.IsPositive);
   Assert(Assigned(FMaterialPileComposition));
   FMaterialPileComposition.Dec(Material, Delta);
end;

function TRegionFeatureNode.TPerDynastyData.ClampedDecMaterialPile(Material: TMaterial; Delta: TQuantity64): TQuantity64;
begin
   // We return how much was _actually_ transferred.
   Assert(Assigned(Material));
   Assert(Delta.IsPositive);
   if (Assigned(FMaterialPileComposition)) then
   begin
      Result := FMaterialPileComposition.ClampedDec(Material, Delta);
   end
   else
   begin
      Result := TQuantity64.Zero;
   end;
end;


class operator TRegionFeatureNode.TRegionData.Initialize(var Rec: TRegionData);
begin
   Rec.FDynasty := nil;
   Rec.FNil := nil;
end;

class operator TRegionFeatureNode.TRegionData.Finalize(var Rec: TRegionData);
begin
   if (Assigned(Rec.FDynasty)) then
   begin
      if (PtrUInt(Rec.FDynasty) = MultiDynastyMarker) then
      begin
         FreeAndNil(Rec.FDynastyTable);
      end
      else
      begin
         Finalize(Rec.FSingleDynastyData^);
         FreeMem(Rec.FSingleDynastyData);
      end;
   end;
end;

function TRegionFeatureNode.TRegionData.GetData(Dynasty: TDynasty): PPerDynastyData;
var
   OldData, NewData: PPerDynastyData;
begin
   Assert(Assigned(Dynasty));
   if (FDynasty = Dynasty) then
   begin
      Result := FSingleDynastyData;
   end
   else
   if (PtrUInt(FDynasty) = MultiDynastyMarker) then
   begin
      Result := FDynastyTable.GetOrAddPtr(Dynasty);
   end
   else
   if (not Assigned(FDynasty)) then
   begin
      FDynasty := Dynasty;
      GetMem(FSingleDynastyData, SizeOf(TPerDynastyData));
      Initialize(FSingleDynastyData^);
      Result := FSingleDynastyData;
   end
   else
   begin
      OldData := FSingleDynastyData;
      FDynastyTable := TDynastyTable.Create(@DynastyHash32);
      NewData := FDynastyTable.ItemsPtr[FDynasty];
      Move(OldData^, NewData^, SizeOf(TPerDynastyData)); // this is safe only because at this point we've guaranteed all those target bytes are zero, so there's nothing to deallocate
      FreeMem(OldData);
      PtrUInt(FDynasty) := MultiDynastyMarker;
      Result := FDynastyTable.GetOrAddPtr(Dynasty);
   end;
end;

function TRegionFeatureNode.TRegionData.GetDynastyEnumerator(): TDynastyEnumerator;
begin
   // TODO: find a more efficient way of doing this in the common case of n=0 or n=1
   // we really shouldn't need to allocate anything, or set up exception handlers, or do function calls
   if (not Assigned(FDynasty)) then
   begin
      Result := nil;
   end
   else
   begin
      Result := TDynastyEnumerator.Create();
      if (PtrUInt(FDynasty) <> MultiDynastyMarker) then
      begin
         Result.FDynasty := FDynasty;
      end
      else
      begin
         Result.FEnumerator := FDynastyTable.GetEnumerator();
      end;
   end;
end;

function TRegionFeatureNode.TRegionData.GetDynastyMode(): TDynastyMode;
begin
   if (not Assigned(FDynasty)) then
   begin
      Result := dmNone;
   end
   else
   if (PtrUInt(FDynasty) <> MultiDynastyMarker) then
   begin
      Result := dmOne;
   end
   else
   begin
      Result := dmMany;
   end;
end;

function TRegionFeatureNode.TRegionData.GetSingleDynastyData(): PPerDynastyData;
begin
   Assert(Assigned(FDynasty) and (PtrUInt(FDynasty) <> MultiDynastyMarker));
   Result := FSingleDynastyData;
end;

function TRegionFeatureNode.TRegionData.HasDynasty(Dynasty: TDynasty): Boolean;
begin
   if (not Assigned(FDynasty)) then
   begin
      Result := False;
   end
   else
   if (PtrUInt(FDynasty) <> MultiDynastyMarker) then
   begin
      Result := Dynasty = FDynasty;
   end
   else
   begin
      Result := FDynastyTable.Has(Dynasty);
   end;
end;


destructor TRegionFeatureNode.TRegionData.TDynastyEnumerator.Destroy();
begin
   FreeAndNil(FEnumerator);
   inherited;
end;

function TRegionFeatureNode.TRegionData.TDynastyEnumerator.GetCurrent(): TDynasty;
begin
   if (Assigned(FDynasty)) then
   begin
      Result := FDynasty;
   end
   else
   begin
      Result := FEnumerator.Current;
   end;
end;

function TRegionFeatureNode.TRegionData.TDynastyEnumerator.MoveNext(): Boolean;
begin
   if (Assigned(FDynasty)) then
   begin
      Result := not FStarted;
      FStarted := True;
   end
   else
   begin
      Result := FEnumerator.MoveNext();
   end;
end;

function TRegionFeatureNode.TRegionData.TDynastyEnumerator.GetEnumerator(): TDynastyEnumerator;
begin
   Result := Self;
end;


constructor TRegionFeatureNode.Create(ASystem: TSystem; AFeatureClass: TRegionFeatureClass);
begin
   inherited Create(ASystem);
   FFeatureClass := AFeatureClass;
   FAnchorTime := TTimeInMilliseconds.NegInfinity;
   Assert(not FActive);
   Assert(not FDynamic);
end;

constructor TRegionFeatureNode.CreateFromJournal(Journal: TJournalReader; AFeatureClass: TFeatureClass; ASystem: TSystem);
begin
   FFeatureClass := AFeatureClass as TRegionFeatureClass;
   Assert(Assigned(AFeatureClass));
   inherited;
   FAnchorTime := TTimeInMilliseconds.NegInfinity;
   Assert(not FActive);
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
   inherited;
end;

function TRegionFeatureNode.GetMass(): TMass;
var
   Ore: TOres;
   Encyclopedia: TEncyclopediaView;
begin
   Encyclopedia := System.Encyclopedia;
   Result := TMass.Zero;
   Assert(Length(FGroundComposition) > 0);
   for Ore := Low(FGroundComposition) to High(FGroundComposition) do // $R-
      Result := Result + FGroundComposition[Ore] * Encyclopedia.Materials[Ore].MassPerUnit;
   // The ore pile composition (see GetOrePileMass) and the material
   // pile composition are exposed on the various pile assets.
   if (FDynamic) then
      Result := Result + (System.Now - FAnchorTime) * MassFlowRate;
end;

function TRegionFeatureNode.GetMassFlowRate(): TMassRate;
begin
   Result := -FNetMiningRate;
   // Refineries, factories, and consumers affect the flow rates of
   // the pile assets (see e.g. GetOrePileMassFlowRate below).
end;

function TRegionFeatureNode.GetTotalOrePileCapacity(Dynasty: TDynasty): TMass; // total for all piles
var
   OrePile: IOrePile;
   DynastyData: PPerDynastyData;
begin
   Assert(FData.HasDynasty(Dynasty));
   Result := TMass.Zero;
   DynastyData := FData[Dynasty];
   if (DynastyData^.FOrePiles.IsNotEmpty) then
   begin
      for OrePile in DynastyData^.FOrePiles.Without(nil) do
         Result := Result + OrePile.GetOrePileCapacity();
   end;
end;

function TRegionFeatureNode.GetTotalOrePileMass(Dynasty: TDynasty): TMass; // total for all piles
var
   Ore: TOres;
   Encyclopedia: TEncyclopediaView;
   DynastyData: PPerDynastyData;
begin
   Assert(FData.HasDynasty(Dynasty));
   DynastyData := FData[Dynasty];
   Encyclopedia := System.Encyclopedia;
   Result := TMass.Zero;
   if (Length(DynastyData^.FOrePileComposition) > 0) then
      for Ore := Low(DynastyData^.FOrePileComposition) to High(DynastyData^.FOrePileComposition) do // $R-
         Result := Result + DynastyData^.FOrePileComposition[Ore] * Encyclopedia.Materials[Ore].MassPerUnit;
   Assert(not Result.IsNegative);
   if (FDynamic) then
   begin
      Assert(not FAnchorTime.IsInfinite);
      Result := Result + (System.Now - FAnchorTime) * GetTotalOrePileMassFlowRate(Dynasty);
   end;
   Assert(not Result.IsNegative);
end;

function TRegionFeatureNode.GetTotalOrePileMassFlowRate(Dynasty: TDynasty): TMassRate; // kg/s (actual miner rate minus refinery rate)
begin
   Assert(FData.HasDynasty(Dynasty));
   Result := FData[Dynasty]^.FOrePileMassFlowRate;
end;

function TRegionFeatureNode.GetOrePileMass(Pile: IOrePile): TMass;
var
   PileRatio: Double;
   Dynasty: TDynasty;
begin
   Dynasty := Pile.GetDynasty();
   PileRatio := Pile.GetOrePileCapacity() / GetTotalOrePileCapacity(Dynasty);
   Assert(PileRatio <= 1.0);
   Result := GetTotalOrePileMass(Dynasty) * PileRatio;
   Assert(Result.AsDouble <= Pile.GetOrePileCapacity().AsDouble + Epsilon, DebugName + ' computed an ore pile mass of ' + Result.ToString() + ' for a pile with capacity ' + Pile.GetOrePileCapacity().ToString() + ' (total ore pile mas is ' + GetTotalOrePileMass(Dynasty).ToString() + ', total capacity is ' + GetTotalOrePileCapacity(Dynasty).ToString() + ')');
end;

function TRegionFeatureNode.GetOrePileMassFlowRate(Pile: IOrePile): TMassRate; // kg/s
var
   RPileRatio: Double;
   Dynasty: TDynasty;
begin
   Dynasty := Pile.GetDynasty();
   // We do it in this weird order to reduce the incidence of floating point error creep.
   // It's weird but fractions are bad, and doing it this way avoids fractions.
   // (I say this is a weird order because to me the intuitive way to do this is to get
   // the PileRatio, Pile.GetOrePileCapacity() / GetTotalOrePileCapacity(), and then
   // multiply the GetTotalOrePileMassFlowRate() by that number.)
   RPileRatio := GetTotalOrePileCapacity(Dynasty) / Pile.GetOrePileCapacity();
   Result := GetTotalOrePileMassFlowRate(Dynasty) / RPileRatio;
end;

function TRegionFeatureNode.GetMaxUnitOreMassTransfer(): TMass;
var
   Ore: TOres;
   Quantity: TQuantity64;
   TransferMassPerUnit: TMassPerUnit;
   Max: TMass;
begin
   Max := TQuantity64.One * System.Encyclopedia.MaxMassPerOreUnit;
   Result := TMass.Zero;
   for Ore in TOres do
   begin
      Quantity := FGroundComposition[Ore];
      if (Quantity.IsPositive) then
      begin
         TransferMassPerUnit := System.Encyclopedia.Materials[Ore].MassPerUnit;
         if (TQuantity64.One * TransferMassPerUnit > Result) then
            Result := TQuantity64.One * TransferMassPerUnit;
         if (Result >= Max) then
            exit;
      end;
   end;
end;

function TRegionFeatureNode.GetTotalMaterialPileQuantity(Dynasty: TDynasty; Material: TMaterial): TQuantity64;
var
   DynastyData: PPerDynastyData;
begin
   Assert(FData.HasDynasty(Dynasty));
   DynastyData := FData[Dynasty];
   if (not Assigned(DynastyData^.FMaterialPileComposition)) then
   begin
      Result := TQuantity64.Zero;
   end
   else
   if (not DynastyData^.FMaterialPileComposition.Has(Material)) then
   begin
      Result := TQuantity64.Zero;
   end
   else
   begin
      Result := DynastyData^.FMaterialPileComposition[Material];
   end;
   Assert(Result <= GetTotalMaterialPileCapacity(Dynasty, Material), 'recorded pile composition (' + Result.ToString() + ') exceeds pile capacity (' + GetTotalMaterialPileCapacity(Dynasty, Material).ToString() + ') for ' + Material.Name);
   if (FDynamic) then
   begin
      Result := Result + (System.Now - FAnchorTime) * GetTotalMaterialPileQuantityFlowRate(Dynasty, Material);
      Assert(Result <= GetTotalMaterialPileCapacity(Dynasty, Material), 'dynasty ' + IntToStr(Dynasty.DynastyID) + ': dynamic pile composition (' + Result.ToString() + ') exceeds pile capacity (' + GetTotalMaterialPileCapacity(Dynasty, Material).ToString() + ') for ' + Material.Name + ' which has flow rate ' + GetTotalMaterialPileQuantityFlowRate(Dynasty, Material).ToString() + ' over ' + (System.Now - FAnchorTime).ToString());
   end;
end;

function TRegionFeatureNode.GetTotalMaterialPileQuantityFlowRate(Dynasty: TDynasty; Material: TMaterial): TQuantityRate; // units/s
var
   Refinery: IRefinery;
   Consumer: IMaterialConsumer;
   Factory: IFactory;
   DynastyData: PPerDynastyData;
   Entry: TMaterialQuantity32;
begin
   Assert(FData.HasDynasty(Dynasty));
   DynastyData := FData[Dynasty];
   Result := TQuantityRate.Zero;
   if (DynastyData^.FRefineries.IsNotEmpty and Material.IsOre) then
   begin
      for Refinery in DynastyData^.FRefineries.Without(nil) do
      begin
         if (Refinery.GetRefineryOre() = Material.ID) then
            Result := Result + Refinery.GetRefineryCurrentRate();
      end;
   end;
   if (DynastyData^.FFactories.IsNotEmpty) then
   begin
      for Factory in DynastyData^.FFactories.Without(nil) do
      begin
         for Entry in Factory.GetFactoryInputs() do
         begin
            if (Entry.Material = Material) then
            begin
               Result := Result - Entry.Quantity * Factory.GetFactoryRate();
            end;
         end;
         for Entry in Factory.GetFactoryOutputs() do
         begin
            if (Entry.Material = Material) then
            begin
               Result := Result + Entry.Quantity * Factory.GetFactoryRate();
            end;
         end;
      end;
   end;
   if (Result.IsPositive and DynastyData^.FMaterialConsumers.IsNotEmpty) then
   begin
      for Consumer in DynastyData^.FMaterialConsumers.Without(nil) do
      begin
         if (Consumer.GetMaterialConsumerMaterial() = Material) then
         begin
            Result := TQuantityRate.Zero;
            exit;
         end;
      end;
   end;
end;

function TRegionFeatureNode.GetTotalMaterialPileCapacity(Dynasty: TDynasty; Material: TMaterial): TQuantity64;
var
   Pile: IMaterialPile;
   DynastyData: PPerDynastyData;
begin
   Assert(FData.HasDynasty(Dynasty));
   DynastyData := FData[Dynasty];
   Result := TQuantity64.Zero;
   if (DynastyData^.FMaterialPiles.IsNotEmpty) then
   begin
      for Pile in DynastyData^.FMaterialPiles.Without(nil) do
      begin
         if (Pile.GetMaterialPileMaterial() = Material) then
            Result := Result + Pile.GetMaterialPileCapacity();
      end;
   end;
end;

function TRegionFeatureNode.GetTotalMaterialPileMass(Dynasty: TDynasty; Material: TMaterial): TMass;
begin
   Result := GetTotalMaterialPileQuantity(Dynasty, Material) * Material.MassPerUnit;
end;

function TRegionFeatureNode.GetTotalMaterialPileMassFlowRate(Dynasty: TDynasty; Material: TMaterial): TMassRate;
begin
   Result := GetTotalMaterialPileQuantityFlowRate(Dynasty, Material) * Material.MassPerUnit;
end;

function TRegionFeatureNode.GetIsMinable(): Boolean;
var
   Ore: TOres;
begin
   Result := False;
   for Ore := Low(FGroundComposition) to High(FGroundComposition) do // $R-
   begin
      if (FGroundComposition[Ore].IsPositive) then
      begin
         Result := True;
         break;
      end;
   end;
end;

function TRegionFeatureNode.ManageBusMessage(Message: TBusMessage): TInjectBusMessageResult;
begin
   if ((Message is TRegisterMinerBusMessage) or
       (Message is TRegisterOrePileBusMessage) or
       (Message is TRegisterRefineryBusMessage) or
       (Message is TRegisterMaterialPileBusMessage) or
       (Message is TRegisterFactoryBusMessage) or
       (Message is TRegisterMaterialConsumerBusMessage) or
       (Message is TObtainMaterialBusMessage) or
       (Message is TStoreMaterialBusMessage) or
       (Message is TFindDestructorsMessage) or
       (Message is TSampleOreBusMessage) or
       (Message is TStoreOreBusMessage) or
       (Message is TDumpOreBusMessage)) then
   begin
      Result := DeferOrHandleBusMessage(Message);
   end
   else
      Result := irDeferred;
end;

function TRegionFeatureNode.HandleBusMessage(Message: TBusMessage): THandleBusMessageResult;
var
   MinerMessage: TRegisterMinerBusMessage;
   OrePileMessage: TRegisterOrePileBusMessage;
   RefineryMessage: TRegisterRefineryBusMessage;
   MaterialPileMessage: TRegisterMaterialPileBusMessage;
   FactoryMessage: TRegisterFactoryBusMessage;
   MaterialConsumerMessage: TRegisterMaterialConsumerBusMessage;
   Obtain: TObtainMaterialBusMessage;
   Store: TStoreMaterialBusMessage;
   Sample: TSampleOreBusMessage;
   StoreOre: TStoreOreBusMessage;
   DumpOre: TDumpOreBusMessage;
   Capacity, CandidateDeliverySize, Usage, ForPiles, ForGround, Quantity, SelectedQuantity: TQuantity64;
   DeliverySize: TQuantity32;
   MaterialPile: IMaterialPile;
   DynastyData: PPerDynastyData;
   Consumer: IMaterialConsumer;
   Material: TMaterial;
   Ore, SelectedOre: TOres;
   KnownMaterials: TGetKnownMaterialsMessage;
   Handled: Boolean;
   Manifest: TOreQuantity64;
   ContainerVolume, Volume, SelectedVolume: Double;
begin
   {$IFOPT C+} Assert(not Busy); {$ENDIF}
   Assert(not ((Message is TRubbleCollectionMessage) or (Message is TDismantleMessage)), ClassName + ' should never see ' + Message.ClassName);
   if (Message is TRegisterMinerBusMessage) then
   begin
      SyncAndReconsider();
      MinerMessage := Message as TRegisterMinerBusMessage;
      DynastyData := FData[MinerMessage.Provider.GetDynasty()];
      Assert(not DynastyData^.FMiners.Contains(MinerMessage.Provider));
      DynastyData^.FMiners.Push(MinerMessage.Provider);
      MinerMessage.Provider.SetMinerRegion(Self);
      Result := hrHandled;
   end
   else

   if (Message is TRegisterOrePileBusMessage) then
   begin
      SyncAndReconsider();
      OrePileMessage := Message as TRegisterOrePileBusMessage;
      DynastyData := FData[OrePileMessage.Provider.GetDynasty()];
      Assert(not DynastyData^.FOrePiles.Contains(OrePileMessage.Provider));
      DynastyData^.FOrePiles.Push(OrePileMessage.Provider);
      OrePileMessage.Provider.SetOrePileRegion(Self);
      Result := hrHandled;
   end
   else

   if (Message is TRegisterRefineryBusMessage) then
   begin
      SyncAndReconsider();
      RefineryMessage := Message as TRegisterRefineryBusMessage;
      DynastyData := FData[RefineryMessage.Provider.GetDynasty()];
      Assert(not DynastyData^.FRefineries.Contains(RefineryMessage.Provider));
      DynastyData^.FRefineries.Push(RefineryMessage.Provider);
      RefineryMessage.Provider.SetRefineryRegion(Self);
      Result := hrHandled;
   end
   else

   if (Message is TRegisterMaterialPileBusMessage) then
   begin
      SyncAndReconsider();
      MaterialPileMessage := Message as TRegisterMaterialPileBusMessage;
      DynastyData := FData[MaterialPileMessage.Provider.GetDynasty()];
      Assert(not DynastyData^.FMaterialPiles.Contains(MaterialPileMessage.Provider));
      DynastyData^.FMaterialPiles.Push(MaterialPileMessage.Provider);
      MaterialPileMessage.Provider.SetMaterialPileRegion(Self);
      Result := hrHandled;
   end
   else

   if (Message is TRegisterFactoryBusMessage) then
   begin
      SyncAndReconsider();
      FactoryMessage := Message as TRegisterFactoryBusMessage;
      DynastyData := FData[FactoryMessage.Provider.GetDynasty()];
      Assert(not DynastyData^.FFactories.Contains(FactoryMessage.Provider));
      DynastyData^.FFactories.Push(FactoryMessage.Provider);
      FactoryMessage.Provider.SetFactoryRegion(Self);
      Result := hrHandled;
   end
   else

   if (Message is TRegisterMaterialConsumerBusMessage) then
   begin
      SyncAndReconsider();
      MaterialConsumerMessage := Message as TRegisterMaterialConsumerBusMessage;
      DynastyData := FData[MaterialConsumerMessage.Provider.GetDynasty()];
      Assert(not DynastyData^.FMaterialConsumers.Contains(MaterialConsumerMessage.Provider));
      DynastyData^.FMaterialConsumers.Push(MaterialConsumerMessage.Provider);
      MaterialConsumerMessage.Provider.SetMaterialConsumerRegion(Self);
      Result := hrHandled;
      // if we get here, they must have first tried to obtain all of this material
      Material := MaterialConsumerMessage.Provider.GetMaterialConsumerMaterial();
      Assert((not Assigned(DynastyData^.FMaterialPileComposition)) or
             (not DynastyData^.FMaterialPileComposition.Has(Material)) or
             (DynastyData^.FMaterialPileComposition[Material].IsZero));
   end
   else

   if (Message is TObtainMaterialBusMessage) then
   begin
      Writeln(DebugName, ' received ', Message.ClassName);
      Obtain := Message as TObtainMaterialBusMessage;
      if (FData.HasDynasty(Obtain.Dynasty)) then
      begin
         DynastyData := FData[Obtain.Dynasty];
         Assert(Obtain.Quantity.IsPositive);
         SyncAndReconsider();
         if (Assigned(DynastyData^.FMaterialPileComposition) and DynastyData^.FMaterialPileComposition.Has(Obtain.Material)) then
         begin
            CandidateDeliverySize := DynastyData^.FMaterialPileComposition[Obtain.Material];
            if (CandidateDeliverySize.IsPositive) then
            begin
               if (CandidateDeliverySize > Obtain.Quantity) then
                  DeliverySize := Obtain.Quantity
               else
                  DeliverySize := TQuantity32.FromQuantity64(CandidateDeliverySize);
               Writeln('  delivering ', Obtain.Material.Name, ' - ', DeliverySize.ToString());
               Obtain.Deliver(DeliverySize);
               DynastyData^.DecMaterialPile(Obtain.Material, DeliverySize);
               if (DynastyData^.FMaterialPiles.IsNotEmpty) then
                  for MaterialPile in DynastyData^.FMaterialPiles.Without(nil) do
                     if (MaterialPile.GetMaterialPileMaterial() = Obtain.Material) then
                        MaterialPile.RegionAdjustedMaterialPiles();
               MarkAsDirty([dkUpdateJournal]);
            end;
         end;
      end;
      if (Obtain.Fulfilled) then
         Result := hrHandled
      else
         Result := inherited;
   end
   else

   if (Message is TStoreMaterialBusMessage) then
   begin
      Store := Message as TStoreMaterialBusMessage;
      Writeln(DebugName, ' received ', Store.ClassName, ' message for ', Store.RemainingQuantity.ToString(), ' of ', Store.Material.Name);
      if (FData.HasDynasty(Store.Dynasty)) then
      begin
         DynastyData := FData[Store.Dynasty];
         Assert(Store.RemainingQuantity.IsPositive);
         SyncAndReconsider();
         if (DynastyData^.FMaterialConsumers.IsNotEmpty) then
         begin
            for Consumer in DynastyData^.FMaterialConsumers.Without(nil) do
            begin
               if (Consumer.GetMaterialConsumerMaterial() = Store.Material) then
               begin
                  Capacity := Consumer.GetMaterialConsumerMaxDelivery(); // this returns a 32 bit value
                  if (Capacity > Store.RemainingQuantity) then
                  begin
                     // by definiton if we get here, Store.RemainingQuantity is smaller than some 32 bit value
                     Capacity := Store.RemainingQuantity;
                  end;
                  if (Capacity.IsPositive) then
                  begin
                     // by definition if we get here, Capacity fits in a 32 bit value
                     Assert(Capacity <= TQuantity32.Max);
                     Writeln('  feeding ', Consumer.GetAsset().DebugName, ' a total of ', Capacity.ToString(), ' of ', Store.Material.Name);
                     Consumer.DeliverMaterialConsumer(TQuantity32.FromQuantity64(Capacity));
                     Store.Store(Capacity);
                     if (Store.Fulfilled) then
                        break;
                  end;
               end;
            end;
            Writeln('  after feeding consumers, we have ', Store.RemainingQuantity.ToString(), ' of ', Store.Material.Name, ' left to deal with');
         end;
         if (Store.RemainingQuantity.IsPositive) then
         begin
            Capacity := GetTotalMaterialPileCapacity(Store.Dynasty, Store.Material);
            Writeln('  we have ', Capacity.ToString(), ' of total capacity for ', Store.Material.Name);
            if (Capacity.IsPositive) then
            begin
               if (Assigned(DynastyData^.FMaterialPileComposition) and DynastyData^.FMaterialPileComposition.Has(Store.Material)) then
               begin
                  Usage := DynastyData^.FMaterialPileComposition[Store.Material];
                  if (Usage < Capacity) then
                  begin
                     Capacity := Capacity - Usage;
                  end
                  else
                  begin
                     Writeln('  (meaning we are completely full)');
                     Capacity := TQuantity64.Zero;
                  end;
               end;
               if (Capacity.IsPositive) then
               begin
                  Writeln('  we have ', Capacity.ToString(), ' of remaining capacity for ', Store.Material.Name);
                  if (Capacity > Store.RemainingQuantity) then
                     Capacity := Store.RemainingQuantity;
                  Writeln('  taking ', Capacity.ToString());
                  Store.Store(Capacity);
                  DynastyData^.IncMaterialPile(Store.Material, Capacity);
                  if (DynastyData^.FMaterialPiles.IsNotEmpty) then
                     for MaterialPile in DynastyData^.FMaterialPiles.Without(nil) do
                        if (MaterialPile.GetMaterialPileMaterial() = Store.Material) then
                           MaterialPile.RegionAdjustedMaterialPiles();
                  MarkAsDirty([dkUpdateJournal]);
               end;
            end;
         end;
      end;
      if (Store.Fulfilled) then
         Result := hrHandled
      else
         Result := inherited;
   end
   else

   if (Message is TSampleOreBusMessage) then
   begin
      Sample := Message as TSampleOreBusMessage;
      Writeln('Sampling ore for ', Sample.Dynasty.DynastyID);
      Handled := False;
      if (FData.HasDynasty(Sample.Dynasty)) then
      begin
         DynastyData := FData[Sample.Dynasty];
         Assert(Sample.Size > 0);
         SyncAndReconsider();
         KnownMaterials := TGetKnownMaterialsMessage.Create(Sample.Dynasty);
         InjectBusMessage(KnownMaterials); // we ignore the result - it doesn't matter if it wasn't handled
         Writeln('continuing to sample ore');
         ContainerVolume := Sample.Size * Sample.Size * Sample.Size;
         Writeln('  container volume: ', ContainerVolume:0:3, 'm^3');
         SelectedVolume := 0.0;
         SelectedQuantity := TQuantity64.Zero;
         for Ore in TOres do
         begin
            Material := System.Encyclopedia.Materials[Ore];
            if (not KnownMaterials.Knows(Material)) then
            begin
               Writeln('    considering ', Material.Name);
               Volume := (DynastyData^.FOrePileComposition[Ore] * Material.MassPerUnit).AsDouble / Material.Density;
               Writeln('      available volume: ', Volume:0:3, 'm^3');
               if (Volume > ContainerVolume) then
                  Volume := ContainerVolume;
               Writeln('      clamped volume: ', Volume:0:3, 'm^3');
               Quantity := TMass.FromKg(Volume * Material.Density) div Material.MassPerUnit;
               Writeln('      corresponding quantity: ', Quantity.ToString());
               if (Quantity > DynastyData^.FOrePileComposition[Ore]) then
                  Quantity := DynastyData^.FOrePileComposition[Ore];
               Writeln('      clamped quantity: ', Quantity.ToString());
               if (Quantity.IsPositive and ((Volume > SelectedVolume) or ((Volume = SelectedVolume) and (Quantity < SelectedQuantity)))) then
               begin
                  Writeln('        selected as possible candidate...');
                  SelectedOre := Ore;
                  SelectedQuantity := Quantity;
                  SelectedVolume := Volume;
               end;
            end;
         end;
         if (SelectedQuantity.IsNotZero) then
         begin
            Material := System.Encyclopedia.Materials[SelectedOre];
            Writeln('    selected ', Material.Name);
            Assert(SelectedQuantity <= DynastyData^.FOrePileComposition[SelectedOre]);
            Sample.Provide(Material, SelectedQuantity);
            DynastyData^.FOrePileComposition[SelectedOre] := DynastyData^.FOrePileComposition[SelectedOre] - SelectedQuantity;
            Assert(not DynastyData^.FOrePileComposition[SelectedOre].IsNegative, 'NEGATIVE ORE COMPOSITION DETECTED');
            Result := hrHandled;
            Handled := True;
         end;
         FreeAndNil(KnownMaterials);
      end;
      if (Handled) then
         Result := hrHandled
      else
         Result := inherited;
   end
   else

   if (Message is TStoreOreBusMessage) then
   begin
      StoreOre := Message as TStoreOreBusMessage;
      if (FData.HasDynasty(StoreOre.Dynasty)) then
      begin
         DynastyData := FData[StoreOre.Dynasty];
         SyncAndReconsider();
         Manifest := StoreOre.Accept();
         Capacity := (GetTotalOrePileCapacity(StoreOre.Dynasty) - GetTotalOrePileMass(StoreOre.Dynasty)) div System.Encyclopedia.Materials[Manifest.Ore].MassPerUnit;
         Assert(not Capacity.IsNegative);
         ForPiles := Manifest.Quantity;
         if (ForPiles > Capacity) then
         begin
            ForGround := ForPiles - Capacity;
            ForPiles := Capacity;
         end
         else
         begin
            ForGround := TQuantity64.Zero;
         end;
         Assert(not ForPiles.IsNegative);
         Assert(not ForGround.IsNegative);
         DynastyData^.FOrePileComposition[Manifest.Ore] := DynastyData^.FOrePileComposition[Manifest.Ore] + ForPiles;
         Assert(not DynastyData^.FOrePileComposition[Manifest.Ore].IsNegative);
         if (ForGround.IsPositive) then
            FGroundComposition[Manifest.Ore] := FGroundComposition[Manifest.Ore] + ForGround; // TODO: handle overflow
         Result := hrHandled;
      end
      else
         Result := inherited;
   end
   else

   if (Message is TDumpOreBusMessage) then
   begin
      DumpOre := Message as TDumpOreBusMessage;
      SyncAndReconsider();
      Manifest := DumpOre.Accept();
      FGroundComposition[Manifest.Ore] := FGroundComposition[Manifest.Ore] + Manifest.Quantity; // TODO: handle overflow
      Result := hrHandled;
   end
   else
      Result := inherited;
end;

procedure TRegionFeatureNode.Sync();
type
   PFactoryEntry = ^TFactoryEntry;
   TFactoryEntry = record
      Factory: IFactory;
      Iterations: Int64;
   end;
   TFactoryEntryHashTable = specialize THashTable<IFactory, TFactoryEntry, FactoryUtils>;
   PFactoryEntryList = ^TFactoryEntryList;
   TFactoryEntryList = specialize PlasticArray<PFactoryEntry, PointerUtils>;
   TFactoryEntryListHashTable = specialize THashTable<TMaterial, TFactoryEntryList, TObjectUtils>;

var
   DynastyData: PPerDynastyData;
   
   procedure Reverse(FactoryEntry: PFactoryEntry);
   var
      Entry: TMaterialQuantity32;
      Factory: IFactory;
   begin
      if (FactoryEntry^.Iterations > 0) then
      begin
         Factory := FactoryEntry^.Factory;
         Writeln('    reversing ', Factory.GetFactoryOutputs()[0].Material.Name, ' factory with iterations count ', FactoryEntry^.Iterations);
         Assert(Factory.GetFactoryRate().IsNotExactZero);
         for Entry in Factory.GetFactoryInputs() do
         begin
            DynastyData^.IncMaterialPile(Entry.Material, Entry.Quantity);
            Writeln('      returning ', Entry.Quantity.ToString(), ' units of ', Entry.Material.Name);
         end;
         for Entry in Factory.GetFactoryOutputs() do
         begin
            DynastyData^.DecMaterialPile(Entry.Material, Entry.Quantity);
            Writeln('      canceling ', Entry.Quantity.ToString(), ' units of ', Entry.Material.Name, ' production');
         end;
         Dec(FactoryEntry^.Iterations);
         Factory.IncBacklog();
      end;
   end;

var
   Miner: IMiner;
   OrePile: IOrePile;
   Refinery: IRefinery;
   Factory: IFactory;
   Consumer: IMaterialConsumer;
   MaterialPile: IMaterialPile;
   Rate: TIterationsRate;
   MassRate: TMassRate;
   TotalMassRate: TMassRateSum;
   QuantityRate: TQuantityRate;
   ActualTransfer, TotalTransferMass, TotalCompositionMass, TotalOrePileMass, OrePileCapacity: TMass;
   {$IFDEF DEBUG}
   OrePileRecordedMass: TMass;
   {$ENDIF}
   SyncDuration: TMillisecondsDuration;
   Ore: TOres;
   OrePilesAffected, MaterialPilesAffected, Good: Boolean;
   Material: TMaterial;
   Encyclopedia: TEncyclopediaView;
   Quantity: TQuantity64;
   TransferQuantity, ActualTransferQuantity, DesiredTransferQuantity, Capacity: TQuantity64;
   Distribution: TOreFractions;
   RefinedOreQuantities: array[TOres] of TQuantity64;
   GroundChanged, GroundWasMinable: Boolean;
   Dynasty: TDynasty;
   Entry: TMaterialQuantity32;
   Iterations: Int64;
   MaterialCapacities: TMaterialQuantityHashTable;
   FactoryEntry: PFactoryEntry;
   FactoryEntryList: PFactoryEntryList;
   Factories: TFactoryEntryHashTable;
   InputFactories, OutputFactories: TFactoryEntryListHashTable;
   MaterialConsumerQuantities: TMaterialQuantityHashTable;
begin
   Writeln(DebugName, ' :: Sync(Active=', FActive, '; Dynamic=', FDynamic, '; Now=', System.Now.ToString(), '; AnchorTime=', FAnchorTime.ToString(), ')');
   Writeln('SYNC');
   Assert(FActive);
   if (not FDynamic) then
   begin
      Assert(not Assigned(FNextEvent));
      exit;
   end;

   SyncDuration := System.Now - FAnchorTime;
   Writeln('  duration: ', SyncDuration.ToString());
   
   if (SyncDuration.IsZero) then
   begin
      exit;
   end;
   Assert(SyncDuration.IsPositive);

   {$IFOPT C+}
   Assert(not Busy);
   Busy := true;
   {$ENDIF}

   Encyclopedia := System.Encyclopedia;

   GroundChanged := False;
   GroundWasMinable := IsMinable;

   for Dynasty in FData.Dynasties do
   begin
      Writeln('  dynasty ', Dynasty.DynastyID);
      DynastyData := FData[Dynasty];

      OrePilesAffected := False;
      MaterialPilesAffected := False;
      MaterialCapacities := nil;
      Factories := nil;
      InputFactories := nil;
      OutputFactories := nil;
      MaterialConsumerQuantities := nil;

      OrePileCapacity := TMass.Zero;
      if (DynastyData^.FOrePiles.IsNotEmpty) then
      begin
         for OrePile in DynastyData^.FOrePiles.Without(nil) do
         begin
            OrePileCapacity := OrePileCapacity + OrePile.GetOrePileCapacity();
         end;
      end;

      {$IFDEF DEBUG}
      if (DynastyData^.FOrePiles.IsNotEmpty) then
      begin
         TotalOrePileMass := GetTotalOrePileMass(Dynasty);
         OrePileRecordedMass := TMass.Zero;
         if (Length(DynastyData^.FOrePileComposition) > 0) then
            for Ore := Low(DynastyData^.FOrePileComposition) to High(DynastyData^.FOrePileComposition) do // $R-
            begin
               OrePileRecordedMass := OrePileRecordedMass + DynastyData^.FOrePileComposition[Ore] * Encyclopedia.Materials[Ore].MassPerUnit;
            end;
         Assert(TotalOrePileMass <= OrePileCapacity, 'already over ore capacity: ' + TotalOrePileMass.ToString() + ' ore in piles with capacity ' + OrePileCapacity.ToString());
      end;
      {$ENDIF}

      // Miners
      if (DynastyData^.FMiners.IsNotEmpty) then
      begin
         Writeln('  miners');
         // we recompute this per dynasty because it may have changed each time
         // we don't use `Mass` because FDynamic is true here
         TotalCompositionMass := TMass.Zero;
         Assert(Length(FGroundComposition) > 0);
         for Ore := Low(FGroundComposition) to High(FGroundComposition) do // $R- // TODO: use a TMassSum
            TotalCompositionMass := TotalCompositionMass + FGroundComposition[Ore] * Encyclopedia.Materials[Ore].MassPerUnit;
         Writeln('  starting with mining debt of ', DynastyData^.FPendingMiningDebt.ToString());
         Writeln('  total composition mass: ', TotalCompositionMass.ToString());
         TotalMassRate.Reset();
         Writeln('  computing total miner rate and mass');
         for Miner in DynastyData^.FMiners.Without(nil) do
         begin
            MassRate := Miner.GetMinerMaxRate(); // Not the current rate; the difference is handled by us dumping excess back into the ground.
            TotalMassRate.Inc(MassRate);
         end;
         TotalTransferMass := DynastyData^.FPendingMiningDebt + SyncDuration * TotalMassRate.Flatten();
         Writeln('  total expected transfer mass: ', TotalTransferMass.ToString(), ' at ', TotalMassRate.ToString(), ' over ', SyncDuration.ToString(), ' with debt ', DynastyData^.FPendingMiningDebt.ToString());
         Assert(not TotalTransferMass.IsNegative);
         ActualTransfer := TMass.Zero;
         for Ore in TOres do
         begin
            Quantity := FGroundComposition[Ore];
            // Fraction of the ground that is this ore is: (Quantity * Encyclopedia.Materials[Ore].MassPerUnit / TotalCompositionMass)
            if (Quantity.IsPositive) then
            begin
               Assert(TotalTransferMass / Encyclopedia.Materials[Ore].MassPerUnit < TQuantity64.Max);
               // The actual transferred quantity is:
               //   ThisOreMass := Quantity * Encyclopedia.Materials[Ore].MassPerUnit;
               //   ThisTransferMass := ThisOreMass * (TotalTransferMass / TotalCompositionMass);
               //   TransferQuantity := ThisTransferMass / Encyclopedia.Materials[Ore].MassPerUnit;
               // which simplifies to:
               TransferQuantity := Quantity.TruncatedMultiply(TotalTransferMass / TotalCompositionMass);
               Writeln('    mined ', TransferQuantity.ToString(), ' of ', Encyclopedia.Materials[Ore].Name, ' (', (Quantity * Encyclopedia.Materials[Ore].MassPerUnit / TotalCompositionMass) * 100.0:3:3, '%, ', (TransferQuantity * Encyclopedia.Materials[Ore].MassPerUnit).ToString(), ') - at max rate ', (TotalMassRate.Flatten() * (Quantity * Encyclopedia.Materials[Ore].MassPerUnit / TotalCompositionMass)).ToString(), ' = ', ((TotalMassRate.Flatten() * (Quantity * Encyclopedia.Materials[Ore].MassPerUnit / TotalCompositionMass)) / Encyclopedia.Materials[Ore].MassPerUnit).ToString());
               Assert(TransferQuantity <= Quantity, 'region composition underflow');
               FGroundComposition[Ore] := FGroundComposition[Ore] - TransferQuantity;
               GroundChanged := True;
               Assert(not DynastyData^.FOrePileComposition[Ore].IsNegative, 'NEGATIVE ORE COMPOSITION DETECTED');
               Assert(TQuantity64.Max - DynastyData^.FOrePileComposition[Ore] >= TransferQuantity);
               ActualTransfer := ActualTransfer + TransferQuantity * Encyclopedia.Materials[Ore].MassPerUnit;
               DynastyData^.FOrePileComposition[Ore] := DynastyData^.FOrePileComposition[Ore] + TransferQuantity; // TODO: handle overflow
               OrePilesAffected := True;
            end;
         end;
         if (ActualTransfer < TotalTransferMass) then
         begin
            Fraction32.InitArray(@Distribution[Low(TOres)], Length(Distribution));
            for Ore in TOres do
            begin
               Distribution[Ore] := Fraction32.FromDouble(FGroundComposition[Ore] * Encyclopedia.Materials[Ore].MassPerUnit / TotalCompositionMass);
            end;
            Fraction32.NormalizeArray(@Distribution[Low(TOres)], Length(Distribution));
            Ore := TOres(Fraction32.ChooseFrom(@Distribution[Low(TOres)], Length(Distribution), System.RandomNumberGenerator) + Low(TOres));
            Quantity := FGroundComposition[Ore];
            Assert(Quantity.IsPositive);
            Writeln('    TotalTransferMass=', TotalTransferMass.ToString());
            Writeln('    ActualTransfer=', ActualTransfer.ToString());
            Writeln('    ', Encyclopedia.Materials[Ore].Name, ' MassPerUnit=', Encyclopedia.Materials[Ore].MassPerUnit.ToString());
            TransferQuantity := (TotalTransferMass - ActualTransfer) div Encyclopedia.Materials[Ore].MassPerUnit;
            Writeln('    additionally mined ', TransferQuantity.ToString(), ' of ', Encyclopedia.Materials[Ore].Name, ' (', (TransferQuantity * Encyclopedia.Materials[Ore].MassPerUnit).ToString(), ') to round off full transfer');
            FGroundComposition[Ore] := FGroundComposition[Ore] - TransferQuantity;
            GroundChanged := True;
            ActualTransfer := ActualTransfer + TransferQuantity * Encyclopedia.Materials[Ore].MassPerUnit;
            DynastyData^.FOrePileComposition[Ore] := DynastyData^.FOrePileComposition[Ore] + TransferQuantity; // TODO: handle overflow
            OrePilesAffected := True;
         end;
         DynastyData^.FPendingMiningDebt := TotalTransferMass - ActualTransfer;
         Writeln('  ending with mining debt of ', DynastyData^.FPendingMiningDebt.ToString());
      end;

      // Refineries
      if (DynastyData^.FRefineries.IsNotEmpty) then
      begin
         Writeln('  refineries');
         for Ore in TOres do
            RefinedOreQuantities[Ore] := TQuantity64.Zero;
         for Refinery in DynastyData^.FRefineries.Without(nil) do
         begin
            Ore := Refinery.GetRefineryOre();
            Material := Encyclopedia.Materials[Ore];
            QuantityRate := Refinery.GetRefineryCurrentRate();
            if (QuantityRate.IsNotExactZero) then
            begin
               TransferQuantity := ApplyIncrementally(QuantityRate, SyncDuration, Refinery.GetPendingFraction()^);
               if (TransferQuantity.IsPositive) then
               begin
                  RefinedOreQuantities[Ore] := RefinedOreQuantities[Ore] + TransferQuantity;
                  Writeln('    refined ', TransferQuantity.ToString(), ' of ', Encyclopedia.Materials[Ore].Name, ' (at ', QuantityRate.ToString(), ' over ', SyncDuration.ToString(), ')');
               end
               else
                  Writeln('    refined no ', Encyclopedia.Materials[Ore].Name, ' (at ', QuantityRate.ToString(), ' over ', SyncDuration.ToString(), ')');
            end;
         end;
         for Ore in TOres do
         begin
            TransferQuantity := RefinedOreQuantities[Ore];
            if (TransferQuantity.IsPositive) then
            begin
               Material := Encyclopedia.Materials[Ore];
               if (TransferQuantity > DynastyData^.FOrePileComposition[Ore]) then
               begin
                  TransferQuantity := DynastyData^.FOrePileComposition[Ore];
               end;
               if (TransferQuantity.IsPositive) then
               begin
                  Writeln('    total refined ', TransferQuantity.ToString(), ' of ', Encyclopedia.Materials[Ore].Name, ' (', (TransferQuantity * Encyclopedia.Materials[Ore].MassPerUnit).ToString(), ')');
                  DynastyData^.FOrePileComposition[Ore] := DynastyData^.FOrePileComposition[Ore] - TransferQuantity;
                  OrePilesAffected := True;
                  DynastyData^.IncMaterialPile(Material, TransferQuantity);
                  MaterialPilesAffected := True;
               end;
            end;
         end;
      end;

      // Factories
      if (DynastyData^.FFactories.IsNotEmpty) then
      begin
         Writeln('  factories');
         Factories := TFactoryEntryHashTable.Create(@FactoryHash32);
         InputFactories := TFactoryEntryListHashTable.Create(@MaterialHash32);
         OutputFactories := TFactoryEntryListHashTable.Create(@MaterialHash32);
         for Factory in DynastyData^.FFactories.Without(nil) do
         begin
            Rate := Factory.GetFactoryRate();
            Assert(Rate.IsNotExactZero);
            Iterations := ApplyIncrementally(Rate, SyncDuration, Factory.GetPendingFraction()^) + Factory.GetBacklog(); // $R-
            Writeln('  - ', Factory.GetFactoryOutputs()[0].Material.Name, ' factory with rate ', Rate.ToString(), ' pending fraction ', Factory.GetPendingFraction()^.ToString(), ' and backlog ', Factory.GetBacklog(), ' computed iterations ', Iterations);
            Assert(Iterations <= High(Cardinal)); // is this safe to assume?
            Assert(Iterations >= 0, 'Negative factory iterations! ' + IntToStr(Iterations));
            if (Iterations > 0) then
            begin
               if (Iterations > High(Cardinal)) then
               begin
                  Writeln('    ?! Had to truncate a high factory iterations count for ', HexStr(Factory), ': ', Iterations);
                  Iterations := High(Cardinal); // otherwise we could theoretically overflow below
               end;
               FactoryEntry := Factories.AddDefault(Factory);
               FactoryEntry^.Factory := Factory;
               FactoryEntry^.Iterations := Iterations;
               for Entry in Factory.GetFactoryInputs() do
               begin
                  Assert(Entry.Quantity.IsPositive);
                  DynastyData^.DecMaterialPile(Entry.Material, Entry.Quantity * Iterations); // $R-
                  MaterialPilesAffected := True;
                  FactoryEntryList := InputFactories.GetOrAddPtr(Entry.Material);
                  FactoryEntryList^.Push(FactoryEntry);
               end;
               for Entry in Factory.GetFactoryOutputs() do
               begin
                  Assert(Entry.Quantity.IsPositive);
                  DynastyData^.IncMaterialPile(Entry.Material, Entry.Quantity * Iterations); // $R-
                  MaterialPilesAffected := True;
                  FactoryEntryList := OutputFactories.GetOrAddPtr(Entry.Material);
                  FactoryEntryList^.Push(FactoryEntry);
               end;
               Factory.ResetBacklog();
            end;
         end;
      end;

      Assert(not Assigned(MaterialCapacities));
      if (Assigned(DynastyData^.FMaterialPileComposition)) then
      begin
         MaterialCapacities := TMaterialQuantityHashTable.Create(DynastyData^.FMaterialPiles.Length);
         if (DynastyData^.FMaterialPiles.IsNotEmpty) then
            for MaterialPile in DynastyData^.FMaterialPiles do
               MaterialCapacities.Inc(MaterialPile.GetMaterialPileMaterial(), MaterialPile.GetMaterialPileCapacity());
      end;
      
      // Count up demand from consumers
      if (DynastyData^.FMaterialConsumers.IsNotEmpty) then
      begin
         Writeln('  consumers demand');
         MaterialConsumerQuantities := TMaterialQuantityHashTable.Create();
         for Consumer in DynastyData^.FMaterialConsumers.Without(nil) do
         begin
            Material := Consumer.GetMaterialConsumerMaterial();
            if (Assigned(Material)) then
            begin
               DesiredTransferQuantity := Consumer.GetMaterialConsumerMaxDelivery();
               MaterialConsumerQuantities.Inc(Material, DesiredTransferQuantity);
            end;
         end;
         {$IFOPT C+}
         for Material in MaterialConsumerQuantities do
            Writeln('    ', Material.Name, ': ', MaterialConsumerQuantities[Material].ToString());
         {$ENDIF}
      end;

      // I really don't like that we do this, but: if we sync too
      // early, it's possible we're in a situation the HandleChanges
      // logic didn't anticipate, namely, that factory A depended on
      // the product of factory B that has not yet triggered, or that
      // factory A generated product intended for factory B that
      // factory B has not yet consumed, and in either case, that can
      // mean that the piles are now too full or too empty.
      // We have to go back and undo those productions for now.
      DesiredTransferQuantity := TQuantity64.Zero;
      if (Assigned(DynastyData^.FMaterialPileComposition) and Assigned(MaterialCapacities)) then
      begin
         Writeln('  reversing factories to enforce pile limits');
         repeat
            Good := True;
            for Material in DynastyData^.FMaterialPileComposition do
            begin
               Quantity := DynastyData^.FMaterialPileComposition[Material];
               Writeln('    ', Material.Name, ': ', Quantity.ToString());
               if (Quantity.IsNotZero) then
               begin
                  if (Quantity.IsNegative) then
                  begin
                     Writeln('    we have a ', Material.Name, ' debt of ', Quantity.ToString());
                     FactoryEntryList := InputFactories.ItemsPtr[Material];
                     if (Assigned(FactoryEntryList)) then
                     begin
                        FactoryEntryList^.Shuffle();
                        for FactoryEntry in FactoryEntryList^ do
                        begin
                           Reverse(FactoryEntry);
                           Writeln('    ', Material.Name, ' now at ', DynastyData^.FMaterialPileComposition[Material].ToString());
                           if (not DynastyData^.FMaterialPileComposition[Material].IsNegative) then
                              break;
                        end;
                        Good := False;
                     end
                     else
                        Assert(False, 'how did we have negative pile composition without a factory consuming the material?');
                  end
                  else
                  begin
                     if (Assigned(MaterialConsumerQuantities)) then
                     begin
                        DesiredTransferQuantity := MaterialConsumerQuantities[Material];
                        Writeln('    DesiredTransferQuantity: ', DesiredTransferQuantity.ToString());
                     end;
                     if ((not Material.IsOre) // (we just dump the ores back into the ground, for simplicity)
                         and (DynastyData^.FMaterialPileComposition[Material] > MaterialCapacities[Material] + DesiredTransferQuantity)) then
                     begin
                        FactoryEntryList := OutputFactories.ItemsPtr[Material];
                        if (Assigned(FactoryEntryList)) then
                        begin
                           FactoryEntryList^.Shuffle();
                           for FactoryEntry in FactoryEntryList^ do
                           begin
                              Reverse(FactoryEntry);
                              Writeln('    ', Material.Name, ' now at ', DynastyData^.FMaterialPileComposition[Material].ToString(), '; capacity=', MaterialCapacities[Material].ToString(), '; consumers=', DesiredTransferQuantity.ToString());
                              if (DynastyData^.FMaterialPileComposition[Material] <= MaterialCapacities[Material] + DesiredTransferQuantity) then
                                 break;
                           end;
                           Good := False;
                        end
                        else
                           Assert(False, 'how did we go over-capacity on ' + Material.Name + ' without a factory generating the material?');
                     end;
                  end;
               end;
            end;
         until Good;
      end;

      FreeAndNil(MaterialCapacities);
      FreeAndNil(InputFactories);
      FreeAndNil(OutputFactories);
      FreeAndNil(Factories);
      FreeAndNil(MaterialConsumerQuantities);
      
      // Consumers
      if (DynastyData^.FMaterialConsumers.IsNotEmpty) then
      begin
         Writeln('  consumers');
         if (Assigned(DynastyData^.FMaterialPileComposition)) then
         begin
            for Consumer in DynastyData^.FMaterialConsumers.Without(nil) do
            begin
               Material := Consumer.GetMaterialConsumerMaterial();
               if (Assigned(Material)) then
               begin
                  QuantityRate := Consumer.GetMaterialConsumerCurrentRate();
                  DesiredTransferQuantity := Consumer.GetMaterialConsumerMaxDelivery();
                  Assert(DesiredTransferQuantity.IsNotZero);
                  Writeln('    feeding ', Material.Name, ' to consumer at ', QuantityRate.ToString());
                  TransferQuantity := ApplyIncrementally(QuantityRate, SyncDuration, Consumer.GetPendingFraction()^);
                  Writeln('      total available to transfer: ', TransferQuantity.ToString(), ' out of ', DesiredTransferQuantity.ToString(), ' desired');
                  if (TransferQuantity > DesiredTransferQuantity) then
                     TransferQuantity := DesiredTransferQuantity;
                  if (TransferQuantity.IsPositive) then
                  begin
                     ActualTransferQuantity := DynastyData^.ClampedDecMaterialPile(Material, TransferQuantity);
                     MaterialPilesAffected := True;
                  end
                  else
                  begin
                     ActualTransferQuantity := TQuantity64.Zero;
                  end;
                  Consumer.DeliverMaterialConsumer(TQuantity32.FromQuantity64(ActualTransferQuantity));
               end;
            end;
            // now go through the list in a random order and give out the remainder, if any
            DynastyData^.FMaterialConsumers.Shuffle();
            for Consumer in DynastyData^.FMaterialConsumers.Without(nil) do
            begin
               Material := Consumer.GetMaterialConsumerMaterial();
               if (Assigned(Material)) then
               begin
                  TransferQuantity := DynastyData^.FMaterialPileComposition[Material];
                  if (TransferQuantity.IsNotZero) then
                  begin
                     Writeln('    did not fully transfer ', Material.Name, ' to consumers; ', DynastyData^.FMaterialPileComposition[Material].ToString(), ' remain');
                     DesiredTransferQuantity := Consumer.GetMaterialConsumerMaxDelivery();
                     Assert(DesiredTransferQuantity.IsNotZero);
                     if (TransferQuantity > DesiredTransferQuantity) then
                        TransferQuantity := DesiredTransferQuantity;
                     if (TransferQuantity.IsPositive) then
                     begin
                        ActualTransferQuantity := DynastyData^.ClampedDecMaterialPile(Material, TransferQuantity);
                        Consumer.DeliverMaterialConsumer(TQuantity32.FromQuantity64(ActualTransferQuantity));
                        Writeln('      transferred ', ActualTransferQuantity.ToString(), ' to one consumer');
                        MaterialPilesAffected := True;
                     end;
                  end;
               end;
            end;
         end
         else
            Writeln('    skipped, we have no material piles');
      end;

      if (Assigned(DynastyData^.FMaterialPileComposition)) then
      begin
         Writeln('  material piles');
         for Material in DynastyData^.FMaterialPileComposition do
         begin
            Quantity := DynastyData^.FMaterialPileComposition[Material];
            Capacity := GetTotalMaterialPileCapacity(Dynasty, Material);
            Writeln('    ', Material.Name, ' piles ended at ', Quantity.ToString(), ' out of ', Capacity.ToString());
            if (Material.IsOre and (Quantity > Capacity)) then
            begin
               TransferQuantity := Quantity - Capacity;
               Writeln('dumping ', TransferQuantity.ToString(), ' of ', Material.Name, ', back into ore piles');
               DynastyData^.FOrePileComposition[Material.ID] := DynastyData^.FOrePileComposition[Material.ID] + TransferQuantity; // TODO: handle overflow
               DynastyData^.FMaterialPileComposition[Material] := Quantity - TransferQuantity;
            end;
         end;
      end;

      // Can't use GetTotalOrePileMass() because FNextEvent might not be nil so it
      // might attempt to re-apply the mass flow rate from before the sync.
      TotalOrePileMass := TMass.Zero;
      if (Length(DynastyData^.FOrePileComposition) > 0) then
         for Ore := Low(DynastyData^.FOrePileComposition) to High(DynastyData^.FOrePileComposition) do // $R-
         begin
            Writeln('  ore piles now contain ', DynastyData^.FOrePileComposition[Ore].ToString(), ' of ', Encyclopedia.Materials[Ore].Name, ' (', (DynastyData^.FOrePileComposition[Ore] * Encyclopedia.Materials[Ore].MassPerUnit).ToString(), ')');
            TotalOrePileMass := TotalOrePileMass + DynastyData^.FOrePileComposition[Ore] * Encyclopedia.Materials[Ore].MassPerUnit;
         end;
      if (TotalOrePileMass > OrePileCapacity) then
      begin
         Writeln('  ore piles contain ', TotalOrePileMass.ToString(), ' which is more than the pile capacity of ', OrePileCapacity.ToString());
         ReturnOreToGround(DynastyData, TotalOrePileMass, TotalOrePileMass - OrePileCapacity);
         OrePilesAffected := True;
         GroundChanged := True;
      end
      else
         Writeln('  ore piles contain ', TotalOrePileMass.ToString(), ' which fits inside pile capacity of ', OrePileCapacity.ToString());

      if (OrePilesAffected and DynastyData^.FOrePiles.IsNotEmpty) then
      begin
         for OrePile in DynastyData^.FOrePiles.Without(nil) do
            OrePile.RegionAdjustedOrePiles();
      end;

      if (MaterialPilesAffected and DynastyData^.FMaterialPiles.IsNotEmpty) then
      begin
         for MaterialPile in DynastyData^.FMaterialPiles.Without(nil) do
            MaterialPile.RegionAdjustedMaterialPiles();
      end;

      Writeln('  end of dynasty ', Dynasty.DynastyID, ' region sync');
      FreeAndNil(MaterialCapacities);
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

   FAnchorTime := System.Now;

   {$IFOPT C+} Assert(Busy); Busy := False; {$ENDIF}
end;

procedure TRegionFeatureNode.SyncAndReconsider();
begin
   if (FActive) then
   begin
      if (FDynamic) then
      begin
         Sync();
         if (Assigned(FNextEvent)) then
            CancelEvent(FNextEvent);
         FAnchorTime := TTimeInMilliseconds.NegInfinity;
      end;
      FActive := False;
      FDynamic := False;
      FNetMiningRate := TMassRate.Zero;
   end;
   MarkAsDirty([dkNeedsHandleChanges]);
end;

procedure TRegionFeatureNode.ReturnOreToGround(DynastyData: PPerDynastyData; TotalOrePileMass, TotalTransferMass: TMass);
var
   Material: TMaterial;
   Ore: TOres;
   ActualTransfer: TMass;
   TransferQuantity, TotalQuantity: TQuantity64;
   Distribution: TOreFractions;
   RemainingCount: Cardinal;
begin
   Writeln(DebugName, ' :: ReturnOreToGround - total mass: ', TotalOrePileMass.ToString, '; returning ', TotalTransferMass.ToString(), ' to ground');
   Assert(not TotalTransferMass.IsNegative);
   ActualTransfer := TMass.Zero;
   for Ore in TOres do
   begin
      Material := System.Encyclopedia.Materials[Ore];
      TransferQuantity := DynastyData^.FOrePileComposition[Ore] * (TotalTransferMass / TotalOrePileMass);
      if (TransferQuantity.IsPositive) then
      begin
         DynastyData^.FOrePileComposition[Ore] := DynastyData^.FOrePileComposition[Ore] - TransferQuantity;
         FGroundComposition[Ore] := FGroundComposition[Ore] + TransferQuantity; // TODO: handle overflow
         ActualTransfer := ActualTransfer + TransferQuantity * Material.MassPerUnit;
      end;
   end;
   if (ActualTransfer < TotalTransferMass) then
   begin
      // Handle the rounding error by randomly chosing an ore to return.
      Fraction32.InitArray(@Distribution[Low(TOres)], Length(Distribution));
      for Ore in TOres do
      begin
         Distribution[Ore] := Fraction32.FromDouble(DynastyData^.FOrePileComposition[Ore] * System.Encyclopedia.Materials[Ore].MassPerUnit / TotalOrePileMass);
      end;
      RemainingCount := Length(Distribution);
      while ((ActualTransfer < TotalTransferMass) and (RemainingCount > 0)) do
      begin
         Fraction32.NormalizeArray(@Distribution[Low(TOres)], Length(Distribution));
         Ore := TOres(Fraction32.ChooseFrom(@Distribution[Low(TOres)], Length(Distribution), System.RandomNumberGenerator) + Low(TOres));
         TotalQuantity := DynastyData^.FOrePileComposition[Ore];
         Assert(TotalQuantity.IsPositive);
         TransferQuantity := System.Encyclopedia.Materials[Ore].MassPerUnit.ConvertMassToQuantity64Ceil(TotalTransferMass - ActualTransfer);
         if (TransferQuantity.IsPositive) then
         begin
            Assert(TransferQuantity <= TotalQuantity);
            DynastyData^.FOrePileComposition[Ore] := DynastyData^.FOrePileComposition[Ore] - TransferQuantity;
            ActualTransfer := ActualTransfer + TransferQuantity * System.Encyclopedia.Materials[Ore].MassPerUnit;
            FGroundComposition[Ore] := FGroundComposition[Ore] + TransferQuantity; // TODO: handle overflow
         end;
         Distribution[Ore].ResetToZero();
         Dec(RemainingCount);
      end;
   end;
   Assert(ActualTransfer >= TotalTransferMass);
end;

procedure TRegionFeatureNode.HandleScheduledEvent(var Data);
begin
   Writeln(DebugName, ' :: HandleScheduledEvent');
   Assert(Assigned(FNextEvent));
   Assert(FDynamic); // otherwise, why did we schedule an event
   FNextEvent := nil; // important to do this before anything that might raise an exception, otherwise we try to free it on exit
   Sync();
   FActive := False;
   FDynamic := False;
   FNetMiningRate := TMassRate.Zero;
   FAnchorTime := TTimeInMilliseconds.NegInfinity;
   MarkAsDirty([dkNeedsHandleChanges]);
end;

procedure TRegionFeatureNode.Reset();
var
   Miner: IMiner;
   OrePile: IOrePile;
   Refinery: IRefinery;
   MaterialPile: IMaterialPile;
   Factory: IFactory;
   MaterialConsumer: IMaterialConsumer;
   Dynasty: TDynasty;
   DynastyData: PPerDynastyData;
begin
   Assert(not Assigned(FNextEvent)); // caller is responsible for canceling everything
   Assert(FActive);
   for Dynasty in FData.Dynasties do
   begin
      DynastyData := FData[Dynasty];
      if (DynastyData^.FMiners.IsNotEmpty) then
      begin
         for Miner in DynastyData^.FMiners.Without(nil) do
            Miner.DisconnectMiner();
         DynastyData^.FMiners.Empty();
      end;
      if (DynastyData^.FOrePiles.IsNotEmpty) then
      begin
         for OrePile in DynastyData^.FOrePiles.Without(nil) do
            OrePile.DisconnectOrePile();
         DynastyData^.FOrePiles.Empty();
      end;
      if (DynastyData^.FRefineries.IsNotEmpty) then
      begin
         for Refinery in DynastyData^.FRefineries.Without(nil) do
            Refinery.DisconnectRefinery();
         DynastyData^.FRefineries.Empty();
      end;
      if (DynastyData^.FMaterialPiles.IsNotEmpty) then
      begin
         for MaterialPile in DynastyData^.FMaterialPiles.Without(nil) do
            MaterialPile.DisconnectMaterialPile();
         DynastyData^.FMaterialPiles.Empty();
      end;
      if (DynastyData^.FFactories.IsNotEmpty) then
      begin
         for Factory in DynastyData^.FFactories.Without(nil) do
            Factory.DisconnectFactory();
         DynastyData^.FFactories.Empty();
      end;
      if (DynastyData^.FMaterialConsumers.IsNotEmpty) then
      begin
         for MaterialConsumer in DynastyData^.FMaterialConsumers.Without(nil) do
            MaterialConsumer.DisconnectMaterialConsumer();
         DynastyData^.FMaterialConsumers.Empty();
      end;
   end;
   FActive := False;
   FDynamic := False;
   FNetMiningRate := TMassRate.Zero;
   FAnchorTime := TTimeInMilliseconds.NegInfinity;
end;

procedure TRegionFeatureNode.HandleChanges();

   procedure AllocateOres();
   var
      Message: TAllocateOresBusMessage;
   begin
      Assert(not FAllocatedOres);
      Message := TAllocateOresBusMessage.Create(FFeatureClass.Depth, FFeatureClass.TargetCount);
      if (InjectBusMessage(Message) = irHandled) then
         FGroundComposition := Message.AssignedOres;
      FreeAndNil(Message);
      FAllocatedOres := True;
   end;

type
   TRefiningLimits = set of (SourceLimited, TargetLimited);
   
var
   OrePileCapacity, RemainingOrePileCapacity, CurrentGroundMass, TotalOrePileMass: TMass;
   Rate: TIterationsRate;
   TotalNetOrePileGrowthRate, FinalRate, MiningRate: TMassRate;
   AllDynastyMiningRate, TotalMinerMaxRate: TMassRateSum;
   TotalMinerMaxRateApproximation: TMassRate;
   NetOrePileGrowthRate, RefiningRate, MaterialConsumptionRate: TQuantityRate;
   TimeUntilGroundEmpty, TimeUntilOrePilesFull, TimeUntilOrePilesEmpty, TimeUntilThisOrePileEmpty,
   TimeUntilAnyMaterialPileFull, TimeUntilThisMaterialPileFull, TimeUntilAnyMaterialPileEmpty, TimeUntilThisMaterialPileEmpty, TimeUntilNextEvent: TMillisecondsDuration;
   Ore: TOres;
   Material: TMaterial;
   Quantity: TQuantity64;
   OreMiningRates: TOreRates;
   OreRefiningRate: TQuantityRate;
   OreRefiningMaxRates, OreRefiningRates: TFixedPointOreRates;
   MaterialCapacities: TMaterialQuantityHashTable;
   MaterialConsumerCounts: TMaterialCountHashTable;
   MaterialFlowRates: TMaterialRateHashTable;
   RemainingMaterials: TMaterialHashSet;
   RemainingMaterial, NeededMaterial: TQuantity64;
   Ratio: Double;
   Miner: IMiner;
   OrePile: IOrePile;
   Refinery: IRefinery;
   Pile: IMaterialPile;
   Factory: IFactory;
   MaterialConsumer: IMaterialConsumer;
   SourceLimiting, TargetLimiting, Stable: Boolean;
   RefiningLimits: array[TOres] of TRefiningLimits;
   DoneCheckingForOverflow, DoneCheckingForUnderflow, MaybeOverflowing, MaybeUnderflowing, Found, Refining: Boolean;
   Dynasty: TDynasty;
   DynastyData: PPerDynastyData;
   Entry: TMaterialQuantity32;
begin
   inherited;
   if (not FAllocatedOres) then
      AllocateOres();
   {$IFOPT C+} Assert(not Busy); Busy := True; {$ENDIF}
   if (not FActive) then
   begin
      Writeln(DebugName, ' recomputing ore and material flow dynamics');
      Writeln('COMPUTING REGION DYNAMICS');
      Assert(not Assigned(FNextEvent));
      Assert(not FDynamic); // so all the "get current mass" etc getters won't be affected by mass flow
      CurrentGroundMass := Mass;
      Writeln('  current ground mass: ', CurrentGroundMass.ToString());
      TimeUntilNextEvent := TMillisecondsDuration.Infinity;
      AllDynastyMiningRate.Reset();
      for Dynasty in FData.Dynasties do
      begin
         DynastyData := FData[Dynasty];
         Writeln('- dynasty ', Dynasty.DynastyID);

         DynastyData^.FMiners.RemoveAll(nil);
         DynastyData^.FOrePiles.RemoveAll(nil);
         DynastyData^.FRefineries.RemoveAll(nil);
         DynastyData^.FMaterialPiles.RemoveAll(nil);
         DynastyData^.FFactories.RemoveAll(nil);
         DynastyData^.FMaterialConsumers.RemoveAll(nil);
         DynastyData^.FOrePileMassFlowRate := TMassRate.Zero;
         TotalOrePileMass := GetTotalOrePileMass(Dynasty);
         MaterialCapacities := nil;
         MaterialFlowRates := nil;
         MaterialConsumerCounts := nil;
         RemainingMaterials := nil;

         // COMPUTE MAX RATES AND CAPACITIES

         // Ore storage
         for Ore in TOres do
         begin
            OreMiningRates[Ore] := TQuantityRate.Zero;
            Assert(OreRefiningRates[Ore].IsZero); {BOGUS Warning: Local variable "OreRefiningRates" of a managed type does not seem to be initialized}
            Assert(OreRefiningMaxRates[Ore].IsZero); {BOGUS Warning: Local variable "OreRefiningMaxRates" of a managed type does not seem to be initialized}
            RefiningLimits[Ore] := [];
            Material := System.Encyclopedia.Materials[Ore];
            if (DynastyData^.FOrePileComposition[Ore].IsNotZero) then
               Writeln('  ', Material.Name, ' ore in piles: ', (DynastyData^.FOrePileComposition[Ore] * Material.MassPerUnit).ToString());
         end;

         Writeln('  total ore pile mass: ', TotalOrePileMass.ToString());
         
         // Ore pile capacities
         OrePileCapacity := TMass.Zero;
         if (DynastyData^.FOrePiles.IsNotEmpty) then
         begin
            for OrePile in DynastyData^.FOrePiles do
            begin
               OrePileCapacity := OrePileCapacity + OrePile.GetOrePileCapacity();
               OrePile.RegionAdjustedOrePiles(); // TODO: only notify if the actual rate of flow for that pile changed
            end;
         end;
         Writeln('  total ore pile capacity: ', OrePileCapacity.ToString());
         Writeln('  max unit ore mass: ', GetMaxUnitOreMassTransfer().ToString());
         if ((OrePileCapacity > TotalOrePileMass) and (OrePileCapacity - TotalOrePileMass < GetMaxUnitOreMassTransfer())) then
            OrePileCapacity := TotalOrePileMass;
         Writeln('  adjusted total ore pile capacity: ', OrePileCapacity.ToString());

         // Sanity-check ore piles
         Assert(TotalOrePileMass <= OrePileCapacity, 'ORE PILE OVERFLOW');
         {$IFOPT C+}
         if (TotalOrePileMass > OrePileCapacity) then
         begin
            Writeln('  ore piles contain ', TotalOrePileMass.ToString(), ' which is more than the pile capacity of ', OrePileCapacity.ToString());
            ReturnOreToGround(DynastyData, TotalOrePileMass, TotalOrePileMass - OrePileCapacity);
            TotalOrePileMass := TotalOrePileMass - OrePileCapacity;
         end
         else
            Writeln('  ore piles contain ', TotalOrePileMass.ToString(), ' which fits inside pile capacity of ', OrePileCapacity.ToString());
         {$ENDIF}
         
         // Total mining rate
         TotalMinerMaxRate.Reset();
         Writeln('  total miner max rate');
         Writeln('      ', TotalMinerMaxRate.ToString());
         if (DynastyData^.FMiners.IsNotEmpty) then
         begin
            for Miner in DynastyData^.FMiners do
            begin
               TotalMinerMaxRate.Inc(Miner.GetMinerMaxRate());
               Writeln('    + ', Miner.GetMinerMaxRate().ToString(), ' = ', TotalMinerMaxRate.ToString());
            end;
            Assert(DynastyData^.FMiners.IsEmpty or TotalMinerMaxRate.IsPositive);
         end;
         TotalMinerMaxRateApproximation := TotalMinerMaxRate.Flatten();
         Writeln('  max mining rate: ', TotalMinerMaxRate.ToString(), ' (approx ', TotalMinerMaxRateApproximation.ToString(), ')');
         
         // Per-ore mining rates
         if ((CurrentGroundMass.IsPositive) and (TotalMinerMaxRateApproximation.IsNotNearZero)) then
         begin
            for Ore in TOres do
            begin
               if (FGroundComposition[Ore].IsPositive) then
               begin
                  // the ore mining rate (R, units/h) is the total mining rate (T, kg/h) times the fraction of the ground that is this ore (F), divided by the mass per unit for that ore (K, kg/units)
                  // the fraction of the ground that is this ore (F) is the ground composition of that ore (G, units) times the mass per unit for that ore (K, kg/units), divided by the total ground mass (M, kg)
                  // i.e. R=T*F/K, F=G*K/M
                  // R = T * (G * K/M) /K
                  // R = T * G * K / (M * K)
                  // R = T * G / M
                  OreMiningRates[Ore] := FGroundComposition[Ore] * (TotalMinerMaxRateApproximation / CurrentGroundMass);
                  Writeln('    max mining rate for ', System.Encyclopedia.Materials[Ore].Name, ': ', OreMiningRates[Ore].ToString(), ' (composition fraction: ', FGroundComposition[Ore] * System.Encyclopedia.Materials[Ore].MassPerUnit / CurrentGroundMass:0:5, ')');
               end;
            end;
         end;

         // Refinery rates
         if (DynastyData^.FRefineries.IsNotEmpty) then
         begin
            Writeln('  handling refineries');
            if (not Assigned(MaterialFlowRates)) then
               MaterialFlowRates := TMaterialRateHashTable.Create(16); // TODO: study what best value to use here
            for Refinery in DynastyData^.FRefineries do
            begin
               // TODO: handle refining debt
               Ore := Refinery.GetRefineryOre();
               RefiningRate := Refinery.GetRefineryMaxRate();
               Material := System.Encyclopedia.Materials[Ore];
               OreRefiningMaxRates[Ore].Inc(RefiningRate);
            end;
            for Ore in TOres do
            begin
               Material := System.Encyclopedia.Materials[Ore];
               Writeln('    ', Material.Name, ' max refining rate: ', OreRefiningMaxRates[Ore].ToString(), ', ore pile composition: ', DynastyData^.FOrePileComposition[Ore].ToString(), ', max mining rate: ', OreMiningRates[Ore].ToString());
               if (DynastyData^.FOrePileComposition[Ore].IsZero and (OreRefiningMaxRates[Ore].ToDouble() > OreMiningRates[Ore].AsDouble)) then
               begin
                  // none of this ore left in ore piles, so limit refining rate to mining rate
                  Assert(OreRefiningRates[Ore].IsZero);
                  OreRefiningRates[Ore].Inc(OreMiningRates[Ore]);
                  Include(RefiningLimits[Ore], SourceLimited);
               end
               else
               begin
                  OreRefiningRates[Ore] := OreRefiningMaxRates[Ore];
               end;
               if (OreRefiningRates[Ore].IsNotZero) then
               begin
                  MaterialFlowRates.Inc(Material, OreRefiningRates[Ore]);
                  Writeln('    max refining rate for ', Material.Name, ': ', OreRefiningRates[Ore].ToString());
               end;
            end;
         end;

         // Material pile capacity
         Writeln('  material piles');
         Assert(not Assigned(MaterialCapacities));
         if (DynastyData^.FMaterialPiles.IsNotEmpty) then
         begin
            MaterialCapacities := TMaterialQuantityHashTable.Create(DynastyData^.FMaterialPiles.Length);
            for Pile in DynastyData^.FMaterialPiles do
            begin
               Material := Pile.GetMaterialPileMaterial();
               MaterialCapacities.Inc(Material, Pile.GetMaterialPileCapacity());
               Pile.RegionAdjustedMaterialPiles(); // TODO: only notify if the actual rate of flow for that pile changed
            end;
            for Material in MaterialCapacities do
            begin
               Writeln('    for ', Material.Name, ' we found piles of capacity ', MaterialCapacities[Material].ToString());
            end;
         end;
         if (Assigned(DynastyData^.FMaterialPileComposition)) then
         begin
            for Material in DynastyData^.FMaterialPileComposition do
            begin
               Quantity := DynastyData^.FMaterialPileComposition[Material];
               if (Quantity.IsNotZero) then
               begin
                  Assert(Assigned(MaterialCapacities)); // how can we have something in a pile, with no piles
                  Assert(MaterialCapacities[Material] >= Quantity);
                  if (MaterialCapacities[Material] >= Quantity) then
                  begin
                     Writeln('    within capacity for ', Material.Name, ' (found ', Quantity.ToString(), ')');
                     MaterialCapacities.Dec(Material, Quantity);
                  end
                  else
                  begin
                     Writeln('    over capacity for ', Material.Name, ' (found ', Quantity.ToString(), ')');
                     MaterialCapacities[Material] := TQuantity64.Zero;
                  end;
               end;
            end;
         end;
         if (Assigned(MaterialCapacities)) then
         begin
            for Material in MaterialCapacities do
            begin
               if (Assigned(DynastyData^.FMaterialPileComposition)) then
                  Writeln('    total ', Material.Name, ' pile remaining capacity: ', (MaterialCapacities[Material] * Material.MassPerUnit).ToString(), ' (', DynastyData^.FMaterialPileComposition[Material].ToString(), ' stored in storage of capacity ', GetTotalMaterialPileCapacity(Dynasty, Material).ToString(), ')')
               else
                  Writeln('    total ', Material.Name, ' pile remaining capacity: ', (MaterialCapacities[Material] * Material.MassPerUnit).ToString(), ' (absolutely nothing stored in storage of capacity ', GetTotalMaterialPileCapacity(Dynasty, Material).ToString(), ')');
            end;
         end;

         // Factories
         if (DynastyData^.FFactories.IsNotEmpty) then
         begin
            Writeln('  factories');
            if (not Assigned(MaterialFlowRates)) then
               MaterialFlowRates := TMaterialRateHashTable.Create(DynastyData^.FFactories.Length);
            for Factory in DynastyData^.FFactories do
            begin
               Rate := Factory.GetFactoryRate();
               Write('   - at ', Rate.ToString(), ' ');
               Assert(Rate.IsNotExactZero);
               for Entry in Factory.GetFactoryInputs() do
               begin
                  MaterialFlowRates.Dec(Entry.Material, Entry.Quantity * Rate);
                  Write(Entry.Material.Name, ' ');
               end;
               Write('-> ');
               for Entry in Factory.GetFactoryOutputs() do
               begin
                  MaterialFlowRates.Inc(Entry.Material, Entry.Quantity * Rate);
                  Write(Entry.Material.Name, ' ');
               end;
               Writeln();
            end;
         end;
         if (Assigned(MaterialFlowRates)) then
         begin
            for Material in MaterialFlowRates do
            begin
               if (Material.IsOre) then
                  Writeln('  ', Material.Name, ' flow rates: ', MaterialFlowRates[Material].ToString(),
                          ' of which ', OreRefiningRates[TOres(Material.ID)].ToString(), ' is from refineries')
               else
                  Writeln('  ', Material.Name, ' flow rates: ', MaterialFlowRates[Material].ToString());
            end;
         end;

         // Consumers
         if (DynastyData^.FMaterialConsumers.IsNotEmpty) then
         begin
            Writeln('  consumers');
            MaterialConsumerCounts := TMaterialCountHashTable.Create(DynastyData^.FMaterialConsumers.Length);
            for MaterialConsumer in DynastyData^.FMaterialConsumers do
            begin
               Writeln('   - ', MaterialConsumer.GetAsset().DebugName);
               Material := MaterialConsumer.GetMaterialConsumerMaterial();
               if (Assigned(Material)) then
               begin
                  Writeln('     consumes ', Material.Name);
                  MaterialConsumerCounts.Inc(Material, 1);
                  // consumers are required to empty the piles first, by contract
                  Assert((not Assigned(DynastyData^.FMaterialPileComposition)) or
                         (not DynastyData^.FMaterialPileComposition.Has(Material)) or
                         (DynastyData^.FMaterialPileComposition[Material].IsZero),
                         'Unexpectedly found ' + DynastyData^.FMaterialPileComposition[Material].ToString() + ' of ' + Material.Name + ' but we have a consumer: ' + MaterialConsumer.GetAsset().DebugName);
               end;
            end;
            for Material in MaterialConsumerCounts do
               Writeln('    ', Material.Name, ' consumer count: ', MaterialConsumerCounts[Material]);
         end;

         // TURN OFF FACTORIES THAT CANNOT OPERATE AT FULL SPEED
         if (Assigned(MaterialFlowRates)) then
         begin
            Writeln('  considering factories to disable');
            RemainingMaterials := TMaterialHashSet.Create();
            for Material in MaterialFlowRates do
               RemainingMaterials.Add(Material);
            repeat
               Stable := True;
               for Material in RemainingMaterials do
               begin
                  DoneCheckingForOverflow := False;
                  DoneCheckingForUnderflow := False;
                  Writeln('    - looking at ', Material.Name);
                  repeat
                     Writeln('      DoneCheckingForOverflow=', DoneCheckingForOverflow, ', flowing at ', MaterialFlowRates[Material].ToString());
                     Writeln('      DoneCheckingForUnderflow=', DoneCheckingForUnderflow);
                     if (Assigned(MaterialConsumerCounts)) then
                        Writeln('      consumers: ', MaterialConsumerCounts[Material]);
                     if (Assigned(MaterialCapacities)) then
                        Writeln('      capacity: ', MaterialCapacities[Material].ToString());
                     if (Material.IsOre) then
                        Writeln('      refining: ', OreRefiningRates[TOres(Material.ID)].ToString());
                     if (Assigned(DynastyData^.FMaterialPileComposition)) then
                        Writeln('      storage: ', DynastyData^.FMaterialPileComposition[Material].ToString());
                     MaybeOverflowing := False;
                     MaybeUnderflowing := False;
                     Assert((not Assigned(MaterialCapacities)) or (not MaterialCapacities[Material].IsNegative));
                     if ((not DoneCheckingForOverflow) and
                         (MaterialFlowRates[Material].IsPositive) and // we want to be generating this material
                         ((not Assigned(MaterialConsumerCounts)) or (MaterialConsumerCounts[Material] = 0)) and // we're not consuming this material as fast as possible
                         ((not Assigned(MaterialCapacities)) or (MaterialCapacities[Material].IsZero)) and // we have no more room for this material
                          (not Material.IsOre or (OreRefiningRates[TOres(Material.ID)] < MaterialFlowRates[Material]))) then // even stopping the refineries would not reduce the overflow to zero
                     begin
                        Writeln('    disabling factories that generate ', Material.Name);
                        if (Material.IsOre) then
                           Writeln('      starting OreRefiningRate for ', Material.Name, ': ', OreRefiningRates[TOres(Material.ID)].ToString());
                        Writeln('      starting MaterialFlowRates for ', Material.Name, ': ', MaterialFlowRates[Material].ToString());
                        // we're out of room and the factories are the cause.
                        // shut down all the factories making this material.
                        for Factory in DynastyData^.FFactories.Without(nil) do
                        begin
                           Rate := Factory.GetFactoryRate();
                           Assert(Rate.IsNotExactZero);
                           Found := False;
                           for Entry in Factory.GetFactoryOutputs() do
                           begin
                              if (Entry.Material = Material) then
                              begin
                                 Found := True;
                                 break;
                              end;
                           end;
                           if (Found) then
                              Write('    - removing ', Rate.ToString(), ' factory turning ')
                           else
                              Write('    - not removing ', Rate.ToString(), ' factory turning ');
                           for Entry in Factory.GetFactoryInputs() do
                              Write(Entry.Material.Name, ' (', (Entry.Quantity * Rate).ToString(), '); ');
                           Write('-> ');
                           for Entry in Factory.GetFactoryOutputs() do
                              Write(Entry.Material.Name, ' (', (Entry.Quantity * Rate).ToString(), '); ');
                           Writeln();
                           if (Found) then
                           begin
                              for Entry in Factory.GetFactoryInputs() do
                                 MaterialFlowRates.Inc(Entry.Material, Entry.Quantity * Rate);
                              for Entry in Factory.GetFactoryOutputs() do
                                 MaterialFlowRates.Dec(Entry.Material, Entry.Quantity * Rate);
                              Factory.StallFactory(srOutput);
                              FData[Factory.GetDynasty()]^.FFactories.Replace(Factory, nil);
                           end;
                        end;
                        if (Material.IsOre) then
                           Writeln('      remaining OreRefiningRate for ', Material.Name, ': ', OreRefiningRates[TOres(Material.ID)].ToString());
                        Writeln('      remaining MaterialFlowRates for ', Material.Name, ': ', MaterialFlowRates[Material].ToString());
                        Stable := False;
                        DoneCheckingForOverflow := True;
                     end
                     else
                        MaybeOverflowing := False;
                     if ((not DoneCheckingForUnderflow) and (MaterialFlowRates[Material].IsNegative)) then
                     begin
                        Writeln('    disabling factories that consume more ', Material.Name, ' than we have');
                        if ((not Assigned(DynastyData^.FMaterialPileComposition)) or (not DynastyData^.FMaterialPileComposition.Has(Material))) then
                        begin
                           RemainingMaterial := TQuantity64.Zero;
                        end
                        else
                        begin
                           RemainingMaterial := DynastyData^.FMaterialPileComposition[Material];
                        end;
                        // we're running out of stuff in piles.
                        // shut down the factories needing more of this material than we have.
                        for Factory in DynastyData^.FFactories.Without(nil) do
                        begin
                           Rate := Factory.GetFactoryRate();
                           Assert(Rate.IsNotExactZero);
                           Found := False;
                           for Entry in Factory.GetFactoryInputs() do
                           begin
                              if (Entry.Material = Material) then
                              begin
                                 Found := True;
                                 NeededMaterial := Entry.Quantity;
                                 break;
                              end;
                           end;
                           Write('    - ');
                           if (not Found) then
                              Write('ignoring unrelated')
                           else
                           if (Rate.IsExactZero) then
                              Write('ignoring stalled')
                           else
                           if (NeededMaterial <= RemainingMaterial) then
                              Write('ignoring satisfied')
                           else
                              Write('disabling');
                           Write(' ', Rate.ToString(), ' factory turning ');
                           for Entry in Factory.GetFactoryInputs() do
                              Write(Entry.Material.Name, ' ');
                           Write('-> ');
                           for Entry in Factory.GetFactoryOutputs() do
                              Write(Entry.Material.Name, ' ');
                           Writeln();
                           if (Found and Rate.IsNotExactZero) then
                           begin
                              if (NeededMaterial > RemainingMaterial) then
                              begin
                                 for Entry in Factory.GetFactoryInputs() do
                                    MaterialFlowRates.Inc(Entry.Material, Entry.Quantity * Rate);
                                 for Entry in Factory.GetFactoryOutputs() do
                                    MaterialFlowRates.Dec(Entry.Material, Entry.Quantity * Rate);
                                 Factory.StallFactory(srInput);
                                 FData[Factory.GetDynasty()]^.FFactories.Replace(Factory, nil);
                              end
                              else
                              begin
                                 RemainingMaterial := RemainingMaterial - NeededMaterial;
                              end;
                           end;
                        end;
                        Stable := False;
                        DoneCheckingForUnderflow := True;
                     end
                     else
                        MaybeUnderflowing := False;
                  until (not MaybeOverflowing) and (not MaybeUnderflowing);
                  if (not Stable) then
                  begin
                     RemainingMaterials.Remove(Material);
                     break;
                  end;
               end;
            until Stable;
            FreeAndNil(RemainingMaterials);
         end;

         // TURN ON ANY FACTORY THAT IS LEFT
         Writeln('  factories (activating):');
         for Factory in DynastyData^.FFactories.Without(nil) do
         begin
            Rate := Factory.GetFactoryRate();
            Write('   - at ', Rate.ToString(), ' ');
            for Entry in Factory.GetFactoryInputs() do
               Write(Entry.Material.Name, ' ');
            Write('-> ');
            for Entry in Factory.GetFactoryOutputs() do
               Write(Entry.Material.Name, ' ');
            Writeln();
            Assert(Rate.IsNotExactZero);
            Factory.StartFactory();
         end;

         // COMPUTE REFINING AND CONSUMPTION RATES

         // Refineries
         for Ore in TOres do
         begin
            Material := System.Encyclopedia.Materials[Ore];
            if (Assigned(MaterialFlowRates) and
                (MaterialFlowRates[Material].IsPositive) and // we are net-generating this material
                ((not Assigned(MaterialConsumerCounts)) or (MaterialConsumerCounts[Material] = 0)) and // we're not consuming this material as fast as possible
                ((not Assigned(MaterialCapacities)) or (MaterialCapacities[Material].IsZero))) then // we have no more room for this material
            begin
               Writeln('  reducing refinery rate for ', Material.Name, ' because');
               Writeln('    OreRefiningRates=', OreRefiningRates[Ore].ToString());
               Writeln('    MaterialFlowRate=', MaterialFlowRates[Material].ToString());
               if (Assigned(MaterialConsumerCounts)) then
                  Writeln('    MaterialConsumerCount=', MaterialConsumerCounts[Material].ToString());
               if (Assigned(MaterialCapacities)) then
                  Writeln('    MaterialCapacity=', MaterialCapacities[Material].ToString());
               // we're generating this material faster than we can handle it, and we know that reducing the refining rate can solve it
               Assert(OreRefiningRates[TOres(Material.ID)] >= MaterialFlowRates[Material]);
               // reduce the ore refining rate so that we're only meeting demand
               OreRefiningRates[Ore] := OreRefiningRates[Ore] - MaterialFlowRates[Material];
               MaterialFlowRates.Reset(Material);
               Include(RefiningLimits[Ore], TargetLimited);
               Writeln('    refining it is now target limited, ', OreRefiningRates[Ore].ToString(), ' refining rate, ', MaterialFlowRates[Material].ToString(), ' material flow rate');
            end;
         end;

         // Consumers
         if (DynastyData^.FMaterialConsumers.IsNotEmpty) then
         begin
            Assert(Assigned(MaterialConsumerCounts));
            for MaterialConsumer in DynastyData^.FMaterialConsumers do
            begin
               Material := MaterialConsumer.GetMaterialConsumerMaterial();
               if (Assigned(Material)) then
               begin
                  Assert(MaterialConsumerCounts.Has(Material));
                  Assert(MaterialConsumerCounts[Material] > 0);
                  if (Assigned(MaterialFlowRates)) then
                  begin
                     MaterialConsumptionRate := MaterialFlowRates[Material].Flatten();
                     if (MaterialConsumptionRate.IsNegative) then
                        MaterialConsumptionRate := TQuantityRate.Zero;
                  end
                  else
                     MaterialConsumptionRate := TQuantityRate.Zero;
                  // If we have consumers who want this, then by definition there's none of that material in
                  // our piles (because they would have taken that first before calling us).
                  Assert((not Assigned(DynastyData^.FMaterialPileComposition)) or
                         (not DynastyData^.FMaterialPileComposition.Has(Material)) or
                         (DynastyData^.FMaterialPileComposition[Material].IsZero),
                         'Unexpectedly found ' + DynastyData^.FMaterialPileComposition[Material].ToString() + ' of ' + Material.Name + ' but we have a consumer: ' + MaterialConsumer.GetAsset().DebugName);
                  MaterialConsumer.StartMaterialConsumer(MaterialConsumptionRate / MaterialConsumerCounts[Material]);
               end;
            end;
            if (Assigned(MaterialFlowRates)) then
            begin
               for Material in MaterialConsumerCounts do
               begin
                  Assert(MaterialConsumerCounts[Material] > 0);
                  if (MaterialFlowRates[Material].IsPositive) then
                     MaterialFlowRates.Reset(Material);
               end;
            end;
         end;
         
         // COMPUTE NEXT EVENT TIMELINE

         // Material Piles
         TimeUntilAnyMaterialPileEmpty := TMillisecondsDuration.Infinity;
         TimeUntilAnyMaterialPileFull := TMillisecondsDuration.Infinity;
         if (Assigned(MaterialFlowRates)) then
         begin
            Writeln('  computing pile limits');
            for Material in MaterialFlowRates do
            begin
               if (MaterialFlowRates[Material].IsPositive) then
               begin
                  // we will eventually fill the piles, but we know they're not full yet
                  Assert(Assigned(MaterialCapacities));
                  Assert(MaterialCapacities[Material].IsPositive);
                  TimeUntilThisMaterialPileFull := MaterialCapacities[Material] / MaterialFlowRates[Material].Flatten();
                  if (TimeUntilThisMaterialPileFull < TimeUntilAnyMaterialPileFull) then
                     TimeUntilAnyMaterialPileFull := TimeUntilThisMaterialPileFull;
                  Writeln('    ', Material.Name, ' (with ', MaterialCapacities[Material].ToString(), ' room left, filling at ', MaterialFlowRates[Material].ToString(), ') will fill in ', TimeUntilThisMaterialPileFull.ToString());
               end
               else
               if (MaterialFlowRates[Material].IsNegative) then
               begin
                  // we will eventually empty the piles, but we know they're not empty yet
                  Assert(Assigned(DynastyData^.FMaterialPileComposition));
                  Assert(DynastyData^.FMaterialPileComposition.Has(Material));
                  Assert(DynastyData^.FMaterialPileComposition[Material].IsPositive);
                  TimeUntilThisMaterialPileEmpty := DynastyData^.FMaterialPileComposition[Material] / -MaterialFlowRates[Material].Flatten();
                  if (TimeUntilThisMaterialPileEmpty < TimeUntilAnyMaterialPileEmpty) then
                     TimeUntilAnyMaterialPileEmpty := TimeUntilThisMaterialPileEmpty;
                  Writeln('    ', Material.Name, ' will empty in ', TimeUntilThisMaterialPileEmpty.ToString());
               end
               else
                  Writeln('    ', Material.Name, ' is stable');
            end;
         end;

         // Ore Piles
         TimeUntilOrePilesEmpty := TMillisecondsDuration.Infinity;
         TimeUntilOrePilesFull := TMillisecondsDuration.Infinity;
         TotalNetOrePileGrowthRate := TMassRate.Zero;            
         for Ore in TOres do
         begin
            Material := System.Encyclopedia.Materials[Ore];
            OreRefiningRate := OreRefiningRates[Ore].Flatten();
            NetOrePileGrowthRate := OreMiningRates[Ore] - OreRefiningRate;
            TotalNetOrePileGrowthRate := TotalNetOrePileGrowthRate + NetOrePileGrowthRate * Material.MassPerUnit;
            if (NetOrePileGrowthRate.IsNegative) then
            begin
               Assert(DynastyData^.FOrePileComposition[Ore].IsPositive);
               // FGroundComposition[Ore] * Material.MassPerUnit  is the mass of this ore in the ground
               // that / CurrentGroundMass  is the fraction of this material relative to other materials in the ground
               // that * DynastyData^.FPendingMiningDebt  is the amount of debt for this ore, as a mass
               // that / Material.MassPerUnit  is the amount of mining debt for this ore, as a quantity
               // that + DynastyData^.FOrePileComposition[Ore]  is the amount that needs to be refined before we run out of ore in the pile
               // that / -NetOrePileGrowthRate  is the time it would take
               TimeUntilThisOrePileEmpty := (((DynastyData^.FPendingMiningDebt * ((FGroundComposition[Ore] * Material.MassPerUnit) / CurrentGroundMass)) / Material.MassPerUnit) + DynastyData^.FOrePileComposition[Ore]) / -NetOrePileGrowthRate;
               if (TimeUntilThisOrePileEmpty < TimeUntilOrePilesEmpty) then
                  TimeUntilOrePilesEmpty := TimeUntilThisOrePileEmpty;
               Writeln('  ore piles will run out of ', Material.Name, ' in ', TimeUntilThisOrePileEmpty.ToString(), ': mining at ', OreMiningRates[Ore].ToString, ', refining at ', OreRefiningRate.ToString(), ', net: ', NetOrePileGrowthRate.ToString(), ', ore pile composition: ', DynastyData^.FOrePileComposition[Ore].ToString(), ', mining debt: total ', DynastyData^.FPendingMiningDebt.ToString(), ', ', ((DynastyData^.FPendingMiningDebt * ((FGroundComposition[Ore] * Material.MassPerUnit) / CurrentGroundMass)) / Material.MassPerUnit).ToString(), ' of ', Material.Name);
               Writeln('  expecting to have mined ', ((TimeUntilThisOrePileEmpty * OreMiningRates[Ore]) + ((DynastyData^.FPendingMiningDebt * ((FGroundComposition[Ore] * Material.MassPerUnit) / CurrentGroundMass)) / Material.MassPerUnit)).ToString());
               Writeln('  expecting to have refined ', (TimeUntilThisOrePileEmpty.AsInt64 * OreRefiningRate.AsDouble):0:10);
               Writeln('  expected net delta ', (TimeUntilThisOrePileEmpty * NetOrePileGrowthRate).ToString());
            end;
         end;
         if (TotalNetOrePileGrowthRate.IsPositive) then
         begin
            RemainingOrePileCapacity := OrePileCapacity - TotalOrePileMass;
            if (RemainingOrePileCapacity.IsPositive) then
            begin
               TimeUntilOrePilesFull := RemainingOrePileCapacity / TotalNetOrePileGrowthRate;
               Writeln('  ore piles will fill in ', TimeUntilOrePilesFull.ToString());
            end
            else
            begin
               TotalNetOrePileGrowthRate := TMassRate.Zero;
               Writeln('  ore piles will remain full');
            end;
         end
         else
            Assert(not TotalOrePileMass.IsNegative, 'TotalOrePileMass is ' + TotalOrePileMass.ToString());
         DynastyData^.FOrePileMassFlowRate := TotalNetOrePileGrowthRate;

         // Refineries
         Refining := False;
         if (DynastyData^.FRefineries.IsNotEmpty) then
         begin
            for Refinery in DynastyData^.FRefineries do
            begin
               Ore := Refinery.GetRefineryOre();
               Ratio := Refinery.GetRefineryMaxRate() / OreRefiningMaxRates[Ore].Flatten();
               Refinery.StartRefinery(OreRefiningRates[Ore].Flatten() * Ratio, SourceLimited in RefiningLimits[Ore], TargetLimited in RefiningLimits[Ore]);
               Material := System.Encyclopedia.Materials[Ore];
               if ((OreRefiningRates[Ore].IsPositive) and (Ratio > 0.0)) then
               begin
                  Refining := True;
                  Writeln('  starting ', Material.Name, ' refinery with rate ', (OreRefiningRates[Ore].Flatten() * Ratio).ToString(), ' (limits: ', SourceLimited in RefiningLimits[Ore], '/' , TargetLimited in RefiningLimits[Ore], ') -- Ratio=', Ratio:0:3);
               end
               else
               begin
                  Writeln('  halting ', Material.Name, ' refinery (limits: ', SourceLimited in RefiningLimits[Ore], '/' , TargetLimited in RefiningLimits[Ore], ') -- max rate ', OreRefiningMaxRates[Ore].ToString(), ', actual rate ', OreRefiningRates[Ore].ToString());
                  Assert(RefiningLimits[Ore] <> [], 'unexpectedly halted refinery');
               end;
            end;
         end;

         // Miners
         if (DynastyData^.FMiners.IsNotEmpty) then
         begin
            if (Refining or (RemainingOrePileCapacity.IsPositive)) then
               Ratio := 1.0
            else
               Ratio := 0.0;
            SourceLimiting := CurrentGroundMass.IsZero;
            TargetLimiting := (not RemainingOrePileCapacity.IsPositive) and (not SourceLimiting);
            for Miner in DynastyData^.FMiners do
            begin
               MiningRate := Miner.GetMinerMaxRate() * Ratio;
               Writeln('  starting miner with rate ', MiningRate.ToString(), ' (limits: ', SourceLimiting, '/' , TargetLimiting, ')');
               Miner.StartMiner(MiningRate, SourceLimiting, TargetLimiting);
            end;
            if (TargetLimiting) then
            begin
               // if we're not filling piles, we're actually net-mining at the refinery speed
               for Ore in TOres do
               begin
                  Material := System.Encyclopedia.Materials[Ore];
                  AllDynastyMiningRate.Inc(OreRefiningRates[Ore].Flatten() * Material.MassPerUnit);
               end;
            end
            else
            begin
               // otherwise we're net-mining at the max rate
               AllDynastyMiningRate.Inc(TotalMinerMaxRate);
            end;
         end;

         // Determine the earliest event
         if (TimeUntilNextEvent > TimeUntilOrePilesFull) then
            TimeUntilNextEvent := TimeUntilOrePilesFull;
         if (TimeUntilNextEvent > TimeUntilOrePilesEmpty) then
            TimeUntilNextEvent := TimeUntilOrePilesEmpty;
         if (TimeUntilNextEvent > TimeUntilAnyMaterialPileFull) then
            TimeUntilNextEvent := TimeUntilAnyMaterialPileFull;
         if (TimeUntilNextEvent > TimeUntilAnyMaterialPileEmpty) then
            TimeUntilNextEvent := TimeUntilAnyMaterialPileEmpty;
         FreeAndNil(MaterialFlowRates);
         FreeAndNil(MaterialCapacities);
         FreeAndNil(MaterialConsumerCounts);
      end;

      if ((CurrentGroundMass.IsPositive) and (AllDynastyMiningRate.IsPositive)) then
      begin
         // we manually set FDynamic to true because in the case where we're mining very
         // slowly (and sinking it straight into a consumer, so we have nothing else in
         // the region that's going to have an event), the time until the ground is full
         // ends up computing as essentially infinite, which means we never otherwise set
         // FDynamic to true below, which means we'd never actually do a real Sync when
         // the consumer decides it's got enough materials.
         FDynamic := True;
         FNetMiningRate := AllDynastyMiningRate.Flatten();
         Writeln('  ground mass: ', CurrentGroundMass.ToString());
         Writeln('  total dynasty mining rate: ', AllDynastyMiningRate.ToString());
         TimeUntilGroundEmpty := CurrentGroundMass / AllDynastyMiningRate.Flatten();
         Writeln('  ground empty in ', TimeUntilGroundEmpty.ToString());
         Assert(TimeUntilGroundEmpty.IsPositive);
         if (TimeUntilNextEvent > TimeUntilGroundEmpty) then
         begin
            TimeUntilNextEvent := TimeUntilGroundEmpty;
         end;
      end
      else
      begin
         Assert(AllDynastyMiningRate.IsZero, 'unexpectedly negative AllDynastyMiningRate: ' + AllDynastyMiningRate.ToString());
         Assert(FNetMiningRate.IsNearZero, 'unexpectedly non-zero FNetMiningRate: ' + FNetMiningRate.ToString());
      end;

      if (not TimeUntilNextEvent.IsInfinite) then
      begin
         Assert(TimeUntilNextEvent.IsPositive);
         Assert(not Assigned(FNextEvent));
         Writeln('  scheduling event for ', TimeUntilNextEvent.ToString());
         FNextEvent := System.ScheduleEvent(TimeUntilNextEvent, @HandleScheduledEvent, Self);
         FDynamic := True;
      end
      else
      if (FDynamic) then
      begin
         Writeln('  region is metastable');
         Assert(not Assigned(FNextEvent));
      end
      else
      begin
         Writeln('  region is stable');
         Assert(not Assigned(FNextEvent));
      end;
      FActive := True;

      Assert(FDynamic or FAnchorTime.IsInfinite);
      if (FDynamic) then
      begin
         if (FAnchorTime.IsInfinite) then
            FAnchorTime := System.Now;
      end;
   end;
   FinalRate := Parent.MassFlowRate;
   Writeln('  after handling region, net mass flow rate is ', FinalRate.ToString());
   Assert(FinalRate.IsNearZero, 'ended with non-zero mass flow rate: ' + FinalRate.ToString());
   {$IFOPT C+} Assert(Busy); Busy := False; {$ENDIF}
   Assert(FDynamic = not FAnchorTime.IsInfinite);
end;


procedure TRegionFeatureNode.RemoveMiner(Miner: IMiner);
begin
   SyncAndReconsider();
   FData[Miner.GetDynasty()]^.FMiners.Replace(Miner, nil);
end;

procedure TRegionFeatureNode.RemoveOrePile(OrePile: IOrePile);
begin
   SyncAndReconsider();
   FData[OrePile.GetDynasty()]^.FOrePiles.Replace(OrePile, nil);
end;

procedure TRegionFeatureNode.RemoveRefinery(Refinery: IRefinery);
begin
   SyncAndReconsider();
   FData[Refinery.GetDynasty()]^.FRefineries.Replace(Refinery, nil);
end;

procedure TRegionFeatureNode.RemoveMaterialPile(MaterialPile: IMaterialPile);
begin
   SyncAndReconsider();
   FData[MaterialPile.GetDynasty()]^.FMaterialPiles.Replace(MaterialPile, nil);
end;

procedure TRegionFeatureNode.RemoveFactory(Factory: IFactory);
begin
   SyncAndReconsider();
   FData[Factory.GetDynasty()]^.FFactories.Replace(Factory, nil);
end;

procedure TRegionFeatureNode.RemoveMaterialConsumer(MaterialConsumer: IMaterialConsumer);
begin
   SyncAndReconsider();
   FData[MaterialConsumer.GetDynasty()]^.FMaterialConsumers.Replace(MaterialConsumer, nil);
end;

procedure TRegionFeatureNode.RehomeOreForPile(OrePile: IOrePile);
var
   Dynasty: TDynasty;
   DynastyData: PPerDynastyData;
   TotalOrePileCapacity, TotalOrePileMass: TMass;
begin
   SyncAndReconsider();
   Assert(not FDynamic);
   Dynasty := OrePile.GetDynasty();
   DynastyData := FData[Dynasty];
   DynastyData^.FOrePiles.Replace(OrePile, nil);
   TotalOrePileCapacity := TMass.Zero;
   if (DynastyData^.FOrePiles.IsNotEmpty) then
   begin
      for OrePile in DynastyData^.FOrePiles.Without(nil) do
      begin
         TotalOrePileCapacity := TotalOrePileCapacity + OrePile.GetOrePileCapacity();
      end;
   end;
   TotalOrePileMass := GetTotalOrePileMass(Dynasty);
   if (TotalOrePileCapacity < TotalOrePileMass) then
   begin
      ReturnOreToGround(DynastyData, TotalOrePileMass, TotalOrePileMass - TotalOrePileCapacity);
   end;
   MarkAsDirty([dkNeedsHandleChanges, dkUpdateClients, dkUpdateJournal]);
end;

procedure TRegionFeatureNode.FlattenOrePileIntoGround(OrePile: IOrePile);
var
   Dynasty: TDynasty;
   DynastyData: PPerDynastyData;
   PileRatio: Double;
   TotalOrePileCapacity, TotalOrePileMass, CurrentOrePileMass: TMass;
begin
   SyncAndReconsider();
   Assert(not FDynamic);
   Dynasty := OrePile.GetDynasty();
   DynastyData := FData[Dynasty];
   TotalOrePileMass := GetTotalOrePileMass(Dynasty);
   if (TotalOrePileMass.IsPositive) then
   begin
      TotalOrePileCapacity := TMass.Zero;
      if (DynastyData^.FOrePiles.IsNotEmpty) then
      begin
         for OrePile in DynastyData^.FOrePiles.Without(nil) do
         begin
            TotalOrePileCapacity := TotalOrePileCapacity + OrePile.GetOrePileCapacity();
         end;
      end;
      PileRatio := OrePile.GetOrePileCapacity() / TotalOrePileCapacity;
      CurrentOrePileMass := TotalOrePileMass * PileRatio;
      ReturnOreToGround(DynastyData, TotalOrePileMass, CurrentOrePileMass);
   end;
   DynastyData^.FOrePiles.Replace(OrePile, nil);
   MarkAsDirty([dkNeedsHandleChanges, dkUpdateClients, dkUpdateJournal]);
end;

function TRegionFeatureNode.ExtractMaterialPile(MaterialPile: IMaterialPile): TQuantity64;
var
   Dynasty: TDynasty;
   DynastyData: PPerDynastyData;
   Material: TMaterial;
   PileRatio: Double;
begin
   SyncAndReconsider();
   Assert(not FDynamic);
   Dynasty := MaterialPile.GetDynasty();
   DynastyData := FData[Dynasty];
   Material := MaterialPile.GetMaterialPileMaterial();
   if (Assigned(DynastyData^.FMaterialPileComposition) and DynastyData^.FMaterialPileComposition.Has(Material)) then
   begin
      PileRatio := MaterialPile.GetMaterialPileCapacity() / GetTotalMaterialPileCapacity(Dynasty, Material);
      Result := GetTotalMaterialPileQuantity(Dynasty, Material) * PileRatio;
      DynastyData^.DecMaterialPile(Material, Result);
   end
   else
      Result := TQuantity64.Zero;
   DynastyData^.FMaterialPiles.Replace(MaterialPile, nil);
   MarkAsDirty([dkNeedsHandleChanges, dkUpdateClients, dkUpdateJournal]);
end;

function TRegionFeatureNode.RehomeMaterialPile(MaterialPile: IMaterialPile): TQuantity64;
var
   Dynasty: TDynasty;
   DynastyData: PPerDynastyData;
   Material: TMaterial;
   PileRatio: Double;
   PileCapacity, TotalCapacity, RemainingCapacity, RemainingQuantity, AffectedQuantity, TotalMaterialQuantity: TQuantity64;
begin
   SyncAndReconsider();
   Assert(not FDynamic);
   Dynasty := MaterialPile.GetDynasty();
   DynastyData := FData[Dynasty];
   Material := MaterialPile.GetMaterialPileMaterial();
   Writeln('  rehoming ', Material.Name);
   if (Assigned(DynastyData^.FMaterialPileComposition) and DynastyData^.FMaterialPileComposition.Has(Material)) then
   begin
      PileCapacity := MaterialPile.GetMaterialPileCapacity();
      TotalCapacity := GetTotalMaterialPileCapacity(Dynasty, Material);
      Assert(PileCapacity <= TotalCapacity);
      PileRatio := PileCapacity / TotalCapacity;
      TotalMaterialQuantity := GetTotalMaterialPileQuantity(Dynasty, Material);
      AffectedQuantity := TotalMaterialQuantity * PileRatio;
      Assert(TotalMaterialQuantity >= AffectedQuantity);
      if (AffectedQuantity.IsPositive) then
      begin
         RemainingCapacity := TotalCapacity - PileCapacity;
         RemainingQuantity := TotalMaterialQuantity - AffectedQuantity;
         if (RemainingCapacity <= RemainingQuantity) then
         begin
            // nothing fits at all, we're completely full
            Result := AffectedQuantity;
         end
         else
         if (RemainingCapacity - RemainingQuantity < AffectedQuantity) then
         begin
            // we can't fit it all in the remaining capacity
            Result := AffectedQuantity - (RemainingCapacity - RemainingQuantity);
         end
         else
         begin
            Assert(TotalMaterialQuantity <= RemainingCapacity);
            // it all fits in the remaining capacity
            Result := TQuantity64.Zero;
         end;
         if (Result.IsPositive) then
         begin
            DynastyData^.DecMaterialPile(Material, Result);
         end;
      end
      else
         Result := TQuantity64.Zero; // the pile didn't have anything in it
   end
   else
      Result := TQuantity64.Zero; // we don't have any of that material
   DynastyData^.FMaterialPiles.Replace(MaterialPile, nil);
   MarkAsDirty([dkNeedsHandleChanges, dkUpdateClients, dkUpdateJournal]);
end;

procedure TRegionFeatureNode.ClientChanged();
begin
   SyncAndReconsider();
end;

function TRegionFeatureNode.GetOresPresentForPile(Pile: IOrePile): TOreFilter;
var
   Ore: TOres;
   IncludeGround: Boolean;
   Source: POreQuantities;
begin
   Result.Clear();
   IncludeGround := FData[Pile.GetDynasty()]^.FOrePileMassFlowRate.IsPositive;
   Source := @(FData[Pile.GetDynasty()]^.FOrePileComposition);
   for Ore in TOres do
   begin
      if (IncludeGround and FGroundComposition[Ore].IsPositive) then
         Result.Enable(Ore)
      else
      if (Source^[Ore].IsPositive) then
         Result.Enable(Ore);
   end;
end;

function TRegionFeatureNode.GetOresForPile(Pile: IOrePile): TOreQuantities;
var
   PileRatio: Double;
   Ore: TOres;
   TotalCapacity: TMass;
   Dynasty: TDynasty;
   DynastyData: PPerDynastyData;
begin
   Dynasty := Pile.GetDynasty();
   DynastyData := FData[Dynasty];
   Assert(DynastyData^.FOrePiles.Contains(Pile));
   Sync();
   TotalCapacity := GetTotalOrePileCapacity(Dynasty);
   if (TotalCapacity.IsPositive) then
   begin
      PileRatio := Pile.GetOrePileCapacity() / TotalCapacity;
      Assert(PileRatio > 0.0);
      Assert(PileRatio <= 1.0);
      for Ore in TOres do
         Result[Ore] := DynastyData^.FOrePileComposition[Ore] * PileRatio;
   end
   else
   begin
      Assert(SizeOf(Result[Low(Result)]) = SizeOf(QWord));
      FillQWord(Result[Low(TOres)], High(TOres) - Low(TOres), 0);
   end;
end;

function TRegionFeatureNode.GetMaterialPileMass(Pile: IMaterialPile): TMass; // kg
var
   Material: TMaterial;
   PileRatio: Double;
   Dynasty: TDynasty;
begin
   Dynasty := Pile.GetDynasty();
   Material := Pile.GetMaterialPileMaterial();
   PileRatio := Pile.GetMaterialPileCapacity() / GetTotalMaterialPileCapacity(Dynasty, Material);
   Assert(PileRatio <= 1.0);
   Result := GetTotalMaterialPileMass(Dynasty, Material) * PileRatio;
   Assert(Result <= Pile.GetMaterialPileCapacity() * Material.MassPerUnit);
end;

function TRegionFeatureNode.GetMaterialPileMassFlowRate(Pile: IMaterialPile): TMassRate; // kg/s
var
   Material: TMaterial;
   PileRatio: Double;
   Dynasty: TDynasty;
begin
   Dynasty := Pile.GetDynasty();
   Material := Pile.GetMaterialPileMaterial();
   PileRatio := Pile.GetMaterialPileCapacity() / GetTotalMaterialPileCapacity(Dynasty, Material);
   Result := GetTotalMaterialPileMassFlowRate(Dynasty, Material) * PileRatio;
end;

function TRegionFeatureNode.GetMaterialPileQuantity(Pile: IMaterialPile): TQuantity64;
var
   Material: TMaterial;
   PileRatio: Double;
   Dynasty: TDynasty;
begin
   Dynasty := Pile.GetDynasty();
   Material := Pile.GetMaterialPileMaterial();
   PileRatio := Pile.GetMaterialPileCapacity() / GetTotalMaterialPileCapacity(Dynasty, Material);
   Result := GetTotalMaterialPileQuantity(Dynasty, Material) * PileRatio;
end;

function TRegionFeatureNode.GetMaterialPileQuantityFlowRate(Pile: IMaterialPile): TQuantityRate; // units/s
var
   Material: TMaterial;
   PileRatio: Double;
   Dynasty: TDynasty;
begin
   Dynasty := Pile.GetDynasty();
   Material := Pile.GetMaterialPileMaterial();
   PileRatio := Pile.GetMaterialPileCapacity() / GetTotalMaterialPileCapacity(Dynasty, Material);
   Result := GetTotalMaterialPileQuantityFlowRate(Dynasty, Material) * PileRatio;
end;

procedure TRegionFeatureNode.Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter);
var
   Visibility: TVisibility;
begin
   Visibility := Parent.ReadVisibilityFor(DynastyIndex);
   if ((dmDetectable * Visibility <> []) and (dmClassKnown in Visibility)) then
   begin
      Writer.WriteCardinal(fcRegion);
      Assert(Length(FGroundComposition) > 0);
      Writer.WriteBoolean(IsMinable); // if we add more flags, they should go into this byte
   end;
end;

procedure TRegionFeatureNode.UpdateJournal(Journal: TJournalWriter);
var
   Ore: TOres;
   Material: TMaterial;
   Dynasty: TDynasty;
   DynastyData: PPerDynastyData;
begin
   Journal.WriteBoolean(FAllocatedOres);
   Assert(Length(FGroundComposition) > 0);
   for Ore := Low(FGroundComposition) to High(FGroundComposition) do
   begin
      if (FGroundComposition[Ore].IsPositive) then
      begin
         Journal.WriteMaterialReference(System.Encyclopedia.Materials[Ore]);
         Journal.WriteInt64(FGroundComposition[Ore].AsInt64);
      end;
   end;
   Journal.WriteCardinal(0);
   for Dynasty in FData.Dynasties do
   begin
      Journal.WriteDynastyReference(Dynasty);
      DynastyData := FData[Dynasty];
      Assert(Length(DynastyData^.FOrePileComposition) > 0);
      for Ore := Low(DynastyData^.FOrePileComposition) to High(DynastyData^.FOrePileComposition) do
      begin
         if (DynastyData^.FOrePileComposition[Ore].IsPositive) then
         begin
            Journal.WriteMaterialReference(System.Encyclopedia.Materials[Ore]);
            Journal.WriteInt64(DynastyData^.FOrePileComposition[Ore].AsInt64);
         end;
      end;
      Journal.WriteCardinal(0); // last ore
      if (Assigned(DynastyData^.FMaterialPileComposition)) then
      begin
         for Material in DynastyData^.FMaterialPileComposition do
         begin
            Journal.WriteMaterialReference(Material);
            Journal.WriteInt64(DynastyData^.FMaterialPileComposition[Material].AsInt64);
         end;
      end;
      Journal.WriteCardinal(0); // last material
      Journal.WriteDouble(DynastyData^.FPendingMiningDebt.AsDouble);
   end;
   Journal.WriteCardinal(0); // last dynasty
end;

procedure TRegionFeatureNode.ApplyJournal(Journal: TJournalReader);

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
            Composition[OreID] := TQuantity64.FromUnits(Journal.ReadInt64());
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
            Materials[Material] := TQuantity64.FromUnits(Journal.ReadInt64());
         end;
      until not Assigned(Material);
   end;

var
   Dynasty: TDynasty;
   DynastyData: PPerDynastyData;
begin
   FAllocatedOres := Journal.ReadBoolean();
   ReadOres(FGroundComposition);
   repeat
      Dynasty := Journal.ReadDynastyReference();
      if (Assigned(Dynasty)) then
      begin
         DynastyData := FData[Dynasty];
         ReadOres(DynastyData^.FOrePileComposition);
         ReadMaterials(DynastyData^.FMaterialPileComposition);
         DynastyData^.FPendingMiningDebt := TMass.FromKg(Journal.ReadDouble());
      end;
   until not Assigned(Dynasty);
end;

procedure TRegionFeatureNode.DescribeExistentiality(var IsDefinitelyReal, IsDefinitelyGhost: Boolean);
begin
   IsDefinitelyReal := True;
end;

initialization
   RegisterFeatureClass(TRegionFeatureClass);
end.