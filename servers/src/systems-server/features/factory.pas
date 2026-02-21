{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit factory;

interface

uses
   basenetwork, systems, internals, serverstream, materials,
   commonbuses, messageport, region, time, systemdynasty,
   annotatedpointer, isdnumbers;

type
   TFactoryFeatureClass = class(TFeatureClass)
   private
      FMaxRate: TIterationsRate;
      FInputs, FOutputs: TMaterialQuantity32Array;
   strict protected
      function GetFeatureNodeClass(): FeatureNodeReference; override;
   protected
      procedure CollectRelatedMaterials(var Materials: TMaterial.TPlasticArray; const Encyclopedia: TMaterialEncyclopedia); override;
   public
      constructor CreateFromTechnologyTree(const Reader: TTechTreeReader); override;
      function InitFeatureNode(ASystem: TSystem): TFeatureNode; override;
   end;

   TFactoryFeatureNode = class(TFeatureNode, IFactory)
   strict private
      type
         TBusStatus = (bsNoRegion, bsInputStalled, bsOutputStalled);
   strict private
      FFeatureClass: TFactoryFeatureClass;
      FRegion: specialize TAnnotatedPointer<TRegionFeatureNode, TBusStatus>;
      FConfiguredMaxRate: TIterationsRate; // the rate set by the player
      FCurrentRate: TIterationsRate; // FFeatureClass.FMaxRate * RateLimit, limited to FConfiguredMaxRate; FLocalDisabledReason overrides this
      FDisabledReasons: TDisabledReasons;
      FPendingFraction: Fraction32;
      FBacklog: Cardinal; // number of cycles we've artificially kept back because it was causing accounting issues
   private // IFactory
      function GetFactoryInputs(): TMaterialQuantity32Array;
      function GetFactoryOutputs(): TMaterialQuantity32Array;
      function GetFactoryRate(): TIterationsRate; // instances (not units!) per second; zero if stalled
      procedure SetFactoryRegion(Region: TRegionFeatureNode);
      procedure StartFactory();
      procedure StallFactory(Reason: TStallReason);
      procedure DisconnectFactory();
      function GetDynasty(): TDynasty;
      function GetPendingFraction(): PFraction32;
      procedure IncBacklog();
      function GetBacklog(): Cardinal;
      procedure ResetBacklog();
   protected
      constructor CreateFromJournal(Journal: TJournalReader; AFeatureClass: TFeatureClass; ASystem: TSystem); override;
      procedure HandleChanges(); override;
      procedure Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter); override;
   public
      constructor Create(ASystem: TSystem; AFeatureClass: TFactoryFeatureClass);
      destructor Destroy(); override;
      procedure Attaching(); override;
      procedure Detaching(); override;
      procedure UpdateJournal(Journal: TJournalWriter); override;
      procedure ApplyJournal(Journal: TJournalReader); override;
      function HandleCommand(PlayerDynasty: TDynasty; Command: UTF8String; var Message: TMessage): Boolean; override;
   end;

implementation

uses
   exceptions, sysutils, isdprotocol, knowledge, masses, typedump, ttparser;

constructor TFactoryFeatureClass.CreateFromTechnologyTree(const Reader: TTechTreeReader);

   function ReadManifest(const Section: UTF8String; var Manifest: TMaterialQuantity32Array): TMassSum;
   var
      NewEntry, Entry: TMaterialQuantity32;
   begin
      Result.Reset();;
      Reader.Tokens.ReadIdentifier(section);
      repeat
         NewEntry.Material := ReadMaterial(Reader);
         if (Reader.Tokens.IsAsterisk()) then
         begin
            Reader.Tokens.ReadAsterisk();
            NewEntry.Quantity := ReadQuantity32(Reader.Tokens, NewEntry.Material);
         end
         else
            NewEntry.Quantity := TQuantity32.FromUnits(1);
         for Entry in Manifest do
         begin
            if Entry.Material = NewEntry.Material then
               Reader.Tokens.Error('Duplicate %s material specified: %s', [Section, Entry.Material.Name]);
         end;
         SetLength(Manifest, Length(Manifest) + 1);
         Manifest[High(Manifest)] := NewEntry;
         Result.Inc(NewEntry.Quantity * NewEntry.Material.MassPerUnit);
         Reader.Tokens.ReadComma();
      until Reader.Tokens.IsIdentifier();
   end;

var
   InputMass: TMassSum;
   OutputMass: TMassSum;
