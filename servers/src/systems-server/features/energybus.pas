{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit energybus;

interface

uses
   sysutils, systems, internals, systemdynasty, serverstream,
   hashsettight, hashtable, genericutils, commonbuses,
   energies, time, hashfunctions;

type
   TEnergyBusFeatureNode = class;
   
   IEnergyGenerator = interface ['IEnergyGenerator']
      function EnergyGeneratorGetEnergy(): TEnergy;
      function EnergyGeneratorGetMaxRate(): TRate;
      function EnergyGeneratorGetDynasty(): TDynasty;
      procedure EnergyGeneratorSetRate(Node: TEnergyBusFeatureNode; ActualRateRatio: Double);
      procedure EnergyGeneratorDisconnectEnergyBus();
   end;

   TRegisterEnergyGeneratorBusMessage = specialize TRegisterProviderBusMessage<TPhysicalConnectionBusMessage, IEnergyGenerator>;
   TEnergyGeneratorHashSet = specialize TInterfaceSet<IEnergyGenerator>;
   
   IEnergyConsumer = interface ['IEnergyConsumer']
      function EnergyConsumerGetEnergy(): TEnergy;
      function EnergyConsumerGetMaxRate(): TRate;
      function EnergyConsumerGetDynasty(): TDynasty;
      procedure EnergyConsumerSetRate(Node: TEnergyBusFeatureNode; ActualRateRatio: Double);
      procedure EnergyConsumerDisconnectEnergyBus();
   end;

   TRegisterEnergyConsumerBusMessage = specialize TRegisterProviderBusMessage<TPhysicalConnectionBusMessage, IEnergyConsumer>;
   TEnergyConsumerHashSet = specialize TInterfaceSet<IEnergyConsumer>;
   
   TEnergyBusFeatureClass = class(TFeatureClass)
   strict protected
      FCapabilities: TEnergyRateHashTable;
      function GetFeatureNodeClass(): FeatureNodeReference; override;
   private
      property Capabilities: TEnergyRateHashTable read FCapabilities;
   public
      constructor CreateFromTechnologyTree(const Reader: TTechTreeReader); override;
      destructor Destroy(); override;
      function InitFeatureNode(ASystem: TSystem): TFeatureNode; override;
   end;

   TEnergyBusFeatureNode = class(TFeatureNode)
   strict private
      type
         PGeneratorsConsumers = ^TGeneratorsConsumers;
         TGeneratorsConsumers = record
            Generators: TEnergyGeneratorHashSet;
            Consumers: TEnergyConsumerHashSet;
            class operator Initialize(var Rec: TGeneratorsConsumers);
         end;
         TPerEnergyHashTable = class(specialize THashTable<TEnergy, TGeneratorsConsumers, TObjectUtils>)
            constructor Create(ACount: THashTableSizeInt = 8);
         end;
         TPerDynastyHashTable = class(specialize THashTable<TDynasty, TPerEnergyHashTable, TObjectUtils>)
            constructor Create(ACount: THashTableSizeInt = 8);
         end;
      var
         FFeatureClass: TEnergyBusFeatureClass;
         FData: TPerDynastyHashTable;
         FDirty: Boolean;
   private
      function GetDynastyTable(Dynasty: TDynasty): TPerEnergyHashTable;
      function GetEnergyEntries(Dynasty: TDynasty; Energy: TEnergy): PGeneratorsConsumers;
   protected
      function ManageBusMessage(Message: TBusMessage): TInjectBusMessageResult; override;
      function HandleBusMessage(Message: TBusMessage): THandleBusMessageResult; override;
      procedure Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter); override;
   public
      constructor Create(ASystem: TSystem; AFeatureClass: TEnergyBusFeatureClass);
      destructor Destroy(); override;
      procedure Detaching(); override;
      procedure HandleChanges(); override;
      procedure UpdateJournal(Journal: TJournalWriter); override;
      procedure ApplyJournal(Journal: TJournalReader); override;
   public
      procedure DisconnectGenerator(Client: IEnergyGenerator);
      procedure DisconnectConsumer(Client: IEnergyConsumer);
      procedure ClientChanged();
   end;

implementation

uses
   ttparser;

constructor TEnergyBusFeatureClass.CreateFromTechnologyTree(const Reader: TTechTreeReader);
var
   Value: Double;
   Units: UTF8String;
   Time: TMillisecondsDuration;
   Energy: TEnergy;
begin
   inherited Create();
   FCapabilities := TEnergyRateHashTable.Create();
   repeat
      Value := Reader.Tokens.ReadDouble();
      Units := Reader.Tokens.ReadIdentifier();
      Energy := Reader.EnergiesByUnits[Units];
      if (not Assigned(Energy)) then
         Reader.Tokens.Error('Unknown energy units "%s"', [Units]);
      if (FCapabilities.Has(Energy)) then
         Reader.Tokens.Error('Energy "%s" (units "%s") listed twice', [Energy.Name, Units]);
      Time := ReadTimeDenominator(Reader.Tokens);
      FCapabilities[Energy] := value / Time;
   until not Reader.Tokens.IsDouble();
