{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit structure;

interface

uses
   systems, serverstream, materials, techtree;

type
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
      FMinimumFunctionalQuantity: Cardinal; // 0.0 .. TotalQuantity
   strict protected
      function GetFeatureNodeClass(): FeatureNodeReference; override;
   protected
      function GetMaterialLineItem(Index: Cardinal): TMaterialLineItem;
      function GetMaterialLineItemCount(): Cardinal;
      function GetTotalQuantity(): Cardinal;
   public
      constructor Create(ABillOfMaterials: TMaterialLineItemArray; AMinimumFunctionalQuantity: Cardinal; ADefaultSize: Double);
      constructor CreateFromTechnologyTree(Reader: TTechTreeReader); override;
      function InitFeatureNode(): TFeatureNode; override;
      property DefaultSize: Double read FDefaultSize;
      property BillOfMaterials[Index: Cardinal]: TMaterialLineItem read GetMaterialLineItem;
      property BillOfMaterialsLength: Cardinal read GetMaterialLineItemCount;
      property TotalQuantity: Cardinal read GetTotalQuantity;
      property MinimumFunctionalQuantity: Cardinal read FMinimumFunctionalQuantity; // minimum MaterialsQuantity for functioning
   end;

   TStructureFeatureNode = class(TFeatureNode)
   protected
      FFeatureClass: TStructureFeatureClass;
      FMaterialsQuantity: Cardinal; // 0.0 .. TStructureFeatureClass.TotalQuantity
      FStructuralIntegrity: Cardinal; // 0.0 .. FMaterialsQuantity
      FDynastyKnowledge: array of TKnowledgeSummary; // for each item in the bill of materials, which dynasties know about it here // TODO: this is expensive when there are not many dynasties (8 bytes per material, even if there's only 1 dynasty).
      constructor CreateFromJournal(Journal: TJournalReader; AFeatureClass: TFeatureClass; ASystem: TSystem); override;
      function GetMass(): Double; override; // kg
      function GetSize(): Double; override; // m
      function HandleBusMessage(Message: TBusMessage): Boolean; override;
      procedure ResetDynastyNotes(OldDynasties: TDynastyIndexHashTable; NewDynasties: TDynastyHashSet; CachedSystem: TSystem); override;
      procedure HandleVisibility(const DynastyIndex: Cardinal; var Visibility: TVisibility; const Sensors: ISensorsProvider; const VisibilityHelper: TVisibilityHelper); override;
      procedure Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter; CachedSystem: TSystem); override;
   public
      constructor Create(AFeatureClass: TStructureFeatureClass; AMaterialsQuantity: Cardinal; AStructuralIntegrity: Cardinal);
      destructor Destroy(); override;
      procedure UpdateJournal(Journal: TJournalWriter; CachedSystem: TSystem); override;
      procedure ApplyJournal(Journal: TJournalReader; CachedSystem: TSystem); override;
      procedure DescribeExistentiality(var IsDefinitelyReal, IsDefinitelyGhost: Boolean); override;
      property MaterialsQuantity: Cardinal read FMaterialsQuantity; // how much of the feature's bill of materials is actually present
      property StructuralIntegrity: Cardinal read FStructuralIntegrity; // how much of the materials are actually in good shape (affects efficiency)
   end;

implementation

uses
   isdprotocol, exceptions, rubble, plasticarrays, genericutils;

constructor TMaterialLineItem.Create(AComponentName: UTF8String; AMaterial: TMaterial; AQuantity: Cardinal);
begin
   ComponentName := AComponentName;
   Material := AMaterial;
   Quantity := AQuantity;
end;


constructor TStructureFeatureClass.Create(ABillOfMaterials: TMaterialLineItemArray; AMinimumFunctionalQuantity: Cardinal; ADefaultSize: Double);
begin
   inherited Create();
   FBillOfMaterials := ABillOfMaterials;
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
   // feature: TStructureFeatureClass size 20m, materials (
   //    "Substructure": "Iron" x 700,
   //    "Logic": "Circuit Board" x 5,
   //    "Shell": "Iron" x 300,
   // ), minimum 805;
   MaterialsList.Init(2);
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

function TStructureFeatureClass.GetTotalQuantity(): Cardinal;
var
   Index: Cardinal;
begin
   Result := 0;
   if (Length(FBillOfMaterials) > 0) then
   begin
      for Index := 0 to High(FBillOfMaterials) do // $R-
      begin
         Assert(FBillOfMaterials[Index].Quantity < High(Cardinal) - Result);
         Result := Result + FBillOfMaterials[Index].Quantity; // $R-
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
   FMaterialsQuantity := AMaterialsQuantity;
   FStructuralIntegrity := AStructuralIntegrity;
   SetLength(FDynastyKnowledge, FFeatureClass.BillOfMaterialsLength);
   if (FFeatureClass.BillOfMaterialsLength > 0) then
   begin
      for Index := 0 to FFeatureClass.BillOfMaterialsLength - 1 do // $R-
      begin
         Assert(not Assigned(FDynastyKnowledge[Index].AsRawPointer));
      end;
   end;
end;

constructor TStructureFeatureNode.CreateFromJournal(Journal: TJournalReader; AFeatureClass: TFeatureClass; ASystem: TSystem);
begin
   inherited CreateFromJournal(Journal, AFeatureClass, ASystem);
   Assert(Assigned(AFeatureClass));
   FFeatureClass := AFeatureClass as TStructureFeatureClass;
   SetLength(FDynastyKnowledge, FFeatureClass.BillOfMaterialsLength);
