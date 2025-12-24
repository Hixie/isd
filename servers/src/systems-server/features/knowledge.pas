{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit knowledge;

interface

uses
   systems, systemdynasty, serverstream, materials, hashtable,
   genericutils, techtree, plasticarrays;

type
   TKnowledgeBusFeatureNode = class;

   TKnowledgeBusMessage = class abstract(TPhysicalConnectionBusMessage) end;
   TTargetedKnowledgeBusMessage = class abstract(TKnowledgeBusMessage) end;
   TGlobalKnowledgeBusMessage = class abstract(TKnowledgeBusMessage) end;

   TCollectKnownMaterialsMessage = class(TGlobalKnowledgeBusMessage)
   private
      FKnownMaterials: TMaterialHashSet;
      // TODO: add a separate 64 bit field tracking the ores specifically
      FOwner: TDynasty;
      FSystem: TSystem;
   public
      constructor Create(AKnownMaterials: TMaterialHashSet; AOwner: TDynasty; ASystem: TSystem);
      procedure AddKnownMaterial(Material: TMaterial); inline;
      property Owner: TDynasty read FOwner;
      property System: TSystem read FSystem;
   end;

   TCollectKnownAssetClassesMessage = class(TGlobalKnowledgeBusMessage)
   private
      FKnownAssetClasses: TAssetClassHashSet;
      FOwner: TDynasty;
      FSystem: TSystem;
   public
      constructor Create(AKnownAssetClasses: TAssetClassHashSet; AOwner: TDynasty; ASystem: TSystem);
      procedure AddKnownAssetClass(AssetClass: TAssetClass); inline;
      property Owner: TDynasty read FOwner;
      property System: TSystem read FSystem;
   end;

   TCollectKnownResearchesMessage = class(TGlobalKnowledgeBusMessage)
   private
      FKnownResearches: TResearchHashSet;
      FOwner: TDynasty;
      FSystem: TSystem;
   public
      constructor Create(AKnownResearches: TResearchHashSet; AOwner: TDynasty; ASystem: TSystem);
      procedure AddKnownResearch(Research: TResearch); inline;
      property Owner: TDynasty read FOwner;
      property System: TSystem read FSystem;
   end;

   TCallback = procedure of object;

   TKnowledgeSubscription = record
   private
      FBus: TKnowledgeBusFeatureNode;
      FIndex: Cardinal;
      class operator Initialize(var Rec: TKnowledgeSubscription);
      function GetSubscribed(): Boolean; inline;
   public
      procedure Unsubscribe();
      procedure Reset();
      property Subscribed: Boolean read GetSubscribed;
      property Bus: TKnowledgeBusFeatureNode read FBus;
   end;

   TSubscribableKnowledgeBusMessage = class abstract (TTargetedKnowledgeBusMessage)
   strict protected
      FBus: TKnowledgeBusFeatureNode;
   public
      function Subscribe(Callback: TCallback): TKnowledgeSubscription; inline;
      property Bus: TKnowledgeBusFeatureNode read FBus;
   end;

   TGetKnownMaterialsMessage = class(TSubscribableKnowledgeBusMessage)
   private
      FOwner: TDynasty;
      FKnownMaterials: TMaterialHashSet;
      procedure SetKnownMaterials(ABus: TKnowledgeBusFeatureNode; AKnownMaterials: TMaterialHashSet); inline;
   public
      constructor Create(AOwner: TDynasty);
      property Owner: TDynasty read FOwner;
      function Knows(Material: TMaterial): Boolean; inline;
      function GetEnumerator(): TMaterialHashSet.TEnumerator; inline;
   end;

   TGetKnownAssetClassesMessage = class(TSubscribableKnowledgeBusMessage)
   private
      FOwner: TDynasty;
      FKnownAssetClasses: TAssetClassHashSet;
      procedure SetKnownAssetClasses(ABus: TKnowledgeBusFeatureNode; AKnownAssetClasses: TAssetClassHashSet); inline;
   public
      constructor Create(AOwner: TDynasty);
      property Owner: TDynasty read FOwner;
      function Knows(AssetClass: TAssetClass): Boolean; inline;
      function GetEnumerator(): TAssetClassHashSet.TEnumerator; inline;
   end;

   TGetKnownResearchesMessage = class(TSubscribableKnowledgeBusMessage)
   private
      FOwner: TDynasty;
      FKnownResearches: TResearchHashSet;
      procedure SetKnownResearches(ABus: TKnowledgeBusFeatureNode; AKnownResearches: TResearchHashSet); inline;
   public
      constructor Create(AOwner: TDynasty);
      property Owner: TDynasty read FOwner;
      function Knows(Research: TResearch): Boolean; inline;
      function GetEnumerator(): TResearchHashSet.TEnumerator; inline;
   end;

   TKnowledgeBusFeatureClass = class(TFeatureClass)
   strict protected
      function GetFeatureNodeClass(): FeatureNodeReference; override;
   public
      constructor CreateFromTechnologyTree(Reader: TTechTreeReader); override;
      function InitFeatureNode(ASystem: TSystem): TFeatureNode; override;
   end;

   TCachedKnownMaterialsHashMap = specialize THashTable<TDynasty, TMaterialHashSet, TObjectUtils>;
   TCachedKnownAssetClassesHashMap = specialize THashTable<TDynasty, TAssetClassHashSet, TObjectUtils>;
   TCachedKnownResearchesHashMap = specialize THashTable<TDynasty, TResearchHashSet, TObjectUtils>;

   TKnowledgeBusFeatureNode = class(TFeatureNode)
   private
      FKnownMaterials: TCachedKnownMaterialsHashMap;
      FKnownAssetClasses: TCachedKnownAssetClassesHashMap;
      FKnownResearches: TCachedKnownResearchesHashMap;
      FSubscriptions: specialize PlasticArray<TCallback, specialize DefaultUnorderedUtils<TCallback>>;
      procedure FreeCaches();
   protected
      procedure NotifySubscribers();
      procedure ParentMarkedAsDirty(ParentDirtyKinds, NewDirtyKinds: TDirtyKinds); override;
      function ManageBusMessage(Message: TBusMessage): TInjectBusMessageResult; override;
      function HandleBusMessage(Message: TBusMessage): Boolean; override;
      procedure Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter); override;
   public
      destructor Destroy(); override;
      procedure UpdateJournal(Journal: TJournalWriter); override;
      procedure ApplyJournal(Journal: TJournalReader); override;
   end;

   TKnowledgeFeatureClass = class(TFeatureClass)
   strict protected
      function GetFeatureNodeClass(): FeatureNodeReference; override;
   public
      constructor CreateFromTechnologyTree(Reader: TTechTreeReader); override;
      function InitFeatureNode(ASystem: TSystem): TFeatureNode; override;
   end;

   TKnowledgeFeatureNode = class(TFeatureNode)
   private
      FResearch: TResearch;
   protected
      function HandleBusMessage(Message: TBusMessage): Boolean; override;
      procedure Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter); override;
   public
      constructor Create(ASystem: TSystem; AResearch: TResearch);
      procedure SetKnowledge(AResearch: TResearch);
      procedure UpdateJournal(Journal: TJournalWriter); override;
      procedure ApplyJournal(Journal: TJournalReader); override;
      procedure DescribeExistentiality(var IsDefinitelyReal, IsDefinitelyGhost: Boolean); override;
   end;

