{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit knowledge;

interface

uses
   systems, internals, systemdynasty, serverstream, materials, hashtable,
   genericutils, plasticarrays;

type
   TKnowledgeBusFeatureNode = class;

   TKnowledgeBusMessage = class abstract(TPhysicalConnectionBusMessage) end;
   TTargetedKnowledgeBusMessage = class abstract(TKnowledgeBusMessage) end;
   TGlobalKnowledgeBusMessage = class abstract(TKnowledgeBusMessage) end;

   TCollectKnownResearchesMessage = class(TGlobalKnowledgeBusMessage)
   private
      FKnownResearches: PResearchHashSet;
      FOwner: TDynasty;
      FSystem: TSystem;
   public
      constructor Create(AKnownResearches: PResearchHashSet; AOwner: TDynasty; ASystem: TSystem);
      procedure AddKnownResearch(Research: TResearch); inline;
      property Owner: TDynasty read FOwner;
      property System: TSystem read FSystem;
   end;

   TCallback = procedure of object;

   TKnowledgeSubscription = record
   strict private
      class operator Initialize(var Rec: TKnowledgeSubscription);
      function GetSubscribed(): Boolean; inline;
   private
      FBus: TKnowledgeBusFeatureNode;
      FIndex: Cardinal;
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
   strict private
      FOwner: TDynasty;
      FKnownMaterials: TMaterialHashSet;
   private
      procedure SetKnownMaterials(ABus: TKnowledgeBusFeatureNode; AKnownMaterials: TMaterialHashSet); inline;
   public
      constructor Create(AOwner: TDynasty);
      property Owner: TDynasty read FOwner;
      function Knows(Material: TMaterial): Boolean; inline;
      function GetEnumerator(): TMaterialHashSet.TEnumerator; inline;
   end;

   TGetKnownAssetClassesMessage = class(TSubscribableKnowledgeBusMessage)
   strict private
      FOwner: TDynasty;
      FKnownAssetClasses: TAssetClassHashSet;
   private
      procedure SetKnownAssetClasses(ABus: TKnowledgeBusFeatureNode; AKnownAssetClasses: TAssetClassHashSet); inline;
   public
      constructor Create(AOwner: TDynasty);
      property Owner: TDynasty read FOwner;
      function Knows(AssetClass: TAssetClass): Boolean; inline;
      function GetEnumerator(): TAssetClassHashSet.TEnumerator; inline;
   end;

   TGetKnownResearchesMessage = class(TSubscribableKnowledgeBusMessage)
   strict private
      FOwner: TDynasty;
      FKnownResearches: PResearchHashSet;
   private
      procedure SetKnownResearches(ABus: TKnowledgeBusFeatureNode; AKnownResearches: PResearchHashSet); inline;
   public
      constructor Create(AOwner: TDynasty);
      property Owner: TDynasty read FOwner;
      function Knows(Research: TResearch): Boolean; inline;
      function GetEnumerator(): TResearchHashSet.TEnumerator; inline;
      procedure CopyTo(var Target: TResearchHashSet);
   end;

   // TODO: mechanism for active situations to be reported to the entire bus

   TKnowledgeBusFeatureClass = class(TFeatureClass)
   strict protected
      function GetFeatureNodeClass(): FeatureNodeReference; override;
   public
      constructor CreateFromTechnologyTree(const Reader: TTechTreeReader); override;
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
      function HandleBusMessage(Message: TBusMessage): THandleBusMessageResult; override;
      procedure Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter); override;
   public
      destructor Destroy(); override;
      procedure UpdateJournal(Journal: TJournalWriter); override;
      procedure ApplyJournal(Journal: TJournalReader); override;
   end;

   TKnowledgeFeatureClass = class(TFeatureClass)
   strict protected
      FResearchID: TResearchID;
      function GetFeatureNodeClass(): FeatureNodeReference; override;
   public
      constructor CreateFromTechnologyTree(const Reader: TTechTreeReader); override;
      function InitFeatureNode(ASystem: TSystem): TFeatureNode; override;
   end;

   TKnowledgeFeatureNode = class(TFeatureNode)
   private
      FResearch: TResearch;
   protected
      function HandleBusMessage(Message: TBusMessage): THandleBusMessageResult; override;
      procedure Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter); override;
   public
      constructor Create(ASystem: TSystem; AResearch: TResearch);
      procedure SetKnowledge(AResearch: TResearch);
      procedure Attaching(); override;
      procedure Detaching(); override;
      procedure UpdateJournal(Journal: TJournalWriter); override;
      procedure ApplyJournal(Journal: TJournalReader); override;
      procedure DescribeExistentiality(var IsDefinitelyReal, IsDefinitelyGhost: Boolean); override;
   end;

