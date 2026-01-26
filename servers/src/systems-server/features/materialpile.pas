{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit materialpile;

interface

uses
   basenetwork, systems, serverstream, materials, techtree,
   messageport, region, time, systemdynasty, masses, annotatedpointer;

type
   TMaterialPileFeatureClass = class(TFeatureClass)
   private
      FMaxQuantity: TQuantity64;
      FMaterial: TMaterial;
   strict protected
      function GetFeatureNodeClass(): FeatureNodeReference; override;
   protected
      procedure CollectRelatedMaterials(var Materials: TMaterial.TPlasticArray; const Encyclopedia: TMaterialEncyclopedia); override;
   public
      constructor CreateFromTechnologyTree(Reader: TTechTreeReader); override;
      function InitFeatureNode(ASystem: TSystem): TFeatureNode; override;
   end;

   TMaterialPileFeatureNode = class(TFeatureNode, IMaterialPile)
   strict private
      type
         TRegionStatus = (rsNoRegion);
   strict private
      FFeatureClass: TMaterialPileFeatureClass;
      FMaterialKnowledge: TKnowledgeSummary;
      FRegion: specialize TAnnotatedPointer<TRegionFeatureNode, TRegionStatus>;
   private // IMaterialPile
      function GetMaterialPileMaterial(): TMaterial;
      function GetMaterialPileCapacity(): TQuantity64;
      procedure SetMaterialPileRegion(Region: TRegionFeatureNode);
      procedure RegionAdjustedMaterialPiles();
      procedure DisconnectMaterialPile();
      function GetDynasty(): TDynasty;
   protected
      constructor CreateFromJournal(Journal: TJournalReader; AFeatureClass: TFeatureClass; ASystem: TSystem); override;
      function GetMass(): TMass; override;
      function GetMassFlowRate(): TMassRate; override;
      function HandleBusMessage(Message: TBusMessage): THandleBusMessageResult; override;
      procedure HandleChanges(); override;
      procedure Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter); override;
      procedure ResetDynastyNotes(OldDynasties: TDynastyIndexHashTable; NewDynasties: TDynasty.TArray); override;
      procedure ResetVisibility(); override;
      procedure HandleKnowledge(const DynastyIndex: Cardinal; const Sensors: ISensorsProvider); override;
   public
      constructor Create(ASystem: TSystem; AFeatureClass: TMaterialPileFeatureClass);
      destructor Destroy(); override;
      procedure Attaching(); override;
      procedure Detaching(); override;
      procedure UpdateJournal(Journal: TJournalWriter); override;
      procedure ApplyJournal(Journal: TJournalReader); override;
   end;

// TODO: handle our ancestor chain changing

implementation

uses
   exceptions, sysutils, knowledge, messages, isdprotocol, rubble, commonbuses;

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

function TMaterialPileFeatureClass.InitFeatureNode(ASystem: TSystem): TFeatureNode;
begin
   Result := TMaterialPileFeatureNode.Create(ASystem, Self);
end;

procedure TMaterialPileFeatureClass.CollectRelatedMaterials(var Materials: TMaterial.TPlasticArray; const Encyclopedia: TMaterialEncyclopedia);
begin
   Materials.Push(FMaterial);
end;


constructor TMaterialPileFeatureNode.Create(ASystem: TSystem; AFeatureClass: TMaterialPileFeatureClass);
begin
   inherited Create(ASystem);
   FFeatureClass := AFeatureClass;
end;

constructor TMaterialPileFeatureNode.CreateFromJournal(Journal: TJournalReader; AFeatureClass: TFeatureClass; ASystem: TSystem);
begin
   Assert(Assigned(AFeatureClass));
   FFeatureClass := AFeatureClass as TMaterialPileFeatureClass;
   inherited;
end;

destructor TMaterialPileFeatureNode.Destroy();
begin
   if (FRegion.Assigned) then
      FRegion.Unwrap().RemoveMaterialPile(Self);
   FRegion.Clear();
   FMaterialKnowledge.Done();
   inherited;
end;

procedure TMaterialPileFeatureNode.Attaching();
begin
   Assert(not FRegion.Assigned);
   Assert(FRegion.IsFlagClear(rsNoRegion));
   MarkAsDirty([dkNeedsHandleChanges]);
end;

procedure TMaterialPileFeatureNode.Detaching();
begin
   if (FRegion.Assigned) then
      FRegion.Unwrap().RemoveMaterialPile(Self);
   FRegion.Clear();
end;

function TMaterialPileFeatureNode.GetMaterialPileMaterial(): TMaterial;
begin
   Result := FFeatureClass.FMaterial;
end;

function TMaterialPileFeatureNode.GetMaterialPileCapacity(): TQuantity64;
begin
   Assert(FFeatureClass.FMaxQuantity.IsPositive);
   Result := FFeatureClass.FMaxQuantity; // $R-
end;

procedure TMaterialPileFeatureNode.SetMaterialPileRegion(Region: TRegionFeatureNode);
begin
   Assert(not FRegion.Assigned);
   FRegion := Region;
end;

procedure TMaterialPileFeatureNode.RegionAdjustedMaterialPiles();
begin
   Assert(FRegion.Assigned);
   MarkAsDirty([dkUpdateClients]);
end;

procedure TMaterialPileFeatureNode.DisconnectMaterialPile();
begin
   Assert(FRegion.Assigned);
   FRegion.Clear();
   MarkAsDirty([dkUpdateClients, dkNeedsHandleChanges]);
