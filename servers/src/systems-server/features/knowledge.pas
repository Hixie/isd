{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit knowledge;

interface

uses
   systems, systemdynasty, serverstream, materials, hashtable, genericutils;

type
   TKnowledgeBusMessage = class abstract(TPhysicalConnectionBusMessage) end;
   TTargetedKnowledgeBusMessage = class abstract(TKnowledgeBusMessage) end;
   TGlobalKnowledgeBusMessage = class abstract(TKnowledgeBusMessage) end;

   TCollectKnownMaterialsMessage = class(TGlobalKnowledgeBusMessage)
   private
      FKnownMaterials: TMaterialHashSet;
      FOwner: TDynasty;
   public
      constructor Create(AKnownMaterials: TMaterialHashSet; AOwner: TDynasty);
      procedure AddKnownMaterial(Material: TMaterial); inline;
      property Owner: TDynasty read FOwner;
   end;
   
   TCollectKnownAssetClassesMessage = class(TGlobalKnowledgeBusMessage)
   private
      FKnownAssetClasses: TAssetClassHashSet;
      FOwner: TDynasty;
   public
      constructor Create(AKnownAssetClasses: TAssetClassHashSet; AOwner: TDynasty);
      procedure AddKnownAssetClass(AssetClass: TAssetClass); inline;
      property Owner: TDynasty read FOwner;
   end;
   
   TGetKnownMaterialsMessage = class(TTargetedKnowledgeBusMessage)
   private
      FOwner: TDynasty;
      FKnownMaterials: TMaterialHashSet;
      procedure SetKnownMaterials(AKnownMaterials: TMaterialHashSet); inline;
   public
      constructor Create(AOwner: TDynasty);
      property Owner: TDynasty read FOwner;
      function Knows(Material: TMaterial): Boolean; inline;
   end;
   
   TGetKnownAssetClassesMessage = class(TTargetedKnowledgeBusMessage)
   private
      FOwner: TDynasty;
      FKnownAssetClasses: TAssetClassHashSet;
      procedure SetKnownAssetClasses(AKnownAssetClasses: TAssetClassHashSet); inline;
   public
      constructor Create(AOwner: TDynasty);
      property Owner: TDynasty read FOwner;
      function Knows(AssetClass: TAssetClass): Boolean; inline;
      function GetEnumerator(): TAssetClassHashSet.TEnumerator;
   end;

type
   TKnowledgeBusFeatureClass = class(TFeatureClass)
   strict protected
      function GetFeatureNodeClass(): FeatureNodeReference; override;
   public
      function InitFeatureNode(): TFeatureNode; override;
   end;

   TCachedKnownMaterialsHashMap = specialize THashTable<TDynasty, TMaterialHashSet, TObjectUtils>;
   TCachedKnownAssetClassesHashMap = specialize THashTable<TDynasty, TAssetClassHashSet, TObjectUtils>;
   
   TKnowledgeBusFeatureNode = class(TFeatureNode)
   private
      FKnownMaterials: TCachedKnownMaterialsHashMap;
      FKnownAssetClasses: TCachedKnownAssetClassesHashMap;
   protected
      procedure MarkAsDirty(DirtyKinds: TDirtyKinds); override;
      function ManageBusMessage(Message: TBusMessage): Boolean; override;
      function HandleBusMessage(Message: TBusMessage): Boolean; override;
      procedure Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter; CachedSystem: TSystem); override;
   public
      destructor Destroy(); override;
      procedure UpdateJournal(Journal: TJournalWriter); override;
      procedure ApplyJournal(Journal: TJournalReader; CachedSystem: TSystem); override;
   end;

type
   TAssetClassKnowledgeFeatureClass = class(TFeatureClass)
   strict protected
      function GetFeatureNodeClass(): FeatureNodeReference; override;
   public
      function InitFeatureNode(): TFeatureNode; override;
   end;
   
   TAssetClassKnowledgeFeatureNode = class(TFeatureNode)
   private
      FAssetClassKnowledge: TAssetClass;
   protected
      function HandleBusMessage(Message: TBusMessage): Boolean; override;
      procedure Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter; CachedSystem: TSystem); override;
   public
      constructor Create(AAssetClassKnowledge: TAssetClass);
      procedure SetAssetClassKnowledge(AAssetClassKnowledge: TAssetClass);
      procedure UpdateJournal(Journal: TJournalWriter); override;
      procedure ApplyJournal(Journal: TJournalReader; CachedSystem: TSystem); override;
      procedure DescribeExistentiality(var IsDefinitelyReal, IsDefinitelyGhost: Boolean); override;
   end;

