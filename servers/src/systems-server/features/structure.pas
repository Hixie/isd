{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit structure;

interface

uses
   systems, serverstream, materials, techtree, builders, region, time,
   commonbuses, systemdynasty, basenetwork, masses, isdnumbers;

type
   TStructureFeatureClass = class;

   TMaterialLineItem = record // 24 bytes
      ComponentName: UTF8String;
      Material: TMaterial;
      Quantity: TQuantity32; // units of material
      constructor Create(AComponentName: UTF8String; AMaterial: TMaterial; AQuantity: TQuantity32);
   end;

   TMaterialLineItemArray = array of TMaterialLineItem;

   TStructureFeatureClass = class(TFeatureClass)
   strict private
      FDefaultSize: Double;
      FBillOfMaterials: TMaterialLineItemArray;
      FTotalQuantityCache: TQuantity32; // computed on creation
      FMinimumFunctionalQuantity: TQuantity32; // 0.0 .. TotalQuantity
      FMassCache: TMass;
   strict protected
      function GetFeatureNodeClass(): FeatureNodeReference; override;
      function GetDefaultSize(): Double; override;
   protected
      function GetMaterialLineItem(Index: Cardinal): TMaterialLineItem;
      function GetMaterialLineItemCount(): Cardinal;
      function ComputeTotalQuantity(): TQuantity32;
      function ComputeMass(): TMass;
   public
      constructor Create(ABillOfMaterials: TMaterialLineItemArray; AMinimumFunctionalQuantity: TQuantity32; ADefaultSize: Double);
      constructor CreateFromTechnologyTree(Reader: TTechTreeReader); override;
      function InitFeatureNode(ASystem: TSystem): TFeatureNode; override;
      property DefaultSize: Double read FDefaultSize;
      property BillOfMaterials[Index: Cardinal]: TMaterialLineItem read GetMaterialLineItem;
      property BillOfMaterialsLength: Cardinal read GetMaterialLineItemCount;
      property TotalQuantity: TQuantity32 read FTotalQuantityCache;
      property Mass: TMass read FMassCache;
      property MinimumFunctionalQuantity: TQuantity32 read FMinimumFunctionalQuantity; // minimum MaterialsQuantity for functioning
   end;

   TBuildingStateFlags = (bsTriggered, bsNoBuilderBus, bsNoRegion);

   PBuildingState = ^TBuildingState;
   TBuildingState = record
   private
      MaterialsQuantity: TQuantity32; // 0.0 .. TStructureFeatureClass.TotalQuantity
      StructuralIntegrity: Cardinal; // 0.0 .. TStructureFeatureClass.TotalQuantity, but cannot be higher than FMaterialsQuantity
      AnchorTime: TTimeInMilliseconds;
      StructuralIntegrityRate: TRate;
      PendingMaterial: TMaterial;
      PendingQuantity: TQuantity32;
      MaterialsQuantityRate: TQuantityRate;
      PendingFraction: Fraction32;
      NextEvent: TSystemEvent; // must trigger when or before the current MaterialsQuantityRate causes the current missing material to be filled, or the StructuralIntegrityRate causes StructuralIntegrity to reach 100%
      BuilderBus: TBuilderBusFeatureNode;
      Builder: TBuilderFeatureNode;
      Region: TRegionFeatureNode;
      Flags: set of TBuildingStateFlags; // could use AnnotatedPointers instead
      Priority: TPriority;
      function IncStructuralIntegrity(const Delta: Double; Threshold: Cardinal): Boolean;
   end;

   // TODO: if MaterialsQuantity changes whether it equals 0, then MarkAsDirty([dkAffectsVisibility])

   TStructureFeatureNode = class(TFeatureNode, IStructure, IMaterialConsumer)
   protected
      FFeatureClass: TStructureFeatureClass;
      FDynastyKnowledge: array of TKnowledgeSummary; // for each item in the bill of materials, which dynasties know about it here // TODO: this is expensive when there are not many dynasties (8 bytes per material, even if there's only 1 dynasty), but it really doesn't have to be, especially if we were to limit the number of materials in a bill of materials to 32 or 64 or something.
      FBuildingState: PBuildingState; // if this is nil, the StructuralIntegrity is 100%
      constructor CreateFromJournal(Journal: TJournalReader; AFeatureClass: TFeatureClass; ASystem: TSystem); override;
      procedure InitBuildingState();
      function GetNextStructureMaterial(): TMaterial;
      function GetNextStructureQuantity(): TQuantity32;
      function GetMass(): TMass; override; // kg
      function GetMassFlowRate(): TMassRate; override;
      function GetSize(): Double; override; // m
      procedure HandleChanges(); override;
      function HandleBusMessage(Message: TBusMessage): THandleBusMessageResult; override;
      procedure ResetDynastyNotes(OldDynasties: TDynastyIndexHashTable; NewDynasties: TDynasty.TArray); override;
      procedure ResetVisibility(); override;
      procedure HandleKnowledge(const DynastyIndex: Cardinal; const Sensors: ISensorsProvider); override;
      procedure FetchMaterials();
      procedure RescheduleNextEvent();
      procedure HandleEvent(var Data);
      procedure TriggerBuilding();
      procedure Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter); override;
   public
      constructor Create(ASystem: TSystem; AFeatureClass: TStructureFeatureClass; AMaterialsQuantity: TQuantity32; AStructuralIntegrity: Cardinal);
      destructor Destroy(); override;
      procedure UpdateJournal(Journal: TJournalWriter); override;
      procedure ApplyJournal(Journal: TJournalReader); override;
      procedure DescribeExistentiality(var IsDefinitelyReal, IsDefinitelyGhost: Boolean); override;
      function HandleCommand(PlayerDynasty: TDynasty; Command: UTF8String; var Message: TMessage): Boolean; override;
   private // IStructure
      procedure BuilderBusConnected(Bus: TBuilderBusFeatureNode); // must come from builder bus
      procedure BuilderBusReset(); // must come from builder bus, can assume all other participants were also reset
      procedure StartBuilding(Builder: TBuilderFeatureNode; BuildRate: TRate); // from builder
      procedure UpdateBuildingRate(BuildRate: TRate);
      procedure StopBuilding(); // from builder
      function GetAsset(): TAssetNode;
      function GetPriority(): TPriority;
      procedure SetAutoPriority(Value: TAutoPriority);
      function GetDynasty(): TDynasty;
   private // IMaterialConsumer
      function GetMaterialConsumerMaterial(): TMaterial;
      function GetMaterialConsumerMaxDelivery(): TQuantity32;
      function GetMaterialConsumerCurrentRate(): TQuantityRate; // quantity per second, cannot be infinite
      procedure SetMaterialConsumerRegion(Region: TRegionFeatureNode);
      procedure StartMaterialConsumer(ActualRate: TQuantityRate); // quantity per second
      procedure DeliverMaterialConsumer(Delivery: TQuantity32);
      procedure DisconnectMaterialConsumer();
      function GetPendingFraction(): PFraction32;
   end;

implementation

uses
   sysutils, isdprotocol, exceptions, rubble, plasticarrays,
   genericutils, assetpile;

constructor TMaterialLineItem.Create(AComponentName: UTF8String; AMaterial: TMaterial; AQuantity: TQuantity32);
begin
   ComponentName := AComponentName;
   Material := AMaterial;
   Quantity := AQuantity;
end;

