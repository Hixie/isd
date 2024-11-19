{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit structure;

interface

uses
   systems, serverstream, materials;

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
      FDynastyKnowledge: array of TKnowledgeSummary; // for each item in the bill of materials, which dynasties know about it here
      constructor CreateFromJournal(Journal: TJournalReader; AFeatureClass: TFeatureClass; ASystem: TSystem); override;
      function GetMass(): Double; override; // kg
      function GetSize(): Double; override; // m
      function GetFeatureName(): UTF8String; override;
      procedure Walk(PreCallback: TPreWalkCallback; PostCallback: TPostWalkCallback); override;
      function HandleBusMessage(Message: TBusMessage): Boolean; override;
      procedure ResetDynastyNotes(OldDynasties: TDynastyIndexHashTable; NewDynasties: TDynastyHashSet; System: TSystem); override;
      procedure HandleVisibility(const DynastyIndex: Cardinal; var Visibility: TVisibility; const Sensors: ISensorProvider; const VisibilityHelper: TVisibilityHelper); override;
      procedure Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter; System: TSystem); override;
   public
      constructor Create(AFeatureClass: TStructureFeatureClass; AMaterialsQuantity: Cardinal; AStructuralIntegrity: Cardinal);
      destructor Destroy(); override;
      procedure UpdateJournal(Journal: TJournalWriter); override;
      procedure ApplyJournal(Journal: TJournalReader; System: TSystem); override;
      property MaterialsQuantity: Cardinal read FMaterialsQuantity; // how much of the feature's bill of materials is actually present
      property StructuralIntegrity: Cardinal read FStructuralIntegrity; // how much of the materials are actually in good shape (affects efficiency)
   end;

implementation

uses
   isdprotocol, exceptions;

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

function TStructureFeatureNode.GetFeatureName(): UTF8String;
begin
   Result := '';
end;

procedure TStructureFeatureNode.Walk(PreCallback: TPreWalkCallback; PostCallback: TPostWalkCallback);
begin
end;

function TStructureFeatureNode.HandleBusMessage(Message: TBusMessage): Boolean;
begin
   Result := False;
end;

procedure TStructureFeatureNode.ResetDynastyNotes(OldDynasties: TDynastyIndexHashTable; NewDynasties: TDynastyHashSet; System: TSystem);
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

procedure TStructureFeatureNode.HandleVisibility(const DynastyIndex: Cardinal; var Visibility: TVisibility; const Sensors: ISensorProvider; const VisibilityHelper: TVisibilityHelper);
var
   MaterialLibrary: TMaterialHashSet;
   Index: Cardinal;
begin
   MaterialLibrary := Sensors.GetKnownMaterials();
   if (FFeatureClass.BillOfMaterialsLength > 0) then
   begin
      for Index := 0 to FFeatureClass.BillOfMaterialsLength - 1 do // $R-
      begin
         if (MaterialLibrary.Has(FFeatureClass.BillOfMaterials[Index].Material)) then
            FDynastyKnowledge[Index].SetEntry(DynastyIndex, True);
      end;
   end;
end;

procedure TStructureFeatureNode.Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter; System: TSystem);
var
   Index, Remaining, Quantity: Cardinal;
   Visibility: TVisibility;
   ClassKnown: Boolean;
begin
   Writer.WriteCardinal(fcStructure);
   Remaining := MaterialsQuantity;
   Visibility := Parent.ReadVisibilityFor(DynastyIndex, System);
   ClassKnown := dmClassKnown in Visibility;
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

procedure TStructureFeatureNode.UpdateJournal(Journal: TJournalWriter);
begin
   Journal.WriteCardinal(MaterialsQuantity);
   Journal.WriteCardinal(StructuralIntegrity);
end;

procedure TStructureFeatureNode.ApplyJournal(Journal: TJournalReader; System: TSystem);
begin
   FMaterialsQuantity := Journal.ReadCardinal();
   FStructuralIntegrity := Journal.ReadCardinal();
end;

end.