implementation

uses
   sysutils, isdprotocol, typedump;

constructor TCollectKnownMaterialsMessage.Create(AKnownMaterials: TMaterialHashSet; AOwner: TDynasty; ASystem: TSystem);
begin
   inherited Create();
   FKnownMaterials := AKnownMaterials;
   FOwner := AOwner;
   FSystem := ASystem;
end;

procedure TCollectKnownMaterialsMessage.AddKnownMaterial(Material: TMaterial);
begin
   FKnownMaterials.Add(Material);
end;


constructor TCollectKnownAssetClassesMessage.Create(AKnownAssetClasses: TAssetClassHashSet; AOwner: TDynasty; ASystem: TSystem);
begin
   inherited Create();
   FKnownAssetClasses := AKnownAssetClasses;
   FOwner := AOwner;
   FSystem := ASystem;
end;

procedure TCollectKnownAssetClassesMessage.AddKnownAssetClass(AssetClass: TAssetClass);
begin
   if (not FKnownAssetClasses.Has(AssetClass)) then
      FKnownAssetClasses.Add(AssetClass);
end;


constructor TCollectKnownResearchesMessage.Create(AKnownResearches: TResearchHashSet; AOwner: TDynasty; ASystem: TSystem);
begin
   inherited Create();
   FKnownResearches := AKnownResearches;
   FOwner := AOwner;
   FSystem := ASystem;
   Assert(FKnownResearches.IsEmpty);
   FKnownResearches.Add(FSystem.Encyclopedia.Researches[0]);
