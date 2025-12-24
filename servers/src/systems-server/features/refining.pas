{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit refining;

interface

// TODO: refactor to avoid code duplication with mining.pas

uses
   basenetwork, systems, serverstream, materials, techtree,
   messageport, region, time, systemdynasty;

type
   TRefiningFeatureClass = class(TFeatureClass)
   private
      FOre: TOres;
      FBandwidth: TRate; // kg per second
   strict protected
      function GetFeatureNodeClass(): FeatureNodeReference; override;
   public
      constructor CreateFromTechnologyTree(Reader: TTechTreeReader); override;
      function InitFeatureNode(ASystem: TSystem): TFeatureNode; override;
   end;

   TRefiningFeatureNode = class(TFeatureNode, IRefinery)
   strict private
      FFeatureClass: TRefiningFeatureClass;
      FStatus: TRegionClientFields;
      FOreKnowledge: TKnowledgeSummary;
   private // IRefinery
      function GetRefineryOre(): TOres;
      function GetRefineryMaxRate(): TRate; // kg per second
      function GetRefineryCurrentRate(): TRate; // kg per second
      procedure SetRefineryRegion(Region: TRegionFeatureNode);
      procedure StartRefinery(Rate: TRate; SourceLimiting, TargetLimiting: Boolean); // kg per second
      procedure DisconnectRefinery();
      function GetDynasty(): TDynasty;
   protected
      constructor CreateFromJournal(Journal: TJournalReader; AFeatureClass: TFeatureClass; ASystem: TSystem); override;
      procedure HandleChanges(); override;
      procedure ResetDynastyNotes(OldDynasties: TDynastyIndexHashTable; NewDynasties: TDynasty.TArray); override;
      procedure ResetVisibility(); override;
      procedure HandleKnowledge(const DynastyIndex: Cardinal; const Sensors: ISensorsProvider); override;
      procedure Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter); override;
   public
      constructor Create(ASystem: TSystem; AFeatureClass: TRefiningFeatureClass);
      destructor Destroy(); override;
      procedure UpdateJournal(Journal: TJournalWriter); override;
      procedure ApplyJournal(Journal: TJournalReader); override;
   end;

// TODO: handle our ancestor chain changing

implementation

uses
   exceptions, sysutils, isdprotocol, knowledge, typedump, commonbuses;

constructor TRefiningFeatureClass.CreateFromTechnologyTree(Reader: TTechTreeReader);
var
   Material: TMaterial;
begin
   inherited Create();
   Reader.Tokens.ReadIdentifier('for');
   Material := ReadMaterial(Reader);
   if ((Material.ID < Low(TOres)) or (Material.ID > High(TOres))) then
      Reader.Tokens.Error('Material "%s" is not an ore', [Material.Name]);
   FOre := Material.ID; // $R-
   Reader.Tokens.ReadComma();
   Reader.Tokens.ReadIdentifier('max');
   Reader.Tokens.ReadIdentifier('throughput');
   FBandwidth := ReadMassPerTime(Reader.Tokens);
end;

function TRefiningFeatureClass.GetFeatureNodeClass(): FeatureNodeReference;
begin
   Result := TRefiningFeatureNode;
end;

function TRefiningFeatureClass.InitFeatureNode(ASystem: TSystem): TFeatureNode;
begin
   Result := TRefiningFeatureNode.Create(ASystem, Self);
end;


constructor TRefiningFeatureNode.Create(ASystem: TSystem; AFeatureClass: TRefiningFeatureClass);
begin
   inherited Create(ASystem);
   FFeatureClass := AFeatureClass;
end;

constructor TRefiningFeatureNode.CreateFromJournal(Journal: TJournalReader; AFeatureClass: TFeatureClass; ASystem: TSystem);
begin
   Assert(Assigned(AFeatureClass));
   FFeatureClass := AFeatureClass as TRefiningFeatureClass;
   inherited;
end;

destructor TRefiningFeatureNode.Destroy();
begin
   if (FStatus.Connected) then
      FStatus.Region.RemoveRefinery(Self);
   inherited;
end;

function TRefiningFeatureNode.GetRefineryOre(): TOres;
begin
   Result := FFeatureClass.FOre;
end;

