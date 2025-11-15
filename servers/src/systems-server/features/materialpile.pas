{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit materialpile;

interface

uses
   basenetwork, systems, serverstream, materials, techtree,
   messageport, region, time, systemdynasty;

type
   TMaterialPileFeatureClass = class(TFeatureClass)
   private
      FMaxQuantity: Int64;
      FMaterial: TMaterial;
   strict protected
      function GetFeatureNodeClass(): FeatureNodeReference; override;
   public
      constructor CreateFromTechnologyTree(Reader: TTechTreeReader); override;
      function InitFeatureNode(): TFeatureNode; override;
   end;

   TMaterialPileFeatureNode = class(TFeatureNode, IMaterialPile)
   strict private
      FFeatureClass: TMaterialPileFeatureClass;
      FMaterialKnowledge: TKnowledgeSummary;
      FRegion: TRegionFeatureNode;
   private // IMaterialPile
      function GetMaterialPileMaterial(): TMaterial;
      function GetMaterialPileCapacity(): UInt64; // quantity
      procedure SetMaterialPileRegion(Region: TRegionFeatureNode);
      procedure RegionAdjustedMaterialPiles();
      procedure DisconnectMaterialPile();
      function GetDynasty(): TDynasty;
   protected
      constructor CreateFromJournal(Journal: TJournalReader; AFeatureClass: TFeatureClass; ASystem: TSystem); override;
      function GetMass(): Double; override;
      function GetMassFlowRate(): TRate; override;
      procedure HandleChanges(CachedSystem: TSystem); override;
      procedure Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter; CachedSystem: TSystem); override;
      procedure ResetDynastyNotes(OldDynasties: TDynastyIndexHashTable; NewDynasties: TDynastyHashSet; CachedSystem: TSystem); override;
      procedure ResetVisibility(CachedSystem: TSystem); override;
      procedure HandleKnowledge(const DynastyIndex: Cardinal; const VisibilityHelper: TVisibilityHelper; const Sensors: ISensorsProvider); override;
   public
      constructor Create(AFeatureClass: TMaterialPileFeatureClass);
      destructor Destroy(); override;
      procedure UpdateJournal(Journal: TJournalWriter; CachedSystem: TSystem); override;
      procedure ApplyJournal(Journal: TJournalReader; CachedSystem: TSystem); override;
   end;

// TODO: handle our ancestor chain changing

implementation

uses
   exceptions, sysutils, knowledge, messages, isdprotocol;

constructor TMaterialPileFeatureClass.CreateFromTechnologyTree(Reader: TTechTreeReader);
begin
   inherited Create();
   Reader.Tokens.ReadIdentifier('for');
   FMaterial := ReadMaterial(Reader);
   Reader.Tokens.ReadComma();
   Reader.Tokens.ReadIdentifier('capacity');
   FMaxQuantity := ReadQuantity(Reader.Tokens, FMaterial);
end;

function TMaterialPileFeatureClass.GetFeatureNodeClass(): FeatureNodeReference;
begin
   Result := TMaterialPileFeatureNode;
end;

function TMaterialPileFeatureClass.InitFeatureNode(): TFeatureNode;
begin
   Result := TMaterialPileFeatureNode.Create(Self);
end;


constructor TMaterialPileFeatureNode.Create(AFeatureClass: TMaterialPileFeatureClass);
begin
   inherited Create();
   FFeatureClass := AFeatureClass;
end;

constructor TMaterialPileFeatureNode.CreateFromJournal(Journal: TJournalReader; AFeatureClass: TFeatureClass; ASystem: TSystem);
begin
   Assert(Assigned(AFeatureClass));
   FFeatureClass := AFeatureClass as TMaterialPileFeatureClass;
   inherited CreateFromJournal(Journal, AFeatureClass, ASystem);
end;

destructor TMaterialPileFeatureNode.Destroy();
begin
   FMaterialKnowledge.Done();
   inherited;
end;

function TMaterialPileFeatureNode.GetMaterialPileMaterial(): TMaterial;
begin
   Result := FFeatureClass.FMaterial;
end;

function TMaterialPileFeatureNode.GetMaterialPileCapacity(): UInt64; // quantity
begin
   Assert(FFeatureClass.FMaxQuantity > 0);
   Result := FFeatureClass.FMaxQuantity; // $R-
end;

procedure TMaterialPileFeatureNode.SetMaterialPileRegion(Region: TRegionFeatureNode);
begin
   Assert(not Assigned(FRegion));
   FRegion := Region;
end;

procedure TMaterialPileFeatureNode.RegionAdjustedMaterialPiles();
begin
   Assert(Assigned(FRegion));
   MarkAsDirty([dkUpdateClients]);
