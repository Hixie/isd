{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit refining;

interface

// TODO: refactor to avoid code duplication with mining.pas

uses
   basenetwork, systems, internals, serverstream, materials,
   messageport, region, time, systemdynasty, isdnumbers;

type
   TRefiningFeatureClass = class(TFeatureClass)
   private
      FOre: TOres;
      FBandwidth: TQuantityRate;
   strict protected
      function GetFeatureNodeClass(): FeatureNodeReference; override;
   protected
      procedure CollectRelatedMaterials(var Materials: TMaterial.TPlasticArray; const Encyclopedia: TMaterialEncyclopedia); override;
   public
      constructor CreateFromTechnologyTree(const Reader: TTechTreeReader); override;
      function InitFeatureNode(ASystem: TSystem): TFeatureNode; override;
   end;

   TRefiningFeatureNode = class(TFeatureNode, IRefinery)
   strict private
      FFeatureClass: TRefiningFeatureClass;
      FStatus: specialize TRegionClientFields<TQuantityRate>;
      {$IFOPT C+} FOreKnowledge: TKnowledgeSummary; {$ENDIF}
   private // IRefinery
      function GetRefineryOre(): TOres;
      function GetRefineryMaxRate(): TQuantityRate;
      function GetRefineryCurrentRate(): TQuantityRate;
      procedure SetRefineryRegion(Region: TRegionFeatureNode);
      procedure StartRefinery(Rate: TQuantityRate; SourceLimiting, TargetLimiting: Boolean);
      procedure DisconnectRefinery();
      function GetDynasty(): TDynasty;
      function GetPendingFraction(): PFraction32;
   protected
      constructor CreateFromJournal(Journal: TJournalReader; AFeatureClass: TFeatureClass; ASystem: TSystem); override;
      procedure HandleChanges(); override;
      {$IFOPT C+}
      procedure ResetDynastyNotes(OldDynasties: TDynastyIndexHashTable; NewDynasties: TDynasty.TArray); override;
      procedure ResetVisibility(); override;
      procedure HandleKnowledge(const DynastyIndex: Cardinal; const Sensors: ISensorsProvider); override;
      {$ENDIF}
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
   exceptions, sysutils, isdprotocol, knowledge, typedump, commonbuses, ttparser;

constructor TRefiningFeatureClass.CreateFromTechnologyTree(const Reader: TTechTreeReader);
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
   FBandwidth := ReadQuantityPerTime(Reader.Tokens, Material);
end;

function TRefiningFeatureClass.GetFeatureNodeClass(): FeatureNodeReference;
begin
   Result := TRefiningFeatureNode;
end;

function TRefiningFeatureClass.InitFeatureNode(ASystem: TSystem): TFeatureNode;
begin
   Result := TRefiningFeatureNode.Create(ASystem, Self);
end;

procedure TRefiningFeatureClass.CollectRelatedMaterials(var Materials: TMaterial.TPlasticArray; const Encyclopedia: TMaterialEncyclopedia);
begin
   Materials.Push(Encyclopedia.Materials[FOre]);
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
   FStatus.Reset();
   inherited;
end;

function TRefiningFeatureNode.GetRefineryOre(): TOres;
begin
   Result := FFeatureClass.FOre;
end;

function TRefiningFeatureNode.GetRefineryMaxRate(): TQuantityRate;
begin
   Result := FFeatureClass.FBandwidth * FStatus.RateLimit;
end;

function TRefiningFeatureNode.GetRefineryCurrentRate(): TQuantityRate;
begin
   Result := FStatus.Rate;
end;

procedure TRefiningFeatureNode.SetRefineryRegion(Region: TRegionFeatureNode);
begin
   FStatus.SetRegion(Region);
end;

procedure TRefiningFeatureNode.StartRefinery(Rate: TQuantityRate; SourceLimiting, TargetLimiting: Boolean);
begin
   Assert(Assigned(FStatus.Region));
   Assert((Rate = FFeatureClass.FBandwidth) xor (SourceLimiting or TargetLimiting));
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
      
function TRefiningFeatureNode.GetPendingFraction(): PFraction32;
begin
   Result := FStatus.GetPendingFraction();
end;

procedure TRefiningFeatureNode.HandleChanges();
var
   DisabledReasons: TDisabledReasons;
   Message: TRegisterRefineryBusMessage;
   RateLimit: Double;
begin
   DisabledReasons := CheckDisabled(Parent, RateLimit);
   if ((RateLimit = 0.0) and (FStatus.Connected)) then
   begin
      FStatus.Region.RemoveRefinery(Self);
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
   Material: TMaterial;
begin
   Visibility := Parent.ReadVisibilityFor(DynastyIndex);
   if ((dmDetectable * Visibility <> []) and (dmClassKnown in Visibility)) then
   begin
      Writer.WriteCardinal(fcRefining);
      {$IFOPT C+}
      Assert(FOreKnowledge.GetEntry(DynastyIndex));
      if (FOreKnowledge.GetEntry(DynastyIndex)) then
      begin
      {$ENDIF}
         Writer.WriteCardinal(FFeatureClass.FOre);
      {$IFOPT C+}
      end
      else
      begin
         Writer.WriteCardinal(0);
      end;
      {$ENDIF};
      Material := System.Encyclopedia.Materials[FFeatureClass.FOre];
      Writer.WriteDouble((FFeatureClass.FBandwidth * Material.MassPerUnit).AsDouble);
      Writer.WriteCardinal(Cardinal(FStatus.DisabledReasons));
      Writer.WriteDouble((FStatus.Rate * Material.MassPerUnit).AsDouble);
      Assert((FStatus.Rate = FFeatureClass.FBandwidth) or (FStatus.DisabledReasons <> []));
   end;
end;

{$IFOPT C+}
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
{$ENDIF}

procedure TRefiningFeatureNode.UpdateJournal(Journal: TJournalWriter);
begin
end;

procedure TRefiningFeatureNode.ApplyJournal(Journal: TJournalReader);
begin
end;

initialization
   RegisterFeatureClass(TRefiningFeatureClass);
end.