end;

procedure TCollectKnownResearchesMessage.AddKnownResearch(Research: TResearch);
begin
   if (not FKnownResearches.Has(Research)) then
      FKnownResearches.Add(Research);
end;


function TKnowledgeSubscription.GetSubscribed(): Boolean;
begin
   Result := Assigned(FBus);
end;

procedure TKnowledgeSubscription.Unsubscribe();
begin
   Assert(Subscribed);
   FBus.FSubscriptions[FIndex] := nil;
end;

procedure TKnowledgeSubscription.Reset();
begin
   FBus := nil;
end;

class operator TKnowledgeSubscription.Initialize(var Rec: TKnowledgeSubscription);
begin
   Rec.Reset();
end;


function TSubscribableKnowledgeBusMessage.Subscribe(Callback: TCallback): TKnowledgeSubscription;
begin
   Assert(Assigned(FBus), 'Never set the bus on ' + ClassName);
   Result.FBus := FBus;
   Result.FIndex := FBus.FSubscriptions.Length;
   FBus.FSubscriptions.Push(Callback);
end;


constructor TGetKnownMaterialsMessage.Create(AOwner: TDynasty);
begin
   inherited Create();
   FOwner := AOwner;
end;

procedure TGetKnownMaterialsMessage.SetKnownMaterials(ABus: TKnowledgeBusFeatureNode; AKnownMaterials: TMaterialHashSet);
begin
   FBus := ABus;
   FKnownMaterials := AKnownMaterials;
end;

function TGetKnownMaterialsMessage.Knows(Material: TMaterial): Boolean;
begin
   Result := Assigned(FKnownMaterials) and FKnownMaterials.Has(Material);
end;

function TGetKnownMaterialsMessage.GetEnumerator(): TMaterialHashSet.TEnumerator;
begin
   if (Assigned(FKnownMaterials)) then
   begin
      Result := FKnownMaterials.GetEnumerator();
   end
   else
   begin
      Result := nil;
   end;
end;


constructor TGetKnownAssetClassesMessage.Create(AOwner: TDynasty);
begin
   inherited Create();
   FOwner := AOwner;
end;

procedure TGetKnownAssetClassesMessage.SetKnownAssetClasses(ABus: TKnowledgeBusFeatureNode; AKnownAssetClasses: TAssetClassHashSet);
begin
   FBus := ABus;
   FKnownAssetClasses := AKnownAssetClasses;
end;

function TGetKnownAssetClassesMessage.Knows(AssetClass: TAssetClass): Boolean;
begin
   Result := Assigned(FKnownAssetClasses) and FKnownAssetClasses.Has(AssetClass);
end;

function TGetKnownAssetClassesMessage.GetEnumerator(): TAssetClassHashSet.TEnumerator;
begin
   if (Assigned(FKnownAssetClasses)) then
   begin
      Result := FKnownAssetClasses.GetEnumerator();
   end
   else
   begin
      Result := nil;
   end;
end;


constructor TGetKnownResearchesMessage.Create(AOwner: TDynasty);
begin
   inherited Create();
   FOwner := AOwner;
end;

procedure TGetKnownResearchesMessage.SetKnownResearches(ABus: TKnowledgeBusFeatureNode; AKnownResearches: TResearchHashSet);
begin
   FBus := ABus;
   FKnownResearches := AKnownResearches;
end;

function TGetKnownResearchesMessage.Knows(Research: TResearch): Boolean;
begin
   Result := Assigned(FKnownResearches) and FKnownResearches.Has(Research);
end;

