{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit builders;

interface

uses
   sysutils, systems, systemdynasty, serverstream, materials,
   techtree, tttokenizer, time, hashsettight, hashtable, genericutils,
   commonbuses;

type
   EInvalidMaterialProvision = class(Exception) end;

   TBuilderBusFeatureNode = class;
   TBuilderFeatureNode = class;
   TBuilderHashSet = specialize TObjectSet<TBuilderFeatureNode>;
   
   IStructure = interface ['IStructure']
      procedure BuilderBusConnected(Bus: TBuilderBusFeatureNode); // must come from builder bus
      procedure BuilderBusReset(); // must come from builder bus, can assume all other participants (notably, builders) were also reset
      procedure StartBuilding(Builder: TBuilderFeatureNode; BuildRate: TRate);
      procedure StopBuilding();
      function GetAsset(): TAssetNode;
      function GetPriority(): TPriority;
      procedure SetAutoPriority(Value: TAutoPriority);
   end;
   TStructureHashSet = specialize TInterfaceSet<IStructure>;

   TRegisterBuilderMessage = class(TPhysicalConnectionBusMessage)
   private
      FBuilder: TBuilderFeatureNode;
   public
      constructor Create(ABuilder: TBuilderFeatureNode);
      property Builder: TBuilderFeatureNode read FBuilder;
      // TODO: some sort of information about prioritization?
   end;

   TRegisterStructureMessage = class(TPhysicalConnectionBusMessage)
   private
      FStructure: IStructure;
   public
      constructor Create(AStructure: IStructure);
      property Structure: IStructure read FStructure;
      // TODO: some sort of information about prioritization?
   end;

   TBuilderFeatureNodeArray = array of TBuilderFeatureNode;
   IStructureArray = array of IStructure;
   
   TBuilderBusRecords = record // TODO: possible improvements to performance are available by inlining a bunch of this, if the compiler doesn't do it for us
   strict private
      FNextPriority: TAutoPriority;
      FAssignedBuilders: Boolean;
   private
      property NextPriority: TAutoPriority read FNextPriority write FNextPriority;
      property AssignedBuilders: Boolean read FAssignedBuilders write FAssignedBuilders;
   strict private
      type
         TPerDynastyBuilders = specialize THashTable<TDynasty, TBuilderHashSet, TObjectUtils>;
         TPerDynastyStructures = specialize THashTable<TDynasty, TStructureHashSet, TObjectUtils>;
   private
      type
        TDynastyEnumerator = class
        strict private
           FDynasty: TDynasty;
           FDynastyEnumerator1: TPerDynastyBuilders.TKeyEnumerator;
           FDynastyEnumerator2: TPerDynastyStructures.TKeyEnumerator;
           FFlag: Boolean;
           function GetCurrent(): TDynasty;
        private
           constructor Create(ADynasty: TDynasty; ADynastyHashTable1: TPerDynastyBuilders; ADynastyHashTable2: TPerDynastyStructures);
        public
           destructor Destroy(); override;
           function MoveNext(): Boolean;
           property Current: TDynasty read GetCurrent;
           function GetEnumerator(): TDynastyEnumerator;
        end;
        TAllBuilderHashsetEnumerator = class
        strict private
           FDynastyEnumerator: TPerDynastyBuilders.TKeyEnumerator;
           FBuilderEnumerator: TBuilderHashSet.TEnumerator;
           function GetCurrent(): TBuilderFeatureNode;
        private
           constructor Create(ADynastyEnumerator: TPerDynastyBuilders.TKeyEnumerator; ABuilderEnumerator: TBuilderHashSet.TEnumerator); // arguments will be freed on destruction!
        public
           destructor Destroy(); override;
           function MoveNext(): Boolean;
           property Current: TBuilderFeatureNode read GetCurrent;
           function GetEnumerator(): TAllBuilderHashsetEnumerator;
        end;
        TAllStructureHashsetEnumerator = class
        strict private
           FDynastyEnumerator: TPerDynastyStructures.TKeyEnumerator;
           FStructureEnumerator: TStructureHashSet.TEnumerator;
           function GetCurrent(): IStructure;
        private
           constructor Create(ADynastyEnumerator: TPerDynastyStructures.TKeyEnumerator; AStructureEnumerator: TStructureHashSet.TEnumerator); // arguments will be freed on destruction!
        public
           destructor Destroy(); override;
           function MoveNext(): Boolean;
           property Current: IStructure read GetCurrent;
           function GetEnumerator(): TAllStructureHashsetEnumerator;
        end;
   strict private
      function GetDynastyEnumerator(): TDynastyEnumerator;
      function GetAllBuilderEnumerator(): TAllBuilderHashsetEnumerator;
      function GetAllStructureEnumerator(): TAllStructureHashsetEnumerator;
   private
      procedure Init();
      procedure AddBuilder(Builder: TBuilderFeatureNode);
      procedure RemoveBuilder(Builder: TBuilderFeatureNode);
      procedure ResetBuilders();
      procedure AddStructure(Structure: IStructure);
      procedure RemoveStructure(Structure: IStructure);
      procedure ResetStructures();
      function HasBothBuildersAndStructures(Dynasty: TDynasty): Boolean;
      procedure Destroy();
      function GetSortedBuildersFor(Dynasty: TDynasty): TBuilderFeatureNodeArray;
      function GetSortedStructuresFor(Dynasty: TDynasty): IStructureArray;
      property Dynasties: TDynastyEnumerator read GetDynastyEnumerator;
      property AllBuilders: TAllBuilderHashsetEnumerator read GetAllBuilderEnumerator;
      property AllStructures: TAllStructureHashsetEnumerator read GetAllStructureEnumerator;
   strict private
      const
         MultiDynastic: Pointer = Pointer(-1);
      var
         FDynasty: TDynasty; // nil, a dynasty, or $FFFFFFFFFFFFFFFF (MultiDynastic) to indicate we're using the hashtables
         case Boolean of
            True: (FBuilders: TBuilderHashSet; FStructures: TStructureHashSet);
            False: (FPerDynastyBuilders: TPerDynastyBuilders; FPerDynastyStructures: TPerDynastyStructures);
   end;

   TBuilderBusFeatureClass = class(TFeatureClass)
   strict protected
      function GetFeatureNodeClass(): FeatureNodeReference; override;
   public
      constructor CreateFromTechnologyTree(Reader: TTechTreeReader); override;
      function InitFeatureNode(): TFeatureNode; override;
   end;

   TBuilderBusFeatureNode = class(TFeatureNode)
   protected
      FRecords: TBuilderBusRecords;
      constructor CreateFromJournal(Journal: TJournalReader; AFeatureClass: TFeatureClass; ASystem: TSystem); override;
      procedure Reset();
      procedure Sync();
      function ManageBusMessage(Message: TBusMessage): TBusMessageResult; override;
      procedure HandleChanges(CachedSystem: TSystem); override;
      procedure Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter; CachedSystem: TSystem); override;
   public
      constructor Create();
      destructor Destroy(); override;
      procedure UpdateJournal(Journal: TJournalWriter; CachedSystem: TSystem); override;
      procedure ApplyJournal(Journal: TJournalReader; CachedSystem: TSystem); override;
      procedure RemoveBuilder(Builder: TBuilderFeatureNode); // will not call BuilderBusSync on caller
      procedure RemoveStructure(Structure: IStructure); // will not call BuilderBusSync on caller
   end;

   TBuilderFeatureClass = class(TFeatureClass)
   strict private
      FCapacity: Cardinal; // number of supported simultaneous worker groups
      FBuildRate: TRate; // rate of HP increase per group
   strict protected
      function GetFeatureNodeClass(): FeatureNodeReference; override;
   public
      constructor Create(ACapacity: Cardinal; ABuildRate: TRate);
      constructor CreateFromTechnologyTree(Reader: TTechTreeReader); override;
      function InitFeatureNode(): TFeatureNode; override;
      property Capacity: Cardinal read FCapacity;
      property BuildRate: TRate read FBuildRate;
   end;

   // TODO: handle our ancestor chain changing - we need to disconnect structures, for example

   TBuilderFeatureNode = class(TFeatureNode)
   strict private
      FFeatureClass: TBuilderFeatureClass;
      FDisabledReasons: TDisabledReasons;
      FBus: TBuilderBusFeatureNode;
      FStructures: TStructureHashSet;
      FPriority: TPriority; // TODO: must be reset to zero whenever the bus changes (including to/from nil)
      function GetCapacity(): Cardinal; inline;
   protected
      constructor CreateFromJournal(Journal: TJournalReader; AFeatureClass: TFeatureClass; ASystem: TSystem); override;
      procedure HandleChanges(CachedSystem: TSystem); override;
      procedure Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter; CachedSystem: TSystem); override;
   public
      constructor Create(AFeatureClass: TBuilderFeatureClass);
      destructor Destroy(); override;
      procedure UpdateJournal(Journal: TJournalWriter; CachedSystem: TSystem); override;
      procedure ApplyJournal(Journal: TJournalReader; CachedSystem: TSystem); override;
      procedure BuilderBusConnected(Bus: TBuilderBusFeatureNode); // must come from builder bus
      procedure BuilderBusReset(); // must come from builder bus; indicates bus is forgetting the registration; BuildingBusConnected will not be called again unless Bus.AddBuilder is called first
      procedure BuilderBusStartBuilding(Structure: IStructure); // must come from builder bus
      procedure BuilderBusSync(); // must come from builder bus; indicates bus is redoing its assignments; BuildingBusStartBuilding may be called again
      procedure StopBuilding(Structure: IStructure); // must come from *structure*; bus must also have RemoveStructure called
      function GetPriority(): TPriority;
      procedure SetAutoPriority(Value: TAutoPriority);
      property Capacity: Cardinal read GetCapacity;
   end;

