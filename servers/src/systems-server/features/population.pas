{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit population;

interface

uses
   systems, serverstream, materials, systemdynasty, techtree,
   peoplebus, commonbuses, gossip, masses;

// TODO: people try to move to the "best" houses
// TODO: people in houses beyond the max are unhappy
// TODO: disabled houses count as max=0, or apply the ratio in some way
// TODO: gossip should spread between population centers

type
   TPopulationFeatureClass = class(TFeatureClass)
   strict protected
      FHiddenIfEmpty: Boolean;
      FMaxPopulation: Cardinal;
      function GetFeatureNodeClass(): FeatureNodeReference; override;
   public
      constructor Create(AHiddenIfEmpty: Boolean; AMaxPopulation: Cardinal);
      constructor CreateFromTechnologyTree(Reader: TTechTreeReader); override;
      function InitFeatureNode(ASystem: TSystem): TFeatureNode; override;
      property HiddenIfEmpty: Boolean read FHiddenIfEmpty;
      property MaxPopulation: Cardinal read FMaxPopulation;
   end;

   TPopulationFeatureNode = class(TFeatureNode, IHousing)
   private
      // source of truth
      FPopulation: Cardinal; // if this changes, call FPeopleBus.ClientChanged and MarkAsDirty dkAffectsVisibility
      FPriority: TPriority; // TODO: if ancestor chain changes, and priority is NoPriority, reset it to zero and mark as dirty
      FDisabledReasons: TDisabledReasons;
      FGossip: TGossipHashTable;
      // cached status
      FFeatureClass: TPopulationFeatureClass;
      FFoodAvailable: Cardinal;
      FWorkers: Cardinal;
      FPeopleBus: TPeopleBusFeatureNode;
      function GetOwner(): TDynasty;
      procedure SetFoodUsage(Quantity: Cardinal);
   protected
      procedure Attaching(); override;
      procedure Detaching(); override;
      function GetMass(): TMass; override;
      function GetHappiness(): Double; override;
      function HandleBusMessage(Message: TBusMessage): THandleBusMessageResult; override;
      procedure Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter); override;
   public
      constructor Create(ASystem: TSystem; AFeatureClass: TPopulationFeatureClass);
      constructor CreatePopulated(ASystem: TSystem; AFeatureClass: TPopulationFeatureClass; APopulation: Cardinal); // only for use in plot-generated population centers
      constructor CreateFromJournal(Journal: TJournalReader; AFeatureClass: TFeatureClass; ASystem: TSystem); override;
      destructor Destroy(); override;
      procedure HandleChanges(); override;
      procedure UpdateJournal(Journal: TJournalWriter); override;
      procedure ApplyJournal(Journal: TJournalReader); override;
      procedure DescribeExistentiality(var IsDefinitelyReal, IsDefinitelyGhost: Boolean); override;
      procedure AbsorbPopulation(Count: Cardinal; Gossip: TGossipHashTable);
   public // IHousing
      procedure PeopleBusConnected(Bus: TPeopleBusFeatureNode);
      procedure PeopleBusAssignJobs(Count: Cardinal);
      procedure PeopleBusDisconnected();
      function GetWorkers(): Cardinal;
      function GetPriority(): TPriority;
      procedure SetAutoPriority(Value: TAutoPriority);
      function GetAsset(): TAssetNode;
   end;

implementation

uses
   exceptions, isdprotocol, messages, orbit, sysutils, rubble, time;

const
   MeanIndividualMass = 70; // kg // TODO: allow species to diverge and such, with different demographics, etc


constructor TPopulationFeatureClass.Create(AHiddenIfEmpty: Boolean; AMaxPopulation: Cardinal);
begin
   inherited Create();
   FHiddenIfEmpty := AHiddenIfEmpty;
   FMaxPopulation := AMaxPopulation;
end;

constructor TPopulationFeatureClass.CreateFromTechnologyTree(Reader: TTechTreeReader);
type
   TPopulationKeyword = (pkMax, pkHidden);
var
   Seen: set of TPopulationKeyword;

   procedure Acknowledge(Keyword: TPopulationKeyword);
   begin
      if (Keyword in Seen) then
         Reader.Tokens.Error('Duplicate parameter', []);
      Include(Seen, Keyword);
   end;

var
   Keyword: UTF8String;
begin
   inherited Create();
   FMaxPopulation := 1;
   Seen := [];
   repeat
      Keyword := Reader.Tokens.ReadIdentifier();
      case Keyword of
         'max':
            begin
               Acknowledge(pkMax);
               FMaxPopulation := ReadNumber(Reader.Tokens, Low(FMaxPopulation), High(FMaxPopulation)); // $R-
            end;
         'hidden':
            begin
               Acknowledge(pkHidden);
               FHiddenIfEmpty := True;
            end;
      else
         Reader.Tokens.Error('Unexpected keyword "%s"', [Keyword]);
      end;
   until not ReadComma(Reader.Tokens);
