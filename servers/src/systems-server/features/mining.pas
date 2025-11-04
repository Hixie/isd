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
   exceptions, sysutils, isdprotocol, knowledge, messages, typedump, onoff;

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
   FStatus.Enable();
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
   Writeln('  FStatus.Region = ', HexStr(FStatus.Region));
   Writeln('  FStatus.Mode = ', specialize EnumToString<TRegionClientMode>(FStatus.Mode));
   Assert(FStatus.Enabled);
   if ((FStatus.Region <> Region) or
       (FStatus.Rate <> Rate) or
       (FStatus.SourceLimiting <> SourceLimiting) or
       (FStatus.TargetLimiting <> TargetLimiting)) then
      MarkAsDirty([dkUpdateClients]);
   FStatus.Region := Region;
   FStatus.Rate := Rate;
   FStatus.SourceLimiting := SourceLimiting;
   FStatus.TargetLimiting := TargetLimiting;
   FStatus.Mode := rcActive;
end;

procedure TMiningFeatureNode.PauseMiner();
begin
   Writeln('PauseMiner(', FStatus.Region.Parent.DebugName, ')');
   FStatus.Mode := rcPending;
end;

procedure TMiningFeatureNode.StopMiner();
begin
   Writeln('StopMiner(', FStatus.Region.Parent.DebugName, ')');
   FStatus.Region := nil;
   FStatus.Rate := TRate.Zero;
   FStatus.SourceLimiting := False;
   FStatus.TargetLimiting := False;
   FStatus.Mode := rcIdle;
   MarkAsDirty([dkUpdateClients, dkNeedsHandleChanges]);
end;

procedure TMiningFeatureNode.HandleChanges(CachedSystem: TSystem);
var
   OnOffMessage: TEnableCheckBusMessage;
   NewEnabled: Boolean;
   Message: TRegisterMinerBusMessage;
begin
   // check if we can turn on
   OnOffMessage := TEnableCheckBusMessage.Create();
   NewEnabled := not Parent.HandleBusMessage(OnOffMessage);
   if (NewEnabled <> FStatus.Enabled) then
   begin
      if (NewEnabled) then
      begin
         Assert(FStatus.Mode = rcIdle);
         FStatus.Enable();
      end
      else
      begin
         if (FStatus.Mode in [rcPending, rcActive]) then
         begin
            Assert(Assigned(FStatus.Region));
            FStatus.Region.RemoveMiner(Self);
         end;
         FStatus.Disable(OnOffMessage.Reasons);
         Assert(not Assigned(FStatus.Region));
      end;
   end;
   FreeAndNil(OnOffMessage);

   // register if necessary
   if ((FStatus.Enabled) and (FStatus.Mode = rcIdle)) then
   begin
      Message := TRegisterMinerBusMessage.Create(Self);
      if (InjectBusMessage(Message) = mrHandled) then
      begin
         Assert(FStatus.Mode = rcIdle);
         FStatus.Mode := rcPending;
      end
      else
      begin
         Assert(FStatus.Mode = rcIdle);
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
      Assert(FStatus.Mode <> rcPending);
      Assert((not FStatus.Enabled) or (FStatus.Mode <> rcIdle));
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