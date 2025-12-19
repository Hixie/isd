{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit commonbuses;

interface

uses
   systems, systemdynasty, materials, time, hashtable, serverstream;

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

type
   TGossipFlag = (gfUpdateJournal);
   TGossipFlags = set of TGossipFlag;
   {$IF SIZEOF(TGossipFlags) <> SIZEOF(Cardinal)} {$FATAL} {$ENDIF}

   PGossip = ^TGossip;
   TGossip = record
      Message: UTF8String;
      Timestamp: TTimeInMilliseconds;
      Duration: TMillisecondsDuration;
      HappinessImpact: Double; // per person
      PopulationAnchorTime: TTimeInMilliseconds; // time that AffectedPeople was last updated
      SpreadRate: TGrowthRate;
      AffectedPeople: Cardinal;
      Flags: TGossipFlags;
      function ComputeHappinessContribution(TotalPopulation: Cardinal; Now: TTimeInMilliseconds): Double;
      function GetTimeUntilNextEvent(Now: TTimeInMilliseconds): TMillisecondsDuration; inline;
   end;

   TGossipIdentifier = record
   private
      class function Hash32(const Value: TGossipIdentifier): DWord; static; inline;
   public
      Source: TAssetNode; // could be nil, if the asset is out-system
      Kind: Cardinal; // value scoped to the asset class
      // when moving gossip out of a system, gossips with the same Kind but different Sources get merged in some way that minimizes abuse potential
   end;

   TSpreadGossipBusMessage = class(TPhysicalConnectionBusMessage)
   private
      FGossip: TGossip;
      FIdentifier: TGossipIdentifier;
   public
      constructor Create(AGossip: TGossip; AIdentifier: TGossipIdentifier);
      property Gossip: TGossip read FGossip;
      property Identifier: TGossipIdentifier read FIdentifier;
   end;

   TGossipIdentifierUtils = record
      class function Equals(const A, B: TGossipIdentifier): Boolean; static; inline;
      class function LessThan(const A, B: TGossipIdentifier): Boolean; static; inline;
      class function GreaterThan(const A, B: TGossipIdentifier): Boolean; static; inline;
      class function Compare(const A, B: TGossipIdentifier): Int64; static; inline;
   end;

   TGossipHashTable = record
   strict private
      type
         TInternalHashTable = specialize THashTable<TGossipIdentifier, TGossip, TGossipIdentifierUtils>;
      var
         FHashTable: TInternalHashTable;
      function GetItems(const Index: TGossipIdentifier): PGossip; inline;
   public
      procedure Create();
      procedure Free();
      procedure AddGossip(const Source: TGossipIdentifier; const Gossip: TGossip); // Gossip.Timestamp must be Now
      function ComputeHappinessContribution(TotalPopulation: Cardinal; Now: TTimeInMilliseconds): Double;
      function GetTimeUntilNextEvent(Now: TTimeInMilliseconds): TMillisecondsDuration;
      procedure Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter; Now: TTimeInMilliseconds);
      procedure UpdateJournal(Journal: TJournalWriter; Now: TTimeInMilliseconds);
      procedure ApplyJournal(Journal: TJournalReader; ASystem: TSystem);
   end;
   
implementation

uses
   sysutils, hashfunctions, math;

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

function Decay(T: Double): Double;
begin // inverse smoothstep with edges 0 and 1
   Result := 1 - T * T * (3.0 - 2.0 * T);
end;

function TGossip.ComputeHappinessContribution(TotalPopulation: Cardinal; Now: TTimeInMilliseconds): Double;
var
   Age: TMillisecondsDuration;
   ActualImpact: Double;
   SpreadTime: TMillisecondsDuration;
   ActualPeople: Cardinal;
begin
   Age := Now - Timestamp;
   ActualImpact := HappinessImpact * Decay(Age / Duration);
   SpreadTime := Now - PopulationAnchorTime;
   ActualPeople := Min(AffectedPeople * SpreadRate ** SpreadTime, TotalPopulation); // $R-
   Result := ActualImpact * ActualPeople;
end;

function TGossip.GetTimeUntilNextEvent(Now: TTimeInMilliseconds): TMillisecondsDuration;
begin
   Result := Now - Timestamp + Duration;