begin
   inherited Create();
   Assert(FInputs = nil);
   Assert(FOutputs = nil);
   InputMass := ReadManifest('input', FInputs);
   OutputMass := ReadManifest('output', FOutputs);
   if (Length(FInputs) = 0) then
      Reader.Tokens.Error('Factory has no configured inputs.', []);
   if (Length(FOutputs) = 0) then
      Reader.Tokens.Error('Factory has no configured outputs.', []);
   if (Length(FInputs) + Length(FOutputs) > High(Integer)) then
      Reader.Tokens.Error('Factory has too many inputs and outputs.', [Length(FInputs), Length(FOutputs)]);
   if (InputMass <> OutputMass) then
      Reader.Tokens.Error('Mass of factory inputs and outputs is inconsistent. Inputs mass %s, outputs mass %s.', [InputMass.Flatten().ToString(), OutputMass.Flatten().ToString()]);
   Reader.Tokens.ReadIdentifier('max');
   Reader.Tokens.ReadIdentifier('throughput');
   FMaxRate := ReadPerTime(Reader.Tokens);
end;

function TFactoryFeatureClass.GetFeatureNodeClass(): FeatureNodeReference;
begin
   Result := TFactoryFeatureNode;
end;

function TFactoryFeatureClass.InitFeatureNode(ASystem: TSystem): TFeatureNode;
begin
   Result := TFactoryFeatureNode.Create(ASystem, Self);
end;

procedure TFactoryFeatureClass.CollectRelatedMaterials(var Materials: TMaterial.TPlasticArray; const Encyclopedia: TMaterialEncyclopedia);
var
   Entry: TMaterialQuantity32;
begin
   Assert(Length(FInputs) > 0);
   Assert(Length(FOutputs) > 0);
   Materials.GrowFor(Length(FInputs) + Length(FOutputs)); // $R-
   for Entry in FInputs do
      Materials.Push(Entry.Material);
   for Entry in FOutputs do
      Materials.Push(Entry.Material);
end;


constructor TFactoryFeatureNode.Create(ASystem: TSystem; AFeatureClass: TFactoryFeatureClass);
begin
   inherited Create(ASystem);
   FFeatureClass := AFeatureClass;
   FConfiguredMaxRate := FFeatureClass.FMaxRate;
end;

constructor TFactoryFeatureNode.CreateFromJournal(Journal: TJournalReader; AFeatureClass: TFeatureClass; ASystem: TSystem);
begin
   Assert(Assigned(AFeatureClass));
   FFeatureClass := AFeatureClass as TFactoryFeatureClass;
   FConfiguredMaxRate := FFeatureClass.FMaxRate;
   inherited;
end;

destructor TFactoryFeatureNode.Destroy();
begin
   if (FRegion.Assigned) then
   begin
      FRegion.Unwrap().RemoveFactory(Self);
      FRegion.Clear();
   end;
   inherited;
end;

procedure TFactoryFeatureNode.Attaching();
begin
   Assert(not FRegion.Assigned);
   Assert(FRegion.IsFlagClear(bsNoRegion));
   MarkAsDirty([dkNeedsHandleChanges]);
end;

procedure TFactoryFeatureNode.Detaching();
begin
   if (FRegion.Assigned) then
      FRegion.Unwrap().RemoveFactory(Self);
   FRegion.ClearFlag(bsNoRegion);
end;

function TFactoryFeatureNode.GetFactoryInputs(): TMaterialQuantity32Array;
begin
   Result := FFeatureClass.FInputs;
   Assert(Length(Result) > 0);
end;

function TFactoryFeatureNode.GetFactoryOutputs(): TMaterialQuantity32Array;
begin
   Result := FFeatureClass.FOutputs;
   Assert(Length(Result) > 0);
end;

function TFactoryFeatureNode.GetFactoryRate(): TIterationsRate; // instances (not units!) per second
begin
   Assert(FRegion.IsFlagClear(bsNoRegion));
   Assert(FRegion.IsFlagClear(bsInputStalled));
   Assert(FRegion.IsFlagClear(bsOutputStalled));
   Assert(FRegion.Assigned);
   Assert(FCurrentRate.IsPositive);
   Result := FCurrentRate;
end;

procedure TFactoryFeatureNode.SetFactoryRegion(Region: TRegionFeatureNode);
begin
   Assert(FRegion.IsFlagClear(bsNoRegion));
   Assert(FRegion.IsFlagClear(bsInputStalled));
   Assert(FRegion.IsFlagClear(bsOutputStalled));
   Assert(not FRegion.Assigned);
   FRegion := Region;
end;

procedure TFactoryFeatureNode.StartFactory();
begin
   Assert(FRegion.IsFlagClear(bsNoRegion));
   Assert(FRegion.IsFlagClear(bsInputStalled));
   Assert(FRegion.IsFlagClear(bsOutputStalled));
   Assert(FRegion.Assigned);
   MarkAsDirty([dkUpdateClients]);
