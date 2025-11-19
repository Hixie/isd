{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit region;

interface

{$DEFINE VERBOSE}

uses
   systems, serverstream, techtree, materials, time, providers,
   hashtable, genericutils, isdprotocol, plasticarrays,
   commonbuses, systemdynasty;

type
   TRegionFeatureNode = class;

   TRegionClientFields = packed record
   strict private
      FRegion: TRegionFeatureNode; // 8 bytes
      FDisabledReasons: TDisabledReasons; // 4 bytes
      FRate: TRate; // 8 bytes
      FSourceLimiting, FTargetLimiting: Boolean; // 1 byte
      function GetNeedsConnection(): Boolean; inline;
      function GetConnected(): Boolean; inline;
   public
      property DisabledReasons: TDisabledReasons read FDisabledReasons;
      property NeedsConnection: Boolean read GetNeedsConnection;
      property Connected: Boolean read GetConnected;
      property Region: TRegionFeatureNode read FRegion;
      property Rate: TRate read FRate;
      property SourceLimiting: Boolean read FSourceLimiting;
      property TargetLimiting: Boolean read FTargetLimiting;
   public
      procedure SetDisabledReasons(Value: TDisabledReasons);
      procedure SetRegion(ARegion: TRegionFeatureNode);
      function Update(ARate: TRate; ASourceLimiting, ATargetLimiting: Boolean): Boolean; // returns whether anything changed
      procedure SetNoRegion(); inline;
      procedure Reset();
   end;
   {$IF SIZEOF(TRegionClientFields) > 3*8} {$FATAL} {$ENDIF}

   IMiner = interface ['IMiner']
      function GetMinerMaxRate(): TRate; // kg per second
      function GetMinerCurrentRate(): TRate; // kg per second
      procedure SetMinerRegion(Region: TRegionFeatureNode);
      procedure StartMiner(Rate: TRate; SourceLimiting, TargetLimiting: Boolean);
      procedure DisconnectMiner();
      function GetDynasty(): TDynasty;
   end;
   TRegisterMinerBusMessage = specialize TRegisterProviderBusMessage<TPhysicalConnectionBusMessage, IMiner>;
   TMinerList = specialize PlasticArray<IMiner, PointerUtils>;

   IOrePile = interface ['IOrePile']
      function GetOrePileCapacity(): Double; // kg
      procedure SetOrePileRegion(Region: TRegionFeatureNode);
      procedure RegionAdjustedOrePiles();
      procedure DisconnectOrePile();
      function GetDynasty(): TDynasty;
   end;
   TRegisterOrePileBusMessage = specialize TRegisterProviderBusMessage<TPhysicalConnectionBusMessage, IOrePile>;
   TOrePileList = specialize PlasticArray<IOrePile, PointerUtils>;

   IRefinery = interface ['IRefinery']
      function GetRefineryOre(): TOres;
      function GetRefineryMaxRate(): TRate; // kg per second
      function GetRefineryCurrentRate(): TRate; // kg per second
      procedure SetRefineryRegion(Region: TRegionFeatureNode);
      procedure StartRefinery(Rate: TRate; SourceLimiting, TargetLimiting: Boolean); // kg per second
      procedure DisconnectRefinery();
      function GetDynasty(): TDynasty;
   end;
   TRegisterRefineryBusMessage = specialize TRegisterProviderBusMessage<TPhysicalConnectionBusMessage, IRefinery>;
   TRefineryList = specialize PlasticArray<IRefinery, PointerUtils>;

   IMaterialPile = interface ['IMaterialPile']
      function GetMaterialPileMaterial(): TMaterial;
      function GetMaterialPileCapacity(): UInt64; // quantity
      procedure SetMaterialPileRegion(Region: TRegionFeatureNode);
      procedure RegionAdjustedMaterialPiles();
      procedure DisconnectMaterialPile();
      function GetDynasty(): TDynasty;
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
      procedure SetMaterialConsumerRegion(Region: TRegionFeatureNode);
      procedure StartMaterialConsumer(ActualRate: TRate); // quantity per second; only called if GetMaterialConsumerMaterial returns non-nil
      procedure DeliverMaterialConsumer(Delivery: UInt64); // 0 <= Delivery <= GetMaterialConsumerMaxDelivery; will always be called when syncing if StartMaterialConsumer was called
      procedure DisconnectMaterialConsumer(); // region is going away
      function GetDynasty(): TDynasty;
   end;
   TRegisterMaterialConsumerBusMessage = specialize TRegisterProviderBusMessage<TPhysicalConnectionBusMessage, IMaterialConsumer>;
   TMaterialConsumerList = specialize PlasticArray<IMaterialConsumer, PointerUtils>;

   TObtainMaterialBusMessage = class(TPhysicalConnectionBusMessage)
   strict private
      FDynasty: TDynasty;
      FRequest: TMaterialQuantity;
      FDelivery: UInt64;
      function GetRemainingQuantity(): UInt64; inline;
      function GetFulfilled(): Boolean; inline;
      function GetTransferredManifest(): TMaterialQuantity; inline;
   public
      constructor Create(ADynasty: TDynasty; ARequest: TMaterialQuantity); overload;
      constructor Create(ADynasty: TDynasty; AMaterial: TMaterial; AQuantity: UInt64); overload;
      procedure Deliver(ADelivery: UInt64);
      property Dynasty: TDynasty read FDynasty;
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
      function InitFeatureNode(ASystem: TSystem): TFeatureNode; override;
      property Depth: Cardinal read FDepth;
      property TargetCount: Cardinal read FTargetCount;
      property TargetQuantity: UInt64 read FTargetQuantity;
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
            FMaterialConsumers: TMaterialConsumerList;
            class operator Initialize(var Rec: TPerDynastyData);
            class operator Finalize(var Rec: TPerDynastyData);
            procedure IncMaterialPile(Material: TMaterial; Delta: UInt64);
            procedure DecMaterialPile(Material: TMaterial; Delta: UInt64);
            function ClampedDecMaterialPile(Material: TMaterial; Delta: UInt64): UInt64; // returns how much was actually transferred
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
            {$IFOPT C+} function HasData(Dynasty: TDynasty): Boolean; {$ENDIF}
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
      {$IFOPT C+} Busy: Boolean; {$ENDIF} // set to true while running our algorithms, to make sure nobody calls us reentrantly
      function GetTotalOrePileCapacity(Dynasty: TDynasty): Double; // kg total for all piles
      function GetTotalOrePileMass(Dynasty: TDynasty): Double; // kg total for all piles
      function GetTotalOrePileMassFlowRate(Dynasty: TDynasty): TRate; // kg/s (total for all piles; total miner rate minus total refinery rate)
      function GetMinOreMassTransfer(): Double; // kg mass that would need to be transferred from the ground to move at least one unit of quantity
      function GetTotalMaterialPileQuantity(Dynasty: TDynasty; Material: TMaterial): UInt64;
      function GetTotalMaterialPileQuantityFlowRate(Dynasty: TDynasty; Material: TMaterial): TRate; // units/s
      function GetTotalMaterialPileCapacity(Dynasty: TDynasty; Material: TMaterial): UInt64;
      function GetTotalMaterialPileMass(Dynasty: TDynasty; Material: TMaterial): Double; // kg
      function GetTotalMaterialPileMassFlowRate(Dynasty: TDynasty; Material: TMaterial): TRate; // kg/s
      function GetIsMinable(): Boolean;
   protected
      constructor CreateFromJournal(Journal: TJournalReader; AFeatureClass: TFeatureClass; ASystem: TSystem); override;
      function GetMass(): Double; override;
      function GetMassFlowRate(): TRate; override;
      function ManageBusMessage(Message: TBusMessage): TBusMessageResult; override;
      function HandleBusMessage(Message: TBusMessage): Boolean; override;
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
      // TODO: RemoveFactory
      procedure RemoveMaterialConsumer(MaterialConsumer: IMaterialConsumer);
      procedure SyncForMaterialConsumer(); // call when a material consumer thinks it might be done
      function GetOrePileMass(Pile: IOrePile): Double; // kg
      function GetOrePileMassFlowRate(Pile: IOrePile): TRate; // kg/s
      function GetOresPresentForPile(Pile: IOrePile): TOreFilter;
      function GetOresForPile(Pile: IOrePile): TOreQuantities;
      function GetMaterialPileMass(Pile: IMaterialPile): Double; // kg
      function GetMaterialPileMassFlowRate(Pile: IMaterialPile): TRate; // kg/s
      function GetMaterialPileQuantity(Pile: IMaterialPile): UInt64; // units
      function GetMaterialPileQuantityFlowRate(Pile: IMaterialPile): TRate; // units/s
      property IsMinable: Boolean read GetIsMinable;
   end;

implementation

uses
   sysutils, planetary, exceptions, isdnumbers, math, hashfunctions;


function TRegionClientFields.GetNeedsConnection(): Boolean;
begin
   Result := (not Assigned(FRegion)) and (FDisabledReasons = []);
end;

function TRegionClientFields.GetConnected(): Boolean;
begin
   Result := Assigned(FRegion);
end;

procedure TRegionClientFields.SetDisabledReasons(Value: TDisabledReasons);
begin
   FDisabledReasons := Value;
   FRegion := nil;
   FRate := TRate.Zero;
   FSourceLimiting := False;
   FTargetLimiting := False;
end;

procedure TRegionClientFields.SetRegion(ARegion: TRegionFeatureNode);
begin
   Assert(Assigned(ARegion));
   Assert(FDisabledReasons = []);
   FRegion := ARegion;
end;

function TRegionClientFields.Update(ARate: TRate; ASourceLimiting, ATargetLimiting: Boolean): Boolean;
begin
   Assert(Assigned(FRegion));
   Assert(FDisabledReasons = []);
   Result := (FRate <> ARate) or
             (FSourceLimiting <> ASourceLimiting) or
             (FTargetLimiting <> ATargetLimiting);
   if (Result) then
   begin
      FRate := ARate;
      FSourceLimiting := ASourceLimiting;
      FTargetLimiting := ATargetLimiting;
   end;
end;

procedure TRegionClientFields.SetNoRegion();
begin
   Assert(FDisabledReasons = []);
   Assert(Rate.IsZero);
   Assert(not SourceLimiting);
   Assert(not TargetLimiting);
   Include(FDisabledReasons, drNoBus);
end;

procedure TRegionClientFields.Reset();
begin
   FRegion := nil;
   FRate := TRate.Zero;
   FSourceLimiting := False;
   FTargetLimiting := False;
   Exclude(FDisabledReasons, drNoBus);
end;


constructor TObtainMaterialBusMessage.Create(ADynasty: TDynasty; ARequest: TMaterialQuantity);
begin
   inherited Create();
   Assert(Assigned(ADynasty));
   Assert(Assigned(ARequest.Material));
   FDynasty := ADynasty;
   FRequest := ARequest;
   Assert(not Fulfilled);
end;

constructor TObtainMaterialBusMessage.Create(ADynasty: TDynasty; AMaterial: TMaterial; AQuantity: UInt64);
begin
   inherited Create();
   Assert(Assigned(ADynasty));
   Assert(Assigned(AMaterial));
   FDynasty := ADynasty;
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

function TRegionFeatureClass.InitFeatureNode(ASystem: TSystem): TFeatureNode;
begin
   Result := nil;
   raise Exception.Create('Cannot create a TRegionFeatureNode from a prototype, it must have an ore composition from an ancestor TPlanetaryBodyFeatureNode.');
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
   // if we do anything else here, see GetData below
end;

class operator TRegionFeatureNode.TPerDynastyData.Finalize(var Rec: TPerDynastyData);
begin
   FreeAndNil(Rec.FMaterialPileComposition);
end;

procedure TRegionFeatureNode.TPerDynastyData.IncMaterialPile(Material: TMaterial; Delta: UInt64);
begin
   Assert(Assigned(Material));
   Assert(Delta > 0);
   if (not Assigned(FMaterialPileComposition)) then
   begin
      FMaterialPileComposition := TMaterialQuantityHashTable.Create(1);
   end;
   FMaterialPileComposition.Inc(Material, Delta);
end;

procedure TRegionFeatureNode.TPerDynastyData.DecMaterialPile(Material: TMaterial; Delta: UInt64);
begin
   Assert(Assigned(Material));
   Assert(Delta > 0);
   Assert(Assigned(FMaterialPileComposition));
   FMaterialPileComposition.Dec(Material, Delta);
end;

function TRegionFeatureNode.TPerDynastyData.ClampedDecMaterialPile(Material: TMaterial; Delta: UInt64): UInt64;
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

{$IFOPT C+}
function TRegionFeatureNode.TRegionData.HasData(Dynasty: TDynasty): Boolean;
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
{$ENDIF}


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
   Dynasty: TDynasty;
   DynastyData: PPerDynastyData;
begin
   Result := TRate.Zero;
   if (FDynamic) then
   begin
      case (FData.DynastyMode) of
         dmNone: ;
         dmOne: if (FData.SingleDynastyData^.FMiners.IsNotEmpty) then
                   for Miner in FData.SingleDynastyData^.FMiners.Without(nil) do
                      Result := Result - Miner.GetMinerCurrentRate();
         dmMany: for Dynasty in FData.Dynasties do
                 begin
                    DynastyData := FData[Dynasty];
                    if (DynastyData^.FMiners.IsNotEmpty) then
                       for Miner in DynastyData^.FMiners.Without(nil) do
                          Result := Result - Miner.GetMinerCurrentRate();
                 end;
      end;
   end;
   // Refineries, factories, and consumers affect the flow rates of
   // the pile assets (see e.g. GetOrePileMassFlowRate below).
end;

function TRegionFeatureNode.GetTotalOrePileCapacity(Dynasty: TDynasty): Double; // kg total for all piles
var
   OrePile: IOrePile;
   DynastyData: PPerDynastyData;
begin
   Assert(FData.HasData(Dynasty));
   Result := 0.0;
   DynastyData := FData[Dynasty];
   if (DynastyData^.FOrePiles.IsNotEmpty) then
   begin
      for OrePile in DynastyData^.FOrePiles.Without(nil) do
         Result := Result + OrePile.GetOrePileCapacity();
   end;
end;

function TRegionFeatureNode.GetTotalOrePileMass(Dynasty: TDynasty): Double; // kg total for all piles
var
   Ore: TOres;
   CachedSystem: TSystem;
   Encyclopedia: TEncyclopediaView;
   DynastyData: PPerDynastyData;
begin
   Assert(FData.HasData(Dynasty));
   DynastyData := FData[Dynasty];
   CachedSystem := System;
   Encyclopedia := CachedSystem.Encyclopedia;
   Result := 0.0;
   if (Length(DynastyData^.FOrePileComposition) > 0) then
      for Ore := Low(DynastyData^.FOrePileComposition) to High(DynastyData^.FOrePileComposition) do // $R-
         Result := Result + Encyclopedia.Materials[Ore].MassPerUnit * DynastyData^.FOrePileComposition[Ore];
   Assert(Result >= 0.0);
   if (FDynamic) then
   begin
      Assert(not FAnchorTime.IsInfinite);
      Result := Result + (CachedSystem.Now - FAnchorTime) * GetTotalOrePileMassFlowRate(Dynasty);
   end;
   Assert(Result >= 0.0);
end;

function TRegionFeatureNode.GetTotalOrePileMassFlowRate(Dynasty: TDynasty): TRate; // kg/s (miner rate minus refinery rate)
var
   Miner: IMiner;
   Refinery: IRefinery;
   DynastyData: PPerDynastyData;
begin
   Assert(FData.HasData(Dynasty));
   Result := TRate.Zero;
   if (FDynamic) then
   begin
      DynastyData := FData[Dynasty];
      if (DynastyData^.FMiners.IsNotEmpty) then
      begin
         for Miner in DynastyData^.FMiners.Without(nil) do
            Result := Result + Miner.GetMinerCurrentRate();
      end;
      if (DynastyData^.FRefineries.IsNotEmpty) then
      begin
         for Refinery in DynastyData^.FRefineries.Without(nil) do
            Result := Result - Refinery.GetRefineryCurrentRate();
      end;
   end;
end;

function TRegionFeatureNode.GetOrePileMass(Pile: IOrePile): Double; // kg
var
   PileRatio: Double;
   Dynasty: TDynasty;
begin
   Dynasty := Pile.GetDynasty();
   PileRatio := Pile.GetOrePileCapacity() / GetTotalOrePileCapacity(Dynasty);
   Result := GetTotalOrePileMass(Dynasty) * PileRatio;
end;

function TRegionFeatureNode.GetOrePileMassFlowRate(Pile: IOrePile): TRate; // kg/s
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

function TRegionFeatureNode.GetMinOreMassTransfer(): Double;
var
   Ore: TOres;
   Quantity: UInt64;
   TransferMassPerUnit, Min: Double;
begin
   Min := System.Encyclopedia.MinMassPerOreUnit;
   {$PUSH} {$IEEEERRORS-} Result := Infinity; {$POP}
   for Ore in TOres do
   begin
      Quantity := FGroundComposition[Ore];
      if (Quantity > 0) then
      begin
         TransferMassPerUnit := System.Encyclopedia.Materials[Ore].MassPerUnit;
         if (TransferMassPerUnit < Result) then
            Result := TransferMassPerUnit;
         if (Result <= Min) then
            exit;
      end;
   end;
end;

function TRegionFeatureNode.GetTotalMaterialPileQuantity(Dynasty: TDynasty; Material: TMaterial): UInt64;
var
   DynastyData: PPerDynastyData;
begin
   Assert(FData.HasData(Dynasty));
   DynastyData := FData[Dynasty];
   if (not Assigned(DynastyData^.FMaterialPileComposition)) then
   begin
      Result := 0;
   end
   else
   if (not DynastyData^.FMaterialPileComposition.Has(Material)) then
   begin
      Result := 0;
   end
   else
   begin
      Result := DynastyData^.FMaterialPileComposition[Material];
   end;
   if (FDynamic) then
   begin
      Inc(Result, RoundUInt64((System.Now - FAnchorTime) * GetTotalMaterialPileQuantityFlowRate(Dynasty, Material)));
   end;
end;

function TRegionFeatureNode.GetTotalMaterialPileQuantityFlowRate(Dynasty: TDynasty; Material: TMaterial): TRate; // units/s
var
   Refinery: IRefinery;
   Consumer: IMaterialConsumer;
   DynastyData: PPerDynastyData;
begin
   Assert(FData.HasData(Dynasty));
   DynastyData := FData[Dynasty];
   Result := TRate.Zero;
   if (DynastyData^.FRefineries.IsNotEmpty and Material.IsOre) then
   begin
      for Refinery in DynastyData^.FRefineries.Without(nil) do
      begin
         if (Refinery.GetRefineryOre() = Material.ID) then
            Result := Result + Refinery.GetRefineryCurrentRate() / Material.MassPerUnit;
      end;
   end;
   // TODO: factories (consumption, generation)
   if (DynastyData^.FMaterialConsumers.IsNotEmpty) then
   begin
      for Consumer in DynastyData^.FMaterialConsumers.Without(nil) do
      begin
         if (Consumer.GetMaterialConsumerMaterial() = Material) then
            Result := Result - Consumer.GetMaterialConsumerCurrentRate();
      end;
   end;
end;

function TRegionFeatureNode.GetTotalMaterialPileCapacity(Dynasty: TDynasty; Material: TMaterial): UInt64;
var
   Pile: IMaterialPile;
   DynastyData: PPerDynastyData;
begin
   Assert(FData.HasData(Dynasty));
   DynastyData := FData[Dynasty];
   Result := 0;
   if (DynastyData^.FMaterialPiles.IsNotEmpty) then
   begin
      for Pile in DynastyData^.FMaterialPiles.Without(nil) do
      begin
         if (Pile.GetMaterialPileMaterial() = Material) then
            Inc(Result, Pile.GetMaterialPileCapacity());
      end;
   end;
end;

function TRegionFeatureNode.GetTotalMaterialPileMass(Dynasty: TDynasty; Material: TMaterial): Double; // kg
var
   DynastyData: PPerDynastyData;
begin
   Assert(FData.HasData(Dynasty));
   DynastyData := FData[Dynasty];
   if (not Assigned(DynastyData^.FMaterialPileComposition)) then
   begin
      Result := 0;
   end
   else
   if (not DynastyData^.FMaterialPileComposition.Has(Material)) then
   begin
      Result := 0;
   end
   else
   begin
      Result := DynastyData^.FMaterialPileComposition[Material] * Material.MassPerUnit;
   end;
   if (FDynamic) then
   begin
      Result := Result + (System.Now - FAnchorTime) * GetTotalMaterialPileMassFlowRate(Dynasty, Material);
   end;
end;

function TRegionFeatureNode.GetTotalMaterialPileMassFlowRate(Dynasty: TDynasty; Material: TMaterial): TRate; // kg/s
var
   Refinery: IRefinery;
   Consumer: IMaterialConsumer;
   DynastyData: PPerDynastyData;
begin
   Assert(FData.HasData(Dynasty));
   DynastyData := FData[Dynasty];
   Result := TRate.Zero;
   if (DynastyData^.FRefineries.IsNotEmpty and Material.IsOre) then
   begin
      for Refinery in DynastyData^.FRefineries.Without(nil) do
      begin
         if (Refinery.GetRefineryOre() = Material.ID) then
            Result := Result + Refinery.GetRefineryCurrentRate();
      end;
   end;
   // TODO: factories (consumption, generation)
   if (DynastyData^.FMaterialConsumers.IsNotEmpty) then
   begin
      for Consumer in DynastyData^.FMaterialConsumers.Without(nil) do
      begin
         if (Consumer.GetMaterialConsumerMaterial() = Material) then
            Result := Result - Consumer.GetMaterialConsumerCurrentRate() * Material.MassPerUnit;
      end;
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
begin
   if ((Message is TRegisterMinerBusMessage) or
       (Message is TRegisterOrePileBusMessage) or
       (Message is TRegisterRefineryBusMessage) or
       (Message is TRegisterMaterialPileBusMessage) or
       (Message is TRegisterMaterialConsumerBusMessage) or
       (Message is TObtainMaterialBusMessage)) then
   begin
      Result := DeferOrManageBusMessage(Message);
   end
   else
      Result := mrDeferred;
end;

function TRegionFeatureNode.HandleBusMessage(Message: TBusMessage): Boolean;
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
   Obtain: TObtainMaterialBusMessage;
   DeliverySize: UInt64;
   MaterialPile: IMaterialPile;
   DynastyData: PPerDynastyData;
begin
   {$IFOPT C+} Assert(not Busy); {$ENDIF}
   if (Message is TRegisterMinerBusMessage) then
   begin
      SyncAndReconsider();
      MinerMessage := Message as TRegisterMinerBusMessage;
      DynastyData := FData[MinerMessage.Provider.GetDynasty()];
      Assert(not DynastyData^.FMiners.Contains(MinerMessage.Provider));
      DynastyData^.FMiners.Push(MinerMessage.Provider);
      MinerMessage.Provider.SetMinerRegion(Self);
      Result := True;
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
      Result := True;
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
      Result := True;
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
      Result := True;
   end
   // TODO: factories
   else
   if (Message is TRegisterMaterialConsumerBusMessage) then
   begin
      SyncAndReconsider();
      MaterialConsumerMessage := Message as TRegisterMaterialConsumerBusMessage;
      DynastyData := FData[MaterialConsumerMessage.Provider.GetDynasty()];
      Assert(not DynastyData^.FMaterialConsumers.Contains(MaterialConsumerMessage.Provider));
      DynastyData^.FMaterialConsumers.Push(MaterialConsumerMessage.Provider);
      MaterialConsumerMessage.Provider.SetMaterialConsumerRegion(Self);
      Result := True;
   end
   else
   if (Message is TObtainMaterialBusMessage) then
   begin
      Obtain := Message as TObtainMaterialBusMessage;
      DynastyData := FData[Obtain.Dynasty];
      Assert(Obtain.Quantity > 0);
      SyncAndReconsider();
      if (Assigned(DynastyData^.FMaterialPileComposition) and DynastyData^.FMaterialPileComposition.Has(Obtain.Material)) then
      begin
         DeliverySize := DynastyData^.FMaterialPileComposition[Obtain.Material];
         if (DeliverySize > 0) then
         begin
            if (DeliverySize > Obtain.Quantity) then
               DeliverySize := Obtain.Quantity;
            Obtain.Deliver(DeliverySize);
            DynastyData^.DecMaterialPile(Obtain.Material, DeliverySize);
            if (DynastyData^.FMaterialPiles.IsNotEmpty) then
               for MaterialPile in DynastyData^.FMaterialPiles.Without(nil) do
                  if (MaterialPile.GetMaterialPileMaterial() = Obtain.Material) then
                     MaterialPile.RegionAdjustedMaterialPiles();
            MarkAsDirty([dkUpdateJournal]);
         end;
      end;
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
   MaterialPile: IMaterialPile;
   Rate: TRate;
   TotalCompositionMass, TotalTransferMass, ApproximateTransferQuantity, ActualTransfer, CurrentOrePileMass, OrePileCapacity: Double;
   {$IFDEF DEBUG}
   OrePileRecordedMass: Double;
   {$ENDIF}
   SyncDuration: TMillisecondsDuration;
   Ore: TOres;
   OrePilesAffected, MaterialPilesAffected: Boolean;
   Material: TMaterial;
   CachedSystem: TSystem;
   Encyclopedia: TEncyclopediaView;
   Quantity: UInt64;
   TransferQuantity, ActualTransferQuantity, DesiredTransferQuantity: UInt64;
   Distribution: TOreFractions;
   RefinedOreMasses: array[TOres] of Double;
   GroundChanged, GroundWasMinable: Boolean;
   Dynasty: TDynasty;
   DynastyData: PPerDynastyData;
begin
   Assert(FActive);
   if (not FDynamic) then
   begin
      Assert(not Assigned(FNextEvent));
      exit;
   end;

   CachedSystem := System;
   SyncDuration := CachedSystem.Now - FAnchorTime;

   if (SyncDuration.IsZero) then
   begin
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

   for Dynasty in FData.Dynasties do
   begin
      DynastyData := FData[Dynasty];

      OrePilesAffected := False;
      MaterialPilesAffected := False;

      OrePileCapacity := 0.0;
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
         CurrentOrePileMass := GetTotalOrePileMass(Dynasty);
         OrePileRecordedMass := 0.0;
         if (Length(DynastyData^.FOrePileComposition) > 0) then
            for Ore := Low(DynastyData^.FOrePileComposition) to High(DynastyData^.FOrePileComposition) do // $R-
            begin
               OrePileRecordedMass := OrePileRecordedMass + Encyclopedia.Materials[Ore].MassPerUnit * DynastyData^.FOrePileComposition[Ore];
            end;
         Assert(CurrentOrePileMass <= OrePileCapacity + 0.00001, 'already over capacity');
      end;
      {$ENDIF}

      if (DynastyData^.FMiners.IsNotEmpty) then
      begin
         TotalCompositionMass := 0.0;
         Assert(Length(FGroundComposition) > 0);
         for Ore := Low(FGroundComposition) to High(FGroundComposition) do // $R-
            TotalCompositionMass := TotalCompositionMass + Encyclopedia.Materials[Ore].MassPerUnit * FGroundComposition[Ore];
         TotalTransferMass := 0.0;
         for Miner in DynastyData^.FMiners.Without(nil) do
         begin
            Rate := Miner.GetMinerMaxRate(); // Not the current rate; the difference is handled by us dumping excess back into the ground.
            TotalTransferMass := TotalTransferMass + SyncDuration * Rate;
         end;
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
               Assert(High(DynastyData^.FOrePileComposition[Ore]) - DynastyData^.FOrePileComposition[Ore] >= TransferQuantity);
               ActualTransfer := ActualTransfer + TransferQuantity * Encyclopedia.Materials[Ore].MassPerUnit;
               Inc(DynastyData^.FOrePileComposition[Ore], TransferQuantity);
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
            Ore := TOres(Fraction32.ChooseFrom(@Distribution[Low(TOres)], Length(Distribution), CachedSystem.RandomNumberGenerator) + Low(TOres));
            Quantity := FGroundComposition[Ore];
            Assert(Quantity > 0);
            // TODO: consider truncating and remembering how much is left over for next time
            TransferQuantity := RoundUInt64((TotalTransferMass - ActualTransfer) / Encyclopedia.Materials[Ore].MassPerUnit);
            Dec(FGroundComposition[Ore], TransferQuantity);
            GroundChanged := True;
            ActualTransfer := ActualTransfer + TransferQuantity * Encyclopedia.Materials[Ore].MassPerUnit;
            Inc(DynastyData^.FOrePileComposition[Ore], TransferQuantity);
            OrePilesAffected := True;
         end;
      end;
      if (DynastyData^.FRefineries.IsNotEmpty) then
      begin
         for Ore in TOres do
            RefinedOreMasses[Ore] := 0.0;
         for Refinery in DynastyData^.FRefineries.Without(nil) do
         begin
            Rate := Refinery.GetRefineryCurrentRate();
            Ore := Refinery.GetRefineryOre();
            if (Rate.IsNotZero) then
            begin
               TotalTransferMass := SyncDuration * Rate;
               Assert(TotalTransferMass >= 0);
               RefinedOreMasses[Ore] := RefinedOreMasses[Ore] + TotalTransferMass;
            end;
         end;
         for Ore in TOres do
         begin
            TotalTransferMass := RefinedOreMasses[Ore];
            if (TotalTransferMass > 0.0) then
            begin
               Material := Encyclopedia.Materials[Ore];
               Assert(Material.MassPerUnit > 0);
               Assert(TotalTransferMass * Material.MassPerUnit < High(TransferQuantity));
               // TODO: consider truncating here and keeping track of how much to add next time
               TransferQuantity := RoundUInt64(TotalTransferMass / Material.MassPerUnit);
               if (TransferQuantity > DynastyData^.FOrePileComposition[Ore]) then
               begin
                  TransferQuantity := DynastyData^.FOrePileComposition[Ore];
               end;
               if (TransferQuantity > 0) then
               begin
                  Dec(DynastyData^.FOrePileComposition[Ore], TransferQuantity);
                  OrePilesAffected := True;
                  DynastyData^.IncMaterialPile(Material, TransferQuantity);
                  MaterialPilesAffected := True;
               end;
            end;
         end;
      end;
      if (DynastyData^.FMaterialConsumers.IsNotEmpty) then
      begin
         for Consumer in DynastyData^.FMaterialConsumers.Without(nil) do
         begin
            Rate := Consumer.GetMaterialConsumerCurrentRate();
            Material := Consumer.GetMaterialConsumerMaterial();
            if (Assigned(Material)) then
            begin
               TransferQuantity := CeilUInt64(SyncDuration * Rate); // TODO: use Trunc and keep track of progress
               DesiredTransferQuantity := Consumer.GetMaterialConsumerMaxDelivery();
               if (TransferQuantity > DesiredTransferQuantity) then
                  TransferQuantity := DesiredTransferQuantity;
               if (TransferQuantity > 0) then
               begin
                  ActualTransferQuantity := DynastyData^.ClampedDecMaterialPile(Material, TransferQuantity);
                  MaterialPilesAffected := True;
               end
               else
               begin
                  ActualTransferQuantity := 0;
               end;
               Consumer.DeliverMaterialConsumer(ActualTransferQuantity);
            end;
         end;
      end;

      // Can't use GetTotalOrePileMass() because FNextEvent might not be nil so it
      // might attempt to re-apply the mass flow rate from before the sync.
      CurrentOrePileMass := 0.0;
      if (Length(DynastyData^.FOrePileComposition) > 0) then
         for Ore := Low(DynastyData^.FOrePileComposition) to High(DynastyData^.FOrePileComposition) do // $R-
         begin
            CurrentOrePileMass := CurrentOrePileMass + Encyclopedia.Materials[Ore].MassPerUnit * DynastyData^.FOrePileComposition[Ore];
         end;
      if (CurrentOrePileMass > OrePileCapacity) then
      begin
         TotalTransferMass := CurrentOrePileMass - OrePileCapacity;
         Assert(TotalTransferMass >= 0);
         ActualTransfer := 0.0;
         for Ore in TOres do
         begin
            TransferQuantity := RoundUInt64(DynastyData^.FOrePileComposition[Ore] * TotalTransferMass / CurrentOrePileMass);
            if (TransferQuantity > 0) then
            begin
               Dec(DynastyData^.FOrePileComposition[Ore], TransferQuantity);
               Inc(FGroundComposition[Ore], TransferQuantity);
               OrePilesAffected := True;
               GroundChanged := True;
               ActualTransfer := ActualTransfer + TransferQuantity * Encyclopedia.Materials[Ore].MassPerUnit;
            end;
         end;

         if (ActualTransfer < TotalTransferMass) then
         begin
            Fraction32.InitArray(@Distribution[Low(TOres)], Length(Distribution));
            for Ore in TOres do
            begin
               Distribution[Ore] := Fraction32.FromDouble(DynastyData^.FOrePileComposition[Ore] * Encyclopedia.Materials[Ore].MassPerUnit / CurrentOrePileMass);
            end;
            Fraction32.NormalizeArray(@Distribution[Low(TOres)], Length(Distribution));
            Ore := TOres(Fraction32.ChooseFrom(@Distribution[Low(TOres)], Length(Distribution), CachedSystem.RandomNumberGenerator) + Low(TOres));
            Quantity := DynastyData^.FOrePileComposition[Ore];
            Assert(Quantity > 0);
            TransferQuantity := RoundUInt64((TotalTransferMass - ActualTransfer) / Encyclopedia.Materials[Ore].MassPerUnit);
            Dec(DynastyData^.FOrePileComposition[Ore], TransferQuantity);
            OrePilesAffected := True;
            ActualTransfer := ActualTransfer + TransferQuantity * Encyclopedia.Materials[Ore].MassPerUnit;
            Inc(FGroundComposition[Ore], TransferQuantity);
            GroundChanged := True;
         end;
      end;

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

      {$IFDEF DEBUG}
      if (DynastyData^.FOrePiles.IsNotEmpty) then
      begin
         CurrentOrePileMass := GetTotalOrePileMass(Dynasty);
         Assert(CurrentOrePileMass <= OrePileCapacity, 'now over capacity');
      end;
      {$ENDIF}
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
   end;
   MarkAsDirty([dkNeedsHandleChanges]);
end;

procedure TRegionFeatureNode.HandleScheduledEvent(var Data);
begin
   Assert(Assigned(FNextEvent));
   Assert(FDynamic); // otherwise, why did we schedule an event
   FNextEvent := nil; // important to do this before anything that might raise an exception, otherwise we try to free it on exit
   Sync();
   FActive := False;
   FDynamic := False;
   FAnchorTime := TTimeInMilliseconds.NegInfinity;
   MarkAsDirty([dkNeedsHandleChanges]);
end;

procedure TRegionFeatureNode.Reset();
var
   Miner: IMiner;
   OrePile: IOrePile;
   Refinery: IRefinery;
   MaterialPile: IMaterialPile;
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
      // TODO: factories
      if (DynastyData^.FMaterialConsumers.IsNotEmpty) then
      begin
         for MaterialConsumer in DynastyData^.FMaterialConsumers.Without(nil) do
            MaterialConsumer.DisconnectMaterialConsumer();
         DynastyData^.FMaterialConsumers.Empty();
      end;
   end;
   FActive := False;
   FDynamic := False;
   FAnchorTime := TTimeInMilliseconds.NegInfinity;
end;

procedure TRegionFeatureNode.HandleChanges();

   procedure AllocateOres();
   var
      Message: TAllocateOresBusMessage;
   begin
      Assert(not FAllocatedOres);
      Message := TAllocateOresBusMessage.Create(FFeatureClass.Depth, FFeatureClass.TargetCount, FFeatureClass.TargetQuantity);
      if (InjectBusMessage(Message) = mrHandled) then
         FGroundComposition := Message.AssignedOres;
      FreeAndNil(Message);
      FAllocatedOres := True;
   end;

var
   OrePileCapacity, RemainingOrePileCapacity: Double;
   CurrentGroundMass, CurrentOrePileMass, MinMassTransfer: Double;
   AllDynastyMiningRate, Rate, TotalMinerMaxRate, TotalMiningToRefineryRate, RefiningRate, MaterialConsumptionRate: TRate;
   TimeUntilGroundEmpty, TimeUntilOrePilesFull, TimeUntilAnyOrePileEmpty, TimeUntilThisOrePileEmpty,
   TimeUntilAnyMaterialPileFull, TimeUntilThisMaterialPileFull, TimeUntilAnyMaterialPileEmpty, TimeUntilNextEvent: TMillisecondsDuration;
   Composition: UInt64;
   Ore: TOres;
   Material: TMaterial;
   OreMiningRates, OreRefiningRates: TOreRates;
   MaterialCapacities, MaterialConsumerCounts: TMaterialQuantityHashTable;
   MaterialFactoryRates: TMaterialRateHashTable;
   Ratio: Double;
   Miner: IMiner;
   OrePile: IOrePile;
   Refinery: IRefinery;
   Pile: IMaterialPile;
   MaterialConsumer: IMaterialConsumer;
   MaterialPileFull, OrePileEmpty: Boolean;
   SourceLimiting, TargetLimiting: Boolean;
   Dynasty: TDynasty;
   DynastyData: PPerDynastyData;
begin
   inherited;
   if (not FAllocatedOres) then
      AllocateOres();
   {$IFOPT C+} Assert(not Busy); Busy := True; {$ENDIF}
   if (not FActive) then
   begin
      Assert(not Assigned(FNextEvent));
      Assert(not FDynamic); // so all the "get current mass" etc getters won't be affected by mass flow
      CurrentGroundMass := Mass;
      TimeUntilNextEvent := TMillisecondsDuration.Infinity;
      AllDynastyMiningRate := TRate.Zero;
      for Dynasty in FData.Dynasties do
      begin
         DynastyData := FData[Dynasty];

         DynastyData^.FMiners.RemoveAll(nil);
         DynastyData^.FOrePiles.RemoveAll(nil);
         DynastyData^.FRefineries.RemoveAll(nil);
         DynastyData^.FMaterialPiles.RemoveAll(nil);
         DynastyData^.FMaterialConsumers.RemoveAll(nil);
         CurrentOrePileMass := GetTotalOrePileMass(Dynasty);
         MaterialCapacities := nil;
         MaterialFactoryRates := nil;
         MaterialConsumerCounts := nil;

         // COMPUTE MAX RATES AND CAPACITIES
         // Total mining rate
         TotalMinerMaxRate := TRate.Zero;
         if (DynastyData^.FMiners).IsNotEmpty then
         begin
            for Miner in DynastyData^.FMiners.Without(nil) do
               TotalMinerMaxRate := TotalMinerMaxRate + Miner.GetMinerMaxRate();
            Assert(DynastyData^.FMiners.IsEmpty or TotalMinerMaxRate.IsPositive);
         end;
         // Per-ore mining rates
         for Ore in TOres do
         begin
            if (CurrentGroundMass > 0) then
            begin
               OreMiningRates[Ore] := TotalMinerMaxRate * (FGroundComposition[Ore] * System.Encyclopedia.Materials[Ore].MassPerUnit / CurrentGroundMass);
            end
            else
            begin
               OreMiningRates[Ore] := TRate.Zero;
            end;
            OreRefiningRates[Ore] := TRate.Zero;
         end;
         // Ore pile capacities
         OrePileCapacity := 0.0;
         if (DynastyData^.FOrePiles.IsNotEmpty) then
         begin
            for OrePile in DynastyData^.FOrePiles.Without(nil) do
            begin
               OrePileCapacity := OrePileCapacity + OrePile.GetOrePileCapacity();
               OrePile.RegionAdjustedOrePiles(); // TODO: only notify if the actual rate of flow for that pile changed
            end;
         end;
         {$IFOPT C+}
         for Ore in TOres do
         begin
            Assert(OrePileCapacity / System.Encyclopedia.Materials[Ore].MassPerUnit < Double(High(DynastyData^.FOrePileComposition[Ore])), 'Ore pile capacity exceeds maximum individual max ore quantity for ' + System.Encyclopedia.Materials[Ore].Name);
         end;
         {$ENDIF}
         // Refinery rates
         if (DynastyData^.FRefineries.IsNotEmpty) then
         begin
            for Refinery in DynastyData^.FRefineries.Without(nil) do
            begin
               Ore := Refinery.GetRefineryOre();
               Rate := Refinery.GetRefineryMaxRate();
               OreRefiningRates[Ore] := OreRefiningRates[Ore] + Rate;
            end;
         end;
         for Ore in TOres do
         begin
            if (Assigned(DynastyData^.FMaterialPileComposition)) then
            begin
               Composition := DynastyData^.FMaterialPileComposition[System.Encyclopedia.Materials[Ore]];
            end
            else
            begin
               Composition := 0;
            end;
         end;
         // Material pile capacity
         if (DynastyData^.FMaterialPiles.IsNotEmpty) then
         begin
            MaterialCapacities := TMaterialQuantityHashTable.Create(DynastyData^.FMaterialPiles.Length);
            for Pile in DynastyData^.FMaterialPiles.Without(nil) do
            begin
               MaterialCapacities.Inc(Pile.GetMaterialPileMaterial(), Pile.GetMaterialPileCapacity());
               Pile.RegionAdjustedMaterialPiles(); // TODO: only notify if the actual rate of flow for that pile changed
            end;
         end;

         // Factories
         // TODO: factories
         // if (DynastyData^.FFactories.IsNotEmpty) then
         // begin
         //    MaterialFactoryRates := TMaterialRateHashTable.Create(DynastyData^.FFactories.Length);
         //    ...
         // end;
         // TODO: factories need to affect MaterialFactoryRates

         if (DynastyData^.FMaterialConsumers.IsNotEmpty) then
         begin
            MaterialConsumerCounts := TMaterialQuantityHashTable.Create(DynastyData^.FMaterialConsumers.Length);
            for MaterialConsumer in DynastyData^.FMaterialConsumers.Without(nil) do
            begin
               Material := MaterialConsumer.GetMaterialConsumerMaterial();
               if (Assigned(Material)) then
               begin
                  MaterialConsumerCounts.Inc(Material, 1);
                  Assert((not Assigned(DynastyData^.FMaterialPileComposition)) or (not DynastyData^.FMaterialPileComposition.Has(Material)) or (DynastyData^.FMaterialPileComposition[Material] = 0));
               end;
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
            Material := System.Encyclopedia.Materials[Ore];
            RefiningRate := OreRefiningRates[Ore];
            if (RefiningRate.IsZero) then
            begin
               // TODO: handle factories when relevant material pile is not empty
               if (DynastyData^.FMaterialConsumers.IsNotEmpty) then
               begin
                  for MaterialConsumer in DynastyData^.FMaterialConsumers.Without(nil) do
                  begin
                     if (MaterialConsumer.GetMaterialConsumerMaterial() = Material) then
                     begin
                        // If we have consumers who want this, then by definition there's none of that material in
                        // our piles (because they would have taken that first before calling us).
                        Assert((not Assigned(DynastyData^.FMaterialPileComposition)) or (not DynastyData^.FMaterialPileComposition.Has(Material)) or (DynastyData^.FMaterialPileComposition[Material] = 0));
                        MaterialConsumer.StartMaterialConsumer(TRate.Zero);
                     end;
                  end;
               end;
               continue;
            end;
            MaterialConsumptionRate := TRate.Zero;
            if (Assigned(MaterialConsumerCounts) and MaterialConsumerCounts.Has(Material)) then
            begin
               Assert((not Assigned(DynastyData^.FMaterialPileComposition)) or (not DynastyData^.FMaterialPileComposition.Has(Material)) or (DynastyData^.FMaterialPileComposition[Material] = 0));
               MaterialConsumptionRate := TRate.Infinity;
            end
            else
            if (Assigned(MaterialFactoryRates) and MaterialFactoryRates.Has(Material)) then
            begin
               MaterialConsumptionRate := MaterialFactoryRates[Material];
            end;
            OrePileEmpty := (OreMiningRates[Ore] < RefiningRate) and (DynastyData^.FOrePileComposition[Ore] = 0.0);
            if (Assigned(MaterialCapacities)) then
            begin
               if (Assigned(DynastyData^.FMaterialPileComposition) and DynastyData^.FMaterialPileComposition.Has(Material)) then
               begin
                  Composition := DynastyData^.FMaterialPileComposition[Material];
               end
               else
               begin
                  Composition := 0;
               end;
               MaterialPileFull := (MaterialConsumptionRate < RefiningRate) and (Composition >= MaterialCapacities[Material]);
            end
            else
            begin
               MaterialPileFull := True;
            end;
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
                  Ratio := OreMiningRates[Ore] / RefiningRate;
                  if ((OreMiningRates[Ore].IsPositive) and (RefiningRate > MaterialConsumptionRate)) then
                  begin
                     TimeUntilThisMaterialPileFull := (MaterialCapacities[Material] - GetTotalMaterialPileQuantity(Dynasty, Material)) * Material.MassPerUnit / (RefiningRate * Ratio - MaterialConsumptionRate);
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
                  if (RefiningRate * Ratio > MaterialConsumptionRate) then
                  begin
                     TimeUntilThisMaterialPileFull := (MaterialCapacities[Material] - GetTotalMaterialPileQuantity(Dynasty, Material)) * Material.MassPerUnit / (RefiningRate * Ratio - MaterialConsumptionRate);
                     Assert(TimeUntilThisMaterialPileFull.IsPositive);
                  end
                  else // we're consuming everything immediately
                     TimeUntilThisMaterialPileFull := TMillisecondsDuration.Infinity;
               end;
               if (OreMiningRates[Ore] < RefiningRate * Ratio) then
               begin
                  TimeUntilThisOrePileEmpty := DynastyData^.FOrePileComposition[Ore] * System.Encyclopedia.Materials[Ore].MassPerUnit / (RefiningRate * Ratio - OreMiningRates[Ore]);
                  Assert(TimeUntilThisOrePileEmpty.IsPositive);
               end
               else
                  TimeUntilThisOrePileEmpty := TMillisecondsDuration.Infinity;
            end;
            for Refinery in DynastyData^.FRefineries.Without(nil) do
            begin
               if (Refinery.GetRefineryOre() = Ore) then
               begin
                  Refinery.StartRefinery(Refinery.GetRefineryMaxRate() * Ratio, SourceLimiting, TargetLimiting);
               end;
            end;
            // TODO: Turn on factories that can operate without running out
            // of source materials or storage for output, and turn off those
            // that cannot; adjust MaterialFactoryRates accordingly.
            if (Assigned(MaterialConsumerCounts) and MaterialConsumerCounts.Has(Material)) then
            begin
               Assert(MaterialConsumerCounts[Material] > 0);
               Assert(MaterialConsumptionRate.IsInfinite);
               if (Assigned(MaterialFactoryRates) and MaterialFactoryRates.Has(Material)) then
                  MaterialConsumptionRate := MaterialFactoryRates[Material]
               else
                  MaterialConsumptionRate := TRate.Zero;
               MaterialConsumptionRate := ((RefiningRate / Material.MassPerUnit) * Ratio - MaterialConsumptionRate) / MaterialConsumerCounts[Material];
               Assert(MaterialConsumptionRate.IsZero or MaterialConsumptionRate.IsPositive);
               for MaterialConsumer in DynastyData^.FMaterialConsumers.Without(nil) do
               begin
                  if (MaterialConsumer.GetMaterialConsumerMaterial() = Material) then
                  begin
                     MaterialConsumer.StartMaterialConsumer(MaterialConsumptionRate);
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
         MinMassTransfer := GetMinOreMassTransfer();
         TimeUntilOrePilesFull := TMillisecondsDuration.Infinity;
         if (CurrentGroundMass > 0) then
         begin
            if ((TotalMinerMaxRate.IsPositive) and ((RemainingOrePileCapacity >= MinMassTransfer) or (TotalMinerMaxRate <= TotalMiningToRefineryRate))) then
            begin
               if (TotalMinerMaxRate > TotalMiningToRefineryRate) then
               begin
                  TimeUntilOrePilesFull := RemainingOrePileCapacity / (TotalMinerMaxRate - TotalMiningToRefineryRate);
                  Assert(TimeUntilOrePilesFull.IsPositive);
               end;
               // ready to go, start the miners!
               if (DynastyData^.FMiners.IsNotEmpty) then
               begin
                  for Miner in DynastyData^.FMiners.Without(nil) do
                     Miner.StartMiner(Miner.GetMinerMaxRate(), False, False);
               end;
               FDynamic := True;
            end
            else
            if ((TotalMinerMaxRate.IsPositive) and (TotalMiningToRefineryRate.IsPositive)) then
            begin
               // piles are full, but we are refining, so there is room being made
               Assert(TotalMiningToRefineryRate < TotalMinerMaxRate);
               if (DynastyData^.FMiners.IsNotEmpty) then
               begin
                  for Miner in DynastyData^.FMiners.Without(nil) do
                     Miner.StartMiner(TotalMiningToRefineryRate * (Miner.GetMinerMaxRate() / TotalMinerMaxRate), False, True);
               end;
               TotalMinerMaxRate := TotalMiningToRefineryRate;
               FDynamic := True;
            end
            else
            begin
               // piles are full, stop the miners
               if (DynastyData^.FMiners.IsNotEmpty) then
               begin
                  for Miner in DynastyData^.FMiners.Without(nil) do
                     Miner.StartMiner(TRate.Zero, False, True);
               end;
               TotalMinerMaxRate := TRate.Zero;
            end;
         end
         else
         begin
            // ground is empty, stop the miners
            if (DynastyData^.FMiners.IsNotEmpty) then
            begin
               for Miner in DynastyData^.FMiners.Without(nil) do
                  Miner.StartMiner(TRate.Zero, True, False);
            end;
            TotalMinerMaxRate := TRate.Zero;
         end;
         if (TimeUntilNextEvent > TimeUntilOrePilesFull) then
            TimeUntilNextEvent := TimeUntilOrePilesFull;
         if (TimeUntilNextEvent > TimeUntilAnyOrePileEmpty) then
            TimeUntilNextEvent := TimeUntilAnyOrePileEmpty;
         if (TimeUntilNextEvent > TimeUntilAnyMaterialPileFull) then
            TimeUntilNextEvent := TimeUntilAnyMaterialPileFull;
         if (TimeUntilNextEvent > TimeUntilAnyMaterialPileEmpty) then
            TimeUntilNextEvent := TimeUntilAnyMaterialPileEmpty;
         AllDynastyMiningRate := AllDynastyMiningRate + TotalMinerMaxRate;
         FreeAndNil(MaterialFactoryRates);
         FreeAndNil(MaterialCapacities);
         FreeAndNil(MaterialConsumerCounts);
      end;

      if ((CurrentGroundMass > 0) and (AllDynastyMiningRate.IsNotZero)) then
      begin
         TimeUntilGroundEmpty := CurrentGroundMass / AllDynastyMiningRate;
         Assert(TimeUntilGroundEmpty.IsPositive);
      end
      else
      begin
         Assert(AllDynastyMiningRate.IsZero);
      end;
      if (TimeUntilNextEvent > TimeUntilGroundEmpty) then
         TimeUntilNextEvent := TimeUntilGroundEmpty;

      Assert(TimeUntilNextEvent.IsFinite or FDynamic or FAnchorTime.IsInfinite);
      if (not TimeUntilNextEvent.IsInfinite) then
      begin
         Assert(TimeUntilNextEvent.IsPositive);
         Assert(not Assigned(FNextEvent));
         FNextEvent := System.ScheduleEvent(TimeUntilNextEvent, @HandleScheduledEvent, Self);
         FDynamic := True;
      end;
      FActive := True;

      Assert(FDynamic or FAnchorTime.IsInfinite);
      if (FDynamic) then
      begin
         if (FAnchorTime.IsInfinite) then
            FAnchorTime := System.Now;
      end;
   end;
   Assert(Parent.MassFlowRate.IsNearZero, '  Ended with non-zero mass flow rate: ' + Parent.MassFlowRate.ToString('kg'));
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

// TODO: factories

procedure TRegionFeatureNode.RemoveMaterialConsumer(MaterialConsumer: IMaterialConsumer);
begin
   SyncAndReconsider();
   FData[MaterialConsumer.GetDynasty()]^.FMaterialConsumers.Replace(MaterialConsumer, nil);
end;

procedure TRegionFeatureNode.SyncForMaterialConsumer();
begin
   SyncAndReconsider();
end;

function TRegionFeatureNode.GetOresPresentForPile(Pile: IOrePile): TOreFilter;
var
   Ore: TOres;
begin
   Result.Clear();
   for Ore in TOres do
   begin
      if (FData[Pile.GetDynasty()]^.FOrePileComposition[Ore] > 0) then
         Result.Enable(Ore);
   end;
end;

function TRegionFeatureNode.GetOresForPile(Pile: IOrePile): TOreQuantities;
var
   PileRatio: Double;
   Ore: TOres;
   TotalCapacity: Double;
   Dynasty: TDynasty;
   DynastyData: PPerDynastyData;
begin
   Dynasty := Pile.GetDynasty();
   DynastyData := FData[Dynasty];
   Assert(DynastyData^.FOrePiles.Contains(Pile));
   Sync();
   TotalCapacity := GetTotalOrePileCapacity(Dynasty);
   if (TotalCapacity > 0) then
   begin
      PileRatio := Pile.GetOrePileCapacity() / TotalCapacity;
      Assert(PileRatio > 0.0);
      Assert(PileRatio <= 1.0);
      for Ore in TOres do
         Result[Ore] := RoundUInt64(DynastyData^.FOrePileComposition[Ore] * PileRatio);
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
   Dynasty: TDynasty;
begin
   Dynasty := Pile.GetDynasty();
   Material := Pile.GetMaterialPileMaterial();
   PileRatio := Pile.GetMaterialPileCapacity() / GetTotalMaterialPileCapacity(Dynasty, Material);
   Result := GetTotalMaterialPileMass(Dynasty, Material) * PileRatio;
end;

function TRegionFeatureNode.GetMaterialPileMassFlowRate(Pile: IMaterialPile): TRate; // kg/s
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

function TRegionFeatureNode.GetMaterialPileQuantity(Pile: IMaterialPile): UInt64; // units
var
   Material: TMaterial;
   PileRatio: Double;
   Dynasty: TDynasty;
begin
   Dynasty := Pile.GetDynasty();
   Material := Pile.GetMaterialPileMaterial();
   PileRatio := Pile.GetMaterialPileCapacity() / GetTotalMaterialPileCapacity(Dynasty, Material);
   Result := RoundUInt64(GetTotalMaterialPileQuantity(Dynasty, Material) * PileRatio);
end;

function TRegionFeatureNode.GetMaterialPileQuantityFlowRate(Pile: IMaterialPile): TRate; // units/s
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
      if (FGroundComposition[Ore] > 0) then
      begin
         Journal.WriteMaterialReference(System.Encyclopedia.Materials[Ore]);
         Journal.WriteUInt64(FGroundComposition[Ore]);
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
         if (DynastyData^.FOrePileComposition[Ore] > 0) then
         begin
            Journal.WriteMaterialReference(System.Encyclopedia.Materials[Ore]);
            Journal.WriteUInt64(DynastyData^.FOrePileComposition[Ore]);
         end;
      end;
      Journal.WriteCardinal(0); // last ore
      if (Assigned(DynastyData^.FMaterialPileComposition)) then
      begin
         for Material in DynastyData^.FMaterialPileComposition do
         begin
            Journal.WriteMaterialReference(Material);
            Journal.WriteUInt64(DynastyData^.FMaterialPileComposition[Material]);
         end;
      end;
      Journal.WriteCardinal(0); // last material
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