{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit staffing;

interface

uses
   basenetwork, systems, serverstream, materials, techtree,
   messageport, isdprotocol, peoplebus, commonbuses;

type
   TStaffingFeatureClass = class(TFeatureClass)
   strict protected
      FJobs: Cardinal;
      function GetFeatureNodeClass(): FeatureNodeReference; override;
   public
      constructor CreateFromTechnologyTree(Reader: TTechTreeReader); override;
      function InitFeatureNode(ASystem: TSystem): TFeatureNode; override;
      property Jobs: Cardinal read FJobs;
   end;

   TStaffingFeatureNode = class(TFeatureNode, IEmployer)
   strict private
      FFeatureClass: TStaffingFeatureClass;
      FPeopleBus: TPeopleBusFeatureNode;
      FPriority: TPriority; // TODO: if equal to NoPriority, should reset to zero when ancestor chain changes
      FWorkers: Cardinal; // call MarkAsDirty dkAffectsVisibility anytime it changes to/from zero
   protected
      constructor CreateFromJournal(Journal: TJournalReader; AFeatureClass: TFeatureClass; ASystem: TSystem); override;
      function HandleBusMessage(Message: TBusMessage): THandleBusMessageResult; override;
      procedure Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter); override;
   public
      constructor Create(ASystem: TSystem; AFeatureClass: TStaffingFeatureClass);
      destructor Destroy(); override;
      procedure Attaching(); override;
      procedure Detaching(); override;
      procedure HandleChanges(); override;
      procedure UpdateJournal(Journal: TJournalWriter); override;
      procedure ApplyJournal(Journal: TJournalReader); override;
      procedure DescribeExistentiality(var IsDefinitelyReal, IsDefinitelyGhost: Boolean); override;
   public // IEmployer
      procedure PeopleBusConnected(Bus: TPeopleBusFeatureNode);
      procedure PeopleBusAssignWorkers(Count: Cardinal);
      procedure PeopleBusDisconnected();
      function GetJobs(): Cardinal;
      function GetPriority(): TPriority;
      procedure SetAutoPriority(Value: TAutoPriority);
      function GetAsset(): TAssetNode;
   end;

implementation

uses
   exceptions, sysutils, knowledge, typedump;

constructor TStaffingFeatureClass.CreateFromTechnologyTree(Reader: TTechTreeReader);
begin
   inherited Create();
   FJobs := ReadNumber(Reader.Tokens, 1, High(FJobs)); // $R-
   if (FJobs = 1) then
   begin
      Reader.Tokens.ReadIdentifier('job');
   end
   else
   begin
      Reader.Tokens.ReadIdentifier('jobs');
   end;
end;

function TStaffingFeatureClass.GetFeatureNodeClass(): FeatureNodeReference;
begin
   Result := TStaffingFeatureNode;
end;

function TStaffingFeatureClass.InitFeatureNode(ASystem: TSystem): TFeatureNode;
begin
   Result := TStaffingFeatureNode.Create(ASystem, Self);
end;


constructor TStaffingFeatureNode.Create(ASystem: TSystem; AFeatureClass: TStaffingFeatureClass);
begin
   inherited Create(ASystem);
   FFeatureClass := AFeatureClass;
end;

constructor TStaffingFeatureNode.CreateFromJournal(Journal: TJournalReader; AFeatureClass: TFeatureClass; ASystem: TSystem);
begin
   Assert(Assigned(AFeatureClass));
   FFeatureClass := AFeatureClass as TStaffingFeatureClass;
   inherited;
end;

destructor TStaffingFeatureNode.Destroy();
begin
   if (Assigned(FPeopleBus)) then
      FPeopleBus.RemoveEmployer(Self);
   inherited;
end;

procedure TStaffingFeatureNode.Attaching();
begin
   Assert(not Assigned(FPeopleBus));
   Assert(FWorkers = 0);
   // FPriority could be non-zero if coming from journal
   MarkAsDirty([dkNeedsHandleChanges]);
end;

procedure TStaffingFeatureNode.Detaching();
begin
   if (Assigned(FPeopleBus)) then
   begin
      FPeopleBus.RemoveEmployer(Self);
      FWorkers := 0;
      Assert(FPriority <> 0);
      FPriority := 0;
      FPeopleBus := nil;
      MarkAsDirty([dkUpdateJournal, dkAffectsVisibility]);
   end;
end;

procedure TStaffingFeatureNode.HandleChanges();
var
   DisabledReasons: TDisabledReasons;
   Message: TRegisterEmployerMessage;