function TBuildingState.IncStructuralIntegrity(const Delta: Double; Threshold: Cardinal): Boolean;
var
   WasAbove: Boolean;
begin
   WasAbove := StructuralIntegrity >= Threshold;
   if (Delta > High(StructuralIntegrity) - StructuralIntegrity) then
   begin
      StructuralIntegrity := High(StructuralIntegrity);
   end
   else
   begin
      Inc(StructuralIntegrity, Round(Delta));
   end;
   if (StructuralIntegrity > MaterialsQuantity.AsCardinal) then
   begin
      StructuralIntegrity := MaterialsQuantity.AsCardinal;
   end;
   Result := WasAbove <> (StructuralIntegrity >= Threshold);
end;


constructor TStructureFeatureClass.Create(ABillOfMaterials: TMaterialLineItemArray; AMinimumFunctionalQuantity: TQuantity32; ADefaultSize: Double);
begin
   inherited Create();
   FBillOfMaterials := ABillOfMaterials;
   FTotalQuantityCache := ComputeTotalQuantity();
   FMassCache := ComputeMass();
   FMinimumFunctionalQuantity := AMinimumFunctionalQuantity;
   FDefaultSize := ADefaultSize;
end;

constructor TStructureFeatureClass.CreateFromTechnologyTree(Reader: TTechTreeReader);
var
   MaterialsList: specialize PlasticArray<TMaterialLineItem, specialize IncomparableUtils<TMaterialLineItem>>;
   ComponentName: UTF8String;
   Material: TMaterial;
   Quantity, Total: TQuantity32;
begin
   inherited Create();
   // feature: TStructureFeatureClass size 20m, materials (
   //    "Substructure": "Iron" x 700,
   //    "Logic": "Circuit Board" x 5,
   //    "Shell": "Iron" x 300,
   // ), minimum 805;
   MaterialsList.Prepare(2);
   Reader.Tokens.ReadIdentifier('size');
   FDefaultSize := ReadLength(Reader.Tokens);
   Reader.Tokens.ReadComma();
   Reader.Tokens.ReadIdentifier('materials');
   Reader.Tokens.ReadOpenParenthesis();
   Total := TQuantity32.Zero;
   repeat
      ComponentName := Reader.Tokens.ReadString();
      Reader.Tokens.ReadColon();
      Material := ReadMaterial(Reader);
      Reader.Tokens.ReadAsterisk();
      Quantity := TQuantity32.FromUnits(ReadNumber(Reader.Tokens, 1, TQuantity32.Max.AsCardinal)); // $R-
      MaterialsList.Push(TMaterialLineItem.Create(ComponentName, Material, Quantity));
      Total := Total + Quantity;
      if (Reader.Tokens.IsCloseParenthesis()) then
         break;
      Reader.Tokens.ReadComma();
   until Reader.Tokens.IsCloseParenthesis();
   Reader.Tokens.ReadCloseParenthesis();
   Reader.Tokens.ReadComma();
   Reader.Tokens.ReadIdentifier('minimum');
   FMinimumFunctionalQuantity := TQuantity32.FromUnits(ReadNumber(Reader.Tokens, 1, Total.AsCardinal)); // $R-
   FBillOfMaterials := MaterialsList.Distill();
   FTotalQuantityCache := ComputeTotalQuantity();
   FMassCache := ComputeMass();
end;

function TStructureFeatureClass.GetDefaultSize(): Double;
begin
   Result := FDefaultSize;
end;

function TStructureFeatureClass.GetFeatureNodeClass(): FeatureNodeReference;
begin
   Result := TStructureFeatureNode;
end;

function TStructureFeatureClass.InitFeatureNode(ASystem: TSystem): TFeatureNode;
begin
   Result := TStructureFeatureNode.Create(ASystem, Self, TQuantity32.Zero, 0);
end;

function TStructureFeatureClass.GetMaterialLineItem(Index: Cardinal): TMaterialLineItem;
begin
   Result := FBillOfMaterials[Index];
end;

function TStructureFeatureClass.GetMaterialLineItemCount(): Cardinal;
begin
   Result := Length(FBillOfMaterials); // $R-
end;

function TStructureFeatureClass.ComputeTotalQuantity(): TQuantity32;
var
   Index: Cardinal;
begin
   Result := TQuantity32.Zero;
   if (Length(FBillOfMaterials) > 0) then
   begin
      for Index := Low(FBillOfMaterials) to High(FBillOfMaterials) do // $R-
      begin
         Assert(FBillOfMaterials[Index].Quantity < TQuantity32.Max - Result);
         Result := Result + FBillOfMaterials[Index].Quantity; // $R-
      end;
   end;
end;

function TStructureFeatureClass.ComputeMass(): TMass;
var
   Index: Cardinal;
begin
   Result := TMass.Zero;
   if (Length(FBillOfMaterials) > 0) then
   begin
      for Index := Low(FBillOfMaterials) to High(FBillOfMaterials) do // $R-
      begin
         Result := Result + FBillOfMaterials[Index].Quantity * FBillOfMaterials[Index].Material.MassPerUnit; // $R-
      end;
   end;
end;


constructor TStructureFeatureNode.Create(ASystem: TSystem; AFeatureClass: TStructureFeatureClass; AMaterialsQuantity: TQuantity32; AStructuralIntegrity: Cardinal);
var
   Index: Cardinal;
begin
   inherited Create(ASystem);
   Assert(Assigned(AFeatureClass));
   FFeatureClass := AFeatureClass;
   if ((AMaterialsQuantity < FFeatureClass.TotalQuantity) or (AStructuralIntegrity < FFeatureClass.TotalQuantity.AsCardinal)) then
   begin
      InitBuildingState();
      FBuildingState^.StructuralIntegrity := AStructuralIntegrity;
      FBuildingState^.MaterialsQuantity := AMaterialsQuantity;
   end;
   SetLength(FDynastyKnowledge, FFeatureClass.BillOfMaterialsLength);
   {$IFOPT C+}
   Assert(FFeatureClass.BillOfMaterialsLength > 0);
   for Index := 0 to FFeatureClass.BillOfMaterialsLength - 1 do // $R-
   begin
      Assert(not Assigned(FDynastyKnowledge[Index].AsRawPointer));
   end;
   {$ENDIF}
end;

constructor TStructureFeatureNode.CreateFromJournal(Journal: TJournalReader; AFeatureClass: TFeatureClass; ASystem: TSystem);
begin
   Assert(Assigned(AFeatureClass));
   FFeatureClass := AFeatureClass as TStructureFeatureClass;
   inherited;
   SetLength(FDynastyKnowledge, FFeatureClass.BillOfMaterialsLength);
end;

procedure TStructureFeatureNode.InitBuildingState();
begin
   FBuildingState := New(PBuildingState);
   FBuildingState^ := Default(TBuildingState);
   Assert(not Assigned(FBuildingState^.PendingMaterial));
   {$IFOPT C+}
   FBuildingState^.AnchorTime := TTimeInMilliseconds.NegInfinity;
   Assert(FBuildingState^.MaterialsQuantityRate.IsNearZero);
   {$ENDIF}
end;

destructor TStructureFeatureNode.Destroy();
var
   Index: Cardinal;
