{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit mining;

interface

// TODO: refactor to avoid code duplication with refining.pas

uses
   basenetwork, systems, serverstream, materials, techtree,
   messageport, region, time, systemdynasty;

type
   TMiningFeatureClass = class(TFeatureClass)
   private
      FBandwidth: TRate; // kg per second
   strict protected
      function GetFeatureNodeClass(): FeatureNodeReference; override;
   public
      constructor CreateFromTechnologyTree(Reader: TTechTreeReader); override;
      function InitFeatureNode(ASystem: TSystem): TFeatureNode; override;
   end;

   TMiningFeatureNode = class(TFeatureNode, IMiner)
   strict private
      FFeatureClass: TMiningFeatureClass;
      FStatus: TRegionClientFields;
   private // IMiner
      function GetMinerMaxRate(): TRate; // kg per second
      function GetMinerCurrentRate(): TRate; // kg per second
      procedure SetMinerRegion(Region: TRegionFeatureNode);
      procedure StartMiner(Rate: TRate; SourceLimiting, TargetLimiting: Boolean);
      procedure DisconnectMiner();
      function GetDynasty(): TDynasty;
   protected
      constructor CreateFromJournal(Journal: TJournalReader; AFeatureClass: TFeatureClass; ASystem: TSystem); override;
      procedure HandleChanges(); override;
      procedure Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter); override;
   public
      constructor Create(ASystem: TSystem; AFeatureClass: TMiningFeatureClass);
      destructor Destroy(); override;
      procedure UpdateJournal(Journal: TJournalWriter); override;
      procedure ApplyJournal(Journal: TJournalReader); override;
   end;

// TODO: handle our ancestor chain changing

implementation

uses
   exceptions, sysutils, isdprotocol, knowledge, messages, typedump, commonbuses;

constructor TMiningFeatureClass.CreateFromTechnologyTree(Reader: TTechTreeReader);
begin
   inherited Create();
   Reader.Tokens.ReadIdentifier('max');
   Reader.Tokens.ReadIdentifier('throughput');
   FBandwidth := ReadMassPerTime(Reader.Tokens);
end;

function TMiningFeatureClass.GetFeatureNodeClass(): FeatureNodeReference;
begin
   Result := TMiningFeatureNode;
end;

function TMiningFeatureClass.InitFeatureNode(ASystem: TSystem): TFeatureNode;
begin
   Result := TMiningFeatureNode.Create(ASystem, Self);
end;


constructor TMiningFeatureNode.Create(ASystem: TSystem; AFeatureClass: TMiningFeatureClass);
begin
   inherited Create(ASystem);
   FFeatureClass := AFeatureClass;
end;

constructor TMiningFeatureNode.CreateFromJournal(Journal: TJournalReader; AFeatureClass: TFeatureClass; ASystem: TSystem);
begin
   Assert(Assigned(AFeatureClass));
   FFeatureClass := AFeatureClass as TMiningFeatureClass;
   inherited;
end;

destructor TMiningFeatureNode.Destroy();
begin
   inherited;
end;

function TMiningFeatureNode.GetMinerMaxRate(): TRate; // kg per second
begin
   Result := FFeatureClass.FBandwidth;
end;

function TMiningFeatureNode.GetMinerCurrentRate(): TRate; // kg per second
begin
   Result := FStatus.Rate;
end;

procedure TMiningFeatureNode.SetMinerRegion(Region: TRegionFeatureNode);
begin
   FStatus.SetRegion(Region);
end;

procedure TMiningFeatureNode.StartMiner(Rate: TRate; SourceLimiting, TargetLimiting: Boolean); // kg per second
begin
   if (FStatus.Update(Rate, SourceLimiting, TargetLimiting)) then
      MarkAsDirty([dkUpdateClients]);
end;

procedure TMiningFeatureNode.DisconnectMiner();
begin
   FStatus.Reset();
   MarkAsDirty([dkUpdateClients, dkNeedsHandleChanges]);
end;

function TMiningFeatureNode.GetDynasty(): TDynasty;
begin
   Result := Parent.Owner;
end;

procedure TMiningFeatureNode.HandleChanges();
var
   DisabledReasons: TDisabledReasons;
   Message: TRegisterMinerBusMessage;
begin
   DisabledReasons := CheckDisabled(Parent);
   if ((DisabledReasons <> []) and (FStatus.Connected)) then
      FStatus.Region.RemoveMiner(Self);
   if (DisabledReasons <> FStatus.DisabledReasons) then
   begin
      FStatus.SetDisabledReasons(DisabledReasons);
      MarkAsDirty([dkUpdateClients]);
   end;
   if (FStatus.NeedsConnection) then
   begin
      Message := TRegisterMinerBusMessage.Create(Self);
      if (InjectBusMessage(Message) <> mrHandled) then
         FStatus.SetNoRegion();
      FreeAndNil(Message);
   end;
   inherited;
end;

procedure TMiningFeatureNode.Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter);
var
   Visibility: TVisibility;
   Flags: Byte;
begin
   Visibility := Parent.ReadVisibilityFor(DynastyIndex);
   if ((dmDetectable * Visibility <> []) and (dmClassKnown in Visibility)) then
   begin
      Writer.WriteCardinal(fcMining);
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

procedure TMiningFeatureNode.UpdateJournal(Journal: TJournalWriter);
begin
end;

procedure TMiningFeatureNode.ApplyJournal(Journal: TJournalReader);
begin
end;

initialization
   RegisterFeatureClass(TMiningFeatureClass);
end.