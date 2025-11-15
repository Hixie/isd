{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit structure;

interface

uses
   systems, serverstream, materials, techtree, builders, region, time, commonbuses, systemdynasty;

type
   TStructureFeatureClass = class;

   TMaterialLineItem = record // 24 bytes
      ComponentName: UTF8String;
      Material: TMaterial;
      Quantity: Cardinal; // units of material
      constructor Create(AComponentName: UTF8String; AMaterial: TMaterial; AQuantity: Cardinal);
   end;

   TMaterialLineItemArray = array of TMaterialLineItem;

   TStructureFeatureClass = class(TFeatureClass)
   strict private
      FDefaultSize: Double;
      FBillOfMaterials: TMaterialLineItemArray;
      FTotalQuantityCache: Cardinal; // computed on creation
      FMinimumFunctionalQuantity: Cardinal; // 0.0 .. TotalQuantity
      FMassCache: Double;
   strict protected
      function GetFeatureNodeClass(): FeatureNodeReference; override;
   protected
      function GetMaterialLineItem(Index: Cardinal): TMaterialLineItem;
      function GetMaterialLineItemCount(): Cardinal;
      function ComputeTotalQuantity(): Cardinal;
      function ComputeMass(): Double;
   public
      constructor Create(ABillOfMaterials: TMaterialLineItemArray; AMinimumFunctionalQuantity: Cardinal; ADefaultSize: Double);
      constructor CreateFromTechnologyTree(Reader: TTechTreeReader); override;
      function InitFeatureNode(): TFeatureNode; override;
      property DefaultSize: Double read FDefaultSize;
      property BillOfMaterials[Index: Cardinal]: TMaterialLineItem read GetMaterialLineItem;
      property BillOfMaterialsLength: Cardinal read GetMaterialLineItemCount;
      property TotalQuantity: Cardinal read FTotalQuantityCache;
      property Mass: Double read FMassCache;
      property MinimumFunctionalQuantity: Cardinal read FMinimumFunctionalQuantity; // minimum MaterialsQuantity for functioning
   end;

   TBuildingStateFlags = (bsTriggered, bsNoBuilderBus, bsNoRegion);

   PBuildingState = ^TBuildingState;
   TBuildingState = record
   private
      MaterialsQuantity: Cardinal; // 0.0 .. TStructureFeatureClass.TotalQuantity
      StructuralIntegrity: Cardinal; // 0.0 .. TStructureFeatureClass.TotalQuantity, but cannot be higher than FMaterialsQuantity
      AnchorTime: TTimeInMilliseconds;
      StructuralIntegrityRate: TRate;
      PendingMaterial: TMaterial;
      PendingQuantity: UInt64;
      MaterialsQuantityRate: TRate;
      NextEvent: TSystemEvent; // must trigger when or before the current MaterialsQuantityRate causes the current missing material to be filled, or the StructuralIntegrityRate causes StructuralIntegrity to reach 100%
      BuilderBus: TBuilderBusFeatureNode;
      Builder: TBuilderFeatureNode;
      Region: TRegionFeatureNode;
      Flags: set of TBuildingStateFlags; // could use AnnotatedPointers instead
      Priority: TPriority;
      procedure IncStructuralIntegrity(const Delta: Double);
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
      function GetNextStructureQuantity(): UInt64;
      function GetMass(): Double; override; // kg
      function GetMassFlowRate(): TRate; override;
      function GetSize(): Double; override; // m
      procedure HandleChanges(CachedSystem: TSystem); override;
      function HandleBusMessage(Message: TBusMessage): Boolean; override;
      procedure ResetDynastyNotes(OldDynasties: TDynastyIndexHashTable; NewDynasties: TDynastyHashSet; CachedSystem: TSystem); override;
      procedure ResetVisibility(CachedSystem: TSystem); override;
      procedure HandleKnowledge(const DynastyIndex: Cardinal; const VisibilityHelper: TVisibilityHelper; const Sensors: ISensorsProvider); override;
      procedure FetchMaterials();
      procedure RescheduleNextEvent(CachedSystem: TSystem);
      procedure HandleEvent(var Data);
      procedure TriggerBuilding();
      procedure Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter; CachedSystem: TSystem); override;
   public
      constructor Create(AFeatureClass: TStructureFeatureClass; AMaterialsQuantity: Cardinal; AStructuralIntegrity: Cardinal);
      destructor Destroy(); override;
      procedure UpdateJournal(Journal: TJournalWriter; CachedSystem: TSystem); override;
      procedure ApplyJournal(Journal: TJournalReader; CachedSystem: TSystem); override;
      procedure DescribeExistentiality(var IsDefinitelyReal, IsDefinitelyGhost: Boolean); override;
   private // IStructure
      procedure BuilderBusConnected(Bus: TBuilderBusFeatureNode); // must come from builder bus
      procedure BuilderBusReset(); // must come from builder bus, can assume all other participants were also reset
      procedure StartBuilding(Builder: TBuilderFeatureNode; BuildRate: TRate); // from builder
      procedure StopBuilding(); // from builder
      function GetAsset(): TAssetNode;
      function GetPriority(): TPriority;
      procedure SetAutoPriority(Value: TAutoPriority);
      function GetDynasty(): TDynasty;
   private // IMaterialConsumer
      function GetMaterialConsumerMaterial(): TMaterial;
      function GetMaterialConsumerMaxDelivery(): UInt64;
      function GetMaterialConsumerCurrentRate(): TRate; // quantity per second, cannot be infinite
      procedure SetMaterialConsumerRegion(Region: TRegionFeatureNode);
      procedure StartMaterialConsumer(ActualRate: TRate); // quantity per second
      procedure DeliverMaterialConsumer(Delivery: UInt64);
      procedure DisconnectMaterialConsumer();
   end;