function TRefiningFeatureNode.GetRefineryMaxRate(): TRate; // kg per second
begin
   Result := FFeatureClass.FBandwidth * FStatus.RateLimit;
end;

function TRefiningFeatureNode.GetRefineryCurrentRate(): TRate; // kg per second
begin
   Result := FStatus.Rate;
end;

procedure TRefiningFeatureNode.SetRefineryRegion(Region: TRegionFeatureNode);
begin
   FStatus.SetRegion(Region);
end;

procedure TRefiningFeatureNode.StartRefinery(Rate: TRate; SourceLimiting, TargetLimiting: Boolean); // kg per second
begin
   Assert(Assigned(FStatus.Region));
   if (FStatus.Update(Rate, SourceLimiting, TargetLimiting)) then
      MarkAsDirty([dkUpdateClients]);
end;

procedure TRefiningFeatureNode.DisconnectRefinery();
begin
   FStatus.Reset();
   MarkAsDirty([dkUpdateClients, dkNeedsHandleChanges]);
end;

function TRefiningFeatureNode.GetDynasty(): TDynasty;
begin
   Result := Parent.Owner;
end;

procedure TRefiningFeatureNode.HandleChanges();
var
   DisabledReasons: TDisabledReasons;
   Message: TRegisterRefineryBusMessage;
   RateLimit: Double;
begin
   DisabledReasons := CheckDisabled(Parent, RateLimit);
   if ((RateLimit = 0.0) and (FStatus.Connected)) then
      FStatus.Region.RemoveRefinery(Self);
   if ((DisabledReasons <> FStatus.DisabledReasons) or (RateLimit <> FStatus.RateLimit)) then
   begin
      if (DisabledReasons <> FStatus.DisabledReasons) then
         MarkAsDirty([dkUpdateClients]);
      FStatus.SetDisabledReasons(DisabledReasons, RateLimit);
   end;
   if (FStatus.NeedsConnection) then
   begin
      Message := TRegisterRefineryBusMessage.Create(Self);
      if (InjectBusMessage(Message) <> irHandled) then
         FStatus.SetNoRegion();
      FreeAndNil(Message);
   end;
   inherited;
end;

procedure TRefiningFeatureNode.Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter);
var
   Visibility: TVisibility;
   Flags: Byte;
begin
   Visibility := Parent.ReadVisibilityFor(DynastyIndex);
   if ((dmDetectable * Visibility <> []) and (dmClassKnown in Visibility)) then
   begin
      Writer.WriteCardinal(fcRefining);
      if (FOreKnowledge.GetEntry(DynastyIndex)) then
      begin
         Writer.WriteCardinal(FFeatureClass.FOre);
      end
      else
      begin
         Writer.WriteCardinal(0);
      end;
      Writer.WriteDouble(FFeatureClass.FBandwidth.AsDouble);
      Writer.WriteCardinal(Cardinal(FStatus.DisabledReasons));
      Flags := $00;
      if (FStatus.SourceLimiting) then
         Flags := Flags or $01; // $R-
      if (FStatus.TargetLimiting) then
         Flags := Flags or $02; // $R-
      Writer.WriteByte(Flags);
      Writer.WriteDouble(FStatus.Rate.AsDouble);
   end;
end;

procedure TRefiningFeatureNode.ResetDynastyNotes(OldDynasties: TDynastyIndexHashTable; NewDynasties: TDynasty.TArray);
begin
   FOreKnowledge.Init(Length(NewDynasties)); // $R-
end;

procedure TRefiningFeatureNode.ResetVisibility();
begin
   FOreKnowledge.Reset();
end;

procedure TRefiningFeatureNode.HandleKnowledge(const DynastyIndex: Cardinal; const Sensors: ISensorsProvider);
begin
   FOreKnowledge.SetEntry(DynastyIndex, Sensors.Knows(System.Encyclopedia.Materials[FFeatureClass.FOre]));
end;

procedure TRefiningFeatureNode.UpdateJournal(Journal: TJournalWriter);
begin
end;

procedure TRefiningFeatureNode.ApplyJournal(Journal: TJournalReader);
begin
end;

initialization
   RegisterFeatureClass(TRefiningFeatureClass);
end.