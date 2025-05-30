{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit plot;

interface

uses
   systems, systemdynasty, serverstream, materials, techtree;

const
   pcNothing = 0;
   pcColonyShip = 1;

type
   TDynastyOriginalColonyShipFeatureClass = class(TFeatureClass)
   strict protected
      function GetFeatureNodeClass(): FeatureNodeReference; override;
   public
      constructor CreateFromTechnologyTree(Reader: TTechTreeReader); override;
      function InitFeatureNode(): TFeatureNode; override;
   end;

   TDynastyOriginalColonyShipFeatureNode = class(TFeatureNode)
   private
      FDynasty: TDynasty; // TODO: what if this dynasty disappears from the system?
   protected
      procedure Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter; CachedSystem: TSystem); override;
   public
      constructor Create(ADynasty: TDynasty);
      procedure UpdateJournal(Journal: TJournalWriter; CachedSystem: TSystem); override;
      procedure ApplyJournal(Journal: TJournalReader; CachedSystem: TSystem); override;
      property Dynasty: TDynasty read FDynasty;
   end;

implementation

uses
   sysutils, isdprotocol;


constructor TDynastyOriginalColonyShipFeatureClass.CreateFromTechnologyTree(Reader: TTechTreeReader);
begin
   Reader.Tokens.Error('Feature class %s is reserved for internal asset classes', [ClassName]);
end;

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

procedure TDynastyOriginalColonyShipFeatureNode.Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter; CachedSystem: TSystem);
begin
   Assert(Assigned(FDynasty));
   if (FDynasty = Parent.Owner) then
   begin
      Writer.WriteCardinal(fcPlotControl);
      Writer.WriteCardinal(pcColonyShip);
   end;
end;

procedure TDynastyOriginalColonyShipFeatureNode.UpdateJournal(Journal: TJournalWriter; CachedSystem: TSystem);
begin
   Assert(Parent.Owner = FDynasty); // if this is ever false, we need to either clear FDynasty or support having dynasties that have no assets in the system
   Journal.WriteDynastyReference(FDynasty);
end;

procedure TDynastyOriginalColonyShipFeatureNode.ApplyJournal(Journal: TJournalReader; CachedSystem: TSystem);
begin
   FDynasty := Journal.ReadDynastyReference();
end;

initialization
   RegisterFeatureClass(TDynastyOriginalColonyShipFeatureClass);
end.