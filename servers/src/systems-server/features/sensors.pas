{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit sensors;

interface

uses
   systems, materials, knowledge, techtree, tttokenizer, commonbuses;

type
   TSensorFeatureClass = class abstract (TFeatureClass)
   protected
      FSensorKind: TVisibility;
   public
      constructor Create(ASensorKind: TVisibility);
      constructor CreateFromTechnologyTree(Reader: TTechTreeReader); override;
   end;

   TSensorFeatureNode = class abstract (TFeatureNode, ISensorsProvider)
   strict private
      procedure SyncKnowledge();
      function GetEnabled(): Boolean; inline;
   protected
      FKnownMaterials: TGetKnownMaterialsMessage;
      FKnownAssetClasses: TGetKnownAssetClassesMessage;
      FDisabledReasons: TDisabledReasons;
      FLastCountDetected: Cardinal;
      procedure ResetVisibility(); override;
      procedure HandleChanges(); override;
      property Enabled: Boolean read GetEnabled;
   public
      destructor Destroy(); override;
      procedure UpdateJournal(Journal: TJournalWriter); override;
      procedure ApplyJournal(Journal: TJournalReader); override;
   public // ISensorsProvider
      function Knows(AssetClass: TAssetClass): Boolean;
      function Knows(Material: TMaterial): Boolean;
      function GetOreKnowledge(): TOreFilter;
      function GetDebugName(): UTF8String;
   end;

implementation

uses
   sysutils, orbit, typedump;

constructor TSensorFeatureClass.Create(ASensorKind: TVisibility);
begin
   inherited Create();
   FSensorKind := ASensorKind;
end;

constructor TSensorFeatureClass.CreateFromTechnologyTree(Reader: TTechTreeReader);
var
   Keyword: UTF8String;

   procedure AddSensorKind(Mechanism: TDetectionMechanism);
   begin
      if (Mechanism in FSensorKind) then
         Reader.Tokens.Error('Duplicate sensor kind "%s"', [Keyword]);
      Include(FSensorKind, Mechanism);
   end;

begin
   inherited Create();
   repeat
      Keyword := Reader.Tokens.ReadIdentifier();
      case Keyword of
         'inference': AddSensorKind(dmInference);
         'light': AddSensorKind(dmVisibleSpectrum);
         'class': AddSensorKind(dmClassKnown); // for debugging only // TODO: remove this in production
         'internals': AddSensorKind(dmInternals); // for debugging only // TODO: remove this in production
      else
         Reader.Tokens.Error('Invalid sensor type "%s", supported sensor types are "light", "internals", "class", "inference"', []);
      end;
   until not ReadComma(Reader.Tokens);
end;


destructor TSensorFeatureNode.Destroy();
begin
   Assert(not Assigned(FKnownMaterials));
   Assert(not Assigned(FKnownAssetClasses));
   inherited;
end;

function TSensorFeatureNode.GetDebugName(): UTF8String;
begin
   Result := DebugName;
end;

procedure TSensorFeatureNode.ResetVisibility();
begin
   Assert(not Assigned(FKnownMaterials));
   Assert(not Assigned(FKnownAssetClasses));
end;

procedure TSensorFeatureNode.HandleChanges();
var
   NewDisabledReasons: TDisabledReasons;
begin
   NewDisabledReasons := CheckDisabled(Parent);
   if (NewDisabledReasons <> FDisabledReasons) then
   begin
      FDisabledReasons := NewDisabledReasons;
      MarkAsDirty([dkUpdateClients, dkAffectsVisibility]);
   end;
   inherited;
end;

function TSensorFeatureNode.GetEnabled(): Boolean;
begin
   Result := FDisabledReasons = [];
end;

procedure TSensorFeatureNode.SyncKnowledge();
begin
   if (not Assigned(FKnownMaterials)) then
   begin
      FKnownMaterials := TGetKnownMaterialsMessage.Create(Parent.Owner);
      InjectBusMessage(FKnownMaterials); // we ignore the result - it doesn't matter if it wasn't handled
      // we free the result in ApplyKnowledge
   end;
   if (not Assigned(FKnownAssetClasses)) then
   begin
      FKnownAssetClasses := TGetKnownAssetClassesMessage.Create(Parent.Owner);
      InjectBusMessage(FKnownAssetClasses); // we ignore the result - it doesn't matter if it wasn't handled
      // we free the result in ApplyKnowledge
   end;
end;

function TSensorFeatureNode.Knows(AssetClass: TAssetClass): Boolean;
begin
   SyncKnowledge();
   // If something fails here, it probably means that someone's HandleKnowledge is calling MarkAsDirty
   // and the knowledge feature we're relying on is blowing away its cache.
   Result := FKnownAssetClasses.Knows(AssetClass);
end;

function TSensorFeatureNode.Knows(Material: TMaterial): Boolean;
begin
   SyncKnowledge();
   // If something fails here, it probably means that someone's HandleKnowledge is calling MarkAsDirty
   // and the knowledge feature we're relying on is blowing away its cache.
   Result := FKnownMaterials.Knows(Material);
end;

function TSensorFeatureNode.GetOreKnowledge(): TOreFilter;
var
   Material: TMaterial;
begin
   SyncKnowledge();
   Result.Clear();
   for Material in FKnownMaterials do
   begin
      Result.EnableMaterialIfOre(Material);
   end;
end;

procedure TSensorFeatureNode.UpdateJournal(Journal: TJournalWriter);
begin
end;

procedure TSensorFeatureNode.ApplyJournal(Journal: TJournalReader);
begin
end;

end.