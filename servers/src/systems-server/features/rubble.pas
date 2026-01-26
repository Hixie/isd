{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit rubble;

interface

uses
   systems, serverstream, materials, techtree, tttokenizer, basenetwork, masses, systemdynasty;

type
   // This is sent just before an asset is demolished. The feature
   // should account for all of its mass; if there's any specific
   // materials for which handling should be deferred to the asset
   // doing the demolition, it can use AddMaterial (this is only
   // available for materials, not other sources of mass like people,
   // unsorted ore, etc).
   TRubbleCollectionMessage = class(TBusMessage)
   private
      FCount: Cardinal;
      FResult: TMaterialQuantity64Array;
      function GetComposition(): TMaterialQuantity64Array;
   public
      procedure Grow(Count: Cardinal);
      procedure AddMaterial(Material: TMaterial; Quantity: TQuantity64);
      property Composition: TMaterialQuantity64Array read GetComposition;
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
      FComposition: TMaterialQuantity64Array;
      FDiameter: Double;
   protected
      function GetMass(): TMass; override; // kg
      function GetSize(): Double; override; // m
      function HandleBusMessage(Message: TBusMessage): THandleBusMessageResult; override;
      procedure Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter); override;
   public
      constructor Create(ASystem: TSystem; ADiameter: Double; AComposition: TMaterialQuantity64Array);
      procedure UpdateJournal(Journal: TJournalWriter); override;
      procedure ApplyJournal(Journal: TJournalReader); override;
      procedure DescribeExistentiality(var IsDefinitelyReal, IsDefinitelyGhost: Boolean); override;
      function HandleCommand(PlayerDynasty: TDynasty; Command: UTF8String; var Message: TMessage): Boolean; override;
      procedure Resize(NewSize: Double);
      procedure AbsorbRubble(Composition: TMaterialQuantity64Array);
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

procedure TRubbleCollectionMessage.AddMaterial(Material: TMaterial; Quantity: TQuantity64);
begin
   Assert(Length(FResult) > FCount);
   FResult[FCount].Init(Material, Quantity);
end;

function TRubbleCollectionMessage.GetComposition(): TMaterialQuantity64Array;
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


constructor TRubblePileFeatureNode.Create(ASystem: TSystem; ADiameter: Double; AComposition: TMaterialQuantity64Array);
var
   CompositionEntry: TMaterialQuantity64;
begin
   inherited Create(ASystem);
   FDiameter := ADiameter;
   FComposition := AComposition;
   for CompositionEntry in FComposition do
   begin
      Assert(CompositionEntry.Quantity.IsPositive);
      Assert(Assigned(CompositionEntry.Material));
   end;
end;

function TRubblePileFeatureNode.GetMass(): TMass; // kg
var
   CompositionEntry: TMaterialQuantity64;
begin
   Result := TMass.Zero;
   for CompositionEntry in FComposition do
   begin
      Assert(CompositionEntry.Quantity.IsPositive);
      Assert(Assigned(CompositionEntry.Material));
      Result := Result + CompositionEntry.Quantity * CompositionEntry.Material.MassPerUnit;
   end;
end;

function TRubblePileFeatureNode.GetSize(): Double;
begin
   Result := FDiameter;
end;

function TRubblePileFeatureNode.HandleBusMessage(Message: TBusMessage): THandleBusMessageResult;
var
   RubbleMessage: TRubbleCollectionMessage;
   DismantleMessage: TDismantleMessage;
   Store: TStoreMaterialBusMessage;
   Entry: TMaterialQuantity64;
begin
   if (Message is TCheckDisabledBusMessage) then
   begin
      (Message as TCheckDisabledBusMessage).AddReason(drStructuralIntegrity);
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
         if (Store.RemainingQuantity.IsPositive) then
            DismantleMessage.AddExcessMaterial(Entry.Material, Store.RemainingQuantity);
         FreeAndNil(Store);
      end;
      SetLength(FComposition, 0);
      MarkAsDirty([dkUpdateClients, dkUpdateJournal]);
   end;
   Result := inherited;
end;

procedure TRubblePileFeatureNode.Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter);
var
   KnownMaterials: TGetKnownMaterialsMessage;
   Other: TQuantity64;
   Index: Cardinal;
begin
   Writer.WriteCardinal(fcRubblePile);
   Other := TQuantity64.Zero;
   if (Length(FComposition) > 0) then
   begin
      KnownMaterials := TGetKnownMaterialsMessage.Create(System.DynastyByIndex[DynastyIndex]);
      InjectBusMessage(KnownMaterials); // we ignore the result - it doesn't matter if it wasn't handled
      for Index := Low(FComposition) to High(FComposition) do // $R-
      begin
         Assert(Assigned(FComposition[Index].Material));
         Assert(FComposition[Index].Quantity.IsPositive);
         if (KnownMaterials.Knows(FComposition[Index].Material)) then
         begin
            Writer.WriteInt32(FComposition[Index].Material.ID);
            Writer.WriteInt64(FComposition[Index].Quantity.AsInt64);
         end
         else
            Other := Other + FComposition[Index].Quantity;
      end;
      FreeAndNil(KnownMaterials);
   end;
   Writer.WriteCardinal(0);
   Writer.WriteInt64(Other.AsInt64);
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
         Assert(FComposition[Index].Quantity.IsPositive);
         Journal.WriteMaterialReference(FComposition[Index].Material);
         Journal.WriteInt64(FComposition[Index].Quantity.AsInt64);
      end;
end;

procedure TRubblePileFeatureNode.ApplyJournal(Journal: TJournalReader);
var
   Index: Cardinal;
   Material: TMaterial;
   Quantity: TQuantity64;
begin
   FDiameter := Journal.ReadDouble();
   SetLength(FComposition, Journal.ReadCardinal());
   if (Length(FComposition) > 0) then
      for Index := Low(FComposition) to High(FComposition) do // $R-
      begin
         Material := Journal.ReadMaterialReference();
         Assert(Assigned(Material));
         Quantity := TQuantity64.FromUnits(Journal.ReadInt64());
         FComposition[Index].Init(Material, Quantity);
         Assert(Assigned(FComposition[Index].Material));
         Assert(FComposition[Index].Quantity.IsPositive);
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

procedure TRubblePileFeatureNode.AbsorbRubble(Composition: TMaterialQuantity64Array);
var
   IndexSrc, IndexDst: Cardinal;
   CompositionEntry: TMaterialQuantity64;
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
      Assert(CompositionEntry.Quantity.IsPositive);
      Assert(Assigned(CompositionEntry.Material));
   end;
   {$ENDIF}
end;

function TRubblePileFeatureNode.HandleCommand(PlayerDynasty: TDynasty; Command: UTF8String; var Message: TMessage): Boolean;
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
   RegisterFeatureClass(TRubblePileFeatureClass);
end.