begin
   if (Assigned(FBuildingState)) then
   begin
      if (Assigned(FBuildingState^.Region)) then
         FBuildingState^.Region.RemoveMaterialConsumer(Self);
      if (Assigned(FBuildingState^.Builder)) then
         FBuildingState^.Builder.StopBuilding(Self);
      if (Assigned(FBuildingState^.BuilderBus)) then
         FBuildingState^.BuilderBus.RemoveStructure(Self);
      if (Assigned(FBuildingState^.NextEvent)) then
         CancelEvent(FBuildingState^.NextEvent);
      Dispose(FBuildingState);
   end;
   for Index := 0 to FFeatureClass.BillOfMaterialsLength - 1 do // $R-
      FDynastyKnowledge[Index].Done();
   inherited;
end;

function TStructureFeatureNode.GetNextStructureMaterial(): TMaterial;
var
   Index: Cardinal;
   Level: TQuantity32;
begin
   if (Assigned(FBuildingState) and (FBuildingState^.MaterialsQuantity < FFeatureClass.TotalQuantity)) then
   begin
      Level := TQuantity32.Zero;
      for Index := 0 to FFeatureClass.BillOfMaterialsLength - 1 do // $R-
      begin
         Level := Level + FFeatureClass.BillOfMaterials[Index].Quantity;
         if (FBuildingState^.MaterialsQuantity < Level) then
         begin
            Result := FFeatureClass.BillOfMaterials[Index].Material;
            exit;
         end;
      end;
      Assert(False); // unreachable
   end;
   Result := nil;
end;

function TStructureFeatureNode.GetNextStructureQuantity(): TQuantity32;
var
   Index: Cardinal;
   Level: TQuantity32;
begin
   Assert(Assigned(GetNextStructureMaterial()));
   if (Assigned(FBuildingState) and (FBuildingState^.MaterialsQuantity < FFeatureClass.TotalQuantity)) then
   begin
      Level := TQuantity32.Zero;
      for Index := 0 to FFeatureClass.BillOfMaterialsLength - 1 do // $R-
      begin
         Level := Level + FFeatureClass.BillOfMaterials[Index].Quantity;
         if (FBuildingState^.MaterialsQuantity < Level) then
         begin
            Result := Level - FBuildingState^.MaterialsQuantity; // $R-
            exit;
         end;
      end;
      Assert(False); // unreachable
   end;
   Result := TQuantity32.Zero;
end;

function TStructureFeatureNode.GetMass(): TMass; // kg
var
   MaterialIndex: Cardinal;
   Remaining, CurrentQuantity: TQuantity32;
begin
   Result := TMass.Zero;
   if (Assigned(FBuildingState)) then
   begin
      Assert(Assigned(FFeatureClass));
      Assert(FFeatureClass.BillOfMaterialsLength > 0);
      Remaining := FBuildingState^.MaterialsQuantity;
      if (FBuildingState^.MaterialsQuantityRate.IsNotExactZero) then
         Remaining := Remaining + TQuantity32.FromQuantity64((System.Now - FBuildingState^.AnchorTime) * FBuildingState^.MaterialsQuantityRate); // $R-
      if (Remaining.IsPositive) then
      begin
         for MaterialIndex := 0 to FFeatureClass.BillOfMaterialsLength - 1 do // $R-
         begin
            CurrentQuantity := FFeatureClass.BillOfMaterials[MaterialIndex].Quantity;
            if (Remaining > CurrentQuantity) then
            begin
               Result := Result + CurrentQuantity * FFeatureClass.BillOfMaterials[MaterialIndex].Material.MassPerUnit;
               Remaining := Remaining - CurrentQuantity; // $R-
            end
            else
            begin
               Result := Result + Remaining * FFeatureClass.BillOfMaterials[MaterialIndex].Material.MassPerUnit;
               Remaining := TQuantity32.Zero;
               break;
            end;
         end;
      end;
      Assert(Remaining.IsZero);
   end
   else
      Result := FFeatureClass.Mass;
end;

function TStructureFeatureNode.GetMassFlowRate(): TMassRate;
begin
   Result := TMassRate.MZero;
   if (Assigned(FBuildingState) and FBuildingState^.MaterialsQuantityRate.IsNotExactZero) then
   begin
      Assert(Assigned(FBuildingState^.PendingMaterial));
      Result := FBuildingState^.MaterialsQuantityRate * FBuildingState^.PendingMaterial.MassPerUnit;
   end;
end;

function TStructureFeatureNode.GetSize(): Double;
begin
   Result := FFeatureClass.DefaultSize;
end;

function TStructureFeatureNode.HandleBusMessage(Message: TBusMessage): THandleBusMessageResult;
var
   RubbleMessage: TRubbleCollectionMessage;
   DismantleMessage: TDismantleMessage;
   TotalQuantity, CurrentQuantity: TQuantity32;
   Index: Cardinal;
   LineItem: TMaterialLineItem;
   Store: TStoreMaterialBusMessage;
begin
   if (Message is TCheckDisabledBusMessage) then
   begin
      if (Assigned(FBuildingState) and (FBuildingState^.StructuralIntegrity < FFeatureClass.MinimumFunctionalQuantity.AsCardinal)) then
         (Message as TCheckDisabledBusMessage).AddReason(drStructuralIntegrity);
   end
   else
   if (Message is TRubbleCollectionMessage) then
   begin
      RubbleMessage := Message as TRubbleCollectionMessage;
      RubbleMessage.Grow(FFeatureClass.BillOfMaterialsLength);
      Assert(FFeatureClass.BillOfMaterialsLength > 0);
      if (Assigned(FBuildingState)) then
      begin
         TotalQuantity := FBuildingState^.MaterialsQuantity;
         FBuildingState^.MaterialsQuantity := TQuantity32.Zero;
      end
      else
      begin
         TotalQuantity := FFeatureClass.TotalQuantity;
         InitBuildingState();
      end;
      for Index := 0 to FFeatureClass.BillOfMaterialsLength - 1 do // $R-
      begin
         LineItem := FFeatureClass.BillOfMaterials[Index];
         if (LineItem.Quantity < TotalQuantity) then
         begin
            RubbleMessage.AddMaterial(LineItem.Material, LineItem.Quantity);
            TotalQuantity := TotalQuantity - LineItem.Quantity;
         end
         else
         begin
            RubbleMessage.AddMaterial(LineItem.Material, TotalQuantity);
            break;
         end;
      end;
      MarkAsDirty([dkUpdateClients, dkUpdateJournal, dkNeedsHandleChanges]);
   end
   else
   if (Message is TDismantleMessage) then
   begin
      Writeln('Dismantling structure feature');
      DismantleMessage := Message as TDismantleMessage;
      Assert((not Assigned(Parent.Owner)) or (DismantleMessage.Owner = Parent.Owner));
      if (Assigned(FBuildingState)) then
      begin
         if (Assigned(FBuildingState^.Region)) then
         begin
            FBuildingState^.Region.RemoveMaterialConsumer(Self);
            FBuildingState^.Region := nil;
            FBuildingState^.MaterialsQuantityRate := TQuantityRate.QZero;
         end;
         if (Assigned(FBuildingState^.Builder)) then
         begin
            FBuildingState^.Builder.StopBuilding(Self);
            FBuildingState^.Builder := nil;
         end;
         if (Assigned(FBuildingState^.BuilderBus)) then
         begin
            FBuildingState^.BuilderBus.RemoveStructure(Self);
            FBuildingState^.BuilderBus := nil;
         end;
         Assert(Assigned(FBuildingState));
         TotalQuantity := FBuildingState^.MaterialsQuantity;
         FBuildingState^.MaterialsQuantity := TQuantity32.Zero;
         Writeln('  actively building, total quantity = ', TotalQuantity.ToString());
      end
      else
      begin
         TotalQuantity := FFeatureClass.TotalQuantity;
         InitBuildingState();
         Writeln('  structure was complete, total quantity = ', TotalQuantity.ToString());
      end;
      if (TotalQuantity.IsPositive) then
      begin
         Writeln('  total quantity was positive');
         for Index := 0 to FFeatureClass.BillOfMaterialsLength - 1 do // $R-
         begin
            LineItem := FFeatureClass.BillOfMaterials[Index];
            if (LineItem.Quantity < TotalQuantity) then
            begin
               CurrentQuantity := LineItem.Quantity;
            end
            else
            begin
               CurrentQuantity := TotalQuantity;
            end;
            Assert(CurrentQuantity <= TotalQuantity);
            Writeln('  attempting to store ', CurrentQuantity.ToString(), ' of ', LineItem.Material.Name);
            Store := TStoreMaterialBusMessage.Create(DismantleMessage.Target, DismantleMessage.Owner, LineItem.Material, CurrentQuantity);
            DismantleMessage.Target.Parent.Parent.InjectBusMessage(Store);
            if (Store.RemainingQuantity.IsPositive) then
            begin
               DismantleMessage.AddExcessMaterial(LineItem.Material, Store.RemainingQuantity);
               Writeln('  ...was left with ', Store.RemainingQuantity.ToString(), ' to put in rubble pile');
            end;
            FreeAndNil(Store);
            TotalQuantity := TotalQuantity - CurrentQuantity;
            if (TotalQuantity.IsZero) then
               break;
         end;
      end;
      MarkAsDirty([dkUpdateClients, dkUpdateJournal, dkNeedsHandleChanges]);
   end;
   Result := inherited;
