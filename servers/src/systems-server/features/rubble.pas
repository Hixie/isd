{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit rubble;

interface

uses
   systems, serverstream, materials;

type
   TRubbleCompositionEntry = record
      Material: TMaterial;
      Quantity: Int64;
      constructor Create(AMaterial: TMaterial; AQuantity: Int64);
   end;

   TRubbleComposition = array of TRubbleCompositionEntry;

   TRubbleCollectionMessage = class(TBusMessage)
   private
      FCount: Cardinal;
      FResult: TRubbleComposition;
      function GetComposition(): TRubbleComposition;
   public
      procedure Grow(Count: Cardinal);
      procedure AddMaterial(Material: TMaterial; Quantity: Int64);
      property Composition: TRubbleComposition read GetComposition;
   end;

type
   TRubblePileFeatureClass = class(TFeatureClass)
   strict protected
      function GetFeatureNodeClass(): FeatureNodeReference; override;
   public
      function InitFeatureNode(): TFeatureNode; override;
   end;

   TRubblePileFeatureNode = class(TFeatureNode)
   strict private
      FComposition: TRubbleComposition;
      FDiameter: Double;
   protected
      function GetMass(): Double; override; // kg
      function GetSize(): Double; override; // m
      function HandleBusMessage(Message: TBusMessage): Boolean; override;
      procedure Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter; CachedSystem: TSystem); override;
   public
      constructor Create(ADiameter: Double; AComposition: TRubbleComposition);
      procedure UpdateJournal(Journal: TJournalWriter); override;
      procedure ApplyJournal(Journal: TJournalReader; CachedSystem: TSystem); override;
      procedure DescribeExistentiality(var IsDefinitelyReal, IsDefinitelyGhost: Boolean); override;
   end;

implementation

uses
   isdprotocol, sysutils, exceptions;

constructor TRubbleCompositionEntry.Create(AMaterial: TMaterial; AQuantity: Int64);
begin
   Material := AMaterial;
   Quantity := AQuantity;
end;


procedure TRubbleCollectionMessage.Grow(Count: Cardinal);
begin
   if (Length(FResult) < FCount + Count) then
   begin
      SetLength(FResult, FCount + Count);
   end;
end;

procedure TRubbleCollectionMessage.AddMaterial(Material: TMaterial; Quantity: Int64);
begin
   Assert(Length(FResult) > FCount);
   FResult[FCount].Create(Material, Quantity);
end;

function TRubbleCollectionMessage.GetComposition(): TRubbleComposition;
begin
   SetLength(FResult, FCount);
   Result := FResult;
end;


function TRubblePileFeatureClass.GetFeatureNodeClass(): FeatureNodeReference;
begin
   Result := TRubblePileFeatureNode;
end;

function TRubblePileFeatureClass.InitFeatureNode(): TFeatureNode;
begin
   Result := nil;
   // TODO: create a technology that knows how to create a pile from a mass of material
   raise Exception.Create('Cannot create a TRubblePileFeatureNode from a prototype; it must have a unique composition.');
end;


constructor TRubblePileFeatureNode.Create(ADiameter: Double; AComposition: TRubbleComposition);
begin
   inherited Create();
   FDiameter := ADiameter;
   FComposition := AComposition;
end;

function TRubblePileFeatureNode.GetMass(): Double; // kg
var
   CompositionEntry: TRubbleCompositionEntry;
begin
   Result := 0.0;
   for CompositionEntry in FComposition do
      Result := Result + CompositionEntry.Quantity * CompositionEntry.Material.MassPerUnit;
end;

function TRubblePileFeatureNode.GetSize(): Double;
begin
   Result := FDiameter;
end;

function TRubblePileFeatureNode.HandleBusMessage(Message: TBusMessage): Boolean;
var
   RubbleMessage: TRubbleCollectionMessage;
   Entry: TRubbleCompositionEntry;
begin
   Result := False;
   if (Message is TRubbleCollectionMessage) then
   begin
      RubbleMessage := Message as TRubbleCollectionMessage;
      RubbleMessage.Grow(Length(FComposition)); // $R-
      for Entry in FComposition do
         RubbleMessage.AddMaterial(Entry.Material, Entry.Quantity);
      exit;
   end;
end;

procedure TRubblePileFeatureNode.Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter; CachedSystem: TSystem);
begin
   Writer.WriteCardinal(fcRubblePile);
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
         Journal.WriteMaterialReference(FComposition[Index].Material);
         Journal.WriteInt64(FComposition[Index].Quantity);
      end;
end;

procedure TRubblePileFeatureNode.ApplyJournal(Journal: TJournalReader; CachedSystem: TSystem);
var
   Index: Cardinal;
begin
   FDiameter := Journal.ReadDouble();
   SetLength(FComposition, Journal.ReadCardinal());
   if (Length(FComposition) > 0) then
      for Index := Low(FComposition) to High(FComposition) do // $R-
      begin
         FComposition[Index].Create(Journal.ReadMaterialReference(), Journal.ReadInt64());
      end;
end;

procedure TRubblePileFeatureNode.DescribeExistentiality(var IsDefinitelyReal, IsDefinitelyGhost: Boolean);
begin
   IsDefinitelyReal := True;
end;

end.