function TGetKnownResearchesMessage.GetEnumerator(): TResearchHashSet.TEnumerator;
begin
   if (Assigned(FKnownResearches)) then
   begin
      Result := FKnownResearches.GetEnumerator();
   end
   else
   begin
      Result := nil;
   end;
end;



constructor TKnowledgeBusFeatureClass.CreateFromTechnologyTree(Reader: TTechTreeReader);
begin
   inherited Create();
end;

function TKnowledgeBusFeatureClass.GetFeatureNodeClass(): FeatureNodeReference;
begin
   Result := TKnowledgeBusFeatureNode;
end;

function TKnowledgeBusFeatureClass.InitFeatureNode(ASystem: TSystem): TFeatureNode;
begin
   Result := TKnowledgeBusFeatureNode.Create(ASystem);
end;

procedure TKnowledgeBusFeatureNode.FreeCaches();
var
   Materials: TMaterialHashSet;
   AssetClasses: TAssetClassHashSet;
   Researches: TResearchHashSet;
begin
   if (Assigned(FKnownMaterials)) then
   begin
      for Materials in FKnownMaterials.Values do
         Materials.Free();
      FreeAndNil(FKnownMaterials);
   end;
   if (Assigned(FKnownAssetClasses)) then
   begin
      for AssetClasses in FKnownAssetClasses.Values do
         AssetClasses.Free();
      FreeAndNil(FKnownAssetClasses);
   end;
   if (Assigned(FKnownResearches)) then
   begin
      for Researches in FKnownResearches.Values do
         Researches.Free();
      FreeAndNil(FKnownResearches);
   end;
end;

destructor TKnowledgeBusFeatureNode.Destroy();
begin
   FreeCaches();
   NotifySubscribers();
   inherited;
end;

procedure TKnowledgeBusFeatureNode.NotifySubscribers();
var
   Callback: TCallback;
   Subscriptions: array of TCallback;
begin
   Subscriptions := FSubscriptions.Distill();
   if (Length(Subscriptions) > 0) then
      FSubscriptions.Prepare(Length(Subscriptions)); // $R-
   for Callback in Subscriptions do
      if (Assigned(Callback)) then
         Callback();
   Assert(FSubscriptions.IsEmpty, 'someone tried to subscribe from a notification');
end;

procedure TKnowledgeBusFeatureNode.ParentMarkedAsDirty(ParentDirtyKinds, NewDirtyKinds: TDirtyKinds);
begin
   if (dkAffectsKnowledge in NewDirtyKinds) then
   begin
      FreeCaches();
      NotifySubscribers();
   end;
   inherited;
end;

function TKnowledgeBusFeatureNode.ManageBusMessage(Message: TBusMessage): TInjectBusMessageResult;
begin
   if (Message is TKnowledgeBusMessage) then
   begin
      Result := DeferOrHandleBusMessage(Message);
      Assert((not (Message is TTargetedKnowledgeBusMessage)) or (Result = irHandled));
      Assert((not (Message is TGlobalKnowledgeBusMessage)) or (Result = irInjected));
   end
   else
      Result := inherited;
end;

function TKnowledgeBusFeatureNode.HandleBusMessage(Message: TBusMessage): Boolean;
var
   KnownMaterialsForDynasty: TMaterialHashSet;
   KnownAssetClassesForDynasty: TAssetClassHashSet;
   KnownResearchesForDynasty: TResearchHashSet;
   CollectMaterialsMessage: TCollectKnownMaterialsMessage;
   CollectAssetClassesMessage: TCollectKnownAssetClassesMessage;
   CollectResearchesMessage: TCollectKnownResearchesMessage;
   Injected: TInjectBusMessageResult;
   Dynasty: TDynasty;
