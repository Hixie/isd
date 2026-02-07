{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit peoplebus;

interface

uses
   sysutils, systems, internals, systemdynasty, serverstream,
   materials, hashsettight, hashtable, genericutils, commonbuses,
   plasticarrays;

type
   TPeopleBusFeatureNode = class;

   TPeopleBusMessage = class abstract(TPhysicalConnectionBusMessage)
   end;

   IEmployer = interface ['IEmployer']
      procedure PeopleBusConnected(Bus: TPeopleBusFeatureNode);
      procedure PeopleBusAssignWorkers(Count: Cardinal);
      procedure PeopleBusDisconnected();
      function GetJobs(): Cardinal;
      function GetPriority(): TPriority;
      procedure SetAutoPriority(Value: TAutoPriority);
      function GetAsset(): TAssetNode;
   end;

   TRegisterEmployerMessage = class(TPeopleBusMessage)
   private
      FEmployer: IEmployer;
   public
      constructor Create(AEmployer: IEmployer);
      property Employer: IEmployer read FEmployer;
   end;

   IHousing = interface ['IHousing']
      procedure PeopleBusConnected(Bus: TPeopleBusFeatureNode);
      procedure PeopleBusAssignJobs(Count: Cardinal);
      procedure PeopleBusDisconnected();
      function GetWorkers(): Cardinal;
      function GetPriority(): TPriority;
      procedure SetAutoPriority(Value: TAutoPriority);
      function GetAsset(): TAssetNode;
   end;

   TRegisterHousingMessage = class(TPeopleBusMessage)
   private
      FHousing: IHousing;
   public
      constructor Create(AHousing: IHousing);
      property Housing: IHousing read FHousing;
   end;

   generic PrioritizableUtils<T> = record
   strict private
      class function GetPriority(const A: T): TPriority; static; inline;
   public
      class function Equals(const A, B: T): Boolean; static; inline;
      class function LessThan(const A, B: T): Boolean; static; inline;
      class function GreaterThan(const A, B: T): Boolean; static; inline;
      class function Compare(const A, B: T): Int64; static; inline;
   end;

   TPeopleBusFeatureClass = class(TFeatureClass)
   strict protected
      function GetFeatureNodeClass(): FeatureNodeReference; override;
   public
      constructor CreateFromTechnologyTree(const Reader: TTechTreeReader); override;
      function InitFeatureNode(ASystem: TSystem): TFeatureNode; override;
   end;

   TPeopleBusFeatureNode = class(TFeatureNode)
   protected
      type
         TPeopleBusRecords = record
         strict private
            FNextPriority: TAutoPriority;
            FWorkersAssignedToEmployers: Boolean;
            class operator Initialize(var Rec: TPeopleBusRecords);
            class operator Finalize(var Rec: TPeopleBusRecords);
         public
            function AssignNextPriority(): TAutoPriority;
            procedure ResetNextPriority(Value: TAutoPriority);
            property NextPriority: TAutoPriority read FNextPriority;
            property WorkersAssignedToEmployers: Boolean read FWorkersAssignedToEmployers write FWorkersAssignedToEmployers;
         public
            type
               TEmployerList = specialize PlasticArray<IEmployer, specialize PrioritizableUtils<IEmployer>>;
               THousingList = specialize PlasticArray<IHousing, specialize PrioritizableUtils<IHousing>>;
               TPerDynastyEmployers = specialize THashTable<TDynasty, TEmployerList, TObjectUtils>; // use ItemsPtr to fetch values!
               TPerDynastyHousing = specialize THashTable<TDynasty, THousingList, TObjectUtils>; // use ItemsPtr to fetch values!
               TDynastySet = specialize TObjectSet<TDynasty>;
         public
            type
               TDynastyEnumerator = class
               strict private
                  FCurrent, FSingleDynasty: TDynasty;
                  FEmployerDynasties: TPerDynastyEmployers.TKeyEnumerator;
                  FHousingDynasties: TPerDynastyHousing.TKeyEnumerator;
                  function GetCurrent(): TDynasty;
               private
                  constructor Create(ASingleDynasty: TDynasty; AEmployerDynasties: TPerDynastyEmployers.TKeyEnumerator; AHousingDynasties: TPerDynastyHousing.TKeyEnumerator); // enumerator arguments will be freed on destruction!
               public
                  destructor Destroy(); override;
                  function MoveNext(): Boolean;
                  property Current: TDynasty read GetCurrent;
                  function GetEnumerator(): TDynastyEnumerator;
               end;
         strict private
            const
               MultiDynasticMarker = High(PtrUInt);
            type
               PEmployerList = ^TEmployerList;
               PHousingList = ^THousingList;
            procedure AddDynasty(Value: TDynasty; out DynastyEmployers: PEmployerList; out DynastyHousing: PHousingList);
            function GetDynasties(): TDynastyEnumerator;
            function GetIsMultidynastic(): Boolean; inline;
            function GetIsNotMultidynastic(): Boolean; inline;
            function GetInternalEmployers(): PEmployerList; inline;
            function GetInternalHousing(): PHousingList; inline;
            property FEmployers: PEmployerList read GetInternalEmployers;
            property FHousing: PHousingList read GetInternalHousing;
            property IsMultidynastic: Boolean read GetIsMultidynastic;
            property IsNotMultidynastic: Boolean read GetIsNotMultidynastic;
         public
            procedure AddEmployer(Dynasty: TDynasty; Employer: IEmployer);
            procedure RemoveEmployer(Dynasty: TDynasty; Employer: IEmployer);
            function GetEmployers(Dynasty: TDynasty): TEmployerList.TReadOnlyView;
            procedure AddHousing(Dynasty: TDynasty; Housing: IHousing);
            procedure RemoveHousing(Dynasty: TDynasty; Housing: IHousing);
            function GetHousing(Dynasty: TDynasty): THousingList.TReadOnlyView;
            property Dynasties: TDynastyEnumerator read GetDynasties; // allocates a new object
         strict private
            FDynasty: TDynasty;
            {$PUSH}
            {$CODEALIGN RECORDMIN=4}
            case Byte of
               0: ();
               1: (FEmployersMem: array[0..SizeOf(TEmployerList)] of Byte; FHousingMem: array[0..SizeOf(THousingList)] of Byte);
               2: (FEmployersPerDynasty: TPerDynastyEmployers; FHousingPerDynasty: TPerDynastyHousing);
            {$POP}
         end;
      var
         FRecords: TPeopleBusRecords;
      function ManageBusMessage(Message: TBusMessage): TInjectBusMessageResult; override;
      function HandleBusMessage(Message: TBusMessage): THandleBusMessageResult; override;
      procedure HandleChanges(); override;
      procedure Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter); override;
   public
      destructor Destroy(); override;
      procedure UpdateJournal(Journal: TJournalWriter); override;
      procedure ApplyJournal(Journal: TJournalReader); override;
      procedure RemoveEmployer(Employer: IEmployer);
      procedure RemoveHousing(Housing: IHousing);
      procedure ClientChanged(); // e.g. if Housing.Workers changed
   end;