end;

function TPopulationFeatureClass.GetFeatureNodeClass(): FeatureNodeReference;
begin
   Result := TPopulationFeatureNode;
end;

function TPopulationFeatureClass.InitFeatureNode(ASystem: TSystem): TFeatureNode;
begin
   Result := TPopulationFeatureNode.Create(ASystem, Self);
end;


constructor TPopulationFeatureNode.Create(ASystem: TSystem; AFeatureClass: TPopulationFeatureClass);
begin
   inherited Create(ASystem);
   Assert(Assigned(AFeatureClass));
   FFeatureClass := AFeatureClass;
end;

constructor TPopulationFeatureNode.CreatePopulated(ASystem: TSystem; AFeatureClass: TPopulationFeatureClass; APopulation: Cardinal);
begin
   inherited Create(ASystem);
   Assert(Assigned(AFeatureClass));
   FFeatureClass := AFeatureClass;
   FPopulation := APopulation;
end;

constructor TPopulationFeatureNode.CreateFromJournal(Journal: TJournalReader; AFeatureClass: TFeatureClass; ASystem: TSystem);
begin
   Assert(Assigned(AFeatureClass));
   FFeatureClass := AFeatureClass as TPopulationFeatureClass;
   inherited;
end;

destructor TPopulationFeatureNode.Destroy();
begin
   if (Assigned(FPeopleBus)) then
      FPeopleBus.RemoveHousing(Self);
   FGossip.Free();
   inherited;
end;

procedure TPopulationFeatureNode.Attaching();
begin
   Assert(not Assigned(FPeopleBus));
   Assert(FWorkers = 0);
   // FPriority can be non-zero here if we were just brought in from the journal
   MarkAsDirty([dkNeedsHandleChanges, dkHappinessChanged]);
end;

procedure TPopulationFeatureNode.Detaching();
begin
   if (Assigned(FPeopleBus)) then
   begin
      FPeopleBus.RemoveHousing(Self);
      FWorkers := 0;
      FPriority := 0;
      FPeopleBus := nil;
   end;
   MarkAsDirty([dkHappinessChanged]);
end;

function TPopulationFeatureNode.GetMass(): TMass;
begin
   Result := TMass.FromKg(MeanIndividualMass) * FPopulation;
end;

function TPopulationFeatureNode.GetHappiness(): Double;
begin
   Result := FGossip.ComputeHappinessContribution(FPopulation, System.Now);
end;

function TPopulationFeatureNode.HandleBusMessage(Message: TBusMessage): THandleBusMessageResult;
var
   GossipMessage: TSpreadGossipBusMessage;
   HelpMessage: TNotificationMessage;
   DismantleMessage: TDismantleMessage;
   Injected: TInjectBusMessageResult;
   Rehome: TRehomePopulation;
   Capacity: Cardinal;
   OrbitMessage: TGetNearestOrbitMessage;
   Ship: TAssetNode;
   Gossip: PGossip;
   GossipIdentifier: TGossipIdentifier;
   CrashGossip: TGossip;