begin
   if (Message is TGetKnownMaterialsMessage) then
   begin
      Dynasty := (Message as TGetKnownMaterialsMessage).Owner;
      if (not Assigned(FKnownMaterials)) then
      begin
         FKnownMaterials := TCachedKnownMaterialsHashMap.Create(@DynastyHash32);
      end;
      if (not FKnownMaterials.Has(Dynasty)) then
      begin
         KnownMaterialsForDynasty := TMaterialHashSet.Create();
         CollectMaterialsMessage := TCollectKnownMaterialsMessage.Create(KnownMaterialsForDynasty, Dynasty, System);
         Injected := InjectBusMessage(CollectMaterialsMessage);
         Assert(Injected = irInjected); // we are a bus for this message!
         FKnownMaterials[Dynasty] := KnownMaterialsForDynasty;
         FreeAndNil(CollectMaterialsMessage);
      end;
      (Message as TGetKnownMaterialsMessage).SetKnownMaterials(Self, FKnownMaterials[Dynasty]);
      Result := True;
   end
   else
   if (Message is TGetKnownAssetClassesMessage) then
   begin
      Dynasty := (Message as TGetKnownAssetClassesMessage).Owner;
      if (not Assigned(FKnownAssetClasses)) then
      begin
         FKnownAssetClasses := TCachedKnownAssetClassesHashMap.Create(@DynastyHash32);
      end;
      if (not FKnownAssetClasses.Has(Dynasty)) then
      begin
         KnownAssetClassesForDynasty := TAssetClassHashSet.Create();
         CollectAssetClassesMessage := TCollectKnownAssetClassesMessage.Create(KnownAssetClassesForDynasty, Dynasty, System);
         Injected := InjectBusMessage(CollectAssetClassesMessage);
         Assert(Injected = irInjected); // we are a bus for this message!
         FKnownAssetClasses[Dynasty] := KnownAssetClassesForDynasty;
         FreeAndNil(CollectAssetClassesMessage);
      end;
      (Message as TGetKnownAssetClassesMessage).SetKnownAssetClasses(Self, FKnownAssetClasses[Dynasty]);
      Result := True;
   end
   else
   if (Message is TGetKnownResearchesMessage) then
   begin
      Dynasty := (Message as TGetKnownResearchesMessage).Owner;
      if (not Assigned(FKnownResearches)) then
      begin
         FKnownResearches := TCachedKnownResearchesHashMap.Create(@DynastyHash32);
      end;
      if (not FKnownResearches.Has(Dynasty)) then
      begin
         KnownResearchesForDynasty := TResearchHashSet.Create();
         CollectResearchesMessage := TCollectKnownResearchesMessage.Create(KnownResearchesForDynasty, Dynasty, System);
         Injected := InjectBusMessage(CollectResearchesMessage);
         Assert(Injected = irInjected); // we are a bus for this message!
         FKnownResearches[Dynasty] := KnownResearchesForDynasty;
         FreeAndNil(CollectResearchesMessage);
      end;
      (Message as TGetKnownResearchesMessage).SetKnownResearches(Self, FKnownResearches[Dynasty]);
      Result := True;
   end
   else
      Result := False;
end;

procedure TKnowledgeBusFeatureNode.Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter);
begin
end;

procedure TKnowledgeBusFeatureNode.UpdateJournal(Journal: TJournalWriter);
begin
end;

procedure TKnowledgeBusFeatureNode.ApplyJournal(Journal: TJournalReader);
begin
end;


constructor TKnowledgeFeatureClass.CreateFromTechnologyTree(Reader: TTechTreeReader);
begin
   inherited Create();
end;

function TKnowledgeFeatureClass.GetFeatureNodeClass(): FeatureNodeReference;
begin
   Result := TKnowledgeFeatureNode;
end;

function TKnowledgeFeatureClass.InitFeatureNode(ASystem: TSystem): TFeatureNode;
begin
   Result := TKnowledgeFeatureNode.Create(ASystem, nil);
end;


constructor TKnowledgeFeatureNode.Create(ASystem: TSystem; AResearch: TResearch);
begin
   inherited Create(ASystem);
   FResearch := AResearch;
end;

procedure TKnowledgeFeatureNode.SetKnowledge(AResearch: TResearch);
begin
   FResearch := AResearch;
   MarkAsDirty([dkUpdateClients, dkUpdateJournal, dkAffectsKnowledge]);
end;

