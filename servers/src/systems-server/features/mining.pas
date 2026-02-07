{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit mining;

interface

// TODO: refactor to avoid code duplication with refining.pas

uses
   basenetwork, systems, internals, serverstream, materials,
   messageport, region, time, systemdynasty;

type
   TMiningFeatureClass = class(TFeatureClass)
   private
      FBandwidth: TMassRate; // kg per second
   strict protected
      function GetFeatureNodeClass(): FeatureNodeReference; override;
   public
      constructor CreateFromTechnologyTree(const Reader: TTechTreeReader); override;
      function InitFeatureNode(ASystem: TSystem): TFeatureNode; override;
   end;

   TMiningFeatureNode = class(TFeatureNode, IMiner)
   strict private
      FFeatureClass: TMiningFeatureClass;
      FStatus: specialize TRegionClientFields<TMassRate>;
   private // IMiner
      function GetMinerMaxRate(): TMassRate; // kg per second
      function GetMinerCurrentRate(): TMassRate; // kg per second
      procedure SetMinerRegion(Region: TRegionFeatureNode);
      procedure StartMiner(Rate: TMassRate; SourceLimiting, TargetLimiting: Boolean);
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
   exceptions, sysutils, isdprotocol, knowledge, messages, typedump, commonbuses, ttparser;

constructor TMiningFeatureClass.CreateFromTechnologyTree(const Reader: TTechTreeReader);
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
   if (FStatus.Connected) then
      FStatus.Region.RemoveMiner(Self);
   FStatus.Reset();
   inherited;
end;

function TMiningFeatureNode.GetMinerMaxRate(): TMassRate; // kg per second
begin
   Result := FFeatureClass.FBandwidth * FStatus.RateLimit;
end;

function TMiningFeatureNode.GetMinerCurrentRate(): TMassRate; // kg per second
begin
   Result := FStatus.Rate;
end;

procedure TMiningFeatureNode.SetMinerRegion(Region: TRegionFeatureNode);
begin
   FStatus.SetRegion(Region);
end;

procedure TMiningFeatureNode.StartMiner(Rate: TMassRate; SourceLimiting, TargetLimiting: Boolean); // kg per second
begin
   Assert((Rate = FFeatureClass.FBandwidth) or SourceLimiting or TargetLimiting, 'unexpectedly running at non-maximum rate without reason');
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
   RateLimit: Double;
begin
   DisabledReasons := CheckDisabled(Parent, RateLimit);
   if ((RateLimit = 0.0) and (FStatus.Connected)) then
   begin
      FStatus.Region.RemoveMiner(Self);
      FStatus.Reset();
   end;
   if ((DisabledReasons <> FStatus.DisabledReasons) or (RateLimit <> FStatus.RateLimit)) then
   begin
      if (DisabledReasons <> FStatus.DisabledReasons) then
         MarkAsDirty([dkUpdateClients]);
      FStatus.SetDisabledReasons(DisabledReasons, RateLimit);
      if (FStatus.Connected) then
         FStatus.Region.ClientChanged();
   end;
   if (FStatus.NeedsConnection) then
   begin
      Message := TRegisterMinerBusMessage.Create(Self);
      if (InjectBusMessage(Message) <> irHandled) then
      begin
         FStatus.SetNoRegion();
         Writeln(DebugName, ' could not find region');
      end;
      FreeAndNil(Message);
   end;
   inherited;
end;

procedure TMiningFeatureNode.Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter);
var
   Visibility: TVisibility;
begin
   Visibility := Parent.ReadVisibilityFor(DynastyIndex);
   if ((dmDetectable * Visibility <> []) and (dmClassKnown in Visibility)) then
   begin
      Writer.WriteCardinal(fcMining);
      Writer.WriteDouble(FFeatureClass.FBandwidth.AsDouble);
      Writer.WriteCardinal(Cardinal(FStatus.DisabledReasons));
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