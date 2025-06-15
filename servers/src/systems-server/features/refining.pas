{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit refining;

interface

uses
   basenetwork, systems, serverstream, materials, techtree,
   messageport, region, time;

type
   TRefiningFeatureClass = class(TFeatureClass)
   private
      FOre: TOres;
      FBandwidth: TRate; // kg per second
   strict protected
      function GetFeatureNodeClass(): FeatureNodeReference; override;
   public
      constructor CreateFromTechnologyTree(Reader: TTechTreeReader); override;
      function InitFeatureNode(): TFeatureNode; override;
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
      procedure StartRefinery(Region: TRegionFeatureNode; Rate: TRate; SourceLimiting, TargetLimiting: Boolean); // kg per second
      procedure StopRefinery();
   protected
      constructor CreateFromJournal(Journal: TJournalReader; AFeatureClass: TFeatureClass; ASystem: TSystem); override;
      procedure HandleChanges(CachedSystem: TSystem); override;
      procedure ResetDynastyNotes(OldDynasties: TDynastyIndexHashTable; NewDynasties: TDynastyHashSet; CachedSystem: TSystem); override;
      procedure ResetVisibility(CachedSystem: TSystem); override;
      procedure HandleKnowledge(const DynastyIndex: Cardinal; const VisibilityHelper: TVisibilityHelper; const Sensors: ISensorsProvider); override;
      procedure Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter; CachedSystem: TSystem); override;
   public
      constructor Create(AFeatureClass: TRefiningFeatureClass);
      destructor Destroy(); override;
      procedure UpdateJournal(Journal: TJournalWriter; CachedSystem: TSystem); override;
      procedure ApplyJournal(Journal: TJournalReader; CachedSystem: TSystem); override;
      function HandleCommand(Command: UTF8String; var Message: TMessage): Boolean; override;
   end;

// TODO: handle our ancestor chain changing
  
implementation

uses
   exceptions, sysutils, isdprotocol, knowledge, messages, typedump;

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

function TRefiningFeatureClass.InitFeatureNode(): TFeatureNode;
begin
   Result := TRefiningFeatureNode.Create(Self);
end;


constructor TRefiningFeatureNode.Create(AFeatureClass: TRefiningFeatureClass);
begin
   inherited Create();
   FFeatureClass := AFeatureClass;
   FStatus.Enabled := True;
end;

constructor TRefiningFeatureNode.CreateFromJournal(Journal: TJournalReader; AFeatureClass: TFeatureClass; ASystem: TSystem);
begin
   inherited CreateFromJournal(Journal, AFeatureClass, ASystem);
   Assert(Assigned(AFeatureClass));
   FFeatureClass := AFeatureClass as TRefiningFeatureClass;
end;

destructor TRefiningFeatureNode.Destroy();
begin
   inherited;
end;

function TRefiningFeatureNode.GetRefineryOre(): TOres;
begin
   Result := FFeatureClass.FOre;
end;

function TRefiningFeatureNode.GetRefineryMaxRate(): TRate; // kg per second
begin
   Result := FFeatureClass.FBandwidth;
end;

function TRefiningFeatureNode.GetRefineryCurrentRate(): TRate; // kg per second
begin
   Result := FStatus.Rate;
end;

procedure TRefiningFeatureNode.StartRefinery(Region: TRegionFeatureNode; Rate: TRate; SourceLimiting, TargetLimiting: Boolean); // kg per second
begin
   Assert(FStatus.Enabled);
   FStatus.Region := Region;
   FStatus.Rate := Rate;
   FStatus.SourceLimiting := SourceLimiting;
   FStatus.TargetLimiting := TargetLimiting;
   FStatus.Mode := rcActive;
   MarkAsDirty([dkUpdateClients, dkUpdateJournal]);
   Writeln('StartRefinery(', FStatus.Region.Parent.DebugName, ', ', Rate.ToString('kg'), ', ', SourceLimiting, ', ', TargetLimiting, ')');
end;

procedure TRefiningFeatureNode.StopRefinery();
begin
   Writeln('StopRefinery(', FStatus.Region.Parent.DebugName, ')');
   FStatus.Region := nil;
   FStatus.Rate := TRate.Zero;
   FStatus.SourceLimiting := False;
   FStatus.TargetLimiting := False;
   FStatus.Mode := rcIdle;
   MarkAsDirty([dkUpdateClients, dkUpdateJournal, dkNeedsHandleChanges]);