end;

destructor TEnergyBusFeatureClass.Destroy();
begin
   FreeAndNil(FCapabilities);
   inherited;
end;

function TEnergyBusFeatureClass.GetFeatureNodeClass(): FeatureNodeReference;
begin
   Result := TEnergyBusFeatureNode;
end;

function TEnergyBusFeatureClass.InitFeatureNode(ASystem: TSystem): TFeatureNode;
begin
   Result := TEnergyBusFeatureNode.Create(ASystem, Self);
end;


class operator TEnergyBusFeatureNode.TGeneratorsConsumers.Initialize(var Rec: TGeneratorsConsumers);
begin
   Rec.Generators := nil;
   Rec.Consumers := nil;
end;

constructor TEnergyBusFeatureNode.TPerEnergyHashTable.Create(ACount: THashTableSizeInt = 8);
begin
   inherited Create(@EnergyHash32, ACount);
end;


constructor TEnergyBusFeatureNode.TPerDynastyHashTable.Create(ACount: THashTableSizeInt = 8);
begin
   inherited Create(@DynastyHash32, ACount);
end;


constructor TEnergyBusFeatureNode.Create(ASystem: TSystem; AFeatureClass: TEnergyBusFeatureClass);
begin
   inherited Create(ASystem);
   FFeatureClass := AFeatureClass;
end;

destructor TEnergyBusFeatureNode.Destroy();
begin
   Detaching(); // TODO: temporary hack until TAssetNode.Destroy is fixed to detach first
   inherited;
end;

procedure TEnergyBusFeatureNode.Detaching();
var
   PerEnergy: TPerEnergyHashTable;
   Energy: TEnergy;
   GeneratorsConsumers: PGeneratorsConsumers;
   Generator: IEnergyGenerator;
   Consumer: IEnergyConsumer;
begin
   if (Assigned(FData)) then
   begin
      for PerEnergy in FData.Values do
      begin
         for Energy in PerEnergy do
         begin
            GeneratorsConsumers := PerEnergy.ItemsPtr[Energy];
            for Generator in GeneratorsConsumers^.Generators do
               Generator.EnergyGeneratorDisconnectEnergyBus();
            for Consumer in GeneratorsConsumers^.Consumers do
               Consumer.EnergyConsumerDisconnectEnergyBus();
            FreeAndNil(GeneratorsConsumers^.Generators);
            FreeAndNil(GeneratorsConsumers^.Consumers);
         end;
         PerEnergy.Free();
      end;
      FreeAndNil(FData);
   end;
end;

function TEnergyBusFeatureNode.GetDynastyTable(Dynasty: TDynasty): TPerEnergyHashTable;
begin
   if (not Assigned(FData)) then
      FData := TPerDynastyHashTable.Create(1);
   Result := FData[Dynasty];
   if (not Assigned(Result)) then
   begin
      Result := TPerEnergyHashTable.Create(4);
      FData[Dynasty] := Result;
   end;
end;

function TEnergyBusFeatureNode.GetEnergyEntries(Dynasty: TDynasty; Energy: TEnergy): PGeneratorsConsumers;
var
   DynastyTable: TPerEnergyHashTable;
begin
   DynastyTable := GetDynastyTable(Dynasty);
   Result := DynastyTable.GetOrAddPtr(Energy);
end;

function TEnergyBusFeatureNode.ManageBusMessage(Message: TBusMessage): TInjectBusMessageResult;
begin
   if ((Message is TRegisterEnergyGeneratorBusMessage) or
       (Message is TRegisterEnergyConsumerBusMessage)) then
   begin
      Result := DeferOrHandleBusMessage(Message);
   end
   else
      Result := irDeferred;
end;

function TEnergyBusFeatureNode.HandleBusMessage(Message: TBusMessage): THandleBusMessageResult;
var
   Dynasty: TDynasty;
   Energy: TEnergy;
   Entries: PGeneratorsConsumers;
   RegisterEnergyGenerator: TRegisterEnergyGeneratorBusMessage;
   RegisterEnergyConsumer: TRegisterEnergyConsumerBusMessage;
