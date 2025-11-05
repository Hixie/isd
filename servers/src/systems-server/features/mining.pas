{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit mining;

interface

// TODO: refactor to avoid code duplication with refining.pas

uses
   basenetwork, systems, serverstream, materials, techtree,
   messageport, region, time;

type
   TMiningFeatureClass = class(TFeatureClass)
   private
      FBandwidth: TRate; // kg per second
   strict protected
      function GetFeatureNodeClass(): FeatureNodeReference; override;
   public
      constructor CreateFromTechnologyTree(Reader: TTechTreeReader); override;
      function InitFeatureNode(): TFeatureNode; override;
   end;

   TMiningFeatureNode = class(TFeatureNode, IMiner)
   strict private
      FFeatureClass: TMiningFeatureClass;
      FStatus: TRegionClientFields;
   private // IMiner
      function GetMinerMaxRate(): TRate; // kg per second
      function GetMinerCurrentRate(): TRate; // kg per second
      procedure StartMiner(Region: TRegionFeatureNode; Rate: TRate; SourceLimiting, TargetLimiting: Boolean);
      procedure PauseMiner();
      procedure StopMiner();
   protected
      constructor CreateFromJournal(Journal: TJournalReader; AFeatureClass: TFeatureClass; ASystem: TSystem); override;
      procedure HandleChanges(CachedSystem: TSystem); override;
      procedure Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter; CachedSystem: TSystem); override;
   public
      constructor Create(AFeatureClass: TMiningFeatureClass);
      destructor Destroy(); override;
      procedure UpdateJournal(Journal: TJournalWriter; CachedSystem: TSystem); override;
      procedure ApplyJournal(Journal: TJournalReader; CachedSystem: TSystem); override;
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

function TMiningFeatureClass.InitFeatureNode(): TFeatureNode;
begin
   Result := TMiningFeatureNode.Create(Self);
end;


constructor TMiningFeatureNode.Create(AFeatureClass: TMiningFeatureClass);
begin
   inherited Create();
   FFeatureClass := AFeatureClass;
end;

constructor TMiningFeatureNode.CreateFromJournal(Journal: TJournalReader; AFeatureClass: TFeatureClass; ASystem: TSystem);
begin
   Assert(Assigned(AFeatureClass));
   FFeatureClass := AFeatureClass as TMiningFeatureClass;
   inherited CreateFromJournal(Journal, AFeatureClass, ASystem);
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

procedure TMiningFeatureNode.StartMiner(Region: TRegionFeatureNode; Rate: TRate; SourceLimiting, TargetLimiting: Boolean); // kg per second
begin
   Assert(Assigned(Region));
   Writeln('StartMiner(', Region.Parent.DebugName, ', ', Rate.ToString('kg'), ', ', SourceLimiting, ', ', TargetLimiting, ')');
   if (FStatus.Update(Region, Rate, SourceLimiting, TargetLimiting)) then
      MarkAsDirty([dkUpdateClients]);
end;

procedure TMiningFeatureNode.PauseMiner();
begin
   Writeln('PauseMiner(', FStatus.Region.Parent.DebugName, ')');
end;

procedure TMiningFeatureNode.StopMiner();
begin
   Writeln('StopMiner(', FStatus.Region.Parent.DebugName, ')');
   FStatus.Reset();
   MarkAsDirty([dkUpdateClients, dkNeedsHandleChanges]);
end;

procedure TMiningFeatureNode.HandleChanges(CachedSystem: TSystem);
var
   DisabledReasons: TDisabledReasons;
   Message: TRegisterMinerBusMessage;
begin
   DisabledReasons := CheckDisabled(Parent);
   if ((DisabledReasons <> []) and (FStatus.Connected)) then
      FStatus.Region.RemoveMiner(Self);
   if (DisabledReasons <> FStatus.DisabledReasons) then
      FStatus.SetDisabledReasons(DisabledReasons);
   if (FStatus.NeedsConnection) then
   begin
      Message := TRegisterMinerBusMessage.Create(Self);
      if (InjectBusMessage(Message) <> mrHandled) then
         FStatus.SetNoRegion();
      FreeAndNil(Message);
   end;
   inherited;
end;

procedure TMiningFeatureNode.Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter; CachedSystem: TSystem);
var
   Visibility: TVisibility;
   Flags: Byte;
begin
   Visibility := Parent.ReadVisibilityFor(DynastyIndex, CachedSystem);
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

procedure TMiningFeatureNode.UpdateJournal(Journal: TJournalWriter; CachedSystem: TSystem);
begin
end;

procedure TMiningFeatureNode.ApplyJournal(Journal: TJournalReader; CachedSystem: TSystem);
begin
end;

initialization
   RegisterFeatureClass(TMiningFeatureClass);
end.