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
      FRegion: TRegionFeatureNode;
      FState: TMinerBlockage; // TODO: we could save memory by putting this into the three low bits of FRegion
   private // IMiner
      function GetMinerRate(): TRate; // kg per second
      procedure StartMiner(Region: TRegionFeatureNode);
      procedure StartMinerBlocked(Region: TRegionFeatureNode; Blockage: TMinerBlockage); // called when we would call StartMiner but there's some problem
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

function TMiningFeatureNode.GetMinerRate(): TRate; // kg per second
begin
   Result := FFeatureClass.FBandwidth;
end;

procedure TMiningFeatureNode.StartMiner(Region: TRegionFeatureNode);
begin
   Writeln('Miner ', Parent.DebugName, ' starting for region ', Region.Parent.DebugName);
   Assert(not Assigned(FRegion));
   Assert(FState in [mbNone, mbPending]);
   FRegion := Region;
   FState := mbNone;
   MarkAsDirty([dkUpdateClients, dkUpdateJournal]);
end;

procedure TMiningFeatureNode.StartMinerBlocked(Region: TRegionFeatureNode; Blockage: TMinerBlockage); // called when we would call StartMiner but there's some problem
begin
   Writeln('Miner ', Parent.DebugName, ' blocked for region ', Region.Parent.DebugName, ' because ', specialize EnumToString<TMinerBlockage>(Blockage), ' (currently ', specialize EnumToString<TMinerBlockage>(FState), ')');
   Assert(not Assigned(FRegion));
   Assert(FState in [mbNone, mbPending]);
   FRegion := Region;
   FState := Blockage;
   MarkAsDirty([dkUpdateClients, dkUpdateJournal]);
end;

procedure TMiningFeatureNode.StopMiner();
begin
   Writeln('Miner ', Parent.DebugName, ' stopping for region ', FRegion.Parent.DebugName);
   Assert(Assigned(FRegion));
   FRegion := nil;
   FState := mbNone;
   MarkAsDirty([dkUpdateClients, dkUpdateJournal, dkNeedsHandleChanges]);
end;

procedure TMiningFeatureNode.HandleChanges(CachedSystem: TSystem);
var
   Message: TRegisterMinerBusMessage;
begin
   // If a region stops us, they will probably restart us before we get here.
   if ((not Assigned(FRegion)) and (FState <> mbDisabled)) then
   begin
      Message := TRegisterMinerBusMessage.Create(Self);
      if (InjectBusMessage(Message) = mrHandled) then
      begin
         FState := mbPending;
      end
      else
      begin
         FState := mbNoRegion;
      end;
      FreeAndNil(Message);
   end;
   inherited;
end;

procedure TMiningFeatureNode.Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter; CachedSystem: TSystem);
var
   Visibility: TVisibility;
begin
   Visibility := Parent.ReadVisibilityFor(DynastyIndex, CachedSystem);
   if ((dmDetectable * Visibility <> []) and (dmClassKnown in Visibility)) then
   begin
      Writer.WriteCardinal(fcMining);
      Writer.WriteDouble(FFeatureClass.FBandwidth.AsDouble);
      Writer.WriteByte(Byte(FState));
   end;
end;

procedure TMiningFeatureNode.UpdateJournal(Journal: TJournalWriter; CachedSystem: TSystem);
begin
   Journal.WriteCardinal(Cardinal(FState));
end;

procedure TMiningFeatureNode.ApplyJournal(Journal: TJournalReader; CachedSystem: TSystem);
begin
   FState := TMinerBlockage(Journal.ReadCardinal());
end;

function TMiningFeatureNode.HandleCommand(Command: UTF8String; var Message: TMessage): Boolean;
begin
   if (Command = 'enable') then
   begin
      Result := True;
      Message.Reply();
      if (FState = mbDisabled) then
      begin
         Message.Output.WriteBoolean(True);
         FState := mbNone;
         MarkAsDirty([dkUpdateClients, dkUpdateJournal, dkNeedsHandleChanges]);
      end
      else
         Message.Output.WriteBoolean(False);
      Message.CloseOutput();
   end
   else
   if (Command = 'disable') then
   begin
      Result := True;
      Message.Reply();
      if (FState <> mbDisabled) then
      begin
         if (FState in [mbNone, mbPilesFull, mbMinesEmpty]) then
         begin
            Assert(Assigned(FRegion));
            FRegion.RemoveMiner(Self);
            FRegion := nil;
         end;
         Assert(not Assigned(FRegion));
         Message.Output.WriteBoolean(True);
         FState := mbDisabled;
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