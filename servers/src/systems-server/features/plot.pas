{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit plot;

interface

uses
   systems, systemdynasty, serverstream, materials;

const
   pcNothing = 0;
   pcColonyShip = 1;

type
   TDynastyOriginalColonyShipFeatureClass = class(TFeatureClass)
   strict protected
      function GetFeatureNodeClass(): FeatureNodeReference; override;
   public
      function InitFeatureNode(): TFeatureNode; override;
   end;

   TDynastyOriginalColonyShipFeatureNode = class(TFeatureNode)
   private
      FDynasty: TDynasty; // TODO: what if this dynasty disappears from the system?
   protected
      function GetMass(): Double; override;
      function GetSize(): Double; override;
      function GetFeatureName(): UTF8String; override;
      procedure Walk(PreCallback: TPreWalkCallback; PostCallback: TPostWalkCallback); override;
      function HandleBusMessage(Message: TBusMessage): Boolean; override;
      procedure Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter; System: TSystem); override;
   public
      constructor Create(ADynasty: TDynasty);
      procedure RecordSnapshot(Journal: TJournalWriter); override;
      procedure ApplyJournal(Journal: TJournalReader; System: TSystem); override;
      property Dynasty: TDynasty read FDynasty;
   end;

implementation

uses
   sysutils, isdprotocol;

function TDynastyOriginalColonyShipFeatureClass.GetFeatureNodeClass(): FeatureNodeReference;
begin
   Result := TDynastyOriginalColonyShipFeatureNode;
end;

function TDynastyOriginalColonyShipFeatureClass.InitFeatureNode(): TFeatureNode;
begin
   Result := nil;
   raise Exception.Create('Cannot create a TDynastyOriginalColonyShipFeatureNode from a prototype, it must be given a dynasty.');
end;


constructor TDynastyOriginalColonyShipFeatureNode.Create(ADynasty: TDynasty);
begin
   inherited Create();
   FDynasty := ADynasty;
end;

function TDynastyOriginalColonyShipFeatureNode.GetMass(): Double;
begin
   Result := 0.0;
end;

function TDynastyOriginalColonyShipFeatureNode.GetSize(): Double;
begin
   Result := 0.0;
end;

function TDynastyOriginalColonyShipFeatureNode.GetFeatureName(): UTF8String;
begin
   Result := '';
end;

procedure TDynastyOriginalColonyShipFeatureNode.Walk(PreCallback: TPreWalkCallback; PostCallback: TPostWalkCallback);
begin
end;

function TDynastyOriginalColonyShipFeatureNode.HandleBusMessage(Message: TBusMessage): Boolean;
begin
   Result := False;
end;

procedure TDynastyOriginalColonyShipFeatureNode.Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter; System: TSystem);
begin
   Assert(Assigned(FDynasty));
   if (FDynasty = Parent.Owner) then
   begin
      Writer.WriteCardinal(fcPlotControl);
      Writer.WriteCardinal(pcColonyShip);
   end;
end;

procedure TDynastyOriginalColonyShipFeatureNode.RecordSnapshot(Journal: TJournalWriter);
begin
   Assert(Parent.Owner = FDynasty); // if this is ever false, we need to either clear FDynasty or support having dynasties that have no assets in the system
   Journal.WriteDynastyReference(FDynasty);
end;

procedure TDynastyOriginalColonyShipFeatureNode.ApplyJournal(Journal: TJournalReader; System: TSystem);
begin
   FDynasty := Journal.ReadDynastyReference();
end;

end.