implementation

uses
   sysutils, isdprotocol, exceptions, rubble, plasticarrays, genericutils, math;

constructor TMaterialLineItem.Create(AComponentName: UTF8String; AMaterial: TMaterial; AQuantity: Cardinal);
begin
   ComponentName := AComponentName;
   Material := AMaterial;
   Quantity := AQuantity;
end;

procedure TBuildingState.IncStructuralIntegrity(const Delta: Double);
begin
   if (Delta > High(StructuralIntegrity) - StructuralIntegrity) then
   begin
      StructuralIntegrity := High(StructuralIntegrity);
   end
   else
   begin
      Inc(StructuralIntegrity, Round(Delta));
   end;
   if (StructuralIntegrity > MaterialsQuantity) then
   begin
      StructuralIntegrity := MaterialsQuantity;
   end;
end;


constructor TStructureFeatureClass.Create(ABillOfMaterials: TMaterialLineItemArray; AMinimumFunctionalQuantity: Cardinal; ADefaultSize: Double);
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
   Quantity, Total: Cardinal;
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
   Total := 0;
   repeat
      ComponentName := Reader.Tokens.ReadString();
      Reader.Tokens.ReadColon();
      Material := ReadMaterial(Reader);
      Reader.Tokens.ReadAsterisk();
      Quantity := ReadNumber(Reader.Tokens, 1, High(Quantity)); // $R-
      MaterialsList.Push(TMaterialLineItem.Create(ComponentName, Material, Quantity));
      Inc(Total, Quantity);
      if (Reader.Tokens.IsCloseParenthesis()) then
         break;
      Reader.Tokens.ReadComma();
   until Reader.Tokens.IsCloseParenthesis();
   Reader.Tokens.ReadCloseParenthesis();
   Reader.Tokens.ReadComma();
   Reader.Tokens.ReadIdentifier('minimum');
   FMinimumFunctionalQuantity := ReadNumber(Reader.Tokens, 1, Total); // $R-
   FBillOfMaterials := MaterialsList.Distill();
   FTotalQuantityCache := ComputeTotalQuantity();
   FMassCache := ComputeMass();
end;

function TStructureFeatureClass.GetFeatureNodeClass(): FeatureNodeReference;
begin
   Result := TStructureFeatureNode;
end;

function TStructureFeatureClass.InitFeatureNode(): TFeatureNode;
begin
   Result := TStructureFeatureNode.Create(Self, 0, 0);
end;

function TStructureFeatureClass.GetMaterialLineItem(Index: Cardinal): TMaterialLineItem;
begin
   Result := FBillOfMaterials[Index];
end;

function TStructureFeatureClass.GetMaterialLineItemCount(): Cardinal;
begin
   Result := Length(FBillOfMaterials); // $R-
end;

function TStructureFeatureClass.ComputeTotalQuantity(): Cardinal;
var
   Index: Cardinal;
begin
   Result := 0;
   if (Length(FBillOfMaterials) > 0) then
   begin
      for Index := Low(FBillOfMaterials) to High(FBillOfMaterials) do // $R-
      begin
         Assert(FBillOfMaterials[Index].Quantity < High(Cardinal) - Result);
         Result := Result + FBillOfMaterials[Index].Quantity; // $R-
      end;
   end;
end;

function TStructureFeatureClass.ComputeMass(): Double;
var
   Index: Cardinal;
begin
   Result := 0;
   if (Length(FBillOfMaterials) > 0) then
   begin
      for Index := Low(FBillOfMaterials) to High(FBillOfMaterials) do // $R-
      begin
         Result := Result + FBillOfMaterials[Index].Quantity * FBillOfMaterials[Index].Material.MassPerUnit; // $R-
      end;
   end;
end;


constructor TStructureFeatureNode.Create(AFeatureClass: TStructureFeatureClass; AMaterialsQuantity: Cardinal; AStructuralIntegrity: Cardinal);
var
   Index: Cardinal;