begin
   if (Message is TRegisterEnergyGeneratorBusMessage) then
   begin
      RegisterEnergyGenerator := Message as TRegisterEnergyGeneratorBusMessage;
      Dynasty := RegisterEnergyGenerator.Provider.EnergyGeneratorGetDynasty();
      Energy := RegisterEnergyGenerator.Provider.EnergyGeneratorGetEnergy();
      Entries := GetEnergyEntries(Dynasty, Energy);
      if (not Assigned(Entries^.Generators)) then
         Entries^.Generators := TEnergyGeneratorHashSet.Create(4);
      Entries^.Generators.Add(RegisterEnergyGenerator.Provider);
      Result := hrHandled;
      MarkAsDirty([dkNeedsHandleChanges]);
      FDirty := True;
   end
   else
   if (Message is TRegisterEnergyConsumerBusMessage) then
   begin
      RegisterEnergyConsumer := Message as TRegisterEnergyConsumerBusMessage;
      Dynasty := RegisterEnergyConsumer.Provider.EnergyConsumerGetDynasty();
      Energy := RegisterEnergyConsumer.Provider.EnergyConsumerGetEnergy();
      Entries := GetEnergyEntries(Dynasty, Energy);
      if (not Assigned(Entries^.Consumers)) then
         Entries^.Consumers := TEnergyConsumerHashSet.Create(4);
      Entries^.Consumers.Add(RegisterEnergyConsumer.Provider);
      Result := hrHandled;
      MarkAsDirty([dkNeedsHandleChanges]);
      FDirty := True;
   end
   else
      Result := inherited;
end;

procedure TEnergyBusFeatureNode.DisconnectGenerator(Client: IEnergyGenerator);
var
   Dynasty: TDynasty;
   Energy: TEnergy;
   Entries: PGeneratorsConsumers;
begin
   Dynasty := Client.EnergyGeneratorGetDynasty();
   Energy := Client.EnergyGeneratorGetEnergy();
   Entries := GetEnergyEntries(Dynasty, Energy);
   Assert(Assigned(Entries^.Generators));
   Assert(Entries^.Generators.Has(Client));
   Entries^.Generators.Remove(Client);
   MarkAsDirty([dkNeedsHandleChanges]);
   FDirty := True;
end;

procedure TEnergyBusFeatureNode.DisconnectConsumer(Client: IEnergyConsumer);
var
   Dynasty: TDynasty;
   Energy: TEnergy;
   Entries: PGeneratorsConsumers;
begin
   Dynasty := Client.EnergyConsumerGetDynasty();
   Energy := Client.EnergyConsumerGetEnergy();
   Entries := GetEnergyEntries(Dynasty, Energy);
   Assert(Assigned(Entries^.Consumers));
   Assert(Entries^.Consumers.Has(Client));
   Entries^.Consumers.Remove(Client);
   MarkAsDirty([dkNeedsHandleChanges]);
   FDirty := True;
end;

procedure TEnergyBusFeatureNode.HandleChanges();
var
   Dynasty: TDynasty;
   Energy: TEnergy;
   DynastyData: TPerEnergyHashTable;
   Entries: PGeneratorsConsumers;
   Generator: IEnergyGenerator;
   Consumer: IEnergyConsumer;
   GeneratedSum, ConsumedSum: TRateSum;
   Generated, Requested, Consumed, Max: TRate;
   GenerationRatio, ConsumptionRatio: Double;
begin
   if (FDirty) then
   begin
      Assert(Assigned(FData));
      for Dynasty in FData do
      begin
         DynastyData := FData[Dynasty];
         Assert(Assigned(DynastyData));
         for Energy in DynastyData do
         begin
            Entries := DynastyData.ItemsPtr[Energy];
            GeneratedSum.Reset();
            for Generator in Entries^.Generators do
               GeneratedSum.Inc(Generator.EnergyGeneratorGetMaxRate());
            Generated := GeneratedSum.Flatten();
            ConsumedSum.Reset();
            for Consumer in Entries^.Consumers do
               ConsumedSum.Inc(Consumer.EnergyConsumerGetMaxRate());
            Requested := ConsumedSum.Flatten();
            Consumed := Requested;
            Max := FFeatureClass.Capabilities[Energy];
            if (Consumed > Max) then
               Consumed := Max;
            if (Consumed > Generated) then
               Consumed := Generated;
            GenerationRatio := Consumed / Generated;
            Assert(GenerationRatio <= 1.0);
            Assert(GenerationRatio >= 0.0);
            for Generator in Entries^.Generators do
               Generator.EnergyGeneratorSetRate(Self, GenerationRatio);
            ConsumptionRatio := Consumed / Requested;
            for Consumer in Entries^.Consumers do
               Consumer.EnergyConsumerSetRate(Self, ConsumptionRatio);
         end;
      end;
      FDirty := False;
   end;
end;

procedure TEnergyBusFeatureNode.Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter);
begin
end;

procedure TEnergyBusFeatureNode.UpdateJournal(Journal: TJournalWriter);
begin
end;

procedure TEnergyBusFeatureNode.ApplyJournal(Journal: TJournalReader);
begin
end;

procedure TEnergyBusFeatureNode.ClientChanged();
begin
   MarkAsDirty([dkNeedsHandleChanges]);
end;

initialization
   RegisterFeatureClass(TEnergyBusFeatureClass);
end.