end;

procedure TStructureFeatureNode.ResetDynastyNotes(OldDynasties: TDynastyIndexHashTable; NewDynasties: TDynasty.TArray);
var
   Index: Cardinal;
begin
   Assert(Length(FDynastyKnowledge) = FFeatureClass.BillOfMaterialsLength);
   Assert(FFeatureClass.BillOfMaterialsLength > 0);
   for Index := 0 to FFeatureClass.BillOfMaterialsLength - 1 do // $R-
      FDynastyKnowledge[Index].Init(Length(NewDynasties)); // $R-
end;

procedure TStructureFeatureNode.ResetVisibility();
var
   Index: Cardinal;
begin
   Assert(FFeatureClass.BillOfMaterialsLength > 0);
   for Index := 0 to FFeatureClass.BillOfMaterialsLength - 1 do // $R-
      FDynastyKnowledge[Index].Reset();
end;

procedure TStructureFeatureNode.HandleKnowledge(const DynastyIndex: Cardinal; const Sensors: ISensorsProvider);
var
   Index: Cardinal;
begin
   Assert(FFeatureClass.BillOfMaterialsLength > 0);
   for Index := 0 to FFeatureClass.BillOfMaterialsLength - 1 do // $R-
   begin
      if (Sensors.Knows(FFeatureClass.BillOfMaterials[Index].Material)) then
         FDynastyKnowledge[Index].SetEntry(DynastyIndex, True);
   end;
end;

procedure TStructureFeatureNode.Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter);
var
   Index, StructuralIntegrity: Cardinal;
   Remaining, Quantity, TotalQuantityAlreadyBuilt: TQuantity32;
   Visibility: TVisibility;
   ClassKnown: Boolean;
begin
   Visibility := Parent.ReadVisibilityFor(DynastyIndex);
   if (dmDetectable * Visibility <> []) then
   begin
      Writer.WriteCardinal(fcStructure);
      ClassKnown := dmClassKnown in Visibility;
      if (Assigned(FBuildingState)) then
      begin
         TotalQuantityAlreadyBuilt := FBuildingState^.MaterialsQuantity;
         if (FBuildingState^.MaterialsQuantityRate.IsNotExactZero) then
            TotalQuantityAlreadyBuilt := TotalQuantityAlreadyBuilt + TQuantity32.FromQuantity64((System.Now - FBuildingState^.AnchorTime) * FBuildingState^.MaterialsQuantityRate); // $R-
      end
      else
      begin
         TotalQuantityAlreadyBuilt := FFeatureClass.TotalQuantity;
      end;
      Assert(TotalQuantityAlreadyBuilt <= FFeatureClass.TotalQuantity);
      Remaining := TotalQuantityAlreadyBuilt;
      Assert(FFeatureClass.BillOfMaterialsLength > 0);
      for Index := 0 to FFeatureClass.BillOfMaterialsLength - 1 do // $R-
      begin
         if ((Remaining.IsPositive) or ClassKnown) then
         begin
            Quantity := FFeatureClass.BillOfMaterials[Index].Quantity;
            if (ClassKnown) then
            begin
               Writer.WriteCardinal(Quantity.AsCardinal);
               Writer.WriteStringReference(FFeatureClass.BillOfMaterials[Index].ComponentName);
            end
            else
            begin
               Assert(Remaining.IsPositive);
               // expected quantity unknown
               if (Remaining < Quantity) then
                  Writer.WriteCardinal(Remaining.AsCardinal)
               else
                  Writer.WriteCardinal(Quantity.AsCardinal);
               Writer.WriteStringReference(''); // component name unknown
            end;
            Writer.WriteStringReference(FFeatureClass.BillOfMaterials[Index].Material.AmbiguousName);
            if (FDynastyKnowledge[Index].GetEntry(DynastyIndex)) then
            begin
               Writer.WriteInt32(FFeatureClass.BillOfMaterials[Index].Material.ID);
            end
            else
            begin
               Writer.WriteInt32(0);
            end;
            if (Remaining < Quantity) then
               Remaining := TQuantity32.Zero
            else
               Remaining := Remaining - Quantity;
         end
         else
            break;
      end;
      Writer.WriteCardinal(0); // material terminator marker
      if (Assigned(FBuildingState)) then
      begin
         if (Assigned(FBuildingState^.Builder)) then
            Writer.WriteCardinal(FBuildingState^.Builder.Parent.ID(DynastyIndex))
         else
            Writer.WriteCardinal(0);
         Writer.WriteCardinal(TotalQuantityAlreadyBuilt.AsCardinal);
         Writer.WriteDouble(FBuildingState^.MaterialsQuantityRate.AsDouble);
         StructuralIntegrity := FBuildingState^.StructuralIntegrity;
         if (FBuildingState^.StructuralIntegrityRate.IsNotExactZero and Assigned(FBuildingState^.NextEvent)) then
         begin
            Assert(not FBuildingState^.AnchorTime.IsInfinite);
            Inc(StructuralIntegrity, Round((System.Now - FBuildingState^.AnchorTime) * FBuildingState^.StructuralIntegrityRate));
         end;
         if (StructuralIntegrity > TotalQuantityAlreadyBuilt.AsCardinal) then
            StructuralIntegrity := TotalQuantityAlreadyBuilt.AsCardinal;
         Writer.WriteCardinal(StructuralIntegrity);
         Writer.WriteDouble(FBuildingState^.StructuralIntegrityRate.AsDouble);
      end
      else
      begin
         Writer.WriteCardinal(0);
         Writer.WriteCardinal(FFeatureClass.TotalQuantity.AsCardinal);
         Writer.WriteDouble(0.0);
         Writer.WriteCardinal(FFeatureClass.TotalQuantity.AsCardinal);
         Writer.WriteDouble(0.0);
      end;
      if (ClassKnown) then
      begin
         Writer.WriteCardinal(FFeatureClass.MinimumFunctionalQuantity.AsCardinal);
      end
      else
      begin
         Writer.WriteCardinal(0);
      end;
   end;