// TODO: this feature assumes that builders and structures can't change ownership.

implementation

uses
   exceptions, isdprotocol, typedump, arrayutils;

procedure TBuilderBusRecords.Init();
begin
   FNextPriority := Low(FNextPriority);
end;

procedure TBuilderBusRecords.AddBuilder(Builder: TBuilderFeatureNode);
var
   NewDynasty: TDynasty;
   SelectedBuilders: TBuilderHashSet;
   SelectedStructures: TStructureHashSet;
begin
   NewDynasty := Builder.Parent.Owner;
   if (not Assigned(FDynasty)) then
   begin
      FDynasty := NewDynasty;
      FBuilders := TBuilderHashSet.Create();
      FBuilders.Add(Builder);
   end
   else
   if (Pointer(FDynasty) = MultiDynastic) then
   begin
      if (not Assigned(FPerDynastyBuilders)) then
      begin
         FPerDynastyBuilders := TPerDynastyBuilders.Create(@DynastyHash32);
         SelectedBuilders := TBuilderHashSet.Create();
         FPerDynastyBuilders[NewDynasty] := SelectedBuilders;
      end
      else
      if (not FPerDynastyBuilders.Has(NewDynasty)) then
      begin
         SelectedBuilders := TBuilderHashSet.Create();
         FPerDynastyBuilders[NewDynasty] := SelectedBuilders;
      end
      else
         SelectedBuilders := FPerDynastyBuilders[NewDynasty];
      SelectedBuilders.Add(Builder);
   end
   else
   if (FDynasty = NewDynasty) then
   begin
      if (not Assigned(FBuilders)) then
         FBuilders := TBuilderHashSet.Create();
      FBuilders.Add(Builder);
   end
   else
   begin
      SelectedBuilders := FBuilders;
      SelectedStructures := FStructures;
      FPerDynastyBuilders := TPerDynastyBuilders.Create(@DynastyHash32);
      FPerDynastyBuilders[FDynasty] := SelectedBuilders;
      if (Assigned(SelectedStructures)) then
      begin
         FPerDynastyStructures := TPerDynastyStructures.Create(@DynastyHash32);
         FPerDynastyStructures[FDynasty] := SelectedStructures;
      end;
      SelectedBuilders := TBuilderHashSet.Create();
      FPerDynastyBuilders[NewDynasty] := SelectedBuilders;
      SelectedBuilders.Add(Builder);
      Pointer(FDynasty) := MultiDynastic;
   end;
   if (Builder.GetPriority() = 0) then
   begin
      Builder.SetAutoPriority(FNextPriority);
      Assert(FNextPriority < High(FNextPriority));
      FNextPriority := FNextPriority + 1; // $R-
   end;