begin
   inherited Create();
   Assert(Assigned(AFeatureClass));
   FFeatureClass := AFeatureClass;
   if ((AMaterialsQuantity < FFeatureClass.TotalQuantity) or (AStructuralIntegrity < FFeatureClass.TotalQuantity)) then
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
   inherited CreateFromJournal(Journal, AFeatureClass, ASystem);
   SetLength(FDynastyKnowledge, FFeatureClass.BillOfMaterialsLength);
end;

procedure TStructureFeatureNode.InitBuildingState();
begin
   FBuildingState := New(PBuildingState);
   FBuildingState^ := Default(TBuildingState);
   Assert(not Assigned(FBuildingState^.PendingMaterial));
   {$IFOPT C+}
   FBuildingState^.AnchorTime := TTimeInMilliseconds.NegInfinity;
   Assert(FBuildingState^.MaterialsQuantityRate.IsZero);
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
   Level: Cardinal;
begin
   if (Assigned(FBuildingState) and (FBuildingState^.MaterialsQuantity < FFeatureClass.TotalQuantity)) then
   begin
      Level := 0;
      for Index := 0 to FFeatureClass.BillOfMaterialsLength - 1 do // $R-
      begin
         Inc(Level, FFeatureClass.BillOfMaterials[Index].Quantity);
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

function TStructureFeatureNode.GetNextStructureQuantity(): UInt64;
var
   Index: Cardinal;
   Level: Cardinal;
begin
   Assert(Assigned(GetNextStructureMaterial()));
   if (Assigned(FBuildingState) and (FBuildingState^.MaterialsQuantity < FFeatureClass.TotalQuantity)) then
   begin
      Level := 0;
      for Index := 0 to FFeatureClass.BillOfMaterialsLength - 1 do // $R-
      begin
         Inc(Level, FFeatureClass.BillOfMaterials[Index].Quantity);
         if (FBuildingState^.MaterialsQuantity < Level) then
         begin
            Result := Level - FBuildingState^.MaterialsQuantity; // $R-
            exit;
         end;
      end;
      Assert(False); // unreachable
   end;
   Result := 0;
end;

function TStructureFeatureNode.GetMass(): Double; // kg
var
   MaterialIndex: Cardinal;
   Remaining, CurrentQuantity: Cardinal;
begin
   Result := 0.0;
   if (Assigned(FBuildingState)) then
   begin
      Assert(Assigned(FFeatureClass));
      Assert(FFeatureClass.BillOfMaterialsLength > 0);
      Remaining := FBuildingState^.MaterialsQuantity;
      if (FBuildingState^.MaterialsQuantityRate.IsNotZero) then
         Inc(Remaining, Round((System.Now - FBuildingState^.AnchorTime) * FBuildingState^.MaterialsQuantityRate));
      if (Remaining > 0) then
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
               Remaining := 0;
               break;
            end;
         end;
      end;
      Assert(Remaining = 0);
   end
   else
      Result := FFeatureClass.Mass;
end;

function TStructureFeatureNode.GetMassFlowRate(): TRate;
begin
   Result := TRate.Zero;
   if (Assigned(FBuildingState) and FBuildingState^.MaterialsQuantityRate.IsNotZero) then
   begin
      Assert(Assigned(FBuildingState^.PendingMaterial));
      Result := FBuildingState^.MaterialsQuantityRate * FBuildingState^.PendingMaterial.MassPerUnit;
   end;
end;

function TStructureFeatureNode.GetSize(): Double;
begin
   Result := FFeatureClass.DefaultSize;
end;

function TStructureFeatureNode.HandleBusMessage(Message: TBusMessage): Boolean;
var
   RubbleMessage: TRubbleCollectionMessage;
   Index: Cardinal;
   LineItem: TMaterialLineItem;
begin
   if (Message is TCheckDisabledBusMessage) then
   begin
      Result := False;
      if (Assigned(FBuildingState) and (FBuildingState^.StructuralIntegrity < FFeatureClass.MinimumFunctionalQuantity)) then
         (Message as TCheckDisabledBusMessage).AddReason(drStructuralIntegrity);
   end
   else
   if (Message is TRubbleCollectionMessage) then
   begin
      Result := False;
      RubbleMessage := Message as TRubbleCollectionMessage;
      RubbleMessage.Grow(FFeatureClass.BillOfMaterialsLength);
      Assert(FFeatureClass.BillOfMaterialsLength > 0);
      for Index := 0 to FFeatureClass.BillOfMaterialsLength - 1 do // $R-
      begin
         LineItem := FFeatureClass.BillOfMaterials[Index];
         RubbleMessage.AddMaterial(LineItem.Material, LineItem.Quantity);
      end;
   end
   else
      Result := inherited;
end;

procedure TStructureFeatureNode.ResetDynastyNotes(OldDynasties: TDynastyIndexHashTable; NewDynasties: TDynastyHashSet; CachedSystem: TSystem);
var
   Index: Cardinal;