end;

procedure TStructureFeatureNode.UpdateJournal(Journal: TJournalWriter);
begin
   if (Assigned(FBuildingState)) then
   begin
      Journal.WriteCardinal(FBuildingState^.MaterialsQuantity.AsCardinal);
      Journal.WriteCardinal(FBuildingState^.StructuralIntegrity);
      Journal.WriteCardinal(FBuildingState^.Priority);
   end
   else
   begin
      Journal.WriteCardinal(FFeatureClass.TotalQuantity.AsCardinal);
      Journal.WriteCardinal(FFeatureClass.TotalQuantity.AsCardinal);
      Journal.WriteCardinal(0);
   end;
end;

procedure TStructureFeatureNode.ApplyJournal(Journal: TJournalReader);
var
   MaterialsQuantity: TQuantity32;
   StructuralIntegrity, Priority: Cardinal;
begin
   MaterialsQuantity := TQuantity32.FromUnits(Journal.ReadCardinal());
   StructuralIntegrity := Journal.ReadCardinal();
   Priority := Journal.ReadCardinal();
   if ((MaterialsQuantity < FFeatureClass.TotalQuantity) or (StructuralIntegrity < FFeatureClass.TotalQuantity.AsCardinal)) then
   begin
      if (not Assigned(FBuildingState)) then
         InitBuildingState();
      FBuildingState^.MaterialsQuantity := MaterialsQuantity;
      FBuildingState^.StructuralIntegrity := StructuralIntegrity;
      FBuildingState^.Priority := Priority; // $R-
   end
   else
   begin
      Assert(Priority = 0);
      if (Assigned(FBuildingState)) then
      begin
         Assert(not Assigned(FBuildingState^.NextEvent));
         Assert(not Assigned(FBuildingState^.Region));
         Assert(not Assigned(FBuildingState^.Builder));
         Assert(not Assigned(FBuildingState^.BuilderBus));
         Dispose(FBuildingState);
         FBuildingState := nil;
      end;
   end;
end;

procedure TStructureFeatureNode.DescribeExistentiality(var IsDefinitelyReal, IsDefinitelyGhost: Boolean);
begin
   IsDefinitelyReal := (not Assigned(FBuildingState)) or (FBuildingState^.MaterialsQuantity.IsPositive);
   IsDefinitelyGhost := (Assigned(FBuildingState)) and (FBuildingState^.MaterialsQuantity.IsZero);
end;

procedure TStructureFeatureNode.HandleChanges();
var
   Message: TRegisterStructureMessage;
begin
   if (Assigned(Parent.Owner)) then
   begin
      if (Assigned(FBuildingState) and (not Assigned(FBuildingState^.BuilderBus)) and (not (bsNoBuilderBus in FBuildingState^.Flags))) then
      begin
         Message := TRegisterStructureMessage.Create(Self);
         if (InjectBusMessage(Message) <> irHandled) then
         begin
            Include(FBuildingState^.Flags, bsNoBuilderBus); // TODO: remove this when the parent changes
         end;
         FreeAndNil(Message);
      end;
      if (Assigned(FBuildingState) and Assigned(FBuildingState^.Builder) and (not (bsTriggered in FBuildingState^.Flags))) then
      begin
         TriggerBuilding();
      end;
   end;
   inherited;
end;

procedure TStructureFeatureNode.BuilderBusConnected(Bus: TBuilderBusFeatureNode); // must come from builder bus
begin
   Assert(Assigned(FBuildingState));
   FBuildingState^.BuilderBus := Bus;
end;

procedure TStructureFeatureNode.BuilderBusReset(); // must come from builder bus, can assume all other participants were also reset
begin
   Assert(Assigned(FBuildingState));
   FBuildingState^.BuilderBus := nil;
end;

procedure TStructureFeatureNode.StartBuilding(Builder: TBuilderFeatureNode; BuildRate: TRate); // called by builder
begin
   Assert(Assigned(FBuildingState));
   Assert((not Assigned(FBuildingState^.NextEvent)) or (FBuildingState^.AnchorTime = System.Now));
   Assert(not Assigned(FBuildingState^.PendingMaterial));
   Assert(FBuildingState^.PendingQuantity.IsZero);
   FBuildingState^.Builder := Builder;
   FBuildingState^.StructuralIntegrityRate := BuildRate;
   TriggerBuilding();
end;

procedure TStructureFeatureNode.UpdateBuildingRate(BuildRate: TRate);
begin
   FBuildingState^.StructuralIntegrityRate := BuildRate;
   Exclude(FBuildingState^.Flags, bsTriggered);
   MarkAsDirty([dkUpdateClients, dkNeedsHandleChanges]);
end;

procedure TStructureFeatureNode.TriggerBuilding();
var
   Injected: TInjectBusMessageResult;
   Message: TRegisterMaterialConsumerBusMessage;
begin
   Writeln(DebugName, ' :: TriggerBuilding');
   Assert(Assigned(Parent.Owner));
   Assert(not (bsTriggered in FBuildingState^.Flags));
   FetchMaterials();
   if (Assigned(FBuildingState^.PendingMaterial)) then
   begin
      if (not Assigned(FBuildingState^.Region)) then
      begin
         Message := TRegisterMaterialConsumerBusMessage.Create(Self);
         Injected := InjectBusMessage(Message);
         if (Injected <> irHandled) then
         begin
            Include(FBuildingState^.Flags, bsNoRegion);
            Assert(FBuildingState^.StructuralIntegrityRate.IsNearZero);
         end;
         FreeAndNil(Message);
      end;
   end
   else
   if (FBuildingState^.StructuralIntegrity = FFeatureClass.TotalQuantity.AsCardinal) then
   begin
      // we're done!
      if (Assigned(FBuildingState^.Region)) then
      begin
         FBuildingState^.Region.RemoveMaterialConsumer(Self);
         FBuildingState^.Region := nil;
         FBuildingState^.MaterialsQuantityRate := TQuantityRate.QZero;
      end;
      Assert(Assigned(FBuildingState^.Builder));
      FBuildingState^.Builder.StopBuilding(Self);
      FBuildingState^.Builder := nil;
      Assert(Assigned(FBuildingState^.BuilderBus));
      FBuildingState^.BuilderBus.RemoveStructure(Self);
      FBuildingState^.BuilderBus := nil;
      if (Assigned(FBuildingState^.NextEvent)) then
      begin
         Assert(False);
         CancelEvent(FBuildingState^.NextEvent);
      end;
      Dispose(FBuildingState);
      FBuildingState := nil;
   end
   else
   begin
      // we're done with materials, but not structural integrity
      Assert(FBuildingState^.StructuralIntegrity < FFeatureClass.TotalQuantity.AsCardinal);
      Assert(Assigned(FBuildingState^.Builder));
      if (Assigned(FBuildingState^.Region)) then
      begin
         FBuildingState^.Region.RemoveMaterialConsumer(Self);
         FBuildingState^.Region := nil;
         FBuildingState^.MaterialsQuantityRate := TQuantityRate.QZero;
      end;
      Assert(not Assigned(FBuildingState^.NextEvent));
      Assert(FBuildingState^.AnchorTime.IsInfinite);
      Assert(FBuildingState^.MaterialsQuantityRate.IsNearZero);
      Assert(FBuildingState^.StructuralIntegrityRate.IsNotNearZero);
      RescheduleNextEvent();
   end;
   if (Assigned(FBuildingState)) then
      Include(FBuildingState^.Flags, bsTriggered);
