{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit population;

interface

uses
   systems, serverstream, materials, food, systemdynasty, techtree,
   peoplebus, commonbuses;

type
   TPopulationFeatureClass = class(TFeatureClass)
   strict protected
      // TODO: max population?
      function GetFeatureNodeClass(): FeatureNodeReference; override;
   public
      constructor CreateFromTechnologyTree(Reader: TTechTreeReader); override;
      function InitFeatureNode(): TFeatureNode; override;
   end;

   TPopulationFeatureNode = class(TFeatureNode, IFoodConsumer, IHousing)
   private
      // source of truth
      FPopulation: Cardinal; // TODO: if this changes, call FPeopleBus.ClientChanged
      FPriority: TPriority; // TODO: if ancestor chain changes, and priority is NoPriority, reset it to zero and mark as dirty
      FMeanHappiness: Double;
      // cached status
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
      procedure Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter; CachedSystem: TSystem); override;
   public
      constructor CreatePopulated(APopulation: Cardinal; AMeanHappiness: Double); // only for use in plot-generated population centers
      destructor Destroy(); override;
      procedure HandleChanges(CachedSystem: TSystem); override;
      procedure UpdateJournal(Journal: TJournalWriter; CachedSystem: TSystem); override;
      procedure ApplyJournal(Journal: TJournalReader; CachedSystem: TSystem); override;
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


constructor TPopulationFeatureClass.CreateFromTechnologyTree(Reader: TTechTreeReader);
begin
   inherited Create();
end;

function TPopulationFeatureClass.GetFeatureNodeClass(): FeatureNodeReference;
begin
   Result := TPopulationFeatureNode;
end;

function TPopulationFeatureClass.InitFeatureNode(): TFeatureNode;
begin
   Result := TPopulationFeatureNode.Create();
   // TODO: people need to actually join the population center presumably
end;


constructor TPopulationFeatureNode.CreatePopulated(APopulation: Cardinal; AMeanHappiness: Double);
begin
   inherited Create();
   FPopulation := APopulation;
   FMeanHappiness := AMeanHappiness;
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
   Assert(FPriority = 0);
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

procedure TPopulationFeatureNode.Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter; CachedSystem: TSystem);
var
   Visibility: TVisibility;
begin
   Visibility := Parent.ReadVisibilityFor(DynastyIndex, CachedSystem);
   if (dmDetectable * Visibility <> []) then
   begin
      Writer.WriteCardinal(fcPopulation);
      Writer.WriteCardinal(FPopulation);
      Writer.WriteCardinal(FWorkers);
      // TODO: if we send the priority, we have to update the clients any time FPriority changes
      if (dmInternals in Visibility) then
         Writer.WriteDouble(FMeanHappiness)
      else
         Writer.WriteDouble(NaN);
   end;
end;

procedure TPopulationFeatureNode.HandleChanges(CachedSystem: TSystem);
var
   Message: TRegisterHousingMessage;
begin
   if ((not Assigned(FPeopleBus)) and (FPriority <> NoPriority)) then
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

procedure TPopulationFeatureNode.UpdateJournal(Journal: TJournalWriter; CachedSystem: TSystem);
begin
   Journal.WriteCardinal(FPopulation);
   Journal.WriteCardinal(FPriority);
   Journal.WriteDouble(FMeanHappiness);
end;

procedure TPopulationFeatureNode.ApplyJournal(Journal: TJournalReader; CachedSystem: TSystem);
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