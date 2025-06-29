{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit mining;

interface

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
      function HandleCommand(Command: UTF8String; var Message: TMessage): Boolean; override;
   end;

// TODO: handle our ancestor chain changing
  
implementation

uses
   exceptions, sysutils, isdprotocol, knowledge, messages, typedump;

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
   FStatus.Enabled := True;
end;

constructor TMiningFeatureNode.CreateFromJournal(Journal: TJournalReader; AFeatureClass: TFeatureClass; ASystem: TSystem);
begin
   inherited CreateFromJournal(Journal, AFeatureClass, ASystem);
   Assert(Assigned(AFeatureClass));
   FFeatureClass := AFeatureClass as TMiningFeatureClass;
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
   Assert(FStatus.Enabled);
   FStatus.Region := Region;
   FStatus.Rate := Rate;
   FStatus.SourceLimiting := SourceLimiting;
   FStatus.TargetLimiting := TargetLimiting;
   FStatus.Mode := rcActive;
   MarkAsDirty([dkUpdateClients, dkUpdateJournal]);
   Writeln('StartMiner(', Region.Parent.DebugName, ', ', Rate.ToString('kg'), ', ', SourceLimiting, ', ', TargetLimiting, ')');
end;

procedure TMiningFeatureNode.StopMiner();
begin
   Writeln('StopMiner(', FStatus.Region.Parent.DebugName, ')');
   FStatus.Region := nil;
   FStatus.Rate := TRate.Zero;
   FStatus.SourceLimiting := False;
   FStatus.TargetLimiting := False;
   FStatus.Mode := rcIdle;
   MarkAsDirty([dkUpdateClients, dkUpdateJournal, dkNeedsHandleChanges]);
end;

procedure TMiningFeatureNode.HandleChanges(CachedSystem: TSystem);
var
   Message: TRegisterMinerBusMessage;
begin
   // If a region stops us, they will probably restart us before we get here.
   if ((FStatus.Enabled) and (FStatus.Mode = rcIdle)) then
   begin
      Message := TRegisterMinerBusMessage.Create(Self);
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

procedure TMiningFeatureNode.UpdateJournal(Journal: TJournalWriter; CachedSystem: TSystem);
begin
   Journal.WriteBoolean(FStatus.Enabled);
end;

procedure TMiningFeatureNode.ApplyJournal(Journal: TJournalReader; CachedSystem: TSystem);
begin
   FStatus.Enabled := Journal.ReadBoolean();
end;

function TMiningFeatureNode.HandleCommand(Command: UTF8String; var Message: TMessage): Boolean;
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
            FStatus.Region.RemoveMiner(Self);
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
   RegisterFeatureClass(TMiningFeatureClass);
end.