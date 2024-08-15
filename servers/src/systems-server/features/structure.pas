{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit structure;

interface

uses
   systems, serverstream;

type
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
      constructor CreateFromJournal(Journal: TJournalReader; AFeatureClass: TFeatureClass); override;
      function GetMass(): Double; override; // kg
      function GetSize(): Double; override; // m
      function GetFeatureName(): UTF8String; override;
      procedure Walk(PreCallback: TPreWalkCallback; PostCallback: TPostWalkCallback); override;
      procedure ApplyVisibility(VisibilityHelper: TVisibilityHelper); override;
      procedure Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter; System: TSystem); override;
   public
      constructor Create(AFeatureClass: TStructureFeatureClass);
      procedure RecordSnapshot(Journal: TJournalWriter); override;
      procedure ApplyJournal(Journal: TJournalReader); override;
      property MaterialsQuantity: Cardinal read FMaterialsQuantity; // how much of the feature's bill of materials is actually present
      property StructuralIntegrity: Cardinal read FStructuralIntegrity; // how much of the materials are actually in good shape (affects efficiency)
   end;

implementation

uses
   isdprotocol, exceptions;

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
   Result := TStructureFeatureNode.Create(Self);
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


constructor TStructureFeatureNode.Create(AFeatureClass: TStructureFeatureClass);
begin
   inherited Create();
   Assert(Assigned(AFeatureClass));
   FFeatureClass := AFeatureClass;
end;

constructor TStructureFeatureNode.CreateFromJournal(Journal: TJournalReader; AFeatureClass: TFeatureClass);
begin
   inherited CreateFromJournal(Journal, AFeatureClass);
   Assert(Assigned(AFeatureClass));
   FFeatureClass := AFeatureClass as TStructureFeatureClass;
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

procedure TStructureFeatureNode.ApplyVisibility(VisibilityHelper: TVisibilityHelper);
begin
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
            Writer.WritePtrUInt(FFeatureClass.BillOfMaterials[Index].Material.ID(System));
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

procedure TStructureFeatureNode.RecordSnapshot(Journal: TJournalWriter);
begin
   Journal.WriteCardinal(MaterialsQuantity);
   Journal.WriteCardinal(StructuralIntegrity);
end;

procedure TStructureFeatureNode.ApplyJournal(Journal: TJournalReader);
begin
   FMaterialsQuantity := Journal.ReadCardinal();
   FStructuralIntegrity := Journal.ReadCardinal();
end;

end.