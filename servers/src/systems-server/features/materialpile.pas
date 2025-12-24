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
      function InitFeatureNode(ASystem: TSystem): TFeatureNode; override;
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
      function HandleBusMessage(Message: TBusMessage): THandleBusMessageResult; override;
      procedure HandleChanges(); override;
      procedure Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter); override;
      procedure ResetDynastyNotes(OldDynasties: TDynastyIndexHashTable; NewDynasties: TDynasty.TArray); override;
      procedure ResetVisibility(); override;
      procedure HandleKnowledge(const DynastyIndex: Cardinal; const Sensors: ISensorsProvider); override;
   public
      constructor Create(ASystem: TSystem; AFeatureClass: TMaterialPileFeatureClass);
      destructor Destroy(); override;
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
   if (Assigned(FRegion)) then
      FRegion.RemoveMaterialPile(Self);
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

function TMaterialPileFeatureNode.HandleBusMessage(Message: TBusMessage): THandleBusMessageResult;
var
   Quantity: UInt64;
begin
   if (Message is TRubbleCollectionMessage) then
   begin
      if (Assigned(FRegion)) then
      begin
         Quantity := FRegion.ExtractMaterialPile(Self);
         FRegion := nil;
         (Message as TRubbleCollectionMessage).AddMaterial(FFeatureClass.FMaterial, Quantity);
         MarkAsDirty([dkUpdateClients, dkNeedsHandleChanges]);
      end;
   end
   else
   if (Message is TDismantleMessage) then
   begin
      Writeln(DebugName, ' received ', Message.ClassName);
      if (not Assigned(Parent.Owner)) then
      begin
         // TODO: once we support frozen piles, transfer the contents to the region's material piles on behalf of the Messsage.Owner
         Assert(not Assigned(FRegion));
      end
      else
      begin
         Assert((Message as TDismantleMessage).Owner = Parent.Owner);
         if (Assigned(FRegion)) then
         begin
            Writeln('  calling region to rehome pile contents');
            Quantity := FRegion.RehomeMaterialPile(Self);
            FRegion := nil;
            if (Quantity > 0) then
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

procedure TMaterialPileFeatureNode.Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter);
var
   Visibility: TVisibility;
begin
   Visibility := Parent.ReadVisibilityFor(DynastyIndex);
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