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
      function InitFeatureNode(): TFeatureNode; override;
      property Jobs: Cardinal read FJobs;
   end;

   TStaffingFeatureNode = class(TFeatureNode, IEmployer)
   strict private
      FFeatureClass: TStaffingFeatureClass;
      FBus: TPeopleBusFeatureNode;
      FPriority: TPriority; // TODO: if equal to NoPriority, should reset to zero when ancestor chain changes
      FWorkers: Cardinal;
   protected
      constructor CreateFromJournal(Journal: TJournalReader; AFeatureClass: TFeatureClass; ASystem: TSystem); override;
      function HandleBusMessage(Message: TBusMessage): Boolean; override;
      procedure Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter; CachedSystem: TSystem); override;
   public
      constructor Create(AFeatureClass: TStaffingFeatureClass);
      destructor Destroy(); override;
      procedure Attaching(); override;
      procedure Detaching(); override;
      procedure HandleChanges(CachedSystem: TSystem); override;
      procedure UpdateJournal(Journal: TJournalWriter; CachedSystem: TSystem); override;
      procedure ApplyJournal(Journal: TJournalReader; CachedSystem: TSystem); override;
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
   Reader.Tokens.ReadIdentifier('jobs');
end;

function TStaffingFeatureClass.GetFeatureNodeClass(): FeatureNodeReference;
begin
   Result := TStaffingFeatureNode;
end;

function TStaffingFeatureClass.InitFeatureNode(): TFeatureNode;
begin
   Result := TStaffingFeatureNode.Create(Self);
end;


constructor TStaffingFeatureNode.Create(AFeatureClass: TStaffingFeatureClass);
begin
   inherited Create();
   FFeatureClass := AFeatureClass;
end;

constructor TStaffingFeatureNode.CreateFromJournal(Journal: TJournalReader; AFeatureClass: TFeatureClass; ASystem: TSystem);
begin
   Assert(Assigned(AFeatureClass));
   FFeatureClass := AFeatureClass as TStaffingFeatureClass;
   inherited CreateFromJournal(Journal, AFeatureClass, ASystem);
end;

destructor TStaffingFeatureNode.Destroy();
begin
   if (Assigned(FBus)) then
      FBus.RemoveEmployer(Self);
   inherited;
end;

procedure TStaffingFeatureNode.Attaching();
begin
   Assert(not Assigned(FBus));
   Assert(FWorkers = 0);
   // FPriority could be non-zero if coming from journal
   MarkAsDirty([dkNeedsHandleChanges]);
end;

procedure TStaffingFeatureNode.Detaching();
begin
   if (Assigned(FBus)) then
   begin
      FBus.RemoveEmployer(Self);
      FWorkers := 0;
      FPriority := 0;
      FBus := nil;
   end;
end;

procedure TStaffingFeatureNode.HandleChanges(CachedSystem: TSystem);
var
   DisabledReasons: TDisabledReasons;
   Message: TRegisterEmployerMessage;
begin
   DisabledReasons := CheckDisabled(Parent);
   Exclude(DisabledReasons, drUnderstaffed); // TODO: consider explicitly listing the reasons for which we wouldn't bother staffing instead
   if (DisabledReasons <> []) then
   begin
      FPriority := 0;
      if (Assigned(FBus)) then
      begin
         FBus.RemoveEmployer(Self);
         FBus := nil;
         FWorkers := 0;
         MarkAsDirty([dkUpdateClients]);
      end;
   end
   else
   begin
      if ((not Assigned(FBus)) and (FPriority <> NoPriority)) then
      begin
         Message := TRegisterEmployerMessage.Create(Self);
         if (InjectBusMessage(Message) <> mrHandled) then
         begin
            FPriority := NoPriority;
         end
         else
         begin
            Assert(Assigned(FBus));
         end;
         FreeAndNil(Message);
      end;
   end;
   inherited;
end;

function TStaffingFeatureNode.HandleBusMessage(Message: TBusMessage): Boolean;
begin
   if (Message is TCheckDisabledBusMessage) then
   begin
      Result := False;
      if (FWorkers < FFeatureClass.Jobs) then
         (Message as TCheckDisabledBusMessage).AddReason(drUnderstaffed);
   end
   else
      Result := inherited;
end;

procedure TStaffingFeatureNode.Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter; CachedSystem: TSystem);
var
   Visibility: TVisibility;
begin
   Visibility := Parent.ReadVisibilityFor(DynastyIndex, CachedSystem);
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

procedure TStaffingFeatureNode.UpdateJournal(Journal: TJournalWriter; CachedSystem: TSystem);
begin
   Journal.WriteCardinal(FPriority);
end;

procedure TStaffingFeatureNode.ApplyJournal(Journal: TJournalReader; CachedSystem: TSystem);
begin
   FPriority := TPriority(Journal.ReadCardinal());
end;

procedure TStaffingFeatureNode.PeopleBusConnected(Bus: TPeopleBusFeatureNode);
begin
   Assert(not Assigned(FBus));
   Assert(FWorkers = 0);
   FBus := Bus;
end;

procedure TStaffingFeatureNode.PeopleBusAssignWorkers(Count: Cardinal);
begin
   if (FWorkers <> Count) then
   begin
      FWorkers := Count;
      MarkAsDirty([dkUpdateClients, dkNeedsHandleChanges]);
   end;
end;

procedure TStaffingFeatureNode.PeopleBusDisconnected();
begin
   Assert(Assigned(FBus));
   FBus := nil;
   FWorkers := 0;
   FPriority := 0;
   MarkAsDirty([dkUpdateClients, dkNeedsHandleChanges]);
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
end;

function TStaffingFeatureNode.GetAsset(): TAssetNode;
begin
   Result := Parent;
end;

initialization
   RegisterFeatureClass(TStaffingFeatureClass);
end.