implementation

uses
   sysutils, isdprotocol;

constructor TCollectKnownMaterialsMessage.Create(AKnownMaterials: TMaterialHashSet; AOwner: TDynasty);
begin
   inherited Create();
   FKnownMaterials := AKnownMaterials;
   FOwner := AOwner;
end;

procedure TCollectKnownMaterialsMessage.AddKnownMaterial(Material: TMaterial);
begin
   FKnownMaterials.Add(Material);
end;


constructor TCollectKnownAssetClassesMessage.Create(AKnownAssetClasses: TAssetClassHashSet; AOwner: TDynasty);
begin
   inherited Create();
   FKnownAssetClasses := AKnownAssetClasses;
   FOwner := AOwner;
end;

procedure TCollectKnownAssetClassesMessage.AddKnownAssetClass(AssetClass: TAssetClass);
begin
   FKnownAssetClasses.Add(AssetClass);
end;


constructor TGetKnownMaterialsMessage.Create(AOwner: TDynasty);
begin
   inherited Create();
   FOwner := AOwner;
end;

procedure TGetKnownMaterialsMessage.SetKnownMaterials(AKnownMaterials: TMaterialHashSet);
begin
   FKnownMaterials := AKnownMaterials;
end;

function TGetKnownMaterialsMessage.Knows(Material: TMaterial): Boolean;
begin
   Result := Assigned(FKnownMaterials) and FKnownMaterials.Has(Material);
end;


constructor TGetKnownAssetClassesMessage.Create(AOwner: TDynasty);
begin
   inherited Create();
   FOwner := AOwner;
end;

procedure TGetKnownAssetClassesMessage.SetKnownAssetClasses(AKnownAssetClasses: TAssetClassHashSet);
begin
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


function TKnowledgeBusFeatureClass.GetFeatureNodeClass(): FeatureNodeReference;
begin
   Result := TKnowledgeBusFeatureNode;
end;

function TKnowledgeBusFeatureClass.InitFeatureNode(): TFeatureNode;
begin
   Result := TKnowledgeBusFeatureNode.Create();
end;


destructor TKnowledgeBusFeatureNode.Destroy();
var
   Materials: TMaterialHashSet;
   Assets: TAssetClassHashSet;
begin
   if (Assigned(FKnownMaterials)) then
   begin
      for Materials in FKnownMaterials.Values do
         Materials.Free();
      FreeAndNil(FKnownMaterials);
   end;
   if (Assigned(FKnownAssetClasses)) then
   begin
      for Assets in FKnownAssetClasses.Values do
         Assets.Free();
      FreeAndNil(FKnownAssetClasses);
   end;
   inherited;
end;

procedure TKnowledgeBusFeatureNode.MarkAsDirty(DirtyKinds: TDirtyKinds);
begin
   if (dkAffectsKnowledge in DirtyKinds) then
   begin
      FreeAndNil(FKnownMaterials);
      FreeAndNil(FKnownAssetClasses);
   end;
   inherited;
end;

function TKnowledgeBusFeatureNode.ManageBusMessage(Message: TBusMessage): Boolean;
var
   Handled: Boolean;
begin
   if (Message is TKnowledgeBusMessage) then
   begin
      Result := False;
      if (Assigned(Parent.Parent)) then
      begin
         Result := Parent.Parent.InjectBusMessage(Message);
      end;
      if (not Result) then
      begin
         Handled := Parent.HandleBusMessage(Message);
         Assert((not (Message is TTargetedKnowledgeBusMessage)) or Handled);
         Assert((not (Message is TGlobalKnowledgeBusMessage)) or not Handled);
         Result := True;
      end;
   end
   else
      Result := inherited;
end;