begin
   Assert(Length(FDynastyKnowledge) = FFeatureClass.BillOfMaterialsLength);
   Assert(FFeatureClass.BillOfMaterialsLength > 0);
   for Index := 0 to FFeatureClass.BillOfMaterialsLength - 1 do // $R-
      FDynastyKnowledge[Index].Init(NewDynasties.Count);
end;

procedure TStructureFeatureNode.ResetVisibility(CachedSystem: TSystem);
var
   Index: Cardinal;
begin
   Assert(FFeatureClass.BillOfMaterialsLength > 0);
   for Index := 0 to FFeatureClass.BillOfMaterialsLength - 1 do // $R-
      FDynastyKnowledge[Index].Reset();
end;

procedure TStructureFeatureNode.HandleKnowledge(const DynastyIndex: Cardinal; const VisibilityHelper: TVisibilityHelper; const Sensors: ISensorsProvider);
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

procedure TStructureFeatureNode.Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter; CachedSystem: TSystem);
var
   Index, Remaining, Quantity, TotalQuantityAlreadyBuilt, StructuralIntegrity: Cardinal;
   Visibility: TVisibility;
   ClassKnown: Boolean;
begin
   Visibility := Parent.ReadVisibilityFor(DynastyIndex, CachedSystem);
   if (dmDetectable * Visibility <> []) then
   begin
      Writer.WriteCardinal(fcStructure);
      ClassKnown := dmClassKnown in Visibility;
      if (Assigned(FBuildingState)) then
      begin
         TotalQuantityAlreadyBuilt := FBuildingState^.MaterialsQuantity;
         if (FBuildingState^.MaterialsQuantityRate.IsNotZero) then
            Inc(TotalQuantityAlreadyBuilt, Round((CachedSystem.Now - FBuildingState^.AnchorTime) * FBuildingState^.MaterialsQuantityRate));
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
         if ((Remaining > 0) or ClassKnown) then
         begin
            Quantity := FFeatureClass.BillOfMaterials[Index].Quantity;
            if (ClassKnown) then
            begin
               Writer.WriteCardinal(Quantity);
               Writer.WriteStringReference(FFeatureClass.BillOfMaterials[Index].ComponentName);
            end
            else
            begin
               Assert(Remaining > 0);
               // expected quantity unknown
               if (Remaining < Quantity) then
                  Writer.WriteCardinal(Remaining)
               else
                  Writer.WriteCardinal(Quantity);
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
               Remaining := 0
            else
               Dec(Remaining, Quantity);
         end
         else
            break;
      end;
      Writer.WriteCardinal(0); // material terminator marker
      if (Assigned(FBuildingState)) then
      begin
         Writer.WriteCardinal(TotalQuantityAlreadyBuilt);
         Writer.WriteDouble(FBuildingState^.MaterialsQuantityRate.AsDouble);
         StructuralIntegrity := FBuildingState^.StructuralIntegrity;
         if (FBuildingState^.StructuralIntegrityRate.IsNotZero and Assigned(FBuildingState^.NextEvent)) then
         begin
            Assert(not FBuildingState^.AnchorTime.IsInfinite);
            Inc(StructuralIntegrity, Round((CachedSystem.Now - FBuildingState^.AnchorTime) * FBuildingState^.StructuralIntegrityRate));
         end;
         if (StructuralIntegrity > TotalQuantityAlreadyBuilt) then
            StructuralIntegrity := TotalQuantityAlreadyBuilt;
         Writer.WriteCardinal(StructuralIntegrity);
         Writer.WriteDouble(FBuildingState^.StructuralIntegrityRate.AsDouble);
      end
      else
      begin
         Writer.WriteCardinal(FFeatureClass.TotalQuantity);
         Writer.WriteDouble(0.0);
         Writer.WriteCardinal(FFeatureClass.TotalQuantity);
         Writer.WriteDouble(0.0);
      end;
      if (ClassKnown) then
      begin
         Writer.WriteCardinal(FFeatureClass.MinimumFunctionalQuantity);
      end
      else
      begin
         Writer.WriteCardinal(0);
      end;
   end;
end;

procedure TStructureFeatureNode.UpdateJournal(Journal: TJournalWriter; CachedSystem: TSystem);
begin
   if (Assigned(FBuildingState)) then
   begin
      Journal.WriteCardinal(FBuildingState^.MaterialsQuantity);
      Journal.WriteCardinal(FBuildingState^.StructuralIntegrity);
      Journal.WriteCardinal(FBuildingState^.Priority);
   end
   else
   begin
      Journal.WriteCardinal(FFeatureClass.TotalQuantity);
      Journal.WriteCardinal(FFeatureClass.TotalQuantity);
      Journal.WriteCardinal(0);
   end;
end;

procedure TStructureFeatureNode.ApplyJournal(Journal: TJournalReader; CachedSystem: TSystem);
var
   MaterialsQuantity, StructuralIntegrity, Priority: Cardinal;