// TODO: handle changes of ownership and ancestor chains

implementation

uses
   exceptions, typedump, arrayutils, ttparser;

constructor TRegisterEmployerMessage.Create(AEmployer: IEmployer);
begin
   inherited Create();
   FEmployer := AEmployer;
end;

constructor TRegisterHousingMessage.Create(AHousing: IHousing);
begin
   inherited Create();
   FHousing := AHousing;
end;


class function PrioritizableUtils.GetPriority(const A: T): TPriority;
begin
   if (Assigned(A)) then
   begin
      Result := A.GetPriority
   end
   else
      Result := High(TPriority);
end;

class function PrioritizableUtils.Equals(const A, B: T): Boolean;
begin
   Result := A = B;
end;

class function PrioritizableUtils.LessThan(const A, B: T): Boolean;
begin
   Result := GetPriority(A) < GetPriority(B);
end;

class function PrioritizableUtils.GreaterThan(const A, B: T): Boolean;
begin
   Result := GetPriority(A) > GetPriority(B);
end;

class function PrioritizableUtils.Compare(const A, B: T): Int64;
begin
   Result := GetPriority(A) - GetPriority(B);
end;


constructor TPeopleBusFeatureNode.TPeopleBusRecords.TDynastyEnumerator.Create(ASingleDynasty: TDynasty; AEmployerDynasties: TPerDynastyEmployers.TKeyEnumerator; AHousingDynasties: TPerDynastyHousing.TKeyEnumerator);
begin
   inherited Create();
   FSingleDynasty := ASingleDynasty;
   FEmployerDynasties := AEmployerDynasties;
   FHousingDynasties := AHousingDynasties;