begin
   if (Message is TSpreadGossipBusMessage) then
   begin
      GossipMessage := Message as TSpreadGossipBusMessage;
      Gossip := GossipMessage.Gossip;
      GossipIdentifier := GossipMessage.Identifier;
      if (not FGossip.Allocated) then
         FGossip.Allocate();
      FGossip.AddNewGossip(GossipIdentifier, Gossip^, FPopulation);
      MarkAsDirty([dkHappinessChanged, dkUpdateClients, dkUpdateJournal]);
      if (GossipMessage.Spread) then
      begin
         Result := hrHandled;
         exit;
      end;
   end
   else
   if (Message is TCrashReportMessage) then
   begin
      OrbitMessage := TGetNearestOrbitMessage.Create();
      InjectBusMessage(OrbitMessage);
      Assert(Assigned(OrbitMessage.Orbit));
      Ship := OrbitMessage.GetSpaceShip(Parent);
      FreeAndNil(OrbitMessage);
      Assert(Assigned(Ship));
      HelpMessage := TNotificationMessage.Create(
         Parent,
         'Urgent Query Regarding Recent Events Aboard ' + Ship.AssetOrClassName + #$0A +
         'From: Passengers'#$0A +
         'WHAT THE HECK WHY DID WE JUST CRASH WHAT IS HAPPENING',
         nil
      );
      Injected := InjectBusMessage(HelpMessage);
      if (Injected <> irHandled) then
         Writeln('Discarding message from population center ("', HelpMessage.Body, '")');
      FreeAndNil(HelpMessage);
      CrashGossip.Timestamp := System.Now;
      CrashGossip.Duration := TMillisecondsDuration.FromWeeks(52);
      CrashGossip.HappinessImpact := -1000.0;
      CrashGossip.PopulationAnchorTime := System.Now;
      CrashGossip.SpreadRate := TGrowthRate.FromDoublingTimeInWeeks(8.0);
      CrashGossip.AffectedPeople := FPopulation;
      CrashGossip.Flags := [];
      GossipIdentifier.Source := Ship;
      GossipIdentifier.Kind := gkCrash;
      if (not FGossip.Allocated) then
         FGossip.Allocate();
      FGossip.AddNewGossip(GossipIdentifier, CrashGossip, FPopulation);
      MarkAsDirty([dkHappinessChanged, dkUpdateClients, dkUpdateJournal]);
      // we don't set Result to hrHandled -- TCrashReportMessage is handled when you explode yourself due to the crash (notifying someone isn't handling it!)
   end
   else
   if (Message is TRubbleCollectionMessage) then
   begin
      XXX; // TODO: we should account for the mass of dead bodies when turning population into rubble
   end
   else
   if (Message is TFindDestructorsMessage) then
   begin
      if ((Message as TFindDestructorsMessage).Owner = Parent.Owner) then
      begin
         Result := hrHandled;
         exit;
      end;
   end
   else
   if (Message is TRehomePopulation) then
   begin
      if (FPopulation < FFeatureClass.MaxPopulation) then
      begin
         Rehome := Message as TRehomePopulation;
         Assert(FFeatureClass.MaxPopulation >= FPopulation);
         Capacity := FFeatureClass.MaxPopulation - FPopulation; // $R-
         if (Rehome.RemainingPopulation < Capacity) then
         begin
            if (FPopulation = 0) then
                MarkAsDirty([dkAffectsVisibility]);
            Inc(FPopulation, Rehome.RemainingPopulation); // TODO: should clamp gossip growth before changing population
            Rehome.Rehome(Rehome.RemainingPopulation, FGossip, System.Now);
            Assert(Rehome.RemainingPopulation = 0);
         end
         else
         begin
            FPopulation := FFeatureClass.MaxPopulation; // TODO: should clamp gossip growth before changing population
            Rehome.Rehome(Capacity, FGossip, System.Now);
            Assert(Rehome.RemainingPopulation > 0);
         end;
         MarkAsDirty([dkHappinessChanged, dkNeedsHandleChanges, dkUpdateClients, dkUpdateJournal]);
         if (Assigned(FPeopleBus)) then
            FPeopleBus.ClientChanged();
         if (Rehome.RemainingPopulation = 0) then
         begin
            Result := hrHandled;
            exit;
         end;
      end;
   end
   else
   if (Message is TDismantleMessage) then
   begin
      Writeln(DebugName, ' getting dismantled with population ', FPopulation);
      DismantleMessage := Message as TDismantleMessage;
      if (not Assigned(Parent.Owner)) then
      begin
         Assert(FPopulation = 0);
      end
      else
      begin
         Assert(DismantleMessage.Owner = Parent.Owner);
         if (FPopulation > 0) then
         begin
            Rehome := TRehomePopulation.Create(DismantleMessage.Target, FPopulation, 0, FGossip);
            DismantleMessage.Target.Parent.Parent.InjectBusMessage(Rehome);
            FPopulation := 0;
            if (Rehome.RemainingPopulation > 0) then
            begin
               DismantleMessage.AddExcessPopulation(Rehome.RemainingPopulation, FGossip);
               Writeln('  some pops remained! ', Rehome.RemainingPopulation);
            end
            else
               Writeln('  pops rehomed');
            FreeAndNil(Rehome);
            MarkAsDirty([dkHappinessChanged, dkNeedsHandleChanges, dkUpdateClients, dkUpdateJournal, dkAffectsVisibility]);
            if (Assigned(FPeopleBus)) then
               FPeopleBus.ClientChanged();
         end;
      end;
   end
   else
   if (Message is TAssetGoingAway) then
   begin
      if (FGossip.Allocated) then
      begin
         if (FGossip.HandleAssetGoingAway((Message as TAssetGoingAway).Asset, FPopulation, System.Now)) then
         begin
            MarkAsDirty([dkHappinessChanged, dkUpdateClients, dkUpdateJournal]);
         end;
      end;
   end;
   Result := inherited;
end;

procedure TPopulationFeatureNode.Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter);
var
   Visibility: TVisibility;