end;

procedure TStructureFeatureNode.FetchMaterials();
var
   Changes: TDirtyKinds;
   NextMaterial: TMaterial;
   NextQuantity: TQuantity32;
   Index: Cardinal;
   Level: TQuantity32;
   Obtain: TObtainMaterialBusMessage;
   ObtainedMaterial: TMaterialQuantity;
begin
   Writeln(DebugName, ' :: FetchMaterials');
   Assert(Assigned(Parent.Owner));
   Changes := [];
   Assert(Assigned(FBuildingState));
   Assert(not Assigned(FBuildingState^.NextEvent));
   Assert(not Assigned(FBuildingState^.PendingMaterial));
   Assert(not (bsTriggered in FBuildingState^.Flags));
   Assert(FBuildingState^.PendingQuantity.IsZero);
   Level := TQuantity32.Zero;
   Index := 0;
   NextMaterial := nil;
   NextQuantity := TQuantity32.Zero;
   while (FBuildingState^.MaterialsQuantity < FFeatureClass.TotalQuantity) do
   begin
      Assert(Index < FFeatureClass.BillOfMaterialsLength);
      Level := Level + FFeatureClass.BillOfMaterials[Index].Quantity;
      if (FBuildingState^.MaterialsQuantity < Level) then
      begin
         // TODO: check if the material is known to the dynasty
         // if it is not, then we cannot fetch it.
         NextMaterial := FFeatureClass.BillOfMaterials[Index].Material;
         NextQuantity := Level - FBuildingState^.MaterialsQuantity; // $R-
         Assert(NextQuantity.IsPositive);
         Obtain := TObtainMaterialBusMessage.Create(Parent.Owner, NextMaterial, NextQuantity);
         InjectBusMessage(Obtain);
         ObtainedMaterial := Obtain.TransferredManifest;
         if (Assigned(ObtainedMaterial.Material)) then
         begin
            Assert(ObtainedMaterial.Material = NextMaterial);
            Assert(ObtainedMaterial.Quantity.IsPositive);
            Assert(ObtainedMaterial.Quantity <= NextQuantity);
            if (FBuildingState^.MaterialsQuantity.IsZero) then
               Include(Changes, dkAffectsVisibility);
            FBuildingState^.MaterialsQuantity := FBuildingState^.MaterialsQuantity + TQuantity32.FromQuantity64(ObtainedMaterial.Quantity);
            NextQuantity := NextQuantity - TQuantity32.FromQuantity64(ObtainedMaterial.Quantity);
            Include(Changes, dkUpdateClients);
            Include(Changes, dkUpdateJournal);
         end;
         FreeAndNil(Obtain);
         if (NextQuantity.IsPositive) then
            break;
         NextMaterial := nil;
      end;
      Inc(Index);
   end;
   FBuildingState^.PendingMaterial := NextMaterial;
   FBuildingState^.PendingQuantity := NextQuantity;
   Assert((FBuildingState^.PendingQuantity.IsPositive) = (Assigned(FBuildingState^.PendingMaterial)));
   MarkAsDirty(Changes);
end;

procedure TStructureFeatureNode.StopBuilding(); // called by builder
var
   Delta: Double;
   Changes: TDirtyKinds;
begin
   Assert(Assigned(FBuildingState));
   Assert(FBuildingState^.StructuralIntegrityRate.IsNotNearZero);
   FBuildingState^.Builder := nil;
   if (Assigned(FBuildingState^.Region)) then
   begin
      if (FBuildingState^.MaterialsQuantityRate.IsPositive) then
      begin
         Assert(Assigned(FBuildingState^.PendingMaterial));
         FBuildingState^.Region.SyncForMaterialConsumer();
         // DeliverMaterialConsumer() will be called here
      end;
      FBuildingState^.Region.RemoveMaterialConsumer(Self);
      FBuildingState^.Region := nil;
      FBuildingState^.MaterialsQuantityRate := TQuantityRate.QZero;
   end
   else
   begin
      Assert(FBuildingState^.MaterialsQuantityRate.IsNearZero);
      if (Assigned(FBuildingState^.NextEvent)) then
      begin
         Assert(not FBuildingState^.AnchorTime.IsInfinite);
         Delta := (System.Now - FBuildingState^.AnchorTime) * FBuildingState^.StructuralIntegrityRate;
         Changes := [dkUpdateJournal, dkUpdateClients];
         if (FBuildingState^.IncStructuralIntegrity(Delta, FFeatureClass.MinimumFunctionalQuantity.AsCardinal)) then
            Include(Changes, dkNeedsHandleChanges);
         MarkAsDirty(Changes);
         Assert(FBuildingState^.StructuralIntegrity <= FFeatureClass.TotalQuantity.AsCardinal);
      end;
   end;
   Assert(Assigned(FBuildingState));
   FBuildingState^.PendingMaterial := nil;
   FBuildingState^.PendingQuantity := TQuantity32.Zero;
   FBuildingState^.StructuralIntegrityRate := TRate.Zero;
   Exclude(FBuildingState^.Flags, bsTriggered);
   if (Assigned(FBuildingState^.NextEvent)) then
   begin
      CancelEvent(FBuildingState^.NextEvent);
      {$IFOPT C+} FBuildingState^.AnchorTime := TTimeInMilliseconds.NegInfinity; {$ENDIF}
      Assert(FBuildingState^.MaterialsQuantityRate.IsNearZero);
   end;
end;

function TStructureFeatureNode.GetAsset(): TAssetNode;
begin
   Result := Parent;
end;

function TStructureFeatureNode.GetPriority(): TPriority;
begin
   Assert(Assigned(FBuildingState));
   Result := FBuildingState^.Priority;
end;

procedure TStructureFeatureNode.SetAutoPriority(Value: TAutoPriority);
begin
   Assert(Assigned(FBuildingState));
   FBuildingState^.Priority := Value;
   MarkAsDirty([dkUpdateJournal]);
end;

function TStructureFeatureNode.GetDynasty(): TDynasty;
begin
   Result := Parent.Owner;
end;

function TStructureFeatureNode.GetMaterialConsumerMaterial(): TMaterial;
begin
   Assert(Assigned(FBuildingState));
   Result := FBuildingState^.PendingMaterial;
end;

function TStructureFeatureNode.GetMaterialConsumerMaxDelivery(): TQuantity32;
begin
   Assert(Assigned(FBuildingState));
   Result := FBuildingState^.PendingQuantity;
end;

function TStructureFeatureNode.GetMaterialConsumerCurrentRate(): TQuantityRate; // quantity per second, cannot be infinite
begin
   Assert(Assigned(FBuildingState));
   Result := FBuildingState^.MaterialsQuantityRate;
end;

procedure TStructureFeatureNode.SetMaterialConsumerRegion(Region: TRegionFeatureNode);
begin
   Assert(Assigned(FBuildingState));
   Assert(not Assigned(FBuildingState^.Region));
   Assert(FBuildingState^.MaterialsQuantityRate.IsNearZero);
   Assert(Assigned(FBuildingState^.PendingMaterial));
   Assert(FBuildingState^.PendingQuantity.IsPositive);
   FBuildingState^.Region := Region;