end;


class function TGossipIdentifier.Hash32(const Value: TGossipIdentifier): DWord;
begin
   Result := PointerHash32(Value.Source) xor Integer32Hash32(Value.Kind);
end;

      
constructor TSpreadGossipBusMessage.Create(AGossip: TGossip; AIdentifier: TGossipIdentifier);
begin
   inherited Create();
   FGossip := AGossip;
   FIdentifier := AIdentifier;
end;


class function TGossipIdentifierUtils.Equals(const A, B: TGossipIdentifier): Boolean;
begin
   Result := (A.Source = B.Source) and (A.Kind = B.Kind);
end;

class function TGossipIdentifierUtils.LessThan(const A, B: TGossipIdentifier): Boolean;
begin
   raise Exception.Create('Gossip identifiers cannot be compared relatively.');
   Result := False;
end;

class function TGossipIdentifierUtils.GreaterThan(const A, B: TGossipIdentifier): Boolean;
begin
   raise Exception.Create('Gossip identifiers cannot be compared relatively.');
   Result := False;
end;

class function TGossipIdentifierUtils.Compare(const A, B: TGossipIdentifier): Int64;
begin
   raise Exception.Create('Gossip identifiers cannot be compared relatively.');
   Result := 0;
end;


procedure TGossipHashTable.Create();
begin
   FHashTable := specialize THashTable<TGossipIdentifier, TGossip, TGossipIdentifierUtils>.Create(@TGossipIdentifier.Hash32);
end;

procedure TGossipHashTable.Free();
begin
   FreeAndNil(FHashTable);
end;

function TGossipHashTable.GetItems(const Index: TGossipIdentifier): PGossip;
begin
   Result := FHashTable.ItemsPtr[Index];
end;

procedure TGossipHashTable.AddGossip(const Source: TGossipIdentifier; const Gossip: TGossip);
var
   NewGossip: PGossip;
begin
   NewGossip := FHashTable.AddDefault(Source);
   NewGossip^.Message := Gossip.Message;
   NewGossip^.Timestamp := Gossip.Timestamp;
   NewGossip^.Duration := Gossip.Duration;
   NewGossip^.HappinessImpact := Gossip.HappinessImpact;
   NewGossip^.PopulationAnchorTime := Gossip.PopulationAnchorTime;
   NewGossip^.SpreadRate := Gossip.SpreadRate;
   NewGossip^.AffectedPeople := Gossip.AffectedPeople;
   NewGossip^.Flags := Gossip.Flags + [gfUpdateJournal];
end;

function TGossipHashTable.ComputeHappinessContribution(TotalPopulation: Cardinal; Now: TTimeInMilliseconds): Double;
var
   Gossip: PGossip;
begin
   Result := 0.0;
   for Gossip in FHashTable.ValuePtrs do
      Result := Result + Gossip^.ComputeHappinessContribution(TotalPopulation, Now);
end;

function TGossipHashTable.GetTimeUntilNextEvent(Now: TTimeInMilliseconds): TMillisecondsDuration;
var
   Gossip: PGossip;
   Candidate: TMillisecondsDuration;
begin
   Result := TMillisecondsDuration.Infinity;
   for Gossip in FHashTable.ValuePtrs do
   begin
      Candidate := Gossip^.GetTimeUntilNextEvent(Now);
      if (Candidate < Result) then
         Result := Candidate;
   end;
end;

procedure TGossipHashTable.Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter; Now: TTimeInMilliseconds);
var
   Gossip: PGossip;
   Identifier: TGossipIdentifier;
begin
   for Identifier in FHashTable do
   begin
      Gossip := FHashTable.ItemsPtr[Identifier];
      Assert(Gossip^.Timestamp <= Now);
      if (Now - Gossip^.Timestamp < Gossip^.Duration) then
      begin
         if (Assigned(Identifier.Source) and Identifier.Source.IsVisibleFor(DynastyIndex)) then
         begin
            Writer.WriteCardinal(Identifier.Source.ID(DynastyIndex));
         end
         else
         begin
            Writer.WriteCardinal(0);
         end;
         Writer.WriteInt64(Gossip^.Timestamp.AsInt64);
         Writer.WriteDouble(Gossip^.HappinessImpact);
         Writer.WriteInt64(Gossip^.Duration.AsInt64);
         Writer.WriteInt64(Gossip^.PopulationAnchorTime.AsInt64);
         Writer.WriteCardinal(Gossip^.AffectedPeople);
         Writer.WriteDouble(Gossip^.SpreadRate.AsDouble);
         Writer.WriteStringReference(Gossip^.Message);
      end;
   end;