end;

destructor TPeopleBusFeatureNode.TPeopleBusRecords.TDynastyEnumerator.Destroy();
begin
   FreeAndNil(FEmployerDynasties);
   FreeAndNil(FHousingDynasties);
   inherited;
end;

function TPeopleBusFeatureNode.TPeopleBusRecords.TDynastyEnumerator.GetCurrent(): TDynasty;
begin
   Result := FCurrent;
end;

function TPeopleBusFeatureNode.TPeopleBusRecords.TDynastyEnumerator.MoveNext(): Boolean;
begin
   if (Assigned(FSingleDynasty)) then
   begin
      FCurrent := FSingleDynasty;
      FSingleDynasty := nil;
      Result := True;
      exit;
   end;
   if (Assigned(FEmployerDynasties)) then
   begin
      if (FEmployerDynasties.MoveNext()) then
      begin
         FCurrent := FEmployerDynasties.Current;
         Result := True;
         exit;
      end;
      FreeAndNil(FEmployerDynasties);
   end;
   if (Assigned(FHousingDynasties)) then
   begin
      if (FHousingDynasties.MoveNext()) then
      begin
         FCurrent := FHousingDynasties.Current;
         Result := True;
         exit;
      end;
      FreeAndNil(FHousingDynasties);
   end;
   FCurrent := nil;
   Result := False;
end;

function TPeopleBusFeatureNode.TPeopleBusRecords.TDynastyEnumerator.GetEnumerator(): TDynastyEnumerator;
begin
   Result := Self;
end;


class operator TPeopleBusFeatureNode.TPeopleBusRecords.Initialize(var Rec: TPeopleBusRecords);
begin
   Rec.FNextPriority := Low(Rec.FNextPriority);
end;

class operator TPeopleBusFeatureNode.TPeopleBusRecords.Finalize(var Rec: TPeopleBusRecords);
begin
   if (Assigned(Rec.FDynasty)) then
   begin
      if (Rec.IsNotMultidynastic) then
      begin
         Finalize(Rec.FEmployers^);
         Finalize(Rec.FHousing^);
      end
      else
      begin
         Assert(Rec.IsMultidynastic);
         FreeAndNil(Rec.FEmployersPerDynasty);
         FreeAndNil(Rec.FHousingPerDynasty);
      end;
      {$IFOPT C+} Rec.FDynasty := nil; {$ENDIF}
   end;
end;

function TPeopleBusFeatureNode.TPeopleBusRecords.AssignNextPriority(): TAutoPriority;
begin
   Result := FNextPriority;
   FNextPriority := FNextPriority + 1; // $R-
end;

procedure TPeopleBusFeatureNode.TPeopleBusRecords.ResetNextPriority(Value: TAutoPriority);
begin
   FNextPriority := Value;
end;

procedure TPeopleBusFeatureNode.TPeopleBusRecords.AddDynasty(Value: TDynasty; out DynastyEmployers: PEmployerList; out DynastyHousing: PHousingList);
var
   NewEmployersPerDynasty: TPerDynastyEmployers;
   NewHousingPerDynasty: TPerDynastyHousing;