end;

procedure TBuilderBusRecords.RemoveBuilder(Builder: TBuilderFeatureNode);
begin
   Assert(Assigned(FDynasty));
   if (Pointer(FDynasty) = MultiDynastic) then
   begin
      Assert(FPerDynastyBuilders.Has(Builder.Parent.Owner));
      Assert(FPerDynastyBuilders[Builder.Parent.Owner].Has(Builder));
      FPerDynastyBuilders[Builder.Parent.Owner].Remove(Builder);
   end
   else
   begin
      Assert(Assigned(FBuilders));
      Assert(FBuilders.Has(Builder));
      FBuilders.Remove(Builder);
   end;
end;

procedure TBuilderBusRecords.ResetBuilders();
var
   Dynasty: TDynasty;
begin
   if (Assigned(FDynasty)) then
   begin
      if (Pointer(FDynasty) = MultiDynastic) then
      begin
         if (Assigned(FPerDynastyBuilders)) then
            for Dynasty in FPerDynastyBuilders do
               FPerDynastyBuilders[Dynasty].Reset();
      end
      else
      begin
         if (Assigned(FBuilders)) then
            FBuilders.Reset();
      end;
   end;
end;

procedure TBuilderBusRecords.AddStructure(Structure: IStructure);
var
   NewDynasty: TDynasty;
   SelectedStructures: TStructureHashSet;
   SelectedBuilders: TBuilderHashSet;
begin
   NewDynasty := Structure.GetAsset().Owner;
   if (not Assigned(FDynasty)) then
   begin
      FDynasty := NewDynasty;
      FStructures := TStructureHashSet.Create();
      FStructures.Add(Structure);
   end
   else
   if (Pointer(FDynasty) = MultiDynastic) then
   begin
      if (not Assigned(FPerDynastyStructures)) then
      begin
         FPerDynastyStructures := TPerDynastyStructures.Create(@DynastyHash32);
         SelectedStructures := TStructureHashSet.Create();
         FPerDynastyStructures[NewDynasty] := SelectedStructures;
      end
      else
      if (not FPerDynastyStructures.Has(NewDynasty)) then
      begin
         SelectedStructures := TStructureHashSet.Create();
         FPerDynastyStructures[NewDynasty] := SelectedStructures;
      end
      else
         SelectedStructures := FPerDynastyStructures[NewDynasty];
      SelectedStructures.Add(Structure);
   end
   else
   if (FDynasty = NewDynasty) then
   begin
      if (not Assigned(FStructures)) then
         FStructures := TStructureHashSet.Create();
      FStructures.Add(Structure);
   end
   else
   begin
      SelectedStructures := FStructures;
      SelectedBuilders := FBuilders;
      FPerDynastyStructures := TPerDynastyStructures.Create(@DynastyHash32);
      FPerDynastyStructures[FDynasty] := SelectedStructures;
      if (Assigned(SelectedBuilders)) then
      begin
         FPerDynastyBuilders := TPerDynastyBuilders.Create(@DynastyHash32);
         FPerDynastyBuilders[FDynasty] := SelectedBuilders;
      end;
      SelectedStructures := TStructureHashSet.Create();
      FPerDynastyStructures[NewDynasty] := SelectedStructures;
      SelectedStructures.Add(Structure);
      Pointer(FDynasty) := MultiDynastic;
   end;
   if (Structure.GetPriority() = 0) then
   begin
      Structure.SetAutoPriority(FNextPriority);
      Assert(FNextPriority < High(FNextPriority));
      FNextPriority := FNextPriority + 1; // $R-
   end;
