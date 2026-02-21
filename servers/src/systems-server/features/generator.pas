{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit generator;

interface

uses
   basenetwork, systems, internals, serverstream,
   commonbuses, time, systemdynasty, energies, energybus, annotatedpointer;

type
   TGeneratorFeatureClass = class(TFeatureClass)
   private
      FMaxOutput: TRate;
      FEnergy: TEnergy;
   strict protected
      function GetFeatureNodeClass(): FeatureNodeReference; override;
   private
      property MaxOutput: TRate read FMaxOutput;
      property Energy: TEnergy read FEnergy;
   public
      constructor CreateFromTechnologyTree(const Reader: TTechTreeReader); override;
      function InitFeatureNode(ASystem: TSystem): TFeatureNode; override;
   end;

   TGeneratorFeatureNode = class(TFeatureNode, IEnergyGenerator)
   strict private
      type
         TStatus = (gsSentBusRegistration);
   strict private
      FFeatureClass: TGeneratorFeatureClass;
      FBus: specialize TAnnotatedPointer<TEnergyBusFeatureNode, TStatus>;
      FDisabledReasons: TDisabledReasons;
      FRateLimit: Double;
      FActualRateRatio: Double;
   protected
      constructor CreateFromJournal(Journal: TJournalReader; AFeatureClass: TFeatureClass; ASystem: TSystem); override;
      procedure HandleChanges(); override;
      procedure Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter); override;
   public
      constructor Create(ASystem: TSystem; AFeatureClass: TGeneratorFeatureClass);
      destructor Destroy(); override;
      procedure Detaching(); override;
      procedure UpdateJournal(Journal: TJournalWriter); override;
      procedure ApplyJournal(Journal: TJournalReader); override;
   public // IEnergyGenerator
      function EnergyGeneratorGetEnergy(): TEnergy;
      function EnergyGeneratorGetMaxRate(): TRate;
      function EnergyGeneratorGetDynasty(): TDynasty;
      procedure EnergyGeneratorSetRate(Node: TEnergyBusFeatureNode; ActualRateRatio: Double);
      procedure EnergyGeneratorDisconnectEnergyBus();
   end;

implementation

uses
   ttparser, isdprotocol;

constructor TGeneratorFeatureClass.CreateFromTechnologyTree(const Reader: TTechTreeReader);
var
   Value: Double;
   Units: UTF8String;
   SelectedEnergy: TEnergy;
   TimeDenominator: TMillisecondsDuration;
begin
   inherited Create();
   Value := Reader.Tokens.ReadDouble();
   Units := Reader.Tokens.ReadIdentifier();
   SelectedEnergy := Reader.EnergiesByUnits[Units];
   if (not Assigned(SelectedEnergy)) then
      Reader.Tokens.Error('Unknown energy units "%s"', [Units]);
   FEnergy := SelectedEnergy;
   TimeDenominator := ReadTimeDenominator(Reader.Tokens);
   FMaxOutput := Value / TimeDenominator;
end;

function TGeneratorFeatureClass.GetFeatureNodeClass(): FeatureNodeReference;
begin
   Result := TGeneratorFeatureNode;
end;

function TGeneratorFeatureClass.InitFeatureNode(ASystem: TSystem): TFeatureNode;
begin
   Result := TGeneratorFeatureNode.Create(ASystem, Self);
end;


constructor TGeneratorFeatureNode.Create(ASystem: TSystem; AFeatureClass: TGeneratorFeatureClass);
begin
   inherited Create(ASystem);
   FFeatureClass := AFeatureClass;
end;

constructor TGeneratorFeatureNode.CreateFromJournal(Journal: TJournalReader; AFeatureClass: TFeatureClass; ASystem: TSystem);
begin
   inherited CreateFromJournal(Journal, AFeatureClass, ASystem);
   FFeatureClass := AFeatureClass as TGeneratorFeatureClass;
end;