end;

procedure TRefiningFeatureNode.HandleChanges(CachedSystem: TSystem);
var
   Message: TRegisterRefineryBusMessage;
begin
   // If a region stops us, they will probably restart us before we get here.
   if ((FStatus.Enabled) and (FStatus.Mode = rcIdle)) then
   begin
      Message := TRegisterRefineryBusMessage.Create(Self);
      if (InjectBusMessage(Message) = mrHandled) then
      begin
         FStatus.Mode := rcPending;
      end
      else
      begin
         FStatus.Mode := rcNoRegion;
      end;
      FreeAndNil(Message);
   end;
   inherited;
end;

procedure TRefiningFeatureNode.Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter; CachedSystem: TSystem);
var
   Visibility: TVisibility;
   Flags: Byte;
begin
   Visibility := Parent.ReadVisibilityFor(DynastyIndex, CachedSystem);
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
      Flags := $00;
      if (FStatus.Enabled) then
         Flags := Flags or $01; // $R-
      if (FStatus.Mode = rcActive) then
         Flags := Flags or $02; // $R-
      Assert(FStatus.Mode <> rcPending);
      Assert((not FStatus.Enabled) or (FStatus.Mode <> rcIdle));
      if (FStatus.SourceLimiting) then
         Flags := Flags or $04; // $R-
      if (FStatus.TargetLimiting) then
         Flags := Flags or $08; // $R-
      Writer.WriteByte(Flags);
      Writer.WriteDouble(FStatus.Rate.AsDouble);
   end;
end;

procedure TRefiningFeatureNode.ResetDynastyNotes(OldDynasties: TDynastyIndexHashTable; NewDynasties: TDynastyHashSet; CachedSystem: TSystem);
begin
   FOreKnowledge.Init(NewDynasties.Count);
end;

procedure TRefiningFeatureNode.ResetVisibility(CachedSystem: TSystem);
begin
   FOreKnowledge.Reset();
end;

procedure TRefiningFeatureNode.HandleKnowledge(const DynastyIndex: Cardinal; const VisibilityHelper: TVisibilityHelper; const Sensors: ISensorsProvider);
begin
   FOreKnowledge.SetEntry(DynastyIndex, Sensors.Knows(System.Encyclopedia.Materials[FFeatureClass.FOre]));
end;

procedure TRefiningFeatureNode.UpdateJournal(Journal: TJournalWriter; CachedSystem: TSystem);
begin
   Journal.WriteBoolean(FStatus.Enabled);
end;

procedure TRefiningFeatureNode.ApplyJournal(Journal: TJournalReader; CachedSystem: TSystem);
begin
   FStatus.Enabled := Journal.ReadBoolean();
end;

function TRefiningFeatureNode.HandleCommand(Command: UTF8String; var Message: TMessage): Boolean;
begin
   if (Command = 'enable') then
   begin
      Result := True;
      Message.Reply();
      if (FStatus.Enabled) then
      begin
         Message.Output.WriteBoolean(False);
      end
      else
      begin
         Message.Output.WriteBoolean(True);
         FStatus.Enabled := True;
         MarkAsDirty([dkUpdateClients, dkUpdateJournal, dkNeedsHandleChanges]);
      end;
      Message.CloseOutput();
   end
   else
   if (Command = 'disable') then
   begin
      Result := True;
      Message.Reply();
      if (FStatus.Enabled) then
      begin
         if (FStatus.Mode in [rcPending, rcActive]) then
         begin
            Assert(Assigned(FStatus.Region));
            FStatus.Region.RemoveRefinery(Self);
            FStatus.Region := nil;
         end;
         Assert(not Assigned(FStatus.Region));
         Message.Output.WriteBoolean(True);
         FStatus.Enabled := False;
         MarkAsDirty([dkUpdateClients, dkUpdateJournal, dkNeedsHandleChanges]);
      end
      else
         Message.Output.WriteBoolean(False);
      Message.CloseOutput();
   end
   else
      Result := inherited;
end;

initialization
   RegisterFeatureClass(TRefiningFeatureClass);
end.