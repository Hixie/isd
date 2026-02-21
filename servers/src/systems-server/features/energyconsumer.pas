{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit energyconsumer;

interface

uses
   basenetwork, systems, internals, serverstream,
   commonbuses, time, systemdynasty, energies, energybus, annotatedpointer;

type
   TEnergyConsumerFeatureClass = class(TFeatureClass)
   strict private
      FMaxInput: TRate;
      FEnergy: TEnergy;
   strict protected
      function GetFeatureNodeClass(): FeatureNodeReference; override;
   public
      constructor CreateFromTechnologyTree(const Reader: TTechTreeReader); override;
      function InitFeatureNode(ASystem: TSystem): TFeatureNode; override;
      property Energy: TEnergy read FEnergy;
      property MaxInput: TRate read FMaxInput;
   end;

   TEnergyConsumerFeatureNode = class(TFeatureNode, IEnergyConsumer)
   strict private
      type
         TStatus = (csSentBusRegistration);
   strict private
      FFeatureClass: TEnergyConsumerFeatureClass;
      FBus: specialize TAnnotatedPointer<TEnergyBusFeatureNode, TStatus>;
      FDisabledReasons: TDisabledReasons;
      FRateLimit: Double;
      FActualRateRatio: Double;
   protected
      constructor CreateFromJournal(Journal: TJournalReader; AFeatureClass: TFeatureClass; ASystem: TSystem); override;
      procedure HandleChanges(); override;
      function HandleBusMessage(Message: TBusMessage): THandleBusMessageResult; override;
      procedure Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter); override;
   public
      constructor Create(ASystem: TSystem; AFeatureClass: TEnergyConsumerFeatureClass);
      destructor Destroy(); override;
      procedure Detaching(); override;
      procedure UpdateJournal(Journal: TJournalWriter); override;
      procedure ApplyJournal(Journal: TJournalReader); override;
   public // IEnergyConsumer
      function EnergyConsumerGetEnergy(): TEnergy;
      function EnergyConsumerGetMaxRate(): TRate;
      function EnergyConsumerGetDynasty(): TDynasty;
      procedure EnergyConsumerSetRate(Node: TEnergyBusFeatureNode; ActualRateRatio: Double);
      procedure EnergyConsumerDisconnectEnergyBus();
   end;

implementation

uses
   ttparser, isdprotocol;

constructor TEnergyConsumerFeatureClass.CreateFromTechnologyTree(const Reader: TTechTreeReader);
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
   FMaxInput := Value / TimeDenominator;
end;

function TEnergyConsumerFeatureClass.GetFeatureNodeClass(): FeatureNodeReference;
begin
   Result := TEnergyConsumerFeatureNode;
end;

function TEnergyConsumerFeatureClass.InitFeatureNode(ASystem: TSystem): TFeatureNode;
begin
   Result := TEnergyConsumerFeatureNode.Create(ASystem, Self);
end;


constructor TEnergyConsumerFeatureNode.Create(ASystem: TSystem; AFeatureClass: TEnergyConsumerFeatureClass);
begin
   inherited Create(ASystem);
   FFeatureClass := AFeatureClass;
end;

constructor TEnergyConsumerFeatureNode.CreateFromJournal(Journal: TJournalReader; AFeatureClass: TFeatureClass; ASystem: TSystem);
begin
   inherited CreateFromJournal(Journal, AFeatureClass, ASystem);
   FFeatureClass := AFeatureClass as TEnergyConsumerFeatureClass;
end;

destructor TEnergyConsumerFeatureNode.Destroy();
begin
   Detaching(); // TODO: temporary hack until TAssetNode.Destroy is fixed to detach first
   inherited;
end;

procedure TEnergyConsumerFeatureNode.Detaching();
begin
   if (FBus.Assigned) then
   begin
      FBus.Unwrap().DisconnectConsumer(Self);
      FBus.Clear();
   end;
end;

procedure TEnergyConsumerFeatureNode.HandleChanges();
var
   RateLimit: Double;
   Message: TRegisterEnergyConsumerBusMessage;