end;

procedure TStructureFeatureNode.StartMaterialConsumer(ActualRate: TQuantityRate); // quantity per second
begin
   Assert(Assigned(FBuildingState));
   Assert(Assigned(FBuildingState^.Region));
   Assert(Assigned(FBuildingState^.PendingMaterial));
   Assert(FBuildingState^.PendingQuantity.IsPositive);
   FBuildingState^.MaterialsQuantityRate := ActualRate;
   RescheduleNextEvent();
   MarkAsDirty([dkUpdateClients]);
end;

procedure TStructureFeatureNode.DeliverMaterialConsumer(Delivery: TQuantity32);
var
   Duration: TMillisecondsDuration;
begin
   Assert(Assigned(FBuildingState));
   Assert(Assigned(FBuildingState^.PendingMaterial));
   Assert(Assigned(FBuildingState^.Region));
   Assert(FBuildingState^.PendingQuantity.IsPositive);
   Assert(Delivery <= FBuildingState^.PendingQuantity);
   if (FBuildingState^.StructuralIntegrityRate.IsNotExactZero and Assigned(FBuildingState^.NextEvent)) then
      Duration := System.Now - FBuildingState^.AnchorTime; // compute this before checking if we need to reset to static regime below
   if (Delivery.IsPositive) then
   begin
      FBuildingState^.MaterialsQuantity := FBuildingState^.MaterialsQuantity + Delivery;
      FBuildingState^.PendingQuantity := FBuildingState^.PendingQuantity - Delivery;
      if (FBuildingState^.PendingQuantity.IsZero) then
      begin
         FBuildingState^.PendingMaterial := nil;
         FBuildingState^.MaterialsQuantityRate := TQuantityRate.QZero;
         if (Assigned(FBuildingState^.NextEvent)) then
         begin
            CancelEvent(FBuildingState^.NextEvent);
            {$IFOPT C+} FBuildingState^.AnchorTime := TTimeInMilliseconds.NegInfinity; {$ENDIF}
         end;
         // Retrigger building:
         Exclude(FBuildingState^.Flags, bsTriggered);
         MarkAsDirty([dkUpdateClients, dkUpdateJournal, dkNeedsHandleChanges]);
      end;
   end;
   if (FBuildingState^.StructuralIntegrityRate.IsNotExactZero and (FBuildingState^.StructuralIntegrity < FBuildingState^.MaterialsQuantity.AsCardinal)) then
   begin
      if (Duration.IsNotZero) then
      begin
         FBuildingState^.IncStructuralIntegrity(Duration * FBuildingState^.StructuralIntegrityRate, FFeatureClass.MinimumFunctionalQuantity.AsCardinal); // result ignored, we always do dkNeedsHandleChanges
         Assert((FBuildingState^.PendingQuantity.IsPositive) = (Assigned(FBuildingState^.PendingMaterial)));
         MarkAsDirty([dkUpdateClients, dkUpdateJournal, dkNeedsHandleChanges]);
      end;
   end;
end;

procedure TStructureFeatureNode.DisconnectMaterialConsumer();
begin
   // DeliverMaterialConsumer will be called first
   Assert(Assigned(FBuildingState));
   Assert(Assigned(FBuildingState^.Region));
   FBuildingState^.Region := nil;
   FBuildingState^.MaterialsQuantityRate := TQuantityRate.QZero;
   if (Assigned(FBuildingState^.NextEvent)) then
   begin
      CancelEvent(FBuildingState^.NextEvent);
      {$IFOPT C+} FBuildingState^.AnchorTime := TTimeInMilliseconds.NegInfinity; {$ENDIF}
   end;
   // Region is going away, so we better try to find another; retrigger:
   Exclude(FBuildingState^.Flags, bsTriggered);
   MarkAsDirty([dkNeedsHandleChanges]);
end;

function TStructureFeatureNode.GetPendingFraction(): PFraction32;
begin
   Assert(Assigned(FBuildingState));
   Result := @(FBuildingState^.PendingFraction);
end;

procedure TStructureFeatureNode.RescheduleNextEvent();
var
   RemainingTime: TMillisecondsDuration;
   TimeUntilMaterialFunctional, TimeUntilIntegrityFunctional: TMillisecondsDuration;
begin
   Assert(Assigned(FBuildingState));
   if (Assigned(FBuildingState^.NextEvent)) then
   begin
      CancelEvent(FBuildingState^.NextEvent);
      {$IFOPT C+} FBuildingState^.AnchorTime := TTimeInMilliseconds.NegInfinity; {$ENDIF}
   end;
   if (Assigned(FBuildingState^.Region) and FBuildingState^.MaterialsQuantityRate.IsNotExactZero) then
   begin
      Assert(FBuildingState^.PendingQuantity.IsPositive);
      Assert(FBuildingState^.AnchorTime.IsInfinite);
      RemainingTime := FBuildingState^.PendingQuantity / FBuildingState^.MaterialsQuantityRate;
   end
   else
   if (FBuildingState^.StructuralIntegrityRate.IsNotExactZero and (FBuildingState^.MaterialsQuantity.AsCardinal > FBuildingState^.StructuralIntegrity)) then
   begin
      Assert((FBuildingState^.PendingQuantity.IsPositive) xor (FBuildingState^.MaterialsQuantity = FFeatureClass.TotalQuantity));
      RemainingTime := (FBuildingState^.MaterialsQuantity.AsCardinal - FBuildingState^.StructuralIntegrity) / FBuildingState^.StructuralIntegrityRate;
      // we may shorten this in case we would hit the structural integrity sooner, see below
   end
   else
   begin
      // nothing to wait for
      exit;
   end;
   if (FBuildingState^.StructuralIntegrity < FFeatureClass.MinimumFunctionalQuantity.AsCardinal) then
   begin
      if (FBuildingState^.MaterialsQuantity < FFeatureClass.MinimumFunctionalQuantity) then
      begin
         if (FBuildingState^.MaterialsQuantityRate.IsExactZero) then
         begin
            TimeUntilMaterialFunctional := TMillisecondsDuration.Infinity;
         end
         else
         begin
            TimeUntilMaterialFunctional := (FFeatureClass.MinimumFunctionalQuantity - FBuildingState^.MaterialsQuantity) / FBuildingState^.MaterialsQuantityRate;
         end;
      end
      else
      begin
         TimeUntilMaterialFunctional := TMillisecondsDuration.Zero;
      end;
      if (FBuildingState^.StructuralIntegrityRate.IsExactZero) then
      begin
         TimeUntilIntegrityFunctional := TMillisecondsDuration.Infinity;
      end
      else
      begin
         TimeUntilIntegrityFunctional := (FFeatureClass.MinimumFunctionalQuantity.AsCardinal - FBuildingState^.StructuralIntegrity) / FBuildingState^.StructuralIntegrityRate;
      end;
      if (TimeUntilMaterialFunctional > TimeUntilIntegrityFunctional) then
         TimeUntilIntegrityFunctional := TimeUntilMaterialFunctional;
      if ((TimeUntilIntegrityFunctional.IsPositive) and (TimeUntilIntegrityFunctional < RemainingTime)) then
      begin
         RemainingTime := TimeUntilIntegrityFunctional;
      end;
   end;
   Assert(RemainingTime.IsNotZero);
   FBuildingState^.NextEvent := System.ScheduleEvent(RemainingTime, @HandleEvent, Self);
   FBuildingState^.AnchorTime := System.Now;