end;

function TMaterialPileFeatureNode.GetDynasty(): TDynasty;
begin
   Result := Parent.Owner;
end;

function TMaterialPileFeatureNode.HandleBusMessage(Message: TBusMessage): THandleBusMessageResult;
var
   Quantity: TQuantity64;
begin
   if (Message is TRubbleCollectionMessage) then
   begin
      if (FRegion.Assigned) then
      begin
         Quantity := FRegion.Unwrap().ExtractMaterialPile(Self); // this also disconnects the pile
         FRegion.Clear();
         (Message as TRubbleCollectionMessage).AddMaterial(FFeatureClass.FMaterial, Quantity);
         MarkAsDirty([dkUpdateClients, dkNeedsHandleChanges]);
      end;
   end
   else
   if (Message is TDismantleMessage) then
   begin
      if (not Assigned(Parent.Owner)) then
      begin
         // TODO: once we support frozen piles, transfer the contents to the region's material piles on behalf of the Messsage.Owner
         Assert(not FRegion.Assigned);
      end
      else
      begin
         Assert((Message as TDismantleMessage).Owner = Parent.Owner);
         if (FRegion.Assigned) then
         begin
            Quantity := FRegion.Unwrap().RehomeMaterialPile(Self); // this also disconnects the pile
            FRegion.Clear();
            if (Quantity.IsPositive) then
               (Message as TDismantleMessage).AddExcessMaterial(FFeatureClass.FMaterial, Quantity);
            MarkAsDirty([dkUpdateClients, dkNeedsHandleChanges]);
         end;
      end;
   end;
   Result := inherited;
end;

procedure TMaterialPileFeatureNode.HandleChanges();
var
   Message: TRegisterMaterialPileBusMessage;
begin
   if (Assigned(Parent.Owner) and not FRegion.Assigned and FRegion.IsFlagClear(rsNoRegion)) then
   begin
      Message := TRegisterMaterialPileBusMessage.Create(Self);
      if (InjectBusMessage(Message) <> irHandled) then
         FRegion.SetFlag(rsNoRegion)
      else
         Assert(FRegion.Assigned);         
      FreeAndNil(Message);
   end;
   inherited;
end;

function TMaterialPileFeatureNode.GetMass(): TMass;
begin
   if (FRegion.Assigned) then
   begin
      Result := FRegion.Unwrap().GetMaterialPileMass(Self);
   end
   else
   begin
      Result := TMass.Zero;
   end;
   Assert(Result.AsDouble >= -0.0000001);
end;

function TMaterialPileFeatureNode.GetMassFlowRate(): TMassRate;
begin
   if (FRegion.Assigned) then
   begin
      Result := FRegion.Unwrap().GetMaterialPileMassFlowRate(Self);
   end
   else
   begin
      Result := TMassRate.Zero;
   end;
end;

procedure TMaterialPileFeatureNode.Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter);
var
   Visibility: TVisibility;
begin
   Visibility := Parent.ReadVisibilityFor(DynastyIndex);
   if (dmDetectable * Visibility <> []) then
   begin
      case (FFeatureClass.FMaterial.UnitKind) of
       ukBulkResource:
         begin
            Writer.WriteCardinal(fcMaterialPile);
            if (FRegion.Assigned) then
            begin
               Writer.WriteDouble(FRegion.Unwrap().GetMaterialPileMass(Self).AsDouble);
               Writer.WriteDouble(FRegion.Unwrap().GetMaterialPileMassFlowRate(Self).AsDouble);
            end
            else
            begin
               Writer.WriteDouble(0);
               Writer.WriteDouble(0);
            end;
            Writer.WriteDouble((FFeatureClass.FMaxQuantity * FFeatureClass.FMaterial.MassPerUnit).AsDouble);
         end;
        ukComponent:
         begin
            Writer.WriteCardinal(fcMaterialStack);
            if (FRegion.Assigned) then
            begin
               Writer.WriteInt64(FRegion.Unwrap().GetMaterialPileQuantity(Self).AsInt64);
               Writer.WriteDouble(FRegion.Unwrap().GetMaterialPileQuantityFlowRate(Self).AsDouble);
            end
            else
            begin
               Writer.WriteInt64(0);
               Writer.WriteDouble(0);
            end;
            Writer.WriteInt64(FFeatureClass.FMaxQuantity.AsInt64);
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

procedure TMaterialPileFeatureNode.ResetDynastyNotes(OldDynasties: TDynastyIndexHashTable; NewDynasties: TDynasty.TArray);
begin
   FMaterialKnowledge.Init(Length(NewDynasties)); // $R-
end;

procedure TMaterialPileFeatureNode.ResetVisibility();
begin
   FMaterialKnowledge.Reset();
end;

procedure TMaterialPileFeatureNode.HandleKnowledge(const DynastyIndex: Cardinal; const Sensors: ISensorsProvider);
begin
   FMaterialKnowledge.SetEntry(DynastyIndex, Sensors.Knows(FFeatureClass.FMaterial));
end;

procedure TMaterialPileFeatureNode.UpdateJournal(Journal: TJournalWriter);
begin
end;

procedure TMaterialPileFeatureNode.ApplyJournal(Journal: TJournalReader);
begin
end;

initialization
   RegisterFeatureClass(TMaterialPileFeatureClass);
end.