end;

procedure TBuilderBusRecords.RemoveStructure(Structure: IStructure);
begin
   Assert(Assigned(FDynasty));
   if (Pointer(FDynasty) = MultiDynastic) then
   begin
      Assert(FPerDynastyStructures.Has(Structure.GetAsset().Owner));
      Assert(FPerDynastyStructures[Structure.GetAsset().Owner].Has(Structure));
      FPerDynastyStructures[Structure.GetAsset().Owner].Remove(Structure);
   end
   else
   begin
      Assert(Assigned(FStructures));
      Assert(FStructures.Has(Structure));
      FStructures.Remove(Structure);
   end;
end;

procedure TBuilderBusRecords.ResetStructures();
var
   Dynasty: TDynasty;
begin
   if (Assigned(FDynasty)) then
   begin
      if (Pointer(FDynasty) = MultiDynastic) then
      begin
         if (Assigned(FPerDynastyStructures)) then
            for Dynasty in FPerDynastyStructures do
               FPerDynastyStructures[Dynasty].Reset();
      end
      else
      begin
         if (Assigned(FStructures)) then
            FStructures.Reset();
      end;
   end;
end;


constructor TBuilderBusRecords.TDynastyEnumerator.Create(ADynasty: TDynasty; ADynastyHashTable1: TPerDynastyBuilders; ADynastyHashTable2: TPerDynastyStructures);
begin
   inherited Create();
   FDynasty := ADynasty;
   if (Assigned(ADynastyHashTable1)) then
      FDynastyEnumerator1 := ADynastyHashTable1.GetEnumerator();
   if (Assigned(ADynastyHashTable2)) then
      FDynastyEnumerator2 := ADynastyHashTable2.GetEnumerator();
end;

destructor TBuilderBusRecords.TDynastyEnumerator.Destroy();
begin
   FreeAndNil(FDynastyEnumerator1);
   FreeAndNil(FDynastyEnumerator2);
   inherited;
end;

function TBuilderBusRecords.TDynastyEnumerator.GetCurrent(): TDynasty;
begin
   Result := FDynasty;
end;

function TBuilderBusRecords.TDynastyEnumerator.MoveNext(): Boolean;
begin
   if (Assigned(FDynastyEnumerator1) and not FFlag) then
   begin
      Result := FDynastyEnumerator1.MoveNext();
      if (Result) then
      begin
         FDynasty := FDynastyEnumerator1.Current;
         exit;
      end;
      FFlag := True;
   end;
   if (Assigned(FDynastyEnumerator2)) then
   begin
      Assert((not Assigned(FDynastyEnumerator1)) or FFlag);
      repeat
         Result := FDynastyEnumerator2.MoveNext();
         if (Result) then
         begin
            FDynasty := FDynastyEnumerator2.Current;
            if (Assigned(FDynastyEnumerator1) and FDynastyEnumerator1.HashTable.Has(FDynasty)) then
               continue;
            exit;
         end;
         FFlag := True;
      until FFlag;
   end;
   Result := not FFlag;
   FFlag := True;
   {$IFOPT C+}
   if (not Result) then
      FDynasty := nil;
   {$ENDIF}
end;

function TBuilderBusRecords.TDynastyEnumerator.GetEnumerator(): TDynastyEnumerator;
begin
   Result := Self;
end;

function TBuilderBusRecords.GetDynastyEnumerator(): TDynastyEnumerator;
begin
   if (not Assigned(FDynasty)) then
   begin
      Result := nil;
   end
   else
   if (Pointer(FDynasty) = MultiDynastic) then
   begin
      Result := TDynastyEnumerator.Create(nil, FPerDynastyBuilders, FPerDynastyStructures);
   end
   else
   begin
      Result := TDynastyEnumerator.Create(FDynasty, nil, nil);
   end;
end;

constructor TBuilderBusRecords.TAllBuilderHashsetEnumerator.Create(ADynastyEnumerator: TPerDynastyBuilders.TKeyEnumerator; ABuilderEnumerator: TBuilderHashSet.TEnumerator);
begin
   inherited Create();
   Assert(Assigned(ADynastyEnumerator) or Assigned(ABuilderEnumerator));
   Assert(Assigned(ADynastyEnumerator) <> Assigned(ABuilderEnumerator));
   FDynastyEnumerator := ADynastyEnumerator;
   FBuilderEnumerator := ABuilderEnumerator;
end;