end;

procedure TFactoryFeatureNode.StallFactory(Reason: TStallReason);
begin
   Writeln(DebugName, ' :: StallFactory');
   Assert(FRegion.IsFlagClear(bsNoRegion));
   Assert(FRegion.IsFlagClear(bsInputStalled));
   Assert(FRegion.IsFlagClear(bsOutputStalled));
   Assert(FRegion.Assigned);
   case Reason of
      srInput: FRegion.SetFlag(bsInputStalled);
      srOutput: FRegion.SetFlag(bsOutputStalled);
   end;
   FRegion.Wrap(nil);
   Assert(FRegion.IsFlagSet(bsInputStalled) xor FRegion.IsFlagSet(bsOutputStalled));
   FPendingFraction.ResetToZero();
   FBacklog := 0;
   MarkAsDirty([dkUpdateClients, dkUpdateJournal]);
end;

procedure TFactoryFeatureNode.DisconnectFactory();
begin
   Assert(FRegion.IsFlagClear(bsNoRegion));
   FRegion.Wrap(nil);
   MarkAsDirty([dkUpdateClients, dkNeedsHandleChanges]);
end;

function TFactoryFeatureNode.GetDynasty(): TDynasty;
begin
   Result := Parent.Owner;
end;

function TFactoryFeatureNode.GetPendingFraction(): PFraction32;
begin
   Result := @FPendingFraction;
   MarkAsDirty([dkUpdateJournal]);
end;

procedure TFactoryFeatureNode.IncBacklog();
begin
   Inc(FBacklog);
   MarkAsDirty([dkUpdateJournal]);
end;

function TFactoryFeatureNode.GetBacklog(): Cardinal;
begin
   Result := FBacklog;
end;

procedure TFactoryFeatureNode.ResetBacklog();
begin
   FBacklog := 0;
   MarkAsDirty([dkUpdateJournal]);
end;

procedure TFactoryFeatureNode.HandleChanges();
var
   DisabledReasons: TDisabledReasons;
   Message: TRegisterFactoryBusMessage;
   RateLimit: Double;
   PoweredLimit: TIterationsRate;
begin
   Writeln(DebugName, ' :: HandleChanges');
   DisabledReasons := CheckDisabled(Parent, RateLimit);
   PoweredLimit := FFeatureClass.FMaxRate * RateLimit;
   if (PoweredLimit > FConfiguredMaxRate) then
      PoweredLimit := FConfiguredMaxRate;
   Writeln('  DisabledReasons: ', specialize SetToString<TDisabledReasons>(DisabledReasons));
   Writeln('  RateLimit: ', RateLimit.ToString());
   Writeln('  MaxRate: ', FFeatureClass.FMaxRate.ToString());
   Writeln('  FConfiguredMaxRate: ', FConfiguredMaxRate.ToString());
   Writeln('  => PoweredLimit: ', PoweredLimit.ToString());
   if (DisabledReasons <> FDisabledReasons) then
   begin
      FDisabledReasons := DisabledReasons;
      MarkAsDirty([dkUpdateClients]);
   end;
   if (PoweredLimit <> FCurrentRate) then
   begin
      FCurrentRate := PoweredLimit;
      if (FRegion.Assigned) then
      begin
         FRegion.Unwrap().ClientChanged();
      end;
      MarkAsDirty([dkUpdateClients]);
   end;
   if (PoweredLimit.IsExactZero) then
   begin
      Writeln('  => Disabled due to configuration or other issue.');
      Assert(FDisabledReasons <> []);
      if (FRegion.Assigned) then
      begin
         FRegion.Unwrap().RemoveFactory(Self);
         FRegion.Wrap(nil);
         FRegion.ClearFlag(bsNoRegion);
      end;
      Assert(FRegion.IsFlagClear(bsNoRegion));
   end
   else
   if (not FRegion.Assigned) then
   begin
      if (FRegion.IsFlagClear(bsNoRegion) and FRegion.IsFlagClear(bsInputStalled) and FRegion.IsFlagClear(bsOutputStalled)) then
      begin
         Writeln('  => Enabled, attempting to connect.');
         Message := TRegisterFactoryBusMessage.Create(Self);
         if (InjectBusMessage(Message) <> irHandled) then
            FRegion.SetFlag(bsNoRegion)
         else
            Assert(FRegion.Assigned);
         FreeAndNil(Message);
      end
      else
      begin
         Writeln('  => Enabled, but marked as failed to connect or stalled.');
         Writeln('  bsNoRegion: ', FRegion.IsFlagSet(bsNoRegion));
         Writeln('  bsInputStalled: ', FRegion.IsFlagSet(bsInputStalled));
         Writeln('  bsOutputStalled: ', FRegion.IsFlagSet(bsOutputStalled));
      end;
   end
   else
      Writeln('  => Enabled, but already connected.');
   inherited;