begin
   if (not Assigned(FDynasty)) then
   begin
      FDynasty := Value;
      Initialize(FEmployers^);
      DynastyEmployers := FEmployers;
      Initialize(FHousing^);
      DynastyHousing := FHousing;
   end
   else
   if (IsNotMultidynastic) then
   begin
      if (FDynasty = Value) then
      begin
         DynastyEmployers := FEmployers;
         DynastyHousing := FHousing;
      end
      else
      begin
         // employers
         NewEmployersPerDynasty := TPerDynastyEmployers.Create(@DynastyHash32);
         NewEmployersPerDynasty.AddDefault(FDynasty);
         NewEmployersPerDynasty.ItemsPtr[FDynasty]^.CloneFrom(FEmployers^);
         Finalize(FEmployers^);
         FEmployersPerDynasty := NewEmployersPerDynasty;
         FEmployersPerDynasty.AddDefault(Value);
         DynastyEmployers := FEmployersPerDynasty.ItemsPtr[Value];
         // housing
         NewHousingPerDynasty := TPerDynastyHousing.Create(@DynastyHash32);
         NewHousingPerDynasty.AddDefault(FDynasty);
         NewHousingPerDynasty.ItemsPtr[FDynasty]^.CloneFrom(FHousing^);
         Finalize(FHousing^);
         FHousingPerDynasty := NewHousingPerDynasty;
         FHousingPerDynasty.AddDefault(Value);
         DynastyHousing := FHousingPerDynasty.ItemsPtr[Value];
         // mark as multi-dynastic
         PtrUInt(FDynasty) := MultiDynasticMarker;
      end;
   end
   else
   begin
      Assert(IsMultidynastic);
      Assert(FEmployersPerDynasty.Has(Value) = FHousingPerDynasty.Has(Value));
      if (not FEmployersPerDynasty.Has(Value)) then
      begin
         FEmployersPerDynasty.AddDefault(Value);
         FHousingPerDynasty.AddDefault(Value);
      end;
      DynastyEmployers := FEmployersPerDynasty.ItemsPtr[Value];
      DynastyHousing := FHousingPerDynasty.ItemsPtr[Value];
   end;
end;

function TPeopleBusFeatureNode.TPeopleBusRecords.GetDynasties(): TDynastyEnumerator;
begin
   if (not Assigned(FDynasty)) then
   begin
      Result := nil;
   end
   else
   if (IsNotMultidynastic) then
   begin
      Result := TDynastyEnumerator.Create(FDynasty, nil, nil);
   end
   else
   begin
      Assert(IsMultidynastic);
      Result := TDynastyEnumerator.Create(nil, FEmployersPerDynasty.GetEnumerator(), FHousingPerDynasty.GetEnumerator());
   end;
end;

function TPeopleBusFeatureNode.TPeopleBusRecords.GetIsMultidynastic(): Boolean;
begin
   Result := PtrUInt(FDynasty) = MultiDynasticMarker;
end;

function TPeopleBusFeatureNode.TPeopleBusRecords.GetIsNotMultidynastic(): Boolean;
begin
   Result := PtrUInt(FDynasty) <> MultiDynasticMarker;
end;

function TPeopleBusFeatureNode.TPeopleBusRecords.GetInternalEmployers(): PEmployerList;
begin
   Assert(Assigned(FDynasty) and (IsNotMultidynastic));
   Result := PEmployerList(@FEmployersMem);
end;

function TPeopleBusFeatureNode.TPeopleBusRecords.GetInternalHousing(): PHousingList;
begin
   Assert(Assigned(FDynasty) and (IsNotMultidynastic));
   Result := PHousingList(@FHousingMem);
end;

procedure TPeopleBusFeatureNode.TPeopleBusRecords.AddEmployer(Dynasty: TDynasty; Employer: IEmployer);
var
   DynastyEmployers: PEmployerList;
   DynastyHousing: PHousingList;
begin
   AddDynasty(Dynasty, DynastyEmployers, DynastyHousing);
   Assert(not DynastyEmployers^.Contains(Employer));
   DynastyEmployers^.Push(Employer);
end;

procedure TPeopleBusFeatureNode.TPeopleBusRecords.RemoveEmployer(Dynasty: TDynasty; Employer: IEmployer);
begin
   Assert(Assigned(FDynasty));
   if (FDynasty = Dynasty) then
   begin
      FEmployers^.Replace(Employer, nil);
   end
   else
   begin
      Assert(IsMultidynastic);
      FEmployersPerDynasty.ItemsPtr[Dynasty]^.Replace(Employer, nil);
   end;
end;