end;

const
   EndGossip = $00;
   ActiveGossip = $01;
   ObsoleteGossip = $02;

procedure TGossipHashTable.UpdateJournal(Journal: TJournalWriter; Now: TTimeInMilliseconds);
var
   Gossip: PGossip;
   Identifier: TGossipIdentifier;
   Enumerator: TInternalHashTable.TValuePtrEnumerator;
begin
   try
      Enumerator := FHashTable.ValuePtrs;
      while (Enumerator.MoveNext()) do
      begin
         Gossip := Enumerator.Current;
         if (Now - Gossip^.Timestamp >= Gossip^.Duration) then
         begin
            // mark that we're dropping it
            Journal.WriteByte(ObsoleteGossip);
            Identifier := Enumerator.CurrentKey;
            Journal.WriteAssetNodeReference(Identifier.Source);
            Journal.WriteCardinal(Identifier.Kind);
            Enumerator.RemoveCurrent();
         end
         else
         if (gfUpdateJournal in Gossip^.Flags) then
         begin
            Exclude(Gossip^.Flags, gfUpdateJournal);
            Journal.WriteByte(ActiveGossip);
            Journal.WriteAssetNodeReference(Identifier.Source);
            Journal.WriteCardinal(Identifier.Kind);
            Journal.WriteString(Gossip^.Message);
            Journal.WriteInt64(Gossip^.Timestamp.AsInt64);
            Journal.WriteInt64(Gossip^.Duration.AsInt64);
            Journal.WriteDouble(Gossip^.HappinessImpact);
            Journal.WriteInt64(Gossip^.PopulationAnchorTime.AsInt64);
            Journal.WriteDouble(Gossip^.SpreadRate.AsDouble);
            Journal.WriteCardinal(Gossip^.AffectedPeople);
            Assert(SizeOf(Gossip^.Flags) = SizeOf(Cardinal));
            Journal.WriteCardinal(Cardinal(Gossip^.Flags));
         end;
      end;
   finally
      FreeAndNil(Enumerator);
   end;
   Journal.WriteByte(EndGossip);
end;

procedure TGossipHashTable.ApplyJournal(Journal: TJournalReader; ASystem: TSystem);
var
   Kind: Byte;
   Gossip: PGossip;
   Identifier: TGossipIdentifier;
begin
   repeat
      Kind := Journal.ReadByte();
      case (Kind) of
         ActiveGossip: begin
            Identifier.Source := Journal.ReadAssetNodeReference(ASystem);
            Identifier.Kind := Journal.ReadCardinal();
            Gossip := FHashTable.GetOrAddPtr(Identifier);
            Gossip^.Message := Journal.ReadString();
            Gossip^.Timestamp := TTimeInMilliseconds.FromMilliseconds(Journal.ReadInt64());
            Gossip^.Duration := TMillisecondsDuration.FromMilliseconds(Journal.ReadInt64());
            Gossip^.HappinessImpact := Journal.ReadDouble();
            Gossip^.PopulationAnchorTime := TTimeInMilliseconds.FromMilliseconds(Journal.ReadInt64());
            Gossip^.SpreadRate := TGrowthRate.FromEachMillisecond(Journal.ReadDouble());
            Gossip^.AffectedPeople := Journal.ReadCardinal();
            Assert(SizeOf(Gossip^.Flags) = SizeOf(Cardinal));
            Gossip^.Flags := TGossipFlags(Journal.ReadCardinal());
         end;
         ObsoleteGossip: begin
            Identifier.Source := Journal.ReadAssetNodeReference(ASystem);
            Identifier.Kind := Journal.ReadCardinal();
            FHashTable.Remove(Identifier);
         end;
      end;
   until Kind = EndGossip;
end;

end.