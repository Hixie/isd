{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit planetary;

interface

uses
   systems, serverstream, materials;

type
   TPlanetaryCompositionEntry = record
      Material: TMaterial;
      Mass: Double;
      constructor Create(AMaterial: TMaterial; AMass: Double);
   end;

   TPlanetaryComposition = array of TPlanetaryCompositionEntry;

   TPlanetaryBodyFeatureClass = class(TFeatureClass)
   strict protected
      function GetFeatureNodeClass(): FeatureNodeReference; override;
   public
      function InitFeatureNode(): TFeatureNode; override;
   end;

   TPlanetaryBodyFeatureNode = class(TFeatureNode)
   protected
      FComposition: TPlanetaryComposition;
      FStructuralIntegrity: Cardinal;
      FDiameter: Double;
      function GetMass(): Double; override; // kg
      function GetSize(): Double; override; // m
      function GetFeatureName(): UTF8String; override;
      procedure Walk(PreCallback: TPreWalkCallback; PostCallback: TPostWalkCallback); override;
      function HandleBusMessage(Message: TBusMessage): Boolean; override;
      procedure ResetVisibility(DynastyCount: Cardinal); override;
      procedure Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter; System: TSystem); override;
   public
      constructor Create(ADiameter: Double; AComposition: TPlanetaryComposition; AStructuralIntegrity: Cardinal);
      procedure RecordSnapshot(Journal: TJournalWriter); override;
      procedure ApplyJournal(Journal: TJournalReader); override;
      property StructuralIntegrity: Cardinal read FStructuralIntegrity;
   end;

implementation

uses
   isdprotocol, sysutils, exceptions;

constructor TPlanetaryCompositionEntry.Create(AMaterial: TMaterial; AMass: Double);
begin
   Material := AMaterial;
   Mass := AMass;
end;


function TPlanetaryBodyFeatureClass.GetFeatureNodeClass(): FeatureNodeReference;
begin
   Result := TPlanetaryBodyFeatureNode;
end;

function TPlanetaryBodyFeatureClass.InitFeatureNode(): TFeatureNode;
begin
   Result := nil;
   // TODO: create a technology that knows how to create a planet from a mass of material
   raise Exception.Create('Cannot create a TPlanetaryBodyFeatureClass from a prototype; it must have a unique composition.');
end;


constructor TPlanetaryBodyFeatureNode.Create(ADiameter: Double; AComposition: TPlanetaryComposition; AStructuralIntegrity: Cardinal);
begin
   inherited Create();
   FDiameter := ADiameter;
   FComposition := AComposition;
   FStructuralIntegrity := AStructuralIntegrity;
end;

function TPlanetaryBodyFeatureNode.GetMass(): Double; // kg
var
   CompositionEntry: TPlanetaryCompositionEntry;
begin
   Result := 0.0;
   for CompositionEntry in FComposition do
      Result := Result + CompositionEntry.Mass;
end;

function TPlanetaryBodyFeatureNode.GetSize(): Double;
begin
   Result := FDiameter;
end;

function TPlanetaryBodyFeatureNode.GetFeatureName(): UTF8String;
begin
   Result := '';
end;

procedure TPlanetaryBodyFeatureNode.Walk(PreCallback: TPreWalkCallback; PostCallback: TPostWalkCallback);
begin
end;

function TPlanetaryBodyFeatureNode.HandleBusMessage(Message: TBusMessage): Boolean;
begin
   Result := False;
end;

procedure TPlanetaryBodyFeatureNode.ResetVisibility(DynastyCount: Cardinal);
begin
end;

procedure TPlanetaryBodyFeatureNode.Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter; System: TSystem);
begin
   Writer.WriteCardinal(fcPlanetaryBody);
   Writer.WriteCardinal(FStructuralIntegrity);
end;

procedure TPlanetaryBodyFeatureNode.RecordSnapshot(Journal: TJournalWriter);
var
   Index: Cardinal;
begin
   Journal.WriteDouble(FDiameter);
   Journal.WriteCardinal(Length(FComposition));
   Assert(Length(FComposition) > 0);
   for Index := Low(FComposition) to High(FComposition) do // $R-
   begin
      Journal.WriteMaterialReference(FComposition[Index].Material);
      Journal.WriteDouble(FComposition[Index].Mass);
   end;
   Journal.WriteCardinal(FStructuralIntegrity);
end;

procedure TPlanetaryBodyFeatureNode.ApplyJournal(Journal: TJournalReader);
var
   Index: Cardinal;
begin
   FDiameter := Journal.ReadDouble();
   SetLength(FComposition, Journal.ReadCardinal());
   Assert(Length(FComposition) > 0);
   for Index := Low(FComposition) to High(FComposition) do // $R-
   begin
      FComposition[Index].Material := Journal.ReadMaterialReference();
      FComposition[Index].Mass := Journal.ReadDouble();
   end;
   FStructuralIntegrity := Journal.ReadCardinal();
end;

end.