destructor TGeneratorFeatureNode.Destroy();
begin
   Detaching(); // TODO: temporary hack until TAssetNode.Destroy is fixed to detach first
   inherited;
end;

procedure TGeneratorFeatureNode.Detaching();
begin
   if (FBus.Assigned) then
   begin
      FBus.Unwrap().DisconnectGenerator(Self);
      FBus.Clear();
   end;
end;

procedure TGeneratorFeatureNode.HandleChanges();
var
   RateLimit: Double;
   Message: TRegisterEnergyGeneratorBusMessage;
begin
   FDisabledReasons := CheckDisabled(Parent, RateLimit);
   if (RateLimit = 0.0) then
   begin
      if (FBus.Assigned) then
      begin
         FBus.Unwrap().DisconnectGenerator(Self);
         FBus.Clear();
      end;
      FRateLimit := RateLimit;
   end
   else
   begin
      if (FBus.IsFlagClear(gsSentBusRegistration)) then
      begin
         Message := TRegisterEnergyGeneratorBusMessage.Create(Self);
         InjectBusMessage(Message);
         Message.Free();
         FBus.SetFlag(gsSentBusRegistration);
      end;
      if (RateLimit <> FRateLimit) then
      begin
         FRateLimit := RateLimit;
         if (FBus.Assigned) then
            FBus.Unwrap().ClientChanged();
      end;
   end;
end;

procedure TGeneratorFeatureNode.Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter);
var
   Visibility: TVisibility;
   MaxOutput, CurrentOutput: TRate;
begin
   Visibility := Parent.ReadVisibilityFor(DynastyIndex);
   if ((dmDetectable * Visibility <> []) and (dmClassKnown in Visibility)) then
   begin
      Writer.WriteCardinal(fcGenerator);
      Writer.WriteStringReference(FFeatureClass.Energy.Name);
      Writer.WriteStringReference(FFeatureClass.Energy.Units);
      Writer.WriteCardinal(Cardinal(FDisabledReasons));
      if (dmInternals in Visibility) then
      begin
         MaxOutput := FFeatureClass.MaxOutput * FRateLimit;
         CurrentOutput := MaxOutput * FActualRateRatio;
         Writer.WriteDouble(FFeatureClass.MaxOutput.AsDouble);
         Writer.WriteDouble(MaxOutput.AsDouble);
         Writer.WriteDouble(CurrentOutput.AsDouble);
      end
      else
      begin
         Writer.WriteDouble(0.0);
         Writer.WriteDouble(0.0);
         Writer.WriteDouble(0.0);
      end;
   end;
end;

procedure TGeneratorFeatureNode.UpdateJournal(Journal: TJournalWriter);
begin
end;

procedure TGeneratorFeatureNode.ApplyJournal(Journal: TJournalReader);
begin
end;

function TGeneratorFeatureNode.EnergyGeneratorGetEnergy(): TEnergy;
begin
   Result := FFeatureClass.Energy;
end;

function TGeneratorFeatureNode.EnergyGeneratorGetMaxRate(): TRate;
begin
   Result := FFeatureClass.MaxOutput * FRateLimit;
end;

function TGeneratorFeatureNode.EnergyGeneratorGetDynasty(): TDynasty;
begin
   Result := Parent.Owner;
end;

procedure TGeneratorFeatureNode.EnergyGeneratorSetRate(Node: TEnergyBusFeatureNode; ActualRateRatio: Double);
begin
   Assert(Assigned(Node));
   Assert(FBus.IsFlagSet(gsSentBusRegistration));
   FBus.Wrap(Node);
   FActualRateRatio := ActualRateRatio;
   MarkAsDirty([dkUpdateClients]);
end;

procedure TGeneratorFeatureNode.EnergyGeneratorDisconnectEnergyBus();
begin
   FBus.Clear();
   FActualRateRatio := 0.0;
   MarkAsDirty([dkNeedsHandleChanges, dkUpdateClients]);
end;

initialization
   RegisterFeatureClass(TGeneratorFeatureClass);
end.