end;

procedure TMaterialPileFeatureNode.DisconnectMaterialPile();
begin
   Assert(Assigned(FRegion));
   FRegion := nil;
   MarkAsDirty([dkUpdateClients, dkNeedsHandleChanges]);
end;

function TMaterialPileFeatureNode.GetDynasty(): TDynasty;
begin
   Result := Parent.Owner;
end;

procedure TMaterialPileFeatureNode.HandleChanges(CachedSystem: TSystem);
var
   Message: TRegisterMaterialPileBusMessage;
begin
   if (Assigned(Parent.Owner) and not Assigned(FRegion)) then
   begin
      Message := TRegisterMaterialPileBusMessage.Create(Self);
      InjectBusMessage(Message); // TODO: if we didn't find a region, we shouldn't do this again until our ancestor chain changed
      FreeAndNil(Message);
   end;
   inherited;
end;

function TMaterialPileFeatureNode.GetMass(): Double;
begin
   if (Assigned(FRegion)) then
   begin
      Result := FRegion.GetMaterialPileMass(Self);
   end
   else
   begin
      Result := 0.0;
   end;
   Assert(Result >= -0.0000001);
end;

function TMaterialPileFeatureNode.GetMassFlowRate(): TRate;
begin
   if (Assigned(FRegion)) then
   begin
      Result := FRegion.GetMaterialPileMassFlowRate(Self);
   end
   else
   begin
      Result := TRate.Zero;
   end;
end;

procedure TMaterialPileFeatureNode.Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter; CachedSystem: TSystem);
var
   Visibility: TVisibility;
begin
   Visibility := Parent.ReadVisibilityFor(DynastyIndex, CachedSystem);
   if ((dmDetectable * Visibility <> []) and (dmClassKnown in Visibility)) then
   begin
      case (FFeatureClass.FMaterial.UnitKind) of
       ukBulkResource:
         begin
            Writer.WriteCardinal(fcMaterialPile);
            if (Assigned(FRegion)) then
            begin
               Writer.WriteDouble(FRegion.GetMaterialPileMass(Self));
               Writer.WriteDouble(FRegion.GetMaterialPileMassFlowRate(Self).AsDouble);
            end
            else
            begin
               Writer.WriteDouble(0);
               Writer.WriteDouble(0);
            end;
            Writer.WriteDouble(FFeatureClass.FMaxQuantity * FFeatureClass.FMaterial.MassPerUnit);
         end;
        ukComponent:
         begin
            Writer.WriteCardinal(fcMaterialStack);
            if (Assigned(FRegion)) then
            begin
               Writer.WriteUInt64(FRegion.GetMaterialPileQuantity(Self));
               Writer.WriteDouble(FRegion.GetMaterialPileQuantityFlowRate(Self).AsDouble);
            end
            else
            begin
               Writer.WriteUInt64(0);
               Writer.WriteDouble(0);
            end;
            Writer.WriteInt64(FFeatureClass.FMaxQuantity);
         end;
      end;
      if (FMaterialKnowledge.GetEntry(DynastyIndex)) then
      begin
         Writer.WriteStringReference(FFeatureClass.FMaterial.Name);
         Writer.WriteInt32(FFeatureClass.FMaterial.ID);
      end
      else
      begin
         Writer.WriteStringReference(FFeatureClass.FMaterial.AmbiguousName);
         Writer.WriteCardinal(0);
      end;
   end;
end;

procedure TMaterialPileFeatureNode.ResetDynastyNotes(OldDynasties: TDynastyIndexHashTable; NewDynasties: TDynastyHashSet; CachedSystem: TSystem);
begin
   FMaterialKnowledge.Init(NewDynasties.Count);
end;

procedure TMaterialPileFeatureNode.ResetVisibility(CachedSystem: TSystem);
begin
   FMaterialKnowledge.Reset();
end;

procedure TMaterialPileFeatureNode.HandleKnowledge(const DynastyIndex: Cardinal; const VisibilityHelper: TVisibilityHelper; const Sensors: ISensorsProvider);
begin
   FMaterialKnowledge.SetEntry(DynastyIndex, Sensors.Knows(FFeatureClass.FMaterial));
end;

procedure TMaterialPileFeatureNode.UpdateJournal(Journal: TJournalWriter; CachedSystem: TSystem);
begin
end;

procedure TMaterialPileFeatureNode.ApplyJournal(Journal: TJournalReader; CachedSystem: TSystem);
begin
end;

initialization
   RegisterFeatureClass(TMaterialPileFeatureClass);
end.