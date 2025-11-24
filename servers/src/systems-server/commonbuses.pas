{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit commonbuses;

interface

uses
   systems, systemdynasty, materials;

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
   public
      procedure AddReason(Reason: TDisabledReason);
      property Reasons: TDisabledReasons read FReasons;
   end; // should be injected using Parent.HandleBusMessage

function CheckDisabled(Asset: TAssetNode; CanOperateWhileUnowned: Boolean = False): TDisabledReasons;

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
      FPopulation: Cardinal;
      FMaterials: TMaterialQuantityHashTable;
      FAssets: TAssetNode.TPlasticArray;
      function GetHasExcess(): Boolean;
      function GetHasExcessMaterials(): Boolean;
   public
      constructor Create(AOwner: TDynasty; ATarget: TAssetNode);
      destructor Destroy(); override;
      procedure AddExcessPopulation(Quantity: Cardinal);
      procedure AddExcessMaterial(Material: TMaterial; Quantity: UInt64);
      procedure AddExcessAsset(Asset: TAssetNode);
      property Owner: TDynasty read FOwner;
      property Target: TAssetNode read FTarget;
      property ExcessPopulation: Cardinal read FPopulation;
      function ExtractExcessMaterials(): TMaterialQuantityHashTable;
      function ExtractExcessAssets(): TAssetNode.TArray;
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
      FPopulation: Cardinal;
   public
      constructor Create(AAsset: TAssetNode; APopulation: Cardinal);
      property RemainingPopulation: Cardinal read FPopulation;
      procedure Rehome(Amount: Cardinal);
   end;
   
implementation

uses
   sysutils;

procedure TCheckDisabledBusMessage.AddReason(Reason: TDisabledReason);
begin
   Include(FReasons, Reason);
end;

function CheckDisabled(Asset: TAssetNode; CanOperateWhileUnowned: Boolean = False): TDisabledReasons;
var
   OnOffMessage: TCheckDisabledBusMessage;
begin
   ASsert(Assigned(Asset));
   if (Assigned(Asset.Owner) or CanOperateWhileUnowned) then
   begin
      OnOffMessage := TCheckDisabledBusMessage.Create();
      try
         Asset.HandleBusMessage(OnOffMessage);
         Result := OnOffMessage.Reasons;
      finally
         FreeAndNil(OnOffMessage);
      end;
   end
   else
   begin
      Result := [drUnowned];
   end;
end;


constructor TFindDestructorsMessage.Create(AOwner: TDynasty);
begin
   inherited Create();
   FOwner := AOwner;
end;


constructor TDismantleMessage.Create(AOwner: TDynasty; ATarget: TAssetNode);
begin
   inherited Create();
   FOwner := AOwner;
   FTarget := ATarget;
end;
      
destructor TDismantleMessage.Destroy();
begin
   FreeAndNil(FMaterials);
   inherited;
end;

procedure TDismantleMessage.AddExcessMaterial(Material: TMaterial; Quantity: UInt64);
begin
   if (not Assigned(FMaterials)) then
      FMaterials := TMaterialQuantityHashTable.Create();
   FMaterials.Inc(Material, Quantity);
end;

procedure TDismantleMessage.AddExcessPopulation(Quantity: Cardinal);
begin
   Inc(FPopulation, Quantity);
end;

procedure TDismantleMessage.AddExcessAsset(Asset: TAssetNode);
begin
   FAssets.Push(Asset);
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


constructor TRehomePopulation.Create(AAsset: TAssetNode; APopulation: Cardinal);
begin
   inherited Create(AAsset);
   FPopulation := APopulation;
end;

procedure TRehomePopulation.Rehome(Amount: Cardinal);
begin
   Assert(Amount <= FPopulation);
   Dec(FPopulation, Amount);
end;

end.