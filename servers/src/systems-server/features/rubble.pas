{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit rubble;

interface

uses
   systems, serverstream, materials, techtree, tttokenizer;

type
   TRubbleCollectionMessage = class(TBusMessage)
   private
      FCount: Cardinal;
      FResult: TMaterialQuantityArray;
      function GetComposition(): TMaterialQuantityArray;
   public
      procedure Grow(Count: Cardinal);
      procedure AddMaterial(Material: TMaterial; Quantity: UInt64);
      property Composition: TMaterialQuantityArray read GetComposition;
   end;

type
   TRubblePileFeatureClass = class(TFeatureClass)
   strict protected
      function GetFeatureNodeClass(): FeatureNodeReference; override;
   public
      constructor CreateFromTechnologyTree(Reader: TTechTreeReader); override;
      function InitFeatureNode(ASystem: TSystem): TFeatureNode; override;
   end;

   TRubblePileFeatureNode = class(TFeatureNode)
   strict private
      FComposition: TMaterialQuantityArray;
      FDiameter: Double;
   protected
      function GetMass(): Double; override; // kg
      function GetSize(): Double; override; // m
      function HandleBusMessage(Message: TBusMessage): Boolean; override;
      procedure Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter); override;
   public
      constructor Create(ASystem: TSystem; ADiameter: Double; AComposition: TMaterialQuantityArray);
      procedure UpdateJournal(Journal: TJournalWriter); override;
      procedure ApplyJournal(Journal: TJournalReader); override;
      procedure DescribeExistentiality(var IsDefinitelyReal, IsDefinitelyGhost: Boolean); override;
      procedure Resize(NewSize: Double);
      procedure AbsorbRubble(Composition: TMaterialQuantityArray);
   end;

implementation

uses
   isdprotocol, sysutils, exceptions, knowledge, commonbuses, region;

procedure TRubbleCollectionMessage.Grow(Count: Cardinal);
begin
   if (Length(FResult) < FCount + Count) then
   begin
      SetLength(FResult, FCount + Count);
   end;
end;

procedure TRubbleCollectionMessage.AddMaterial(Material: TMaterial; Quantity: UInt64);
begin
   Assert(Length(FResult) > FCount);
   FResult[FCount].Init(Material, Quantity);
end;

function TRubbleCollectionMessage.GetComposition(): TMaterialQuantityArray;
begin
   SetLength(FResult, FCount);
   Result := FResult;
end;


constructor TRubblePileFeatureClass.CreateFromTechnologyTree(Reader: TTechTreeReader);
begin
   inherited Create();
   Reader.Tokens.Error('Feature class %s is reserved for internal asset classes', [ClassName]);
end;

function TRubblePileFeatureClass.GetFeatureNodeClass(): FeatureNodeReference;
begin
   Result := TRubblePileFeatureNode;
end;

function TRubblePileFeatureClass.InitFeatureNode(ASystem: TSystem): TFeatureNode;
begin
   Result := TRubblePileFeatureNode.Create(ASystem, 0.0, []);
end;


constructor TRubblePileFeatureNode.Create(ASystem: TSystem; ADiameter: Double; AComposition: TMaterialQuantityArray);
var
   CompositionEntry: TMaterialQuantity;
begin
   inherited Create(ASystem);
   FDiameter := ADiameter;
   FComposition := AComposition;
   for CompositionEntry in FComposition do
   begin
      Assert(CompositionEntry.Quantity > 0);
      Assert(Assigned(CompositionEntry.Material));
   end;
end;

function TRubblePileFeatureNode.GetMass(): Double; // kg
var
   CompositionEntry: TMaterialQuantity;
begin
   Result := 0.0;
   for CompositionEntry in FComposition do
   begin
      Assert(CompositionEntry.Quantity > 0);
      Assert(Assigned(CompositionEntry.Material));
      Result := Result + CompositionEntry.Quantity * CompositionEntry.Material.MassPerUnit;
   end;
end;

function TRubblePileFeatureNode.GetSize(): Double;
begin
   Result := FDiameter;
end;

function TRubblePileFeatureNode.HandleBusMessage(Message: TBusMessage): Boolean;
var
   RubbleMessage: TRubbleCollectionMessage;
   DismantleMessage: TDismantleMessage;
   Store: TStoreMaterialBusMessage;
   Entry: TMaterialQuantity;