destructor TBuilderBusRecords.TAllBuilderHashsetEnumerator.Destroy();
begin
   FreeAndNil(FDynastyEnumerator);
   FreeAndNil(FBuilderEnumerator);
   inherited;
end;

function TBuilderBusRecords.TAllBuilderHashsetEnumerator.GetEnumerator(): TAllBuilderHashsetEnumerator;
begin
   Result := Self;
end;

function TBuilderBusRecords.TAllBuilderHashsetEnumerator.GetCurrent(): TBuilderFeatureNode;
begin
   Result := FBuilderEnumerator.Current;
end;

function TBuilderBusRecords.TAllBuilderHashsetEnumerator.MoveNext(): Boolean;
begin
   if (Assigned(FBuilderEnumerator)) then
   begin
      Result := FBuilderEnumerator.MoveNext();
      if (Result) then
         exit;
   end;
   if (Assigned(FDynastyEnumerator)) then
   begin
      repeat
         if (Assigned(FBuilderEnumerator)) then
            FreeAndNil(FBuilderEnumerator);
         Result := FDynastyEnumerator.MoveNext();
         if (not Result) then
            exit;
         FBuilderEnumerator := FDynastyEnumerator.CurrentValue.GetEnumerator();
         Result := FBuilderEnumerator.MoveNext();
      until Result;
   end;
   Result := False;
end;

function TBuilderBusRecords.GetAllBuilderEnumerator(): TAllBuilderHashsetEnumerator;
begin
   if (not Assigned(FDynasty)) then
   begin
      Result := nil;
   end
   else
   if (Pointer(FDynasty) = MultiDynastic) then
   begin
      Assert(Assigned(FPerDynastyBuilders));
      Result := TAllBuilderHashsetEnumerator.Create(FPerDynastyBuilders.GetEnumerator(), nil);
   end
   else
   begin
      if (Assigned(FBuilders)) then
         Result := TAllBuilderHashsetEnumerator.Create(nil, FBuilders.GetEnumerator())
      else
         Result := nil;
   end;
end;

constructor TBuilderBusRecords.TAllStructureHashsetEnumerator.Create(ADynastyEnumerator: TPerDynastyStructures.TKeyEnumerator; AStructureEnumerator: TStructureHashSet.TEnumerator);
begin
   inherited Create();
   Assert(Assigned(ADynastyEnumerator) or Assigned(AStructureEnumerator));
   Assert(Assigned(ADynastyEnumerator) <> Assigned(AStructureEnumerator));
   FDynastyEnumerator := ADynastyEnumerator;
   FStructureEnumerator := AStructureEnumerator;
end;

destructor TBuilderBusRecords.TAllStructureHashsetEnumerator.Destroy();
begin
   FreeAndNil(FDynastyEnumerator);
   FreeAndNil(FStructureEnumerator);
   inherited;
end;

function TBuilderBusRecords.TAllStructureHashsetEnumerator.GetEnumerator(): TAllStructureHashsetEnumerator;
begin
   Result := Self;
end;

function TBuilderBusRecords.TAllStructureHashsetEnumerator.GetCurrent(): IStructure;
begin
   Result := FStructureEnumerator.Current;
end;

function TBuilderBusRecords.TAllStructureHashsetEnumerator.MoveNext(): Boolean;
begin
   if (Assigned(FStructureEnumerator)) then
   begin
      Result := FStructureEnumerator.MoveNext();
      if (Result) then
         exit;
   end;
   if (Assigned(FDynastyEnumerator)) then
   begin
      repeat
         if (Assigned(FStructureEnumerator)) then
            FreeAndNil(FStructureEnumerator);
         Result := FDynastyEnumerator.MoveNext();
         if (not Result) then
            exit;
         FStructureEnumerator := FDynastyEnumerator.CurrentValue.GetEnumerator();
         Result := FStructureEnumerator.MoveNext();
      until Result;
   end;
   Result := False;
end;

function TBuilderBusRecords.GetAllStructureEnumerator(): TAllStructureHashsetEnumerator;
var
   StructureEnumerator: TStructureHashSet.TEnumerator;
begin
   if (not Assigned(FDynasty)) then
   begin
      Result := nil;
   end
   else
   if (Pointer(FDynasty) = MultiDynastic) then
   begin
      Assert(Assigned(FPerDynastyStructures));
      Result := TAllStructureHashsetEnumerator.Create(FPerDynastyStructures.GetEnumerator(), nil);
   end
   else
   begin
      if (Assigned(FStructures)) then
      begin
         StructureEnumerator := FStructures.GetEnumerator();
         Assert(Assigned(StructureEnumerator));
         Result := TAllStructureHashsetEnumerator.Create(nil, StructureEnumerator);
      end
      else
         Result := nil;
   end;
end;

function TBuilderBusRecords.HasBothBuildersAndStructures(Dynasty: TDynasty): Boolean;
begin
   Assert(Assigned(FDynasty));
   if (Pointer(FDynasty) = MultiDynastic) then
   begin
      Result := Assigned(FPerDynastyBuilders) and
                Assigned(FPerDynastyStructures) and
                FPerDynastyBuilders.Has(Dynasty) and
                FPerDynastyStructures.Has(Dynasty) and
                (FPerDynastyBuilders[Dynasty].Count > 0) and
                (FPerDynastyStructures[Dynasty].Count > 0);
   end
   else
   begin
      Result := Assigned(FBuilders) and
                Assigned(FStructures) and
                (FBuilders.Count > 0) and
                (FStructures.Count > 0);
   end;