end;

destructor TStructureFeatureNode.Destroy();
var
   Index: Cardinal;
begin
   if (FFeatureClass.BillOfMaterialsLength > 0) then
   begin
      for Index := 0 to FFeatureClass.BillOfMaterialsLength - 1 do // $R-
      begin
         FDynastyKnowledge[Index].Done();
      end;
   end;
   inherited;
end;

function TStructureFeatureNode.GetMass(): Double; // kg
var
   MaterialIndex: Cardinal;
   Remaining, CurrentQuantity: Cardinal;
begin
   Result := 0.0;
   Remaining := MaterialsQuantity;
   Assert(Assigned(FFeatureClass));
   Assert((Remaining = 0) or (FFeatureClass.BillOfMaterialsLength > 0));
   if (FFeatureClass.BillOfMaterialsLength > 0) then
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
   Result := False;
   if (Message is TRubbleCollectionMessage) then
   begin
      RubbleMessage := Message as TRubbleCollectionMessage;
      RubbleMessage.Grow(FFeatureClass.BillOfMaterialsLength);
      if (FFeatureClass.BillOfMaterialsLength > 0) then
      begin
         for Index := 0 to FFeatureClass.BillOfMaterialsLength - 1 do // $R-
         begin
            LineItem := FFeatureClass.BillOfMaterials[Index];
            RubbleMessage.AddMaterial(LineItem.Material, LineItem.Quantity);
         end;
      end;
      exit;
   end;
end;

procedure TStructureFeatureNode.ResetDynastyNotes(OldDynasties: TDynastyIndexHashTable; NewDynasties: TDynastyHashSet; CachedSystem: TSystem);
var
   Index: Cardinal;
begin
   Assert(Length(FDynastyKnowledge) = FFeatureClass.BillOfMaterialsLength);
   if (FFeatureClass.BillOfMaterialsLength > 0) then
   begin
      for Index := 0 to FFeatureClass.BillOfMaterialsLength - 1 do // $R-
      begin
         FDynastyKnowledge[Index].Init(NewDynasties.Count);
      end;
   end;
end;

procedure TStructureFeatureNode.HandleVisibility(const DynastyIndex: Cardinal; var Visibility: TVisibility; const Sensors: ISensorsProvider; const VisibilityHelper: TVisibilityHelper);
var
   Index: Cardinal;
begin
   if (FFeatureClass.BillOfMaterialsLength > 0) then
   begin
      for Index := 0 to FFeatureClass.BillOfMaterialsLength - 1 do // $R-
      begin
         if (Sensors.Knows(FFeatureClass.BillOfMaterials[Index].Material)) then
            FDynastyKnowledge[Index].SetEntry(DynastyIndex, True);
      end;
   end;
end;

procedure TStructureFeatureNode.Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter; CachedSystem: TSystem);
var
   Index, Remaining, Quantity: Cardinal;
   Visibility: TVisibility;
   ClassKnown: Boolean;
begin
   Visibility := Parent.ReadVisibilityFor(DynastyIndex, CachedSystem);
   if (dmDetectable * Visibility <> []) then
   begin
      Writer.WriteCardinal(fcStructure);
      ClassKnown := dmClassKnown in Visibility;
      Remaining := MaterialsQuantity;
      if (FFeatureClass.BillOfMaterialsLength > 0) then
      begin
         for Index := 0 to FFeatureClass.BillOfMaterialsLength - 1 do // $R-
         begin
            if ((Remaining > 0) or ClassKnown) then
            begin
               Writer.WriteCardinal($FFFFFFFF); // sentinel
               Quantity := FFeatureClass.BillOfMaterials[Index].Quantity;
               if (Quantity < Remaining) then
               begin
                  Writer.WriteCardinal(Quantity);
                  Dec(Remaining, Quantity);
               end
               else
               begin
                  Writer.WriteCardinal(Remaining);
                  Remaining := 0;
               end;
               if (ClassKnown) then
               begin
                  Writer.WriteCardinal(Quantity);
                  Writer.WriteStringReference(FFeatureClass.BillOfMaterials[Index].ComponentName);
               end
               else
               begin
                  Writer.WriteCardinal(0); // expected quantity unknown
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
            end
            else
               break;
         end;
      end;
      Writer.WriteCardinal(0); // material terminator marker
      Writer.WriteCardinal(StructuralIntegrity);
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
   Journal.WriteCardinal(MaterialsQuantity);
   Journal.WriteCardinal(StructuralIntegrity);
end;

procedure TStructureFeatureNode.ApplyJournal(Journal: TJournalReader; CachedSystem: TSystem);
begin
   FMaterialsQuantity := Journal.ReadCardinal();
   FStructuralIntegrity := Journal.ReadCardinal();
end;

procedure TStructureFeatureNode.DescribeExistentiality(var IsDefinitelyReal, IsDefinitelyGhost: Boolean);
begin
   IsDefinitelyReal := FMaterialsQuantity > 0;
   IsDefinitelyGhost := FMaterialsQuantity = 0;
   // TODO: if FMaterialsQuantity changes whether it equals 0, then MarkAsDirty([dkAffectsVisibility])
end;

initialization
   RegisterFeatureClass(TStructureFeatureClass);
end.