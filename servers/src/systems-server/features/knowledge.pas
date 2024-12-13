{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit knowledge;

interface

uses
   systems, systemdynasty, serverstream, materials, hashtable, genericutils;

type
   TKnowledgeBusMessage = class abstract(TPhysicalConnectionBusMessage) end;

   TCollectKnownMaterialsMessage = class(TKnowledgeBusMessage)
   private
      FKnownMaterials: TMaterialHashSet;
      FOwner: TDynasty;
   public
      constructor Create(AKnownMaterials: TMaterialHashSet; AOwner: TDynasty);
      procedure AddKnownMaterial(Material: TMaterial); inline;
      property Owner: TDynasty read FOwner;
   end;
   
   TCollectKnownAssetClassesMessage = class(TKnowledgeBusMessage)
   private
      FKnownAssetClasses: TAssetClassHashSet;
      FOwner: TDynasty;
   public
      constructor Create(AKnownAssetClasses: TAssetClassHashSet; AOwner: TDynasty);
      procedure AddKnownAssetClass(AssetClass: TAssetClass); inline;
      property Owner: TDynasty read FOwner;
   end;
   
   TGetKnownMaterialsMessage = class(TKnowledgeBusMessage)
   private
      FOwner: TDynasty;
      FKnownMaterials: TMaterialHashSet;
      procedure SetKnownMaterials(AKnownMaterials: TMaterialHashSet); inline;
   public
      constructor Create(AOwner: TDynasty);
      property Owner: TDynasty read FOwner;
      function Knows(Material: TMaterial): Boolean; inline;
   end;
   
   TGetKnownAssetClassesMessage = class(TKnowledgeBusMessage)
   private
      FOwner: TDynasty;
      FKnownAssetClasses: TAssetClassHashSet;
      procedure SetKnownAssetClasses(AKnownAssetClasses: TAssetClassHashSet); inline;
   public
      constructor Create(AOwner: TDynasty);
      property Owner: TDynasty read FOwner;
      function Knows(AssetClass: TAssetClass): Boolean; inline;
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
      function GetMass(): Double; override;
      function GetSize(): Double; override;
      function GetFeatureName(): UTF8String; override;
      procedure Walk(PreCallback: TPreWalkCallback; PostCallback: TPostWalkCallback); override;
      function ManageBusMessage(Message: TBusMessage): Boolean; override;
      function HandleBusMessage(Message: TBusMessage): Boolean; override;
      procedure Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter; CachedSystem: TSystem); override;
   public
      destructor Destroy(); override;
      procedure UpdateJournal(Journal: TJournalWriter); override;
      procedure ApplyJournal(Journal: TJournalReader; CachedSystem: TSystem); override;
   end;

implementation

uses
   sysutils;

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


function TKnowledgeBusFeatureClass.GetFeatureNodeClass(): FeatureNodeReference;
begin
   Result := TKnowledgeBusFeatureNode;
end;

function TKnowledgeBusFeatureClass.InitFeatureNode(): TFeatureNode;
begin
   Result := TKnowledgeBusFeatureNode.Create();
end;


destructor TKnowledgeBusFeatureNode.Destroy();
begin
   FreeAndNil(FKnownMaterials);
   FreeAndNil(FKnownAssetClasses);
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

function TKnowledgeBusFeatureNode.GetMass(): Double;
begin
   Result := 0.0;
end;

function TKnowledgeBusFeatureNode.GetSize(): Double;
begin
   Result := 0.0;
end;

function TKnowledgeBusFeatureNode.GetFeatureName(): UTF8String;
begin
   Result := '';
end;

procedure TKnowledgeBusFeatureNode.Walk(PreCallback: TPreWalkCallback; PostCallback: TPostWalkCallback);
begin
end;

function TKnowledgeBusFeatureNode.ManageBusMessage(Message: TBusMessage): Boolean;
begin
   if (Message is TKnowledgeBusMessage) then
   begin
      Result := False;
      if (Assigned(Parent.Parent)) then
         Result := Parent.Parent.InjectBusMessage(Message);
      if (not Result) then
         Result := Parent.HandleBusMessage(Message);
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
         Assert(not Handled, 'TCollectKnownMaterialsMessage should not be marked as handled');
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
         Assert(not Handled, 'TCollectKnownAssetClassesMessage should not be marked as handled');
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

end.