procedure TPeopleBusFeatureNode.TPeopleBusRecords.AddHousing(Dynasty: TDynasty; Housing: IHousing);
var
   DynastyEmployers: PEmployerList;
   DynastyHousing: PHousingList;
begin
   AddDynasty(Dynasty, DynastyEmployers, DynastyHousing);
   Assert(not DynastyHousing^.Contains(Housing));
   DynastyHousing^.Push(Housing);
end;

procedure TPeopleBusFeatureNode.TPeopleBusRecords.RemoveHousing(Dynasty: TDynasty; Housing: IHousing);
begin
   Assert(Assigned(FDynasty));
   if (FDynasty = Dynasty) then
   begin
      FHousing^.Replace(Housing, nil);
   end
   else
   begin
      Assert(IsMultidynastic);
      FHousingPerDynasty.ItemsPtr[Dynasty]^.Replace(Housing, nil);
   end;
end;

function TPeopleBusFeatureNode.TPeopleBusRecords.GetEmployers(Dynasty: TDynasty): TEmployerList.TReadOnlyView;
var
   Employers: PEmployerList;
begin
   Assert(Assigned(FDynasty));
   if (IsNotMultidynastic) then
   begin
      Employers := FEmployers;
   end
   else
   begin
      Assert(IsMultidynastic);
      Employers := FEmployersPerDynasty.ItemsPtr[Dynasty];
   end;
   Employers^.Sort();
   Employers^.RemoveAllTrailing(nil);
   Result := Employers^.GetReadOnlyView();
end;

function TPeopleBusFeatureNode.TPeopleBusRecords.GetHousing(Dynasty: TDynasty): THousingList.TReadOnlyView;
var
   Housing: PHousingList;
begin
   Assert(Assigned(FDynasty));
   if (IsNotMultidynastic) then
   begin
      Housing := FHousing;
   end
   else
   begin
      Assert(IsMultidynastic);
      Housing := FHousingPerDynasty.ItemsPtr[Dynasty];
   end;
   Housing^.Sort();
   Housing^.RemoveAllTrailing(nil);
   Result := Housing^.GetReadOnlyView();
end;


constructor TPeopleBusFeatureClass.CreateFromTechnologyTree(const Reader: TTechTreeReader);
begin
   inherited Create();
end;

function TPeopleBusFeatureClass.GetFeatureNodeClass(): FeatureNodeReference;
begin
   Result := TPeopleBusFeatureNode;
end;

function TPeopleBusFeatureClass.InitFeatureNode(ASystem: TSystem): TFeatureNode;
begin
   Result := TPeopleBusFeatureNode.Create(ASystem);
end;


destructor TPeopleBusFeatureNode.Destroy();
var
   Dynasty: TDynasty;
   EmployerList: TPeopleBusRecords.TEmployerList.TReadOnlyView;
   Employer: IEmployer;
   HousingList: TPeopleBusRecords.THousingList.TReadOnlyView;
   Housing: IHousing;
begin
   for Dynasty in FRecords.Dynasties do
   begin
      EmployerList := FRecords.GetEmployers(Dynasty);
      HousingList := FRecords.GetHousing(Dynasty);
      for Employer in EmployerList do
      begin
         Employer.PeopleBusDisconnected();
      end;
      for Housing in HousingList do
      begin
         Housing.PeopleBusDisconnected();
      end;
   end;
   inherited;
end;

function TPeopleBusFeatureNode.ManageBusMessage(Message: TBusMessage): TInjectBusMessageResult;
begin
   if (Message is TPeopleBusMessage) then
   begin
      Result := DeferOrHandleBusMessage(Message);
   end
   else
      Result := inherited;
end;

function TPeopleBusFeatureNode.HandleBusMessage(Message: TBusMessage): THandleBusMessageResult;
var
   RegisterEmployer: TRegisterEmployerMessage;
   RegisterHousing: TRegisterHousingMessage;
