{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit commonbuses;

interface

uses
   systems, systemdynasty, materials, gossip, time;

type
   TPriority = 0..2147483647;
   TManualPriority = 1..1073741823;
   TAutoPriority = 1073741824..2147483646;

const
   NoPriority = 2147483647; // used by some features to track that they couldn't find a bus, by others as a marker for deleted nodes; should never be exposed (even internally)

type
   TDisabledReason = (
      drManuallyDisabled, // Manually disabled.
      drStructuralIntegrity, // Structural integrity has not yet reached minimum functional threshold.
      drNoBus, // Not usually used with TCheckDisabledBusMessage, but indicates no appropriate bus could be reached (e.g. TRegionFeatureNode for mining/refining, or TBuilderBusFeatureNode for builders).
      drUnderstaffed, // Staffing levels are below required levels for funcionality.
      drUnowned // The asset is not associated with a dynasty.
   );
   TDisabledReasons = set of TDisabledReason;

   TCheckDisabledBusMessage = class(TBusMessage)
   strict private
      FReasons: TDisabledReasons;
      FRateLimit: Double;
      FIdentifier: Pointer;
   public
      constructor Create(AIdentifier: Pointer);
      procedure AddReason(Reason: TDisabledReason; ARateLimit: Double = 0.0);
      property Reasons: TDisabledReasons read FReasons;
      property RateLimit: Double read FRateLimit;
      property Identifier: Pointer read FIdentifier;
   end; // should be injected using Parent.HandleBusMessage

function CheckDisabled(Asset: TAssetNode; out RateLimit: Double; CanOperateWhileUnowned: Boolean = False; Identifier: Pointer = nil): TDisabledReasons;

type
   TFindDestructorsMessage = class(TPhysicalConnectionBusMessage)
   private
      FOwner: TDynasty;
   public
      constructor Create(AOwner: TDynasty);
      property Owner: TDynasty read FOwner;
   end;

   TDismantleMessage = class(TPhysicalConnectionBusMessage)
   private
      FOwner: TDynasty;
      FTarget: TAssetNode;
      FNow: TTimeInMilliseconds;
      FPopulation: Cardinal;
      FGossip: TGossipHashTable;
      FMaterials: TMaterialQuantityHashTable;
      FAssets: TAssetNode.TPlasticArray;
      function GetHasExcess(): Boolean;
      function GetHasExcessMaterials(): Boolean;
   public
      constructor Create(AOwner: TDynasty; ATarget: TAssetNode; ANow: TTimeInMilliseconds);
      destructor Destroy(); override;
      procedure AddExcessPopulation(Quantity: Cardinal; Gossip: TGossipHashTable);
      procedure AddExcessMaterial(Material: TMaterial; Quantity: UInt64);
      procedure AddExcessAsset(Asset: TAssetNode);
      property Owner: TDynasty read FOwner;
      property Target: TAssetNode read FTarget;
      property ExcessPopulation: Cardinal read FPopulation;
   public
      procedure HandleAssetGoingAway(Asset: TAssetNode);
      function ExtractExcessMaterials(): TMaterialQuantityHashTable;
      function ExtractExcessAssets(): TAssetNode.TArray;
      function ExtractGossip(): TGossipHashTable;
      function ExtractPopulation(): Cardinal;
      property HasExcess: Boolean read GetHasExcess;
      property HasExcessMaterials: Boolean read GetHasExcessMaterials;
   end;

   TPhysicalConnectionWithExclusionBusMessage = class abstract(TPhysicalConnectionBusMessage)
   private
      FAsset: TAssetNode;
   public
      constructor Create(AAsset: TAssetNode);
      property Asset: TAssetNode read FAsset; // TAssetNode will not propagate this message into this asset
   end;

   TRehomePopulation = class(TPhysicalConnectionWithExclusionBusMessage)
   private
      FMovingPopulation, FStayingPopulation: Cardinal;
      FSourceGossip: TGossipHashTable;
   public
      constructor Create(AAsset: TAssetNode; AMovingPopulation, AStayingPopulation: Cardinal; ASourceGossip: TGossipHashTable);
      property RemainingPopulation: Cardinal read FMovingPopulation; // population left to move
      procedure Rehome(Amount: Cardinal; TargetGossip: TGossipHashTable; Now: TTimeInMilliseconds);
   end;
   
implementation

uses
   sysutils;

constructor TCheckDisabledBusMessage.Create(AIdentifier: Pointer);
begin
   inherited Create();
   FRateLimit := 1.0;
   FIdentifier := AIdentifier;
end;

procedure TCheckDisabledBusMessage.AddReason(Reason: TDisabledReason; ARateLimit: Double = 0.0);
begin
   Include(FReasons, Reason);
   Assert(ARateLimit >= 0.0);
   Assert(ARateLimit < 1.0);
   if (ARateLimit < FRateLimit) then
   begin
      FRateLimit := ARateLimit;
   end;
end;

function CheckDisabled(Asset: TAssetNode; out RateLimit: Double; CanOperateWhileUnowned: Boolean = False; Identifier: Pointer = nil): TDisabledReasons;
var
   OnOffMessage: TCheckDisabledBusMessage;
begin
   Assert(Assigned(Asset));
   if (Assigned(Asset.Owner) or CanOperateWhileUnowned) then
   begin
      OnOffMessage := TCheckDisabledBusMessage.Create(Identifier);
      try
         Asset.HandleBusMessage(OnOffMessage);
         Result := OnOffMessage.Reasons;
         RateLimit := OnOffMessage.RateLimit;
         Assert((Result <> []) or (RateLimit = 1.0));
      finally
         FreeAndNil(OnOffMessage);
      end;
   end
   else
   begin
      Result := [drUnowned];
      RateLimit := 0.0;
   end;
end;


constructor TFindDestructorsMessage.Create(AOwner: TDynasty);
begin
   inherited Create();
   FOwner := AOwner;
end;


constructor TDismantleMessage.Create(AOwner: TDynasty; ATarget: TAssetNode; ANow: TTimeInMilliseconds);
begin
   inherited Create();
   FOwner := AOwner;
   FTarget := ATarget;
   FNow := ANow;
end;

destructor TDismantleMessage.Destroy();
begin
   // everything should be extracted
   Assert(FAssets.IsEmpty);
   Assert(not Assigned(FMaterials));
   Assert(FPopulation = 0);
   Assert(not FGossip.Allocated);
   // but free things just in case
   FreeAndNil(FMaterials);
   FGossip.Free();
   inherited;
end;

procedure TDismantleMessage.AddExcessMaterial(Material: TMaterial; Quantity: UInt64);
begin
   if (not Assigned(FMaterials)) then
      FMaterials := TMaterialQuantityHashTable.Create();
   FMaterials.Inc(Material, Quantity);
end;

procedure TDismantleMessage.AddExcessPopulation(Quantity: Cardinal; Gossip: TGossipHashTable);
begin
   Inc(FPopulation, Quantity);
   if (Gossip.Allocated) then
   begin
      if (not FGossip.Allocated) then
         FGossip.Allocate();
      FGossip.MoveGossip(Gossip, FGossip, Quantity, Quantity, FNow);
   end;
end;

procedure TDismantleMessage.AddExcessAsset(Asset: TAssetNode);
begin
   FAssets.Push(Asset);
end;

procedure TDismantleMessage.HandleAssetGoingAway(Asset: TAssetNode);
begin
   if (FGossip.Allocated) then
      FGossip.HandleAssetGoingAway(Asset, FPopulation, FNow);
end;

function TDismantleMessage.ExtractExcessMaterials(): TMaterialQuantityHashTable;
begin
   Result := FMaterials;
   FMaterials := nil;
end;

function TDismantleMessage.ExtractExcessAssets(): TAssetNode.TArray;
begin
   Result := FAssets.Distill();
end;

function TDismantleMessage.ExtractGossip(): TGossipHashTable;
begin
   Result := FGossip.Extract();
end;

function TDismantleMessage.ExtractPopulation(): Cardinal;
begin
   Result := FPopulation;
   FPopulation := 0;
end;

function TDismantleMessage.GetHasExcess(): Boolean;
begin
   Result := (Assigned(FMaterials)) or (FPopulation > 0) or (FAssets.IsNotEmpty);
end;

function TDismantleMessage.GetHasExcessMaterials(): Boolean;
begin
   Result := Assigned(FMaterials);
end;


constructor TPhysicalConnectionWithExclusionBusMessage.Create(AAsset: TAssetNode);
begin
   inherited Create;
   FAsset := AAsset;
end;


constructor TRehomePopulation.Create(AAsset: TAssetNode; AMovingPopulation, AStayingPopulation: Cardinal; ASourceGossip: TGossipHashTable);
begin
   inherited Create(AAsset);
   FMovingPopulation := AMovingPopulation;
   FStayingPopulation := AStayingPopulation;
   FSourceGossip := ASourceGossip;
end;

procedure TRehomePopulation.Rehome(Amount: Cardinal; TargetGossip: TGossipHashTable; Now: TTimeInMilliseconds);
begin
   Assert(Amount <= FMovingPopulation);
   if (FSourceGossip.Allocated and TargetGossip.Allocated) then
      TGossipHashTable.MoveGossip(FSourceGossip, TargetGossip, FMovingPopulation + FStayingPopulation, Amount, Now); // $R-
   Dec(FMovingPopulation, Amount);
end;

end.