begin
   MaterialsQuantity := Journal.ReadCardinal();
   StructuralIntegrity := Journal.ReadCardinal();
   Priority := Journal.ReadCardinal();
   if ((MaterialsQuantity < FFeatureClass.TotalQuantity) or (StructuralIntegrity < FFeatureClass.TotalQuantity)) then
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
   IsDefinitelyReal := (not Assigned(FBuildingState)) or (FBuildingState^.MaterialsQuantity > 0);
   IsDefinitelyGhost := (Assigned(FBuildingState)) and (FBuildingState^.MaterialsQuantity = 0);
end;

procedure TStructureFeatureNode.HandleChanges(CachedSystem: TSystem);
var
   Message: TRegisterStructureMessage;
begin
   if (Assigned(Parent.Owner)) then
   begin
      if (Assigned(FBuildingState) and (not Assigned(FBuildingState^.BuilderBus)) and (not (bsNoBuilderBus in FBuildingState^.Flags))) then
      begin
         Message := TRegisterStructureMessage.Create(Self);
         if (InjectBusMessage(Message) <> mrHandled) then
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
   Assert(FBuildingState^.PendingQuantity = 0);
   FBuildingState^.Builder := Builder;
   FBuildingState^.StructuralIntegrityRate := BuildRate;
   TriggerBuilding();
end;

procedure TStructureFeatureNode.TriggerBuilding();
var
   Injected: TBusMessageResult;
   Message: TRegisterMaterialConsumerBusMessage;
begin
   Assert(Assigned(Parent.Owner));
   Assert(not (bsTriggered in FBuildingState^.Flags));
   FetchMaterials();
   if (Assigned(FBuildingState^.PendingMaterial)) then
   begin
      if (not Assigned(FBuildingState^.Region)) then
      begin
         Message := TRegisterMaterialConsumerBusMessage.Create(Self);
         Injected := InjectBusMessage(Message);
         if (Injected <> mrHandled) then
         begin
            Include(FBuildingState^.Flags, bsNoRegion);
            Assert(FBuildingState^.StructuralIntegrityRate.IsZero);
         end;
         FreeAndNil(Message);
      end;
   end
   else
   if (FBuildingState^.StructuralIntegrity = FFeatureClass.TotalQuantity) then
   begin
      // we're done!
      if (Assigned(FBuildingState^.Region)) then
      begin
         FBuildingState^.Region.RemoveMaterialConsumer(Self);
         FBuildingState^.Region := nil;
         FBuildingState^.MaterialsQuantityRate := TRate.Zero;
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
      Assert(FBuildingState^.StructuralIntegrity < FFeatureClass.TotalQuantity);
      Assert(Assigned(FBuildingState^.Builder));
      if (Assigned(FBuildingState^.Region)) then
      begin
         FBuildingState^.Region.RemoveMaterialConsumer(Self);
         FBuildingState^.Region := nil;
         FBuildingState^.MaterialsQuantityRate := TRate.Zero;
      end;
      Assert(not Assigned(FBuildingState^.NextEvent));
      Assert(FBuildingState^.AnchorTime.IsInfinite);
      Assert(FBuildingState^.MaterialsQuantityRate.IsZero);
      Assert(FBuildingState^.StructuralIntegrityRate.IsNotZero);
      RescheduleNextEvent(System);
   end;
   if (Assigned(FBuildingState)) then
      Include(FBuildingState^.Flags, bsTriggered);
end;

procedure TStructureFeatureNode.FetchMaterials();
var
   Changes: TDirtyKinds;
   NextMaterial: TMaterial;
   NextQuantity: UInt64;
   Index: Cardinal;
   Level: Cardinal;
   Obtain: TObtainMaterialBusMessage;
   ObtainedMaterial: TMaterialQuantity;
begin
   Assert(Assigned(Parent.Owner));
   Changes := [];
   Assert(Assigned(FBuildingState));
   Assert(not Assigned(FBuildingState^.NextEvent));
   Assert(not Assigned(FBuildingState^.PendingMaterial));
   Assert(not (bsTriggered in FBuildingState^.Flags));
   Assert(FBuildingState^.PendingQuantity = 0);
   Level := 0;
   Index := 0;
   NextMaterial := nil;
   NextQuantity := 0;
   while (FBuildingState^.MaterialsQuantity < FFeatureClass.TotalQuantity) do
   begin
      Assert(Index < FFeatureClass.BillOfMaterialsLength);
      Inc(Level, FFeatureClass.BillOfMaterials[Index].Quantity);
      if (FBuildingState^.MaterialsQuantity < Level) then
      begin
         // TODO: check if the material is known to the dynasty
         // if it is not, then we cannot fetch it.
         NextMaterial := FFeatureClass.BillOfMaterials[Index].Material;
         NextQuantity := Level - FBuildingState^.MaterialsQuantity; // $R-
         Assert(NextQuantity > 0);
         Obtain := TObtainMaterialBusMessage.Create(Parent.Owner, NextMaterial, NextQuantity);
         InjectBusMessage(Obtain);
         ObtainedMaterial := Obtain.TransferredManifest;
         if (Assigned(ObtainedMaterial.Material)) then
         begin
            Assert(ObtainedMaterial.Material = NextMaterial);
            Assert(ObtainedMaterial.Quantity > 0);
            Assert(ObtainedMaterial.Quantity <= NextQuantity);
            if (FBuildingState^.MaterialsQuantity = 0) then
               Include(Changes, dkAffectsVisibility);
            Inc(FBuildingState^.MaterialsQuantity, ObtainedMaterial.Quantity);
            Dec(NextQuantity, ObtainedMaterial.Quantity);
            Include(Changes, dkUpdateClients);
            Include(Changes, dkUpdateJournal);
         end;
         FreeAndNil(Obtain);
         if (NextQuantity > 0) then
            break;
         NextMaterial := nil;
      end;
      Inc(Index);
   end;
   FBuildingState^.PendingMaterial := NextMaterial;
   FBuildingState^.PendingQuantity := NextQuantity;
   Assert((FBuildingState^.PendingQuantity > 0) = (Assigned(FBuildingState^.PendingMaterial)));
   MarkAsDirty(Changes);