end;

procedure TBuilderBusRecords.Destroy();
begin
   if (Assigned(FDynasty)) then
   begin
      if (Pointer(FDynasty) = MultiDynastic) then
      begin
         FreeAndNil(FPerDynastyBuilders);
         FreeAndNil(FPerDynastyStructures);
      end
      else
      begin
         FreeAndNil(FBuilders);
         FreeAndNil(FStructures);
      end;
   end;
end;

function TBuilderBusRecords.GetSortedBuildersFor(Dynasty: TDynasty): TBuilderFeatureNodeArray;

   function Compare(const A, B: TBuilderFeatureNode): Integer;
   begin
      Result := A.GetPriority() - B.GetPriority(); // $R-
   end;

var
   Builders: TBuilderHashSet;
   Builder: TBuilderFeatureNode;
   Index: Cardinal;
begin
   Assert(Assigned(Dynasty));
   if (FDynasty = Dynasty) then
   begin
      Builders := FBuilders;
   end
   else
   if ((Pointer(FDynasty) = MultiDynastic) and Assigned(FPerDynastyBuilders)) then
   begin
      Builders := FPerDynastyBuilders[Dynasty];
   end
   else
   begin
      Builders := nil;
   end;
   if (not Assigned(Builders)) then
   begin
      Result := [];
      exit;
   end;
   SetLength(Result, Builders.Count);
   Index := 0;
   for Builder in Builders do
   begin
      Result[Index] := Builder;
      Inc(Index);
   end;
   specialize Sort<TBuilderFeatureNode>(Result, @Compare);
end;

function TBuilderBusRecords.GetSortedStructuresFor(Dynasty: TDynasty): IStructureArray;

   function Compare(const A, B: IStructure): Integer;
   begin
      Result := A.GetPriority() - B.GetPriority(); // $R-
   end;

var
   Structures: TStructureHashSet;
   Structure: IStructure;
   Index: Cardinal;
begin
   Assert(Assigned(Dynasty));
   if (FDynasty = Dynasty) then
   begin
      Structures := FStructures;
   end
   else
   if ((Pointer(FDynasty) = MultiDynastic) and Assigned(FPerDynastyStructures)) then
   begin
      Structures := FPerDynastyStructures[Dynasty];
   end
   else
   begin
      Structures := nil;
   end;
   if (not Assigned(Structures)) then
   begin
      Result := [];
      exit;
   end;
   SetLength(Result, Structures.Count);
   Index := 0;
   for Structure in Structures do
   begin
      Result[Index] := Structure;
      Inc(Index);
   end;
   specialize Sort<IStructure>(Result, @Compare);
end;



constructor TRegisterBuilderMessage.Create(ABuilder: TBuilderFeatureNode);
begin
   inherited Create();
   FBuilder := ABuilder;
end;


constructor TRegisterStructureMessage.Create(AStructure: IStructure);
begin
   inherited Create();
   FStructure := AStructure;
end;


constructor TBuilderBusFeatureClass.CreateFromTechnologyTree(Reader: TTechTreeReader);
begin
   inherited Create();
end;

function TBuilderBusFeatureClass.GetFeatureNodeClass(): FeatureNodeReference;
begin
   Result := TBuilderBusFeatureNode;
end;

function TBuilderBusFeatureClass.InitFeatureNode(): TFeatureNode;
begin
   Result := TBuilderBusFeatureNode.Create();
end;


constructor TBuilderBusFeatureNode.Create();
begin
   inherited;
   FRecords.Init();
end;

constructor TBuilderBusFeatureNode.CreateFromJournal(Journal: TJournalReader; AFeatureClass: TFeatureClass; ASystem: TSystem);
begin
   inherited;
   FRecords.Init();
end;

destructor TBuilderBusFeatureNode.Destroy();
begin
   Reset();
   FRecords.Destroy();
   inherited;
end;

procedure TBuilderBusFeatureNode.Reset();
var
   Builder: TBuilderFeatureNode;
   Structure: IStructure;
begin
   for Builder in FRecords.AllBuilders do
      Builder.BuilderBusReset();
   FRecords.ResetBuilders();
   for Structure in FRecords.AllStructures do
      Structure.BuilderBusReset();
   FRecords.ResetStructures();
   FRecords.AssignedBuilders := False;
end;

procedure TBuilderBusFeatureNode.Sync();
var
   Builder: TBuilderFeatureNode;
begin
   if (FRecords.AssignedBuilders) then
   begin
      for Builder in FRecords.AllBuilders do
         Builder.BuilderBusSync(); // they will call the structures to tell them to sync and disconnect from them
      FRecords.AssignedBuilders := False;
   end;
end;

function TBuilderBusFeatureNode.ManageBusMessage(Message: TBusMessage): TBusMessageResult;
var
   RegisterBuilder: TRegisterBuilderMessage;
   RegisterStructure: TRegisterStructureMessage;