function TKnowledgeBusFeatureNode.HandleBusMessage(Message: TBusMessage): Boolean;
var
   KnownMaterialsForDynasty: TMaterialHashSet;
   KnownAssetClassesForDynasty: TAssetClassHashSet;
   CollectMaterialsMessage: TCollectKnownMaterialsMessage;
   CollectAssetClassesMessage: TCollectKnownAssetClassesMessage;
   Handled: Boolean;
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
         CollectMaterialsMessage := TCollectKnownMaterialsMessage.Create(KnownMaterialsForDynasty, Dynasty);
         Handled := InjectBusMessage(CollectMaterialsMessage);
         Assert(Handled); // at a minimum, we should have handled it
         FKnownMaterials[Dynasty] := KnownMaterialsForDynasty;
         FreeAndNil(CollectMaterialsMessage);
      end;
      (Message as TGetKnownMaterialsMessage).SetKnownMaterials(FKnownMaterials[Dynasty]);
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
         CollectAssetClassesMessage := TCollectKnownAssetClassesMessage.Create(KnownAssetClassesForDynasty, Dynasty);
         Handled := InjectBusMessage(CollectAssetClassesMessage);
         Assert(Handled); // at a minimum, we should have handled it
         FKnownAssetClasses[Dynasty] := KnownAssetClassesForDynasty;
         FreeAndNil(CollectAssetClassesMessage);
      end;
      (Message as TGetKnownAssetClassesMessage).SetKnownAssetClasses(FKnownAssetClasses[Dynasty]);
      Result := True;
   end
   else
      Result := False;
end;

procedure TKnowledgeBusFeatureNode.Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter; CachedSystem: TSystem);
begin
end;

procedure TKnowledgeBusFeatureNode.UpdateJournal(Journal: TJournalWriter);
begin
end;

procedure TKnowledgeBusFeatureNode.ApplyJournal(Journal: TJournalReader; CachedSystem: TSystem);
begin
end;


function TAssetClassKnowledgeFeatureClass.GetFeatureNodeClass(): FeatureNodeReference;
begin
   Result := TAssetClassKnowledgeFeatureNode;
end;

function TAssetClassKnowledgeFeatureClass.InitFeatureNode(): TFeatureNode;
begin
   Result := TAssetClassKnowledgeFeatureNode.Create(nil);
end;

   
constructor TAssetClassKnowledgeFeatureNode.Create(AAssetClassKnowledge: TAssetClass);
begin
   inherited Create;
   FAssetClassKnowledge := AAssetClassKnowledge
end;

procedure TAssetClassKnowledgeFeatureNode.SetAssetClassKnowledge(AAssetClassKnowledge: TAssetClass);
begin
   FAssetClassKnowledge := AAssetClassKnowledge;
   MarkAsDirty([dkSelf]);
end;

function TAssetClassKnowledgeFeatureNode.HandleBusMessage(Message: TBusMessage): Boolean;
begin
   if (Message is TCollectKnownAssetClassesMessage) then
   begin
      if (Assigned(FAssetClassKnowledge) and (Parent.Owner = (Message as TCollectKnownAssetClassesMessage).Owner)) then
      begin
         (Message as TCollectKnownAssetClassesMessage).AddKnownAssetClass(FAssetClassKnowledge);
      end;
   end;
   Result := False;
end;
   
procedure TAssetClassKnowledgeFeatureNode.Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter; CachedSystem: TSystem);
var
   Visibility: TVisibility;
begin
   Visibility := Parent.ReadVisibilityFor(DynastyIndex, CachedSystem);
   if ((dmDetectable * Visibility <> []) and (dmClassKnown in Visibility)) then
   begin
      Writer.WriteCardinal(fcAssetClassKnowledge);
      if (Assigned(FAssetClassKnowledge) and (dmInternals in Visibility)) then
      begin
         FAssetClassKnowledge.Serialize(Writer);
      end
      else
         Writer.WriteCardinal(0);
   end;
end;
   
procedure TAssetClassKnowledgeFeatureNode.UpdateJournal(Journal: TJournalWriter);
begin
   Journal.WriteAssetClassReference(FAssetClassKnowledge);
end;
   
procedure TAssetClassKnowledgeFeatureNode.ApplyJournal(Journal: TJournalReader; CachedSystem: TSystem);
begin
   FAssetClassKnowledge := Journal.ReadAssetClassReference();
end;
   
procedure TAssetClassKnowledgeFeatureNode.DescribeExistentiality(var IsDefinitelyReal, IsDefinitelyGhost: Boolean);
begin
   IsDefinitelyReal := True;
end;
   
end.