end;

procedure TStructureFeatureNode.StopBuilding(); // called by builder
begin
   Assert(Assigned(FBuildingState));
   Assert(FBuildingState^.StructuralIntegrityRate.IsNotZero);
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
      FBuildingState^.MaterialsQuantityRate := TRate.Zero;
   end
   else
   begin
      Assert(FBuildingState^.MaterialsQuantityRate.IsZero);
      if (Assigned(FBuildingState^.NextEvent)) then
      begin
         Assert(not FBuildingState^.AnchorTime.IsInfinite);
         FBuildingState^.IncStructuralIntegrity((System.Now - FBuildingState^.AnchorTime) * FBuildingState^.StructuralIntegrityRate);
         MarkAsDirty([dkUpdateJournal, dkUpdateClients]);
         Assert(FBuildingState^.StructuralIntegrity <= FFeatureClass.TotalQuantity);
      end;
   end;
   Assert(Assigned(FBuildingState));
   FBuildingState^.PendingMaterial := nil;
   FBuildingState^.PendingQuantity := 0;
   FBuildingState^.StructuralIntegrityRate := TRate.Zero;
   Exclude(FBuildingState^.Flags, bsTriggered);
   if (Assigned(FBuildingState^.NextEvent)) then
   begin
      CancelEvent(FBuildingState^.NextEvent);
      {$IFOPT C+} FBuildingState^.AnchorTime := TTimeInMilliseconds.NegInfinity; {$ENDIF}
      Assert(FBuildingState^.MaterialsQuantityRate.IsZero);
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

function TStructureFeatureNode.GetMaterialConsumerMaxDelivery(): UInt64;
begin
   Assert(Assigned(FBuildingState));
   Result := FBuildingState^.PendingQuantity;
end;

function TStructureFeatureNode.GetMaterialConsumerCurrentRate(): TRate; // quantity per second, cannot be infinite
begin
   Assert(Assigned(FBuildingState));
   Result := FBuildingState^.MaterialsQuantityRate;
end;

procedure TStructureFeatureNode.SetMaterialConsumerRegion(Region: TRegionFeatureNode);
begin
   Assert(Assigned(FBuildingState));
   Assert(not Assigned(FBuildingState^.Region));
   Assert(FBuildingState^.MaterialsQuantityRate.IsZero);
   Assert(Assigned(FBuildingState^.PendingMaterial));
   Assert(FBuildingState^.PendingQuantity > 0);
   FBuildingState^.Region := Region;
end;

procedure TStructureFeatureNode.StartMaterialConsumer(ActualRate: TRate); // quantity per second
begin
   Assert(Assigned(FBuildingState));
   Assert(Assigned(FBuildingState^.Region));
   Assert(Assigned(FBuildingState^.PendingMaterial));
   Assert(FBuildingState^.PendingQuantity > 0);
   FBuildingState^.MaterialsQuantityRate := ActualRate;
   RescheduleNextEvent(System);
   MarkAsDirty([dkUpdateClients]);
end;

procedure TStructureFeatureNode.DeliverMaterialConsumer(Delivery: UInt64);
var
   Duration: TMillisecondsDuration;
   CachedSystem: TSystem;

   procedure MeasureDuration();
   begin
      if (not Assigned(CachedSystem)) then
      begin
         CachedSystem := System;
         Duration := System.Now - FBuildingState^.AnchorTime;
      end;
   end;