begin
   if (Message is TCheckDisabledBusMessage) then
   begin
      (Message as TCheckDisabledBusMessage).AddReason(drStructuralIntegrity);
      Result := False;
   end
   else
   if (Message is TRubbleCollectionMessage) then
   begin
      RubbleMessage := Message as TRubbleCollectionMessage;
      RubbleMessage.Grow(Length(FComposition)); // $R-
      for Entry in FComposition do
         RubbleMessage.AddMaterial(Entry.Material, Entry.Quantity);
      SetLength(FComposition, 0);
      MarkAsDirty([dkUpdateClients, dkUpdateJournal]);
      Result := False;
   end
   else
   if (Message is TDismantleMessage) then
   begin
      DismantleMessage := Message as TDismantleMessage;
      Assert((not Assigned(Parent.Owner)) or (DismantleMessage.Owner = Parent.Owner));
      for Entry in FComposition do
      begin
         Store := TStoreMaterialBusMessage.Create(DismantleMessage.Target, DismantleMessage.Owner, Entry.Material, Entry.Quantity);
         DismantleMessage.Target.Parent.Parent.InjectBusMessage(Store);
         if (Store.RemainingQuantity > 0) then
            DismantleMessage.AddExcessMaterial(Entry.Material, Store.RemainingQuantity);
         FreeAndNil(Store);
      end;
      SetLength(FComposition, 0);
      MarkAsDirty([dkUpdateClients, dkUpdateJournal]);
      Result := False;
   end
   else
      Result := False;
end;

procedure TRubblePileFeatureNode.Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter);
var
   KnownMaterials: TGetKnownMaterialsMessage;
   Other: UInt64;
   Index: Cardinal;
begin
   Writer.WriteCardinal(fcRubblePile);
   Other := 0;
   if (Length(FComposition) > 0) then
   begin
      KnownMaterials := TGetKnownMaterialsMessage.Create(System.DynastyByIndex[DynastyIndex]);
      InjectBusMessage(KnownMaterials); // we ignore the result - it doesn't matter if it wasn't handled
      for Index := Low(FComposition) to High(FComposition) do // $R-
      begin
         Assert(Assigned(FComposition[Index].Material));
         Assert(FComposition[Index].Quantity > 0);
         if (KnownMaterials.Knows(FComposition[Index].Material)) then
         begin
            Writer.WriteInt32(FComposition[Index].Material.ID);
            Writer.WriteUInt64(FComposition[Index].Quantity);
         end
         else
            Inc(Other, FComposition[Index].Quantity);
      end;
      FreeAndNil(KnownMaterials);
   end;
   Writer.WriteCardinal(0);
   Writer.WriteUInt64(Other);
end;

procedure TRubblePileFeatureNode.UpdateJournal(Journal: TJournalWriter);
var
   Index: Cardinal;
begin
   Journal.WriteDouble(FDiameter);
   Journal.WriteCardinal(Length(FComposition));
   if (Length(FComposition) > 0) then
      for Index := Low(FComposition) to High(FComposition) do // $R-
      begin
         Assert(Assigned(FComposition[Index].Material));
         Assert(FComposition[Index].Quantity > 0);
         Journal.WriteMaterialReference(FComposition[Index].Material);
         Journal.WriteUInt64(FComposition[Index].Quantity);
      end;
end;

procedure TRubblePileFeatureNode.ApplyJournal(Journal: TJournalReader);
var
   Index: Cardinal;
   Material: TMaterial;
   Quantity: UInt64;
begin
   FDiameter := Journal.ReadDouble();
   SetLength(FComposition, Journal.ReadCardinal());
   if (Length(FComposition) > 0) then
      for Index := Low(FComposition) to High(FComposition) do // $R-
      begin
         Material := Journal.ReadMaterialReference();
         Assert(Assigned(Material));
         Quantity := Journal.ReadUInt64();
         FComposition[Index].Init(Material, Quantity);
         Assert(Assigned(FComposition[Index].Material));
         Assert(FComposition[Index].Quantity > 0);
      end;
end;

procedure TRubblePileFeatureNode.DescribeExistentiality(var IsDefinitelyReal, IsDefinitelyGhost: Boolean);
begin
   IsDefinitelyReal := True;
end;

procedure TRubblePileFeatureNode.Resize(NewSize: Double);
begin
   FDiameter := NewSize;
end;

procedure TRubblePileFeatureNode.AbsorbRubble(Composition: TMaterialQuantityArray);
var
   IndexSrc, IndexDst: Cardinal;
   CompositionEntry: TMaterialQuantity;
begin
   Assert(Length(Composition) > 0);
   if (Length(FComposition) = 0) then
   begin
      FComposition := Composition;
   end
   else
   begin
      IndexDst := Length(FComposition); // $R-
      SetLength(FComposition, Length(FComposition) + Length(Composition));
      for IndexSrc := Low(Composition) to High(Composition) do // $R-
      begin
         FComposition[IndexDst] := Composition[IndexSrc];
         Inc(IndexDst);
      end;
   end;
   {$IFOPT C+}
   for CompositionEntry in FComposition do
   begin
      Assert(CompositionEntry.Quantity > 0);
      Assert(Assigned(CompositionEntry.Material));
   end;
   {$ENDIF}
end;

initialization
   RegisterFeatureClass(TRubblePileFeatureClass);
end.