begin
   if (Message is TRegisterBuilderMessage) then
   begin
      RegisterBuilder := Message as TRegisterBuilderMessage;
      Sync();
      FRecords.AddBuilder(RegisterBuilder.Builder);
      RegisterBuilder.Builder.BuilderBusConnected(Self);
      MarkAsDirty([dkNeedsHandleChanges]);
      Result := mrHandled;
   end
   else
   if (Message is TRegisterStructureMessage) then
   begin
      RegisterStructure := Message as TRegisterStructureMessage;
      Sync();
      FRecords.AddStructure(RegisterStructure.Structure);
      RegisterStructure.Structure.BuilderBusConnected(Self);
      MarkAsDirty([dkNeedsHandleChanges]);
      Result := mrHandled;
   end
   else
      Result := inherited;
end;

procedure TBuilderBusFeatureNode.RemoveBuilder(Builder: TBuilderFeatureNode);
begin
   FRecords.RemoveBuilder(Builder);
   Sync();
   MarkAsDirty([dkNeedsHandleChanges]);
end;

procedure TBuilderBusFeatureNode.RemoveStructure(Structure: IStructure);
begin
   FRecords.RemoveStructure(Structure);
   Sync();
   MarkAsDirty([dkNeedsHandleChanges]);
end;

procedure TBuilderBusFeatureNode.HandleChanges(CachedSystem: TSystem);
var
   Builders: TBuilderFeatureNodeArray;
   BuilderIndex: Integer;
   Structure: IStructure;
   Remaining: Cardinal;
   Dynasty: TDynasty;
begin
   if (not FRecords.AssignedBuilders) then
   begin
      for Dynasty in FRecords.Dynasties do
      begin
         if (FRecords.HasBothBuildersAndStructures(Dynasty)) then
         begin
            Builders := FRecords.GetSortedBuildersFor(Dynasty);
            BuilderIndex := -1;
            Remaining := 0;
            for Structure in FRecords.GetSortedStructuresFor(Dynasty) do
            begin
               if (Remaining = 0) then
               begin
                  Inc(BuilderIndex);
                  if (BuilderIndex < Length(Builders)) then
                  begin
                     Remaining := Builders[BuilderIndex].Capacity;
                  end;
               end;
               if (Remaining > 0) then
               begin
                  Builders[BuilderIndex].BuilderBusStartBuilding(Structure);
                  Dec(Remaining);
               end;
            end;
         end;
      end;
      FRecords.AssignedBuilders := True;
   end;
   inherited;
end;

procedure TBuilderBusFeatureNode.Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter; CachedSystem: TSystem);
begin
end;

procedure TBuilderBusFeatureNode.UpdateJournal(Journal: TJournalWriter; CachedSystem: TSystem);
begin
   Journal.WriteCardinal(FRecords.NextPriority);
end;

procedure TBuilderBusFeatureNode.ApplyJournal(Journal: TJournalReader; CachedSystem: TSystem);
begin
   FRecords.NextPriority := Journal.ReadCardinal(); // $R-
end;



constructor TBuilderFeatureClass.Create(ACapacity: Cardinal; ABuildRate: TRate);
begin
   inherited Create();
   FCapacity := ACapacity;
   FBuildRate := ABuildRate;
end;

constructor TBuilderFeatureClass.CreateFromTechnologyTree(Reader: TTechTreeReader);
type
   TBuilderKeyword = (bkCapacity, bkBuildRate);
var
   Seen: set of TBuilderKeyword;

   procedure Acknowledge(Keyword: TBuilderKeyword);
   begin
      if (Keyword in Seen) then
         Reader.Tokens.Error('Duplicate parameter', []);
      Include(Seen, Keyword);
   end;

var
   Keyword: UTF8String;
begin
   inherited Create();
   FCapacity := 1;
   FBuildRate := TRate.FromPerSecond(1.0 / (60.0 * 60.0)); // 1 HP per hour
   Seen := [];
   repeat
      Keyword := Reader.Tokens.ReadIdentifier();
      case Keyword of
         'capacity':
            begin
               Acknowledge(bkCapacity);
               FCapacity := ReadNumber(Reader.Tokens, 1, High(FCapacity)); // $R-
            end;
         'build':
            begin
               Acknowledge(bkBuildRate);
               FBuildRate := ReadKeywordPerTime(Reader.Tokens, 'hp', 1, High(Int64));
            end;
      else
         Reader.Tokens.Error('Unexpected keyword "%s"', [Keyword]);
      end;
   until not ReadComma(Reader.Tokens);
end;

function TBuilderFeatureClass.GetFeatureNodeClass(): FeatureNodeReference;
begin
   Result := TBuilderFeatureNode;
end;

function TBuilderFeatureClass.InitFeatureNode(): TFeatureNode;
begin
   Result := TBuilderFeatureNode.Create(Self);
end;


constructor TBuilderFeatureNode.Create(AFeatureClass: TBuilderFeatureClass);
begin
   inherited Create();
   Assert(Assigned(AFeatureClass));
   FFeatureClass := AFeatureClass;
