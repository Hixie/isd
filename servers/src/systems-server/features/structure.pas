{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit structure;

interface

uses
   systems, binarystream;

type
   TStructureFeatureClass = class(TFeatureClass)
   strict protected
      function GetFeatureNodeClass(): FeatureNodeReference; override;
   protected
      FDefaultSize: Double;
      FBillOfMaterials: TMaterialLineItemArray;
      FMinimumFunctionalQuantity: Cardinal; // 0.0 .. TotalQuantity
      function GetMaterialLineItem(Index: Cardinal): TMaterialLineItem;
      function GetMaterialLineItemCount(): Cardinal;
      function GetTotalQuantity(): Cardinal;
   public
      constructor Create(ABillOfMaterials: TMaterialLineItemArray; AMinimumFunctionalQuantity: Cardinal);
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
      procedure SerializeFor(DynastyIndex: Cardinal; Writer: TBinaryStreamWriter; System: TSystem); override;
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

constructor TStructureFeatureClass.Create(ABillOfMaterials: TMaterialLineItemArray; AMinimumFunctionalQuantity: Cardinal);
begin
   inherited Create();
   FBillOfMaterials := ABillOfMaterials;
   FMinimumFunctionalQuantity := AMinimumFunctionalQuantity;
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
      for MaterialIndex := 0 to FFeatureClass.BillOfMaterialsLength-1 do // $R-
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
   Result := FFeatureClass.FDefaultSize;
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

procedure TStructureFeatureNode.SerializeFor(DynastyIndex: Cardinal; Writer: TBinaryStreamWriter; System: TSystem);
begin
   // TODO: surely someone should be able to figure out that something is made of wood even if they don't know what the asset class is, if they know what wood is
   Writer.WriteCardinal(fcStructure);
   Writer.WriteCardinal(MaterialsQuantity);
   Writer.WriteCardinal(StructuralIntegrity);
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