function TKnowledgeFeatureNode.HandleBusMessage(Message: TBusMessage): Boolean;

   function CanSeeKnowledge(Target: TDynasty): Boolean;
   var
      Visibility: TVisibility;
   begin
      if (not Assigned(FResearch)) then
      begin
         Result := False;
         exit;
      end;
      Visibility := Parent.ReadVisibilityFor(System.DynastyIndex[Target]);
      Result := dmInternals in Visibility;
   end;

var
   Reward: TReward;
begin
   if (Message is TCollectKnownMaterialsMessage) then
   begin
      if (CanSeeKnowledge((Message as TCollectKnownMaterialsMessage).Owner)) then
      begin
         for Reward in FResearch.Rewards do
         begin
            if (Reward.Kind = rkMaterial) then
               (Message as TCollectKnownMaterialsMessage).AddKnownMaterial(Reward.Material);
         end;
      end;
   end
   else
   if (Message is TCollectKnownAssetClassesMessage) then
   begin
      if (CanSeeKnowledge((Message as TCollectKnownAssetClassesMessage).Owner)) then
      begin
         for Reward in FResearch.Rewards do
         begin
            if (Reward.Kind = rkAssetClass) then
               (Message as TCollectKnownAssetClassesMessage).AddKnownAssetClass(Reward.AssetClass);
         end;
      end;
   end
   else
   if (Message is TCollectKnownResearchesMessage) then
   begin
      if (CanSeeKnowledge((Message as TCollectKnownResearchesMessage).Owner)) then
      begin
         (Message as TCollectKnownResearchesMessage).AddKnownResearch(FResearch);
      end;
   end;
   Result := False;
end;

procedure TKnowledgeFeatureNode.Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter);
var
   Visibility: TVisibility;
   Reward: TReward;
   Material: TMaterial;
   Flags: UInt64;
begin
   Visibility := Parent.ReadVisibilityFor(DynastyIndex);
   if ((dmDetectable * Visibility <> []) and (dmClassKnown in Visibility)) then
   begin
      Writer.WriteCardinal(fcKnowledge);
      if (Assigned(FResearch) and (dmInternals in Visibility)) then
      begin
         for Reward in FResearch.Rewards do
         begin
            case Reward.Kind of
               rkAssetClass:
                  begin
                     Writer.WriteByte($01);
                     Reward.AssetClass.Serialize(Writer);
                  end;
               rkMaterial:
                  begin
                     Writer.WriteByte($02);
                     Material := Reward.Material;
                     Writer.WriteInt32(Material.ID);
                     Writer.WriteStringReference(Material.Icon);
                     Writer.WriteStringReference(Material.Name);
                     Writer.WriteStringReference(Material.Description);
                     Flags := $00;
                     case Material.UnitKind of
                        ukBulkResource: ;
                        ukComponent: Flags := Flags or $02;
                     end;
                     if (mtFluid in Material.Tags) then
                        Flags := Flags or $01;
                     if (mtPressurized in Material.Tags) then
                        Flags := Flags or $10;
                     Writer.WriteUInt64(Flags);
                     Writer.WriteDouble(Material.MassPerUnit);
                     Writer.WriteDouble(Material.Density);
                  end;
               rkMessage: ;
            end;
         end;
      end;
      Writer.WriteByte($00);
   end;
end;

procedure TKnowledgeFeatureNode.UpdateJournal(Journal: TJournalWriter);
begin
   if (Assigned(FResearch)) then
   begin
      Journal.WriteInt32(FResearch.ID);
   end
   else
   begin
      Journal.WriteInt32(TResearch.kNil);
   end;
end;

procedure TKnowledgeFeatureNode.ApplyJournal(Journal: TJournalReader);
var
   ID: TResearchID;
begin
   ID := Journal.ReadInt32();
   if (ID <> TResearch.kNil) then
   begin
      Assert(ID >= Low(TResearchID));
      Assert(ID <= High(TResearchID));
      FResearch := System.Encyclopedia.Researches[ID]; // $R-
   end;
end;

procedure TKnowledgeFeatureNode.DescribeExistentiality(var IsDefinitelyReal, IsDefinitelyGhost: Boolean);
begin
   IsDefinitelyReal := True;
end;

initialization
   RegisterFeatureClass(TKnowledgeBusFeatureClass);
   RegisterFeatureClass(TKnowledgeFeatureClass);
end.