end;

procedure TFactoryFeatureNode.Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter);

   procedure WriteManifest(Materials: TMaterialQuantity32Array);
   var
      Entry: TMaterialQuantity32;
   begin
      for Entry in Materials do
      begin
         Writer.WriteInt32(Entry.Material.ID);
         Writer.WriteCardinal(Entry.Quantity.AsCardinal);
      end;
      Writer.WriteInt32(0);
   end;
   
var
   Visibility: TVisibility;
   ReportedDisabledReason: TDisabledReasons;
begin
   Visibility := Parent.ReadVisibilityFor(DynastyIndex);
   if ((dmDetectable * Visibility <> []) and (dmClassKnown in Visibility)) then
   begin
      Writer.WriteCardinal(fcFactory);
      WriteManifest(FFeatureClass.FInputs);
      WriteManifest(FFeatureClass.FOutputs);
      Writer.WriteDouble(FFeatureClass.FMaxRate.AsDouble);
      Writer.WriteDouble(FConfiguredMaxRate.AsDouble);
      if (FRegion.Assigned) then
      begin
         Writer.WriteDouble(FCurrentRate.AsDouble)
      end
      else
      begin
         Writer.WriteDouble(0.0);
      end;
      ReportedDisabledReason := FDisabledReasons;
      if (FRegion.IsFlagSet(bsNoRegion)) then
         Include(ReportedDisabledReason, drNoBus);
      if (FRegion.IsFlagSet(bsInputStalled)) then
         Include(ReportedDisabledReason, drSourceLimited);
      if (FRegion.IsFlagSet(bsOutputStalled)) then
         Include(ReportedDisabledReason, drTargetLimited);
      Assert((FRegion.Assigned and FCurrentRate.IsNotExactZero) or FConfiguredMaxRate.IsExactZero or (ReportedDisabledReason <> [])); // PROBLEM ASSERT
      Writer.WriteCardinal(Cardinal(ReportedDisabledReason));
   end;
end;

procedure TFactoryFeatureNode.UpdateJournal(Journal: TJournalWriter);
begin
   Journal.WriteDouble(FConfiguredMaxRate.AsDouble);
   Journal.WriteCardinal(FPendingFraction.AsCardinal);
   Journal.WriteCardinal(FBacklog);
   Journal.WriteBoolean(FRegion.IsFlagClear(bsInputStalled));
   Journal.WriteBoolean(FRegion.IsFlagClear(bsOutputStalled));
end;

procedure TFactoryFeatureNode.ApplyJournal(Journal: TJournalReader);
begin
   FConfiguredMaxRate := TIterationsRate.FromPerMillisecond(Journal.ReadDouble());
   FPendingFraction := Fraction32.FromCardinal(Journal.ReadCardinal());
   FBacklog := Journal.ReadCardinal();
   FRegion.ConfigureFlag(bsInputStalled, Journal.ReadBoolean());
   FRegion.ConfigureFlag(bsOutputStalled, Journal.ReadBoolean());
end;

function TFactoryFeatureNode.HandleCommand(PlayerDynasty: TDynasty; Command: UTF8String; var Message: TMessage): Boolean;
var
   RequestedValue: Double;
begin
   if (Command = ccRate) then
   begin
      Result := True;
      RequestedValue := Message.Input.ReadDouble();
      if (Message.CloseInput()) then
      begin
         Message.Reply();
         if ((RequestedValue > FFeatureClass.FMaxRate.AsDouble) or
             (RequestedValue < 0.0)) then
         begin
            Message.Error(ieRangeError);
         end
         else
         begin
            FConfiguredMaxRate := TIterationsRate.FromPerMillisecond(RequestedValue);
            FRegion.ClearFlag(bsInputStalled);
            FRegion.ClearFlag(bsOutputStalled);
            Writeln(DebugName, ' user request to set rate to ', FConfiguredMaxRate.ToString());
            if (FConfiguredMaxRate.IsExactZero) then
            begin
               FPendingFraction.ResetToZero();
               FBacklog := 0;
            end;
            MarkAsDirty([dkUpdateClients, dkUpdateJournal, dkNeedsHandleChanges]);
            Message.CloseOutput();
         end;
      end;
   end
   else
      Result := False;
end;

initialization
   RegisterFeatureClass(TFactoryFeatureClass);
end.