end;

procedure TStructureFeatureNode.HandleEvent(var Data);
var
   Duration: TMillisecondsDuration;
   Changes: TDirtyKinds;
begin
   Writeln(DebugName, ' :: HandleEvent');
   // if we get here, we're in one of these states:
   //   - we were hoping to build ourselves, and we have waited long enough that we should have all the materials we need
   //       - and that worked out and we are entirely done
   //       - and that worked out but we still need to heal
   //       - and that worked out but we have more different materials to build
   //       - and for some reason that didn't quite work out so we have more of this material to build
   //   - we were hoping ot heal ourselves, and we have waited long enough that we should be healed up to the current max
   //       - and that means we're done
   //       - and we're now blocked on materials
   Assert(Assigned(FBuildingState));
   Assert(Assigned(FBuildingState^.NextEvent));
   FBuildingState^.NextEvent := nil; // this must be done early because the pointer is no longer valid so we don't want to risk canceling it
   // Do not reset anchor time until after DeliverMaterialConsumer might have been called.
   if (Assigned(FBuildingState^.Region)) then
   begin
      if (FBuildingState^.MaterialsQuantityRate.IsNotExactZero) then
      begin
         Assert(Assigned(FBuildingState^.PendingMaterial));
         FBuildingState^.Region.SyncForMaterialConsumer();
         // DeliverMaterialConsumer() will be called here, and it handles the structural integrity stuff
      end
      else
      begin
         DeliverMaterialConsumer(TQuantity32.Zero); // update structural integrity
      end;
      if (FBuildingState^.StructuralIntegrity = FFeatureClass.TotalQuantity.AsCardinal) then
      begin
         // we're done!
         Assert(FBuildingState^.MaterialsQuantity = FFeatureClass.TotalQuantity);
         Assert(Assigned(FBuildingState^.Region));
         FBuildingState^.Region.RemoveMaterialConsumer(Self);
         Assert(Assigned(FBuildingState^.Builder));
         FBuildingState^.Builder.StopBuilding(Self);
         Assert(Assigned(FBuildingState^.BuilderBus));
         FBuildingState^.BuilderBus.RemoveStructure(Self);
         Assert(not Assigned(FBuildingState^.NextEvent));
         Dispose(FBuildingState);
         FBuildingState := nil;
      end
      else
      if (FBuildingState^.MaterialsQuantity = FFeatureClass.TotalQuantity) then
      begin
         // we're done with materials, not structural integrity
         FBuildingState^.Region.RemoveMaterialConsumer(Self);
         FBuildingState^.Region := nil;
         FBuildingState^.MaterialsQuantityRate := TQuantityRate.QZero;
         Assert(not Assigned(FBuildingState^.PendingMaterial)); // reset by DeliverMaterialConsumer
         Assert(FBuildingState^.PendingQuantity.IsZero); // reset by DeliverMaterialConsumer
         Assert(FBuildingState^.StructuralIntegrity < FFeatureClass.TotalQuantity.AsCardinal);
         Assert(FBuildingState^.StructuralIntegrityRate.IsNotNearZero);
         {$IFOPT C+} FBuildingState^.AnchorTime := TTimeInMilliseconds.NegInfinity; {$ENDIF}
         Assert(FBuildingState^.MaterialsQuantityRate.IsNearZero);
         Assert(not (bsTriggered in FBuildingState^.Flags)); // so we're going to get retriggered
      end
      else
      if (not Assigned(FBuildingState^.PendingMaterial)) then
      begin
         // we still have materials to get, but we don't yet know what is next
         Assert(FBuildingState^.PendingQuantity.IsZero); // reset by DeliverMaterialConsumer
         FBuildingState^.Region.SyncForMaterialConsumer();
         Assert(FBuildingState^.MaterialsQuantityRate.IsNearZero); // reset by ReconsiderMaterialConsumer calling PauseMaterialConsumer
         Assert(FBuildingState^.StructuralIntegrity < FFeatureClass.TotalQuantity.AsCardinal);
         Assert(FBuildingState^.StructuralIntegrityRate.IsNotNearZero);
         {$IFOPT C+} FBuildingState^.AnchorTime := TTimeInMilliseconds.NegInfinity; {$ENDIF}
         Assert(FBuildingState^.MaterialsQuantityRate.IsExactZero);
      end
      else
      begin
         Assert(FBuildingState^.PendingQuantity.IsPositive);
         Assert(FBuildingState^.StructuralIntegrity < FFeatureClass.TotalQuantity.AsCardinal);
         Assert(FBuildingState^.StructuralIntegrityRate.IsNotNearZero);
         {$IFOPT C+} FBuildingState^.AnchorTime := TTimeInMilliseconds.NegInfinity; {$ENDIF}
         Assert(bsTriggered in FBuildingState^.Flags); // so we're NOT going to get retriggered
         RescheduleNextEvent();
      end;
   end
   else
   if (FBuildingState^.StructuralIntegrityRate.IsNotExactZero and (FBuildingState^.MaterialsQuantity.AsCardinal > FBuildingState^.StructuralIntegrity)) then
   begin
      Duration := System.Now - FBuildingState^.AnchorTime;
      Assert(Duration.IsNotZero and Duration.IsPositive);
      Changes := [dkUpdateClients, dkUpdateJournal];
      if (FBuildingState^.IncStructuralIntegrity(Duration * FBuildingState^.StructuralIntegrityRate, FFeatureClass.MinimumFunctionalQuantity.AsCardinal)) then
         Include(Changes, dkNeedsHandleChanges);
      MarkAsDirty(Changes);
      if (FBuildingState^.StructuralIntegrity = FFeatureClass.TotalQuantity.AsCardinal) then
      begin
         // we're done!
         Assert(not Assigned(FBuildingState^.Region));
         Assert(FBuildingState^.MaterialsQuantityRate.IsExactZero);
         Assert(Assigned(FBuildingState^.Builder));
         FBuildingState^.Builder.StopBuilding(Self);
         Assert(Assigned(FBuildingState^.BuilderBus));
         FBuildingState^.BuilderBus.RemoveStructure(Self);
         {$IFOPT C+} FBuildingState^.AnchorTime := TTimeInMilliseconds.NegInfinity; {$ENDIF}
         Assert(FBuildingState^.MaterialsQuantityRate.IsExactZero);
         Assert(not Assigned(FBuildingState^.NextEvent));
         Dispose(FBuildingState);
         FBuildingState := nil;
      end
      else
      begin
         // we're not yet done, so retrigger ourselves to figure out why
         {$IFOPT C+} FBuildingState^.AnchorTime := TTimeInMilliseconds.NegInfinity; {$ENDIF}
         Assert(FBuildingState^.MaterialsQuantityRate.IsExactZero);
         // Retrigger building:
         Exclude(FBuildingState^.Flags, bsTriggered);
         MarkAsDirty([dkUpdateClients, dkUpdateJournal, dkNeedsHandleChanges]);
      end;
   end;
end;

function TStructureFeatureNode.HandleCommand(PlayerDynasty: TDynasty; Command: UTF8String; var Message: TMessage): Boolean;
begin
   if (Command = ccDismantle) then
   begin
      System.Encyclopedia.Dismantle(Parent, Message);
      Result := True;
   end
   else
      Result := False;
end;

initialization
   RegisterFeatureClass(TStructureFeatureClass);
end.