implementation

uses
   sysutils, isdprotocol, typedump, ttparser;

constructor TCollectKnownResearchesMessage.Create(AKnownResearches: PResearchHashSet; AOwner: TDynasty; ASystem: TSystem);
begin
   inherited Create();
   Assert(Assigned(AKnownResearches));
   FKnownResearches := AKnownResearches;
   FOwner := AOwner;
   FSystem := ASystem;
   Assert(FKnownResearches^.IsEmpty);
   FKnownResearches^.Add(0);
end;

procedure TCollectKnownResearchesMessage.AddKnownResearch(Research: TResearch);
begin
   if (not FKnownResearches^.Has(Research.Index)) then
      FKnownResearches^.Add(Research.Index);
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

procedure TGetKnownResearchesMessage.SetKnownResearches(ABus: TKnowledgeBusFeatureNode; AKnownResearches: PResearchHashSet);
begin
   FBus := ABus;
   FKnownResearches := AKnownResearches;
end;

function TGetKnownResearchesMessage.Knows(Research: TResearch): Boolean;
begin
   Result := FKnownResearches^.Has(Research.Index);
end;

function TGetKnownResearchesMessage.GetEnumerator(): TResearchHashSet.TEnumerator;
begin
   Result := FKnownResearches^.GetEnumerator();
end;

procedure TGetKnownResearchesMessage.CopyTo(var Target: TResearchHashSet);
begin
   FKnownResearches^.CloneTo(Target);
end;


constructor TKnowledgeBusFeatureClass.CreateFromTechnologyTree(const Reader: TTechTreeReader);
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
   FreeAndNil(FKnownResearches);
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

function TKnowledgeBusFeatureNode.HandleBusMessage(Message: TBusMessage): THandleBusMessageResult;

   procedure PrimeKnownResearches(Dynasty: TDynasty);
   var
      CollectResearchesMessage: TCollectKnownResearchesMessage;
      Injected: TInjectBusMessageResult;
   begin
      if (not Assigned(FKnownResearches)) then
      begin
         FKnownResearches := TCachedKnownResearchesHashMap.Create(@DynastyHash32);
      end;
      if (not FKnownResearches.Has(Dynasty)) then
      begin
         FKnownResearches.AddDefault(Dynasty);
         CollectResearchesMessage := TCollectKnownResearchesMessage.Create(FKnownResearches.ItemsPtr[Dynasty], Dynasty, System);
         Injected := InjectBusMessage(CollectResearchesMessage);
         Assert(Injected = irInjected); // we are a bus for this message!
         FreeAndNil(CollectResearchesMessage);
      end;
   end;

var
   KnownMaterialsForDynasty: TMaterialHashSet;
   KnownAssetClassesForDynasty: TAssetClassHashSet;
   ResearchIndex: TResearchIndex;
   Research: TResearch;
   Dynasty: TDynasty;
   Unlock: TUnlockedKnowledge;
begin
   // TODO: support a message for getting active situations
   if (Message is TGetKnownMaterialsMessage) then
   begin
      Dynasty := (Message as TGetKnownMaterialsMessage).Owner;
      PrimeKnownResearches(Dynasty);
      if (not Assigned(FKnownMaterials)) then
      begin
         FKnownMaterials := TCachedKnownMaterialsHashMap.Create(@DynastyHash32);
      end;
      if (not FKnownMaterials.Has(Dynasty)) then
      begin
         KnownMaterialsForDynasty := TMaterialHashSet.Create();
         for ResearchIndex in FKnownResearches.ItemsPtr[Dynasty]^ do
         begin
            Research := System.Encyclopedia.ResearchesByIndex[ResearchIndex];
            for Unlock in Research.UnlockedKnowledge do
            begin
               if (Unlock.Kind = ukMaterial) then
               begin
                  if (not KnownMaterialsForDynasty.Has(Unlock.Material)) then
                     KnownMaterialsForDynasty.Add(Unlock.Material);
               end;
            end;
         end;
         FKnownMaterials[Dynasty] := KnownMaterialsForDynasty;
      end;
      (Message as TGetKnownMaterialsMessage).SetKnownMaterials(Self, FKnownMaterials[Dynasty]);
      Result := hrHandled;
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
         for ResearchIndex in FKnownResearches.ItemsPtr[Dynasty]^ do
         begin
            Research := System.Encyclopedia.ResearchesByIndex[ResearchIndex];
            for Unlock in Research.UnlockedKnowledge do
            begin
               if (Unlock.Kind = ukAssetClass) then
               begin
                  if (not KnownAssetClassesForDynasty.Has(Unlock.AssetClass)) then
                     KnownAssetClassesForDynasty.Add(Unlock.AssetClass);
               end;
            end;
         end;
         FKnownAssetClasses[Dynasty] := KnownAssetClassesForDynasty;
      end;
      (Message as TGetKnownAssetClassesMessage).SetKnownAssetClasses(Self, FKnownAssetClasses[Dynasty]);
      Result := hrHandled;
   end
   else
   if (Message is TGetKnownResearchesMessage) then
   begin
      Dynasty := (Message as TGetKnownResearchesMessage).Owner;
      PrimeKnownResearches(Dynasty);
      (Message as TGetKnownResearchesMessage).SetKnownResearches(Self, FKnownResearches.ItemsPtr[Dynasty]);
      Result := hrHandled;
   end
   else
      Result := inherited;
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