begin
   Assert(Assigned(FBuildingState));
   Assert(Assigned(FBuildingState^.PendingMaterial));
   Assert(Assigned(FBuildingState^.Region));
   Assert(FBuildingState^.PendingQuantity > 0);
   Assert(Delivery <= FBuildingState^.PendingQuantity);
   Assert((Delivery = 0) or (not FBuildingState^.AnchorTime.IsInfinite)); // nextevent might be nil already but even then we must not have reset the anchor time yet
   Assert((Delivery = 0) or (FBuildingState^.MaterialsQuantityRate.IsNotZero));
   CachedSystem := nil;
   if (Delivery > 0) then
   begin
      MeasureDuration();
      Assert(Delivery <= Ceil(Duration * FBuildingState^.MaterialsQuantityRate));
      Inc(FBuildingState^.MaterialsQuantity, Delivery);
      Dec(FBuildingState^.PendingQuantity, Delivery);
      if (FBuildingState^.PendingQuantity = 0) then
      begin
         FBuildingState^.PendingMaterial := nil;
         FBuildingState^.MaterialsQuantityRate := TRate.Zero;
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
   if (FBuildingState^.StructuralIntegrityRate.IsNotZero and (FBuildingState^.StructuralIntegrity < FBuildingState^.MaterialsQuantity)) then
   begin
      MeasureDuration();
      FBuildingState^.IncStructuralIntegrity(Duration * FBuildingState^.StructuralIntegrityRate);
      Assert((FBuildingState^.PendingQuantity > 0) = (Assigned(FBuildingState^.PendingMaterial)));
      MarkAsDirty([dkUpdateClients, dkUpdateJournal, dkNeedsHandleChanges]);
   end;
end;

procedure TStructureFeatureNode.DisconnectMaterialConsumer();
begin
   // DeliverMaterialConsumer will be called first
   Assert(Assigned(FBuildingState));
   Assert(Assigned(FBuildingState^.Region));
   FBuildingState^.Region := nil;
   FBuildingState^.MaterialsQuantityRate := TRate.Zero;
   if (Assigned(FBuildingState^.NextEvent)) then
   begin
      CancelEvent(FBuildingState^.NextEvent);
      {$IFOPT C+} FBuildingState^.AnchorTime := TTimeInMilliseconds.NegInfinity; {$ENDIF}
   end;
   // Region is going away, so we better try to find another; retrigger:
   Exclude(FBuildingState^.Flags, bsTriggered);
   MarkAsDirty([dkNeedsHandleChanges]);
end;

procedure TStructureFeatureNode.RescheduleNextEvent(CachedSystem: TSystem);
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
   if (Assigned(FBuildingState^.Region) and FBuildingState^.MaterialsQuantityRate.IsNotZero) then
   begin
      Assert(FBuildingState^.PendingQuantity > 0);
      Assert(FBuildingState^.AnchorTime.IsInfinite);
      RemainingTime := FBuildingState^.PendingQuantity / FBuildingState^.MaterialsQuantityRate;
   end
   else
   if (FBuildingState^.StructuralIntegrityRate.IsNotZero and (FBuildingState^.MaterialsQuantity > FBuildingState^.StructuralIntegrity)) then
   begin
      Assert((FBuildingState^.PendingQuantity > 0) xor (FBuildingState^.MaterialsQuantity = FFeatureClass.TotalQuantity));
      RemainingTime := (FBuildingState^.MaterialsQuantity - FBuildingState^.StructuralIntegrity) / FBuildingState^.StructuralIntegrityRate;
   end
   else
   begin
      // nothing to wait for
      exit;
   end;
   if (FBuildingState^.StructuralIntegrity < FFeatureClass.MinimumFunctionalQuantity) then
   begin
      if (FBuildingState^.MaterialsQuantity < FFeatureClass.MinimumFunctionalQuantity) then
      begin
         if (FBuildingState^.MaterialsQuantityRate.IsZero) then
         begin
            TimeUntilMaterialFunctional := TMillisecondsDuration.Infinity;
         end
         else
         begin
            TimeUntilMaterialFunctional := (FBuildingState^.MaterialsQuantity - FFeatureClass.MinimumFunctionalQuantity) / FBuildingState^.MaterialsQuantityRate;
         end;
      end
      else
      begin
         TimeUntilMaterialFunctional := TMillisecondsDuration.Zero;
      end;
      if (FBuildingState^.StructuralIntegrityRate.IsZero) then
      begin
         TimeUntilIntegrityFunctional := TMillisecondsDuration.Infinity;
      end
      else
      begin
         TimeUntilIntegrityFunctional := (FBuildingState^.StructuralIntegrity - FFeatureClass.MinimumFunctionalQuantity) / FBuildingState^.StructuralIntegrityRate;
      end;
      if (TimeUntilMaterialFunctional > TimeUntilIntegrityFunctional) then
         TimeUntilIntegrityFunctional := TimeUntilMaterialFunctional;
      if ((TimeUntilIntegrityFunctional.IsPositive) and (TimeUntilIntegrityFunctional < RemainingTime)) then
      begin
         RemainingTime := TimeUntilIntegrityFunctional;
      end;
   end;
   Assert(RemainingTime.IsNotZero);
   FBuildingState^.NextEvent := CachedSystem.ScheduleEvent(RemainingTime, @HandleEvent, Self);
   FBuildingState^.AnchorTime := CachedSystem.Now;