begin
   DisabledReasons := CheckDisabled(Parent);
   Exclude(DisabledReasons, drUnderstaffed); // TODO: consider explicitly listing the reasons for which we wouldn't bother staffing instead
   if (DisabledReasons <> []) then
   begin
      if (FPriority <> 0) then
      begin
         FPriority := 0;
         MarkAsDirty([dkUpdateJournal]);
      end;
      if (Assigned(FPeopleBus)) then
      begin
         FPeopleBus.RemoveEmployer(Self);
         FPeopleBus := nil;
         FWorkers := 0;
         MarkAsDirty([dkUpdateClients, dkNeedsHandleChanges, dkAffectsVisibility]);
      end;
   end
   else
   begin
      if ((not Assigned(FPeopleBus)) and (FPriority <> NoPriority)) then
      begin
         Message := TRegisterEmployerMessage.Create(Self);
         if (InjectBusMessage(Message) <> irHandled) then
         begin
            FPriority := NoPriority;
            MarkAsDirty([dkUpdateJournal]);
         end
         else
         begin
            Assert(Assigned(FPeopleBus));
         end;
         FreeAndNil(Message);
      end;
   end;
   inherited;
end;

function TStaffingFeatureNode.HandleBusMessage(Message: TBusMessage): THandleBusMessageResult;
begin
   if (Message is TCheckDisabledBusMessage) then
   begin
      if (FWorkers < FFeatureClass.Jobs) then
         (Message as TCheckDisabledBusMessage).AddReason(drUnderstaffed);
   end;
   Result := inherited;
end;

procedure TStaffingFeatureNode.Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter);
var
   Visibility: TVisibility;
begin
   Visibility := Parent.ReadVisibilityFor(DynastyIndex);
   if (dmDetectable * Visibility <> []) then
   begin
      Writer.WriteCardinal(fcStaffing);
      if ([dmClassKnown, dmInternals] * Visibility <> []) then
      begin
         Writer.WriteCardinal(FFeatureClass.Jobs);
      end
      else
      begin
         Writer.WriteCardinal(0);
      end;
      Writer.WriteCardinal(FWorkers);
   end;
end;

procedure TStaffingFeatureNode.UpdateJournal(Journal: TJournalWriter);
begin
   if (FPriority = NoPriority) then
   begin
      Journal.WriteCardinal(0);
   end
   else
   begin
      Journal.WriteCardinal(FPriority);
   end;
end;

procedure TStaffingFeatureNode.ApplyJournal(Journal: TJournalReader);
begin
   FPriority := TPriority(Journal.ReadCardinal());
end;

procedure TStaffingFeatureNode.DescribeExistentiality(var IsDefinitelyReal, IsDefinitelyGhost: Boolean);
begin
   IsDefinitelyReal := FWorkers > 0;
end;

procedure TStaffingFeatureNode.PeopleBusConnected(Bus: TPeopleBusFeatureNode);
begin
   Assert(not Assigned(FPeopleBus));
   Assert(FWorkers = 0);
   FPeopleBus := Bus;
end;

procedure TStaffingFeatureNode.PeopleBusAssignWorkers(Count: Cardinal);
begin
   if (FWorkers <> Count) then
   begin
      FWorkers := Count;
      MarkAsDirty([dkUpdateClients, dkNeedsHandleChanges, dkAffectsVisibility]);
   end;
end;

procedure TStaffingFeatureNode.PeopleBusDisconnected();
begin
   Assert(Assigned(FPeopleBus));
   FPeopleBus := nil;
   Assert(FPriority <> 0);
   FPriority := 0;
   MarkAsDirty([dkUpdateJournal]);
   if (FWorkers > 0) then
   begin
      FWorkers := 0;
      MarkAsDirty([dkUpdateClients, dkNeedsHandleChanges, dkAffectsVisibility]);
   end;
end;

function TStaffingFeatureNode.GetJobs(): Cardinal;
begin
   Result := FFeatureClass.Jobs;
end;

function TStaffingFeatureNode.GetPriority(): TPriority;
begin
   Result := FPriority;
end;

procedure TStaffingFeatureNode.SetAutoPriority(Value: TAutoPriority);
begin
   FPriority := Value;
   MarkAsDirty([dkUpdateJournal]);
end;

function TStaffingFeatureNode.GetAsset(): TAssetNode;
begin
   Result := Parent;
end;

initialization
   RegisterFeatureClass(TStaffingFeatureClass);
end.