end;

constructor TBuilderFeatureNode.CreateFromJournal(Journal: TJournalReader; AFeatureClass: TFeatureClass; ASystem: TSystem);
begin
   Assert(Assigned(AFeatureClass));
   FFeatureClass := AFeatureClass as TBuilderFeatureClass;
   inherited CreateFromJournal(Journal, AFeatureClass, ASystem);
end;

destructor TBuilderFeatureNode.Destroy();
var
   Structure: IStructure;
begin
   if (Assigned(FBus)) then
   begin
      FBus.RemoveBuilder(Self);
      FBus := nil;
   end;
   if (Assigned(FStructures)) then
   begin
      for Structure in FStructures do
         Structure.StopBuilding();
      FreeAndNil(FStructures);
   end;
   inherited;
end;

function TBuilderFeatureNode.GetCapacity(): Cardinal;
begin
   Result := FFeatureClass.Capacity;
end;

procedure TBuilderFeatureNode.HandleChanges(CachedSystem: TSystem);
var
   Structure: IStructure;
   NewDisabledReasons: TDisabledReasons;
   Message: TRegisterBuilderMessage;
begin
   NewDisabledReasons := CheckDisabled(Parent);
   if (NewDisabledReasons <> FDisabledReasons) then
   begin
      FDisabledReasons := NewDisabledReasons;
      MarkAsDirty([dkUpdateClients]);
   end;
   if ((FDisabledReasons <> []) and (Assigned(FBus))) then
   begin
      FBus.RemoveBuilder(Self);
      FBus := nil;
      if (Assigned(FStructures)) then
      begin
         for Structure in FStructures do
            Structure.StopBuilding();
         FreeAndNil(FStructures);
      end;
   end;
   if ((FDisabledReasons = []) and (not Assigned(FBus))) then
   begin
      Message := TRegisterBuilderMessage.Create(Self);
      if (InjectBusMessage(Message) <> mrHandled) then
         Include(FDisabledReasons, drNoBus);
      FreeAndNil(Message);
   end;
   inherited;
end;

procedure TBuilderFeatureNode.Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter; CachedSystem: TSystem);
var
   Visibility: TVisibility;
   Structure: IStructure;
begin
   Visibility := Parent.ReadVisibilityFor(DynastyIndex, CachedSystem);
   if ((dmDetectable * Visibility <> []) and (dmClassKnown in Visibility) and (dmInternals in Visibility)) then
   begin
      Writer.WriteCardinal(fcBuilder);
      Writer.WriteCardinal(Capacity);
      Writer.WriteDouble(FFeatureClass.BuildRate.AsDouble);
      Writer.WriteCardinal(Cardinal(FDisabledReasons));
      if (Assigned(FStructures)) then
         for Structure in FStructures do
            Writer.WriteCardinal(Structure.GetAsset().ID(CachedSystem, DynastyIndex));
      Writer.WriteCardinal(0);
   end;
end;

procedure TBuilderFeatureNode.UpdateJournal(Journal: TJournalWriter; CachedSystem: TSystem);
begin
   Journal.WriteCardinal(FPriority);
end;

procedure TBuilderFeatureNode.ApplyJournal(Journal: TJournalReader; CachedSystem: TSystem);
begin
   FPriority := Journal.ReadCardinal(); // $R-
end;

procedure TBuilderFeatureNode.BuilderBusConnected(Bus: TBuilderBusFeatureNode); // must come from builder bus
begin
   FBus := Bus;
   if (not Assigned(FStructures)) then
      FStructures := TStructureHashSet.Create();
   Assert(FStructures.IsEmpty);
end;

procedure TBuilderFeatureNode.BuilderBusStartBuilding(Structure: IStructure); // must come from builder bus
begin
   FStructures.Add(Structure);
   Structure.StartBuilding(Self, FFeatureClass.BuildRate);
end;

procedure TBuilderFeatureNode.BuilderBusSync(); // must come from builder bus
var
   Structure: IStructure;
begin
   Assert(Assigned(FBus));
   Assert(Assigned(FStructures));
   for Structure in FStructures do
      Structure.StopBuilding();
   FStructures.Reset();
end;

procedure TBuilderFeatureNode.StopBuilding(Structure: IStructure); // must come from structure!
begin
   FStructures.Remove(Structure);
end;

procedure TBuilderFeatureNode.BuilderBusReset(); // must come from builder bus
var
   Structure: IStructure;
begin
   Assert(Assigned(FBus));
   Assert(Assigned(FStructures));
   FBus := nil;
   for Structure in FStructures do
      Structure.StopBuilding();
   FreeAndNil(FStructures);
   MarkAsDirty([dkNeedsHandleChanges]);
end;

function TBuilderFeatureNode.GetPriority(): TPriority;
begin
   Result := FPriority;
end;

procedure TBuilderFeatureNode.SetAutoPriority(Value: TAutoPriority);
begin
   FPriority := Value;
   MarkAsDirty([dkUpdateJournal]);
end;


initialization
   RegisterFeatureClass(TBuilderBusFeatureClass);
   RegisterFeatureClass(TBuilderFeatureClass);
end.