begin
   FDisabledReasons := CheckDisabled(Parent, RateLimit);
   if (RateLimit = 0.0) then
   begin
      if (FBus.Assigned) then
      begin
         FBus.Unwrap().DisconnectConsumer(Self);
         FBus.Clear();
      end;
      FRateLimit := RateLimit;
   end
   else
   begin
      if (FBus.IsFlagClear(csSentBusRegistration)) then
      begin
         Message := TRegisterEnergyConsumerBusMessage.Create(Self);
         InjectBusMessage(Message);
         Message.Free();
         FBus.SetFlag(csSentBusRegistration);
      end;
      if (RateLimit <> FRateLimit) then
      begin
         FRateLimit := RateLimit;
         if (FBus.Assigned) then
            FBus.Unwrap().ClientChanged();
      end;
   end;
end;

function TEnergyConsumerFeatureNode.HandleBusMessage(Message: TBusMessage): THandleBusMessageResult;
var
   DisabledMessage: TCheckDisabledBusMessage;
begin
   if (Message is TCheckDisabledBusMessage) then
   begin
      DisabledMessage := Message as TCheckDisabledBusMessage;
      if (DisabledMessage.Identifier = Pointer(Self)) then
      begin
         Result := hrShortcut;
         exit;
      end;
      if (not FBus.Assigned) then
      begin
         Assert(FBus.IsFlagSet(csSentBusRegistration));
         DisabledMessage.AddReason(drNoBus);
      end
      else
      if (FActualRateRatio < 1.0) then
      begin
         DisabledMessage.AddReason(drInsufficientEnergy, FActualRateRatio);
      end;
   end;
   Result := inherited HandleBusMessage(Message);
end;

procedure TEnergyConsumerFeatureNode.Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter);
var
   Visibility: TVisibility;
   CurrentInput: TRate;
begin
   Visibility := Parent.ReadVisibilityFor(DynastyIndex);
   if ((dmDetectable * Visibility <> []) and (dmClassKnown in Visibility)) then
   begin
      Writer.WriteCardinal(fcConsumer);
      Writer.WriteStringReference(FFeatureClass.Energy.Name);
      Writer.WriteStringReference(FFeatureClass.Energy.Units);
      Writer.WriteCardinal(Cardinal(FDisabledReasons));
      if (dmInternals in Visibility) then
      begin
         CurrentInput := FFeatureClass.MaxInput * FRateLimit * FActualRateRatio;
         Writer.WriteDouble(FFeatureClass.MaxInput.AsDouble);
         Writer.WriteDouble(CurrentInput.AsDouble);
      end
      else
      begin
         Writer.WriteDouble(0.0);
         Writer.WriteDouble(0.0);
      end;
   end;
end;

procedure TEnergyConsumerFeatureNode.UpdateJournal(Journal: TJournalWriter);
begin
end;

procedure TEnergyConsumerFeatureNode.ApplyJournal(Journal: TJournalReader);
begin
end;

function TEnergyConsumerFeatureNode.EnergyConsumerGetEnergy(): TEnergy;
begin
   Result := FFeatureClass.Energy;
end;

function TEnergyConsumerFeatureNode.EnergyConsumerGetMaxRate(): TRate;
begin
   Result := FFeatureClass.MaxInput * FRateLimit;
end;

function TEnergyConsumerFeatureNode.EnergyConsumerGetDynasty(): TDynasty;
begin
   Result := Parent.Owner;
end;

procedure TEnergyConsumerFeatureNode.EnergyConsumerSetRate(Node: TEnergyBusFeatureNode; ActualRateRatio: Double);
begin
   Assert(Assigned(Node));
   Assert(FBus.IsFlagSet(csSentBusRegistration));
   FBus.Wrap(Node);
   if (FActualRateRatio <> ActualRateRatio) then
   begin
      FActualRateRatio := ActualRateRatio;
      MarkAsDirty([dkUpdateClients]);
   end;
end;

procedure TEnergyConsumerFeatureNode.EnergyConsumerDisconnectEnergyBus();
begin
   FBus.Clear();
   FActualRateRatio := 0.0;
   MarkAsDirty([dkNeedsHandleChanges, dkUpdateClients]);
end;

initialization
   RegisterFeatureClass(TEnergyConsumerFeatureClass);
end.
