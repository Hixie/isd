{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit population;

interface

uses
   systems, serverstream, materials, food, systemdynasty, techtree;

type
   TPopulationFeatureClass = class(TFeatureClass)
   strict protected
      // TODO: max population?
      function GetFeatureNodeClass(): FeatureNodeReference; override;
   public
      constructor CreateFromTechnologyTree(Reader: TTechTreeReader); override;
      function InitFeatureNode(): TFeatureNode; override;
   end;

   TPopulationFeatureNode = class(TFeatureNode, IFoodConsumer)
   private
      FPopulation: Int64;
      FFoodAvailable: Int64;
      FMeanHappiness: Double;
      function GetOwner(): TDynasty;
      procedure SetFoodUsage(Quantity: Int64);
   protected
      procedure Attached(); override;
      procedure Detaching(); override;
      function GetMass(): Double; override;
      function GetHappiness(): Double; override;
      function HandleBusMessage(Message: TBusMessage): Boolean; override;
      procedure Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter; CachedSystem: TSystem); override;
   public
      constructor CreatePopulated(APopulation: Int64; AMeanHappiness: Double); // only for use in plot-generated population centers
      procedure UpdateJournal(Journal: TJournalWriter; CachedSystem: TSystem); override;
      procedure ApplyJournal(Journal: TJournalReader; CachedSystem: TSystem); override;
      procedure DescribeExistentiality(var IsDefinitelyReal, IsDefinitelyGhost: Boolean); override;
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


constructor TPopulationFeatureNode.CreatePopulated(APopulation: Int64; AMeanHappiness: Double);
begin
   inherited Create();
   FPopulation := APopulation;
   FMeanHappiness := AMeanHappiness;
end;

procedure TPopulationFeatureNode.Attached();
begin
   System.ReportScoreChanged(Parent.Owner);
end;

procedure TPopulationFeatureNode.Detaching();
begin
   System.ReportScoreChanged(Parent.Owner);
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
      Writer.WriteInt64(FPopulation);
      if (dmInternals in Visibility) then
         Writer.WriteDouble(FMeanHappiness)
      else
         Writer.WriteDouble(NaN);
   end;
end;

procedure TPopulationFeatureNode.UpdateJournal(Journal: TJournalWriter; CachedSystem: TSystem);
begin
   Journal.WriteInt64(FPopulation);
   Journal.WriteDouble(FMeanHappiness);
end;

procedure TPopulationFeatureNode.ApplyJournal(Journal: TJournalReader; CachedSystem: TSystem);
begin
   FPopulation := Journal.ReadInt64();
   FMeanHappiness := Journal.ReadDouble();
end;

function TPopulationFeatureNode.GetOwner(): TDynasty;
begin
   Result := Parent.Owner;
end;

procedure TPopulationFeatureNode.SetFoodUsage(Quantity: Int64);
begin
   if (Quantity <> FFoodAvailable) then
   begin
      FFoodAvailable := Quantity;
      // TODO: happiness should change over time, not instantly
      FMeanHappiness := FFoodAvailable / FPopulation; // TODO: expose why the happiness is as it is
      System.ReportScoreChanged(Parent.Owner);
   end;
end;

procedure TPopulationFeatureNode.DescribeExistentiality(var IsDefinitelyReal, IsDefinitelyGhost: Boolean);
begin
   IsDefinitelyReal := FPopulation > 0; // TODO: if FPopulation ever changes whether it's 0 or not, MarkAsDirty([dkAffectsVisibility])
end;

initialization
   RegisterFeatureClass(TPopulationFeatureClass);
end.