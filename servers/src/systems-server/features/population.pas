{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit population;

interface

uses
   systems, serverstream, materials, food, systemdynasty, techtree,
   peoplebus, commonbuses;

// TODO: people need to actually join the population center presumably

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

   TPopulationFeatureNode = class(TFeatureNode, IFoodConsumer, IHousing)
   private
      // source of truth
      FPopulation: Cardinal; // TODO: if this changes, call FPeopleBus.ClientChanged
      FPriority: TPriority; // TODO: if ancestor chain changes, and priority is NoPriority, reset it to zero and mark as dirty
      FDisabledReasons: TDisabledReasons;
      FMeanHappiness: Double;
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
      function GetMass(): Double; override;
      function GetHappiness(): Double; override;
      function HandleBusMessage(Message: TBusMessage): Boolean; override;
      procedure Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter); override;
   public
      constructor Create(ASystem: TSystem; AFeatureClass: TPopulationFeatureClass);
      constructor CreatePopulated(ASystem: TSystem; AFeatureClass: TPopulationFeatureClass; APopulation: Cardinal; AMeanHappiness: Double); // only for use in plot-generated population centers
      constructor CreateFromJournal(Journal: TJournalReader; AFeatureClass: TFeatureClass; ASystem: TSystem); override;
      destructor Destroy(); override;
      procedure HandleChanges(); override;
      procedure UpdateJournal(Journal: TJournalWriter); override;
      procedure ApplyJournal(Journal: TJournalReader); override;
      procedure DescribeExistentiality(var IsDefinitelyReal, IsDefinitelyGhost: Boolean); override;
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
   isdprotocol, messages, orbit, sysutils, math;

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

constructor TPopulationFeatureNode.CreatePopulated(ASystem: TSystem; AFeatureClass: TPopulationFeatureClass; APopulation: Cardinal; AMeanHappiness: Double);
begin
   inherited Create(ASystem);
   Assert(Assigned(AFeatureClass));
   FFeatureClass := AFeatureClass;
   FPopulation := APopulation;
   FMeanHappiness := AMeanHappiness;
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
   inherited;
end;

procedure TPopulationFeatureNode.Attaching();
begin
   Assert(not Assigned(FPeopleBus));
   Assert(FWorkers = 0);
   // FPriority can be non-zero here if we were just brought in from the journal
   System.ReportScoreChanged(Parent.Owner);
   MarkAsDirty([dkNeedsHandleChanges]);
end;

procedure TPopulationFeatureNode.Detaching();
begin
   System.ReportScoreChanged(Parent.Owner);
   if (Assigned(FPeopleBus)) then
   begin
      FPeopleBus.RemoveHousing(Self);
      FWorkers := 0;
      FPriority := 0;
      FPeopleBus := nil;
   end;
end;

function TPopulationFeatureNode.GetMass(): Double;
begin
   Result := MeanIndividualMass * FPopulation;
end;

function TPopulationFeatureNode.GetHappiness(): Double;
begin
   Result := FPopulation * FMeanHappiness;
end;

function TPopulationFeatureNode.HandleBusMessage(Message: TBusMessage): Boolean;
var
   HelpMessage: TNotificationMessage;
   Injected: TBusMessageResult;
begin
   if (Message is TCrashReportMessage) then
   begin
      HelpMessage := TNotificationMessage.Create(
         Parent,
         'URGENT QUERY REGARDING RECENT EVENTS ABOARD COLONY SHIP'#$0A +
         'From: Passengers'#$0A +
         'WHAT THE HECK WHY DID WE JUST CRASH WHAT IS HAPPENING',
         nil
      );
      Injected := InjectBusMessage(HelpMessage);
      if (Injected <> mrHandled) then
         Writeln('Discarding message from population center ("', HelpMessage.Body, '")');
      Result := False; // TCrashReportMessage is handled when you explode yourself due to the crash (notifying someone isn't handling it!)
      FreeAndNil(HelpMessage);
      FMeanHappiness := FMeanHappiness - 0.1; // $R-
      System.ReportScoreChanged(Parent.Owner);
   end
   else
   if (Message is TInitFoodMessage) then
   begin
      (Message as TInitFoodMessage).RequestFoodToEat(Self, FPopulation);
      Result := False;
   end
   else
      Result := False;
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
      if (dmInternals in Visibility) then
         Writer.WriteDouble(FMeanHappiness)
      else
         Writer.WriteDouble(NaN);
   end;
end;

procedure TPopulationFeatureNode.HandleChanges();
var
   NewDisabledReasons: TDisabledReasons;
   Message: TRegisterHousingMessage;
begin
   NewDisabledReasons := CheckDisabled(Parent);
   if (NewDisabledReasons <> FDisabledReasons) then
   begin
      FDisabledReasons := NewDisabledReasons;
      MarkAsDirty([dkUpdateClients]);
   end;
   // TODO: people try to move to the "best" houses, but if they can't, they get unhappy
   Assert((FPopulation = 0) or Assigned(Parent.Owner));
   if ((FPopulation > 0) and (not Assigned(FPeopleBus)) and (FPriority <> NoPriority)) then
   begin
      Message := TRegisterHousingMessage.Create(Self);
      if (InjectBusMessage(Message) <> mrHandled) then
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
   Journal.WriteDouble(FMeanHappiness);
end;

procedure TPopulationFeatureNode.ApplyJournal(Journal: TJournalReader);
begin
   FPopulation := Journal.ReadCardinal();
   FPriority := TPriority(Journal.ReadCardinal());
   FMeanHappiness := Journal.ReadDouble();
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
      FMeanHappiness := FFoodAvailable / FPopulation; // TODO: expose why the happiness is as it is
      System.ReportScoreChanged(Parent.Owner);
   end;
end;

procedure TPopulationFeatureNode.DescribeExistentiality(var IsDefinitelyReal, IsDefinitelyGhost: Boolean);
begin
   IsDefinitelyReal := FPopulation > 0; // TODO: if FPopulation ever changes whether it's 0 or not, MarkAsDirty([dkAffectsVisibility])
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