begin
   if (FFeatureClass.HiddenIfEmpty and (FPopulation = 0)) then
      exit;
   Visibility := Parent.ReadVisibilityFor(DynastyIndex);
   if (dmDetectable * Visibility <> []) then
   begin
      Writer.WriteCardinal(fcPopulation);
      Writer.WriteCardinal(Cardinal(FDisabledReasons));
      Writer.WriteCardinal(FPopulation);
      Writer.WriteCardinal(FFeatureClass.MaxPopulation);
      Writer.WriteCardinal(FWorkers);
      // TODO: if we send the priority, we have to update the clients any time FPriority changes
      FGossip.Serialize(DynastyIndex, Writer, System.Now);
   end;
end;

procedure TPopulationFeatureNode.HandleChanges();
var
   NewDisabledReasons: TDisabledReasons;
   Message: TRegisterHousingMessage;
   RateLimit: Double;
begin
   Assert(Assigned(Parent));
   NewDisabledReasons := CheckDisabled(Parent, RateLimit); // TODO: do something with the rate limit
   if (NewDisabledReasons <> FDisabledReasons) then
   begin
      FDisabledReasons := NewDisabledReasons;
      MarkAsDirty([dkUpdateClients]);
   end;
   Assert((FPopulation = 0) or Assigned(Parent.Owner));
   if ((FPopulation > 0) and (not Assigned(FPeopleBus)) and (FPriority <> NoPriority)) then
   begin
      Message := TRegisterHousingMessage.Create(Self);
      if (InjectBusMessage(Message) <> irHandled) then
      begin
         FPriority := NoPriority;
      end
      else
      begin
         Assert(Assigned(FPeopleBus));
      end;
      FreeAndNil(Message);
   end;
   inherited;
end;

procedure TPopulationFeatureNode.UpdateJournal(Journal: TJournalWriter);
begin
   Journal.WriteCardinal(FPopulation);
   Journal.WriteCardinal(FPriority);
   FGossip.UpdateJournal(Journal, System.Now);
end;

procedure TPopulationFeatureNode.ApplyJournal(Journal: TJournalReader);
begin
   FPopulation := Journal.ReadCardinal();
   FPriority := TPriority(Journal.ReadCardinal());
   FGossip.ApplyJournal(Journal, System);
end;

function TPopulationFeatureNode.GetOwner(): TDynasty;
begin
   Result := Parent.Owner;
end;

procedure TPopulationFeatureNode.SetFoodUsage(Quantity: Cardinal);
begin
   if (Quantity <> FFoodAvailable) then
   begin
      FFoodAvailable := Quantity;
      // TODO: add gossip
   end;
end;

procedure TPopulationFeatureNode.DescribeExistentiality(var IsDefinitelyReal, IsDefinitelyGhost: Boolean);
begin
   IsDefinitelyReal := FPopulation > 0; // if FPopulation ever changes whether it's 0 or not, MarkAsDirty([dkAffectsVisibility])
end;

procedure TPopulationFeatureNode.AbsorbPopulation(Count: Cardinal; Gossip: TGossipHashTable);
begin
   Assert(Count > 0);
   if (FPopulation = 0) then
      MarkAsDirty([dkAffectsVisibility]); // because of DescribeExistentiality
   Inc(FPopulation, Count);
   if (Gossip.Allocated) then
   begin
      if (not FGossip.Allocated) then
         FGossip.Allocate();
      TGossipHashTable.MoveGossip(Gossip, FGossip, Count, Count, System.Now);
   end;
   if (Assigned(FPeopleBus)) then
      FPeopleBus.ClientChanged();
end;

procedure TPopulationFeatureNode.PeopleBusConnected(Bus: TPeopleBusFeatureNode);
begin
   Assert(not Assigned(FPeopleBus));
   Assert(FWorkers = 0);
   FPeopleBus := Bus;
end;

procedure TPopulationFeatureNode.PeopleBusAssignJobs(Count: Cardinal);
begin
   if (FWorkers <> Count) then
   begin
      FWorkers := Count;
      MarkAsDirty([dkUpdateClients]);
   end;
end;

procedure TPopulationFeatureNode.PeopleBusDisconnected();
begin
   Assert(Assigned(FPeopleBus));
   if (FWorkers <> 0) then
      MarkAsDirty([dkUpdateClients]);
   FWorkers := 0;
   FPriority := 0; // TODO: also update clients here if we ever send this to the clients
   FPeopleBus := nil;
end;

function TPopulationFeatureNode.GetWorkers(): Cardinal;
begin
   Result := FPopulation;
end;

function TPopulationFeatureNode.GetPriority(): TPriority;
begin
   Result := FPriority;
end;

procedure TPopulationFeatureNode.SetAutoPriority(Value: TAutoPriority);
begin
   FPriority := Value;
end;

function TPopulationFeatureNode.GetAsset(): TAssetNode;
begin
   Result := Parent;
end;

initialization
   RegisterFeatureClass(TPopulationFeatureClass);
end.