begin
   if (Message is TRegisterEmployerMessage) then
   begin
      RegisterEmployer := Message as TRegisterEmployerMessage;
      FRecords.AddEmployer(RegisterEmployer.Employer.GetAsset().Owner, RegisterEmployer.Employer);
      RegisterEmployer.Employer.PeopleBusConnected(Self);
      if (RegisterEmployer.Employer.GetPriority() = 0) then
         RegisterEmployer.Employer.SetAutoPriority(FRecords.AssignNextPriority());
      FRecords.WorkersAssignedToEmployers := False;
      MarkAsDirty([dkNeedsHandleChanges]);
      Result := hrHandled;
   end
   else
   if (Message is TRegisterHousingMessage) then
   begin
      RegisterHousing := Message as TRegisterHousingMessage;
      FRecords.AddHousing(RegisterHousing.Housing.GetAsset().Owner, RegisterHousing.Housing);
      RegisterHousing.Housing.PeopleBusConnected(Self);
      if (RegisterHousing.Housing.GetPriority() = 0) then
         RegisterHousing.Housing.SetAutoPriority(FRecords.AssignNextPriority());
      FRecords.WorkersAssignedToEmployers := False;
      MarkAsDirty([dkNeedsHandleChanges]);
      Result := hrHandled;
   end
   else
      Result := inherited;
end;

procedure TPeopleBusFeatureNode.HandleChanges();
var
   Dynasty: TDynasty;
   EmployerList: TPeopleBusRecords.TEmployerList.TReadOnlyView;
   Employer: IEmployer;
   HousingList: TPeopleBusRecords.THousingList.TReadOnlyView;
   Housing: IHousing;
   WorkerCount, Jobs, TotalJobs: Cardinal;
begin
   if (not FRecords.WorkersAssignedToEmployers) then
   begin
      for Dynasty in FRecords.Dynasties do
      begin
         EmployerList := FRecords.GetEmployers(Dynasty);
         HousingList := FRecords.GetHousing(Dynasty);
         WorkerCount := 0;
         for Housing in HousingList do
         begin
            Inc(WorkerCount, Housing.GetWorkers());
         end;
         TotalJobs := 0;
         // TODO: support sending suboptimal amounts of people to employers
         for Employer in EmployerList do
         begin
            Jobs := Employer.GetJobs();
            if (WorkerCount >= Jobs) then
            begin
               Employer.PeopleBusAssignWorkers(Jobs);
               Dec(WorkerCount, Jobs);
               Inc(TotalJobs, Jobs);
            end
            else
               Employer.PeopleBusAssignWorkers(0);
         end;
         for Housing in HousingList do
         begin
            WorkerCount := Housing.GetWorkers();
            if (TotalJobs < WorkerCount) then
            begin
               Housing.PeopleBusAssignJobs(TotalJobs);
               TotalJobs := 0;
            end
            else
            begin
               Housing.PeopleBusAssignJobs(WorkerCount);
               Dec(TotalJobs, WorkerCount);
            end;
         end;
      end;
      FRecords.WorkersAssignedToEmployers := True;
   end;
end;

procedure TPeopleBusFeatureNode.Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter);
begin
end;

procedure TPeopleBusFeatureNode.UpdateJournal(Journal: TJournalWriter);
begin
   Journal.WriteCardinal(FRecords.NextPriority);
end;

procedure TPeopleBusFeatureNode.ApplyJournal(Journal: TJournalReader);
begin
   FRecords.ResetNextPriority(TAutoPriority(Journal.ReadCardinal()));
end;

procedure TPeopleBusFeatureNode.RemoveEmployer(Employer: IEmployer);
begin
   FRecords.RemoveEmployer(Employer.GetAsset().Owner, Employer);
   FRecords.WorkersAssignedToEmployers := False;
   MarkAsDirty([dkNeedsHandleChanges]);
end;

procedure TPeopleBusFeatureNode.RemoveHousing(Housing: IHousing);
begin
   FRecords.RemoveHousing(Housing.GetAsset().Owner, Housing);
   FRecords.WorkersAssignedToEmployers := False;
   MarkAsDirty([dkNeedsHandleChanges]);
end;

procedure TPeopleBusFeatureNode.ClientChanged();
begin
   FRecords.WorkersAssignedToEmployers := False;
   MarkAsDirty([dkNeedsHandleChanges]);
end;

initialization
   RegisterFeatureClass(TPeopleBusFeatureClass);
end.