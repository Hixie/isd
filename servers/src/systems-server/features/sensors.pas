{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit sensors;

interface

uses
   systems, materials, knowledge, techtree, tttokenizer;

type
   TSensorFeatureClass = class abstract (TFeatureClass)
   protected
      FSensorKind: TVisibility;
   public
      constructor Create(ASensorKind: TVisibility);
      constructor CreateFromTechnologyTree(Reader: TTechTreeReader); override;
   end;

   TSensorFeatureNode = class abstract (TFeatureNode, ISensorsProvider)
   private
      procedure SyncKnowledge();
   protected
      FKnownMaterials: TGetKnownMaterialsMessage;
      FKnownAssetClasses: TGetKnownAssetClassesMessage;
      FLastCountDetected: Cardinal;
      procedure ResetVisibility(CachedSystem: TSystem); override;
   public
      destructor Destroy(); override;
      procedure UpdateJournal(Journal: TJournalWriter; CachedSystem: TSystem); override;
      procedure ApplyJournal(Journal: TJournalReader; CachedSystem: TSystem); override;
      function Knows(AssetClass: TAssetClass): Boolean;
      function Knows(Material: TMaterial): Boolean;
      function GetOreKnowledge(): TOreFilter;
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

   function HasComma(): Boolean;
   begin
      Result := Reader.Tokens.IsComma();
      if (Result) then
         Reader.Tokens.ReadComma();
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
   until not HasComma();
end;


destructor TSensorFeatureNode.Destroy();
begin
   Assert(not Assigned(FKnownMaterials));
   Assert(not Assigned(FKnownAssetClasses));
   inherited;
end;

procedure TSensorFeatureNode.ResetVisibility(CachedSystem: TSystem);
begin
   Assert(not Assigned(FKnownMaterials));
   Assert(not Assigned(FKnownAssetClasses));
end;

procedure TSensorFeatureNode.SyncKnowledge();
begin
   if (not Assigned(FKnownMaterials)) then
   begin
      Writeln('Initializing FKnownMaterials for ', DebugName);
      FKnownMaterials := TGetKnownMaterialsMessage.Create(Parent.Owner);
      InjectBusMessage(FKnownMaterials); // we ignore the result - it doesn't matter if it wasn't handled
      // we free the result in ApplyKnowledge
   end;
   if (not Assigned(FKnownAssetClasses)) then
   begin
      Writeln('Initializing FKnownAssetClasses for ', DebugName);
      FKnownAssetClasses := TGetKnownAssetClassesMessage.Create(Parent.Owner);
      InjectBusMessage(FKnownAssetClasses); // we ignore the result - it doesn't matter if it wasn't handled
      // we free the result in ApplyKnowledge
   end;
end;

function TSensorFeatureNode.Knows(AssetClass: TAssetClass): Boolean;
begin
   SyncKnowledge();
   // If something crashes here, it probably means that someone's HandleKnowledge is calling MarkAsDirty
   // and the knowledge feature we're relying on is blowing away its cache.
   Result := FKnownAssetClasses.Knows(AssetClass);
end;

function TSensorFeatureNode.Knows(Material: TMaterial): Boolean;
begin
   SyncKnowledge();
   // If something crashes here, it probably means that someone's HandleKnowledge is calling MarkAsDirty
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

procedure TSensorFeatureNode.UpdateJournal(Journal: TJournalWriter; CachedSystem: TSystem);
begin
end;

procedure TSensorFeatureNode.ApplyJournal(Journal: TJournalReader; CachedSystem: TSystem);
begin
end;

end.