constructor TKnowledgeFeatureClass.CreateFromTechnologyTree(const Reader: TTechTreeReader);
begin
   inherited Create();
   if (Reader.Tokens.IsIdentifier()) then
   begin
      Reader.Tokens.ReadIdentifier('research');
      Reader.Tokens.ReadIdentifier('id');
      FResearchID := ReadNumber(Reader.Tokens, Low(FResearchID), High(FResearchID)); // $R-
      if (FResearchID = 0) then
         Reader.Tokens.Error('Cannot create a knowledge feature that represents the root research.', []);
   end;
end;

function TKnowledgeFeatureClass.GetFeatureNodeClass(): FeatureNodeReference;
begin
   Result := TKnowledgeFeatureNode;
end;

function TKnowledgeFeatureClass.InitFeatureNode(ASystem: TSystem): TFeatureNode;
var
   Research: TResearch;
begin
   if (FResearchID <> 0) then
      Research := ASystem.Encyclopedia.ResearchesByID[FResearchID]
   else
      Research := nil;
   Result := TKnowledgeFeatureNode.Create(ASystem, Research);
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

procedure TKnowledgeFeatureNode.Attaching();
begin
   MarkAsDirty([dkAffectsKnowledge]);
end;

procedure TKnowledgeFeatureNode.Detaching();
begin
   MarkAsDirty([dkAffectsKnowledge]);
end;

function TKnowledgeFeatureNode.HandleBusMessage(Message: TBusMessage): THandleBusMessageResult;

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

begin
   if (Message is TCollectKnownResearchesMessage) then
   begin
      if (CanSeeKnowledge((Message as TCollectKnownResearchesMessage).Owner)) then
      begin
         (Message as TCollectKnownResearchesMessage).AddKnownResearch(FResearch);
      end;
   end;
   Result := inherited;
end;

procedure TKnowledgeFeatureNode.Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter);

   procedure SendMaterial(Material: TMaterial);
   var
      Flags: UInt64;
   begin
      Writer.WriteByte($02);
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
      Writer.WriteDouble(Material.MassPerUnit.AsDouble);
      Writer.WriteDouble(Material.Density);
   end;

var
   Visibility: TVisibility;
   Unlock: TUnlockedKnowledge;
   Material: TMaterial;
begin
   Visibility := Parent.ReadVisibilityFor(DynastyIndex);
   if ((dmDetectable * Visibility <> []) and (dmClassKnown in Visibility)) then
   begin
      Writer.WriteCardinal(fcKnowledge);
      if (Assigned(FResearch) and (dmInternals in Visibility)) then
      begin
         for Unlock in FResearch.UnlockedKnowledge do
         begin
            case Unlock.Kind of
               ukAssetClass:
                  begin
                     Writer.WriteByte($01);
                     Unlock.AssetClass.Serialize(Writer);
                     for Material in Unlock.AssetClass.GetRelatedMaterials(System) do
                        SendMaterial(Material);
                  end;
               ukMaterial:
                  begin
                     SendMaterial(Unlock.Material);
                  end;
               ukMessage:
                  begin
                     // messages are sent with fcMessage features
                  end;
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
      Journal.WriteInt32(TResearch.kNilID);
   end;
end;

procedure TKnowledgeFeatureNode.ApplyJournal(Journal: TJournalReader);
var
   ID: TResearchID;
begin
   ID := Journal.ReadInt32();
   if (ID <> TResearch.kNilID) then
   begin
      Assert(ID >= Low(TResearchID));
      Assert(ID <= High(TResearchID));
      FResearch := System.Encyclopedia.ResearchesByID[ID]; // $R-
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