end;

procedure TStructureFeatureNode.HandleEvent(var Data);
var
   Duration: TMillisecondsDuration;
begin
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
      if (FBuildingState^.MaterialsQuantityRate.IsNotZero) then
      begin
         Assert(Assigned(FBuildingState^.PendingMaterial));
         FBuildingState^.Region.SyncForMaterialConsumer();
         // DeliverMaterialConsumer() will be called here, and it handles the structural integrity stuff
      end
      else
      begin
         DeliverMaterialConsumer(0); // update structural integrity
      end;
      if (FBuildingState^.StructuralIntegrity = FFeatureClass.TotalQuantity) then
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
         FBuildingState^.MaterialsQuantityRate := TRate.Zero;
         Assert(not Assigned(FBuildingState^.PendingMaterial)); // reset by DeliverMaterialConsumer
         Assert(FBuildingState^.PendingQuantity = 0); // reset by DeliverMaterialConsumer
         Assert(FBuildingState^.StructuralIntegrity < FFeatureClass.TotalQuantity);
         Assert(FBuildingState^.StructuralIntegrityRate.IsNotZero);
         {$IFOPT C+} FBuildingState^.AnchorTime := TTimeInMilliseconds.NegInfinity; {$ENDIF}
         Assert(FBuildingState^.MaterialsQuantityRate.IsZero);
         Assert(not (bsTriggered in FBuildingState^.Flags)); // so we're going to get retriggered
      end
      else
      if (not Assigned(FBuildingState^.PendingMaterial)) then
      begin
         // we still have materials to get, but we don't yet know what is next
         Assert(FBuildingState^.PendingQuantity = 0); // reset by DeliverMaterialConsumer
         FBuildingState^.Region.SyncForMaterialConsumer();
         Assert(FBuildingState^.MaterialsQuantityRate.IsZero); // reset by ReconsiderMaterialConsumer calling PauseMaterialConsumer
         Assert(FBuildingState^.StructuralIntegrity < FFeatureClass.TotalQuantity);
         Assert(FBuildingState^.StructuralIntegrityRate.IsNotZero);
         {$IFOPT C+} FBuildingState^.AnchorTime := TTimeInMilliseconds.NegInfinity; {$ENDIF}
         Assert(FBuildingState^.MaterialsQuantityRate.IsZero);
      end
      else
      begin
         Assert(FBuildingState^.PendingQuantity > 0);
         Assert(FBuildingState^.StructuralIntegrity < FFeatureClass.TotalQuantity);
         Assert(FBuildingState^.StructuralIntegrityRate.IsNotZero);
         {$IFOPT C+} FBuildingState^.AnchorTime := TTimeInMilliseconds.NegInfinity; {$ENDIF}
         Assert(bsTriggered in FBuildingState^.Flags); // so we're NOT going to get retriggered
         RescheduleNextEvent(System);
      end;
   end
   else
   if (FBuildingState^.StructuralIntegrityRate.IsNotZero and (FBuildingState^.MaterialsQuantity > FBuildingState^.StructuralIntegrity)) then
   begin
      Duration := System.Now - FBuildingState^.AnchorTime;
      Assert(Duration.IsNotZero and Duration.IsPositive);
      FBuildingState^.IncStructuralIntegrity(Duration * FBuildingState^.StructuralIntegrityRate);
      MarkAsDirty([dkUpdateClients, dkUpdateJournal]);
      if (FBuildingState^.StructuralIntegrity = FFeatureClass.TotalQuantity) then
      begin
         // we're done!
         Assert(not Assigned(FBuildingState^.Region));
         Assert(FBuildingState^.MaterialsQuantityRate.IsZero);
         Assert(Assigned(FBuildingState^.Builder));
         FBuildingState^.Builder.StopBuilding(Self);
         Assert(Assigned(FBuildingState^.BuilderBus));
         FBuildingState^.BuilderBus.RemoveStructure(Self);
         {$IFOPT C+} FBuildingState^.AnchorTime := TTimeInMilliseconds.NegInfinity; {$ENDIF}
         Assert(FBuildingState^.MaterialsQuantityRate.IsZero);
         Assert(not Assigned(FBuildingState^.NextEvent));
         Dispose(FBuildingState);
         FBuildingState := nil;
      end
      else
      begin
         // we're not yet done, so retrigger ourselves to figure out why
         {$IFOPT C+} FBuildingState^.AnchorTime := TTimeInMilliseconds.NegInfinity; {$ENDIF}
         Assert(FBuildingState^.MaterialsQuantityRate.IsZero);
         // Retrigger building:
         Exclude(FBuildingState^.Flags, bsTriggered);
         MarkAsDirty([dkUpdateClients, dkUpdateJournal, dkNeedsHandleChanges]);
      end;
   end;
end;

initialization
   RegisterFeatureClass(TStructureFeatureClass);
end.