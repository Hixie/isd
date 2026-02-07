{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit internals;

interface

uses
   rtlutils, hashtable, hashsetwords, plasticarrays,
   genericutils, stringutils;

// ASSETS

type
   TAssetID = Cardinal; // 0 is reserved for placeholders or sentinels

   TAssetChangeKind = (ckAdd, ckChange, ckEndOfList);

   TDirtyKind = (
      dkVisibilityNew, // this asset node is newly created, and ResetDynastyNotes needs to be called (with a nil first argument) [1]
      dkDescendantsVisibilityNew, // one or more of the descendants has dkVisibilityNew set [2]
      dkNeedsHandleChanges, // the node wants HandleChanges to be called [1]
      dkDescendantNeedsHandleChanges, // one of the node's descendants has dkNeedsHandleChanges set [2]
      dkUpdateClients, // this asset node is dirty and we need to update the client [1] // TODO: audit uses of this now that it has a specific meaning
      dkDescendantUpdateClients, // one or more of the descendants has dkUpdateClients set [2]
      dkUpdateJournal, // this asset node is dirty and we need to update the journal( // TODO: audit uses of this now that it has a specific meaning
      dkDescendantUpdateJournal, // one or more of the descendants has dkUpdateJournal set [2]
      dkJournalNew, // this asset node is newly created, asset will be added to the journal using jcNewAsset [1]
      dkChildren, // this asset's node's children changed in some way [1][2]
      dkAffectsNames, // the asset's name changed [1]
      dkChildAffectsNames, // a child's name changed [1][2]
      dkAffectsVisibility, // system needs to redo a visibility scan
      dkVisibilityDidChange, // one or more dynasties changed whether they can see this node (set during CheckVisibilityChanged)
      dkAffectsDynastyCount, // system needs to redo a dynasty census (requires dkAffectsVisibility)
      dkAffectsKnowledge, // any nodes caching knowledge of descendants should reset caches
      dkMassChanged, // Mass or MassFlowRate changed // TODO: set this where appropriate, handle where appropriate
      dkHappinessChanged // Happiness changed [1]
   );
   TDirtyKinds = set of TDirtyKind;
   //  [1] removed when propagating to parent
   //  [2] added automatically when appropriate when propagating to parent

const
   dkNewNode = [ // initial dirty flags used on creation
      dkJournalNew, dkVisibilityNew,
      dkUpdateClients, dkUpdateJournal, dkNeedsHandleChanges,
      dkVisibilityDidChange, dkAffectsVisibility,
      dkDescendantNeedsHandleChanges, dkDescendantUpdateClients, dkDescendantUpdateJournal
      // dkAffectsDynastyCount is set conditionally
   ];
   dkIdentityChanged = [
      dkUpdateClients, dkUpdateJournal, dkNeedsHandleChanges,
      dkAffectsNames, dkVisibilityDidChange, dkAffectsVisibility
   ];
   dkAffectsTreeStructure = [ // set on old/new parents when child's parent changes
      dkUpdateClients, dkUpdateJournal,
      dkAffectsVisibility,
      dkChildren, dkChildAffectsNames,
      dkMassChanged
      // assets that affect happiness should set dkHappinessChanged when attaching and detaching
   ];

type
   TBuildEnvironment = (bePlanetRegion, beSpaceDock);
   TBuildEnvironments = set of TBuildEnvironment;

// VISIBILITY AND KNOWLEDGE

type
   {$PUSH}
   {$PACKSET 2}
   TDetectionMechanism = (
      dmInference, // set on anything with a descendant with non-empty visibility
      dmVisibleSpectrum,
      dmClassKnown,
      dmInternals, // the dynasty can see internals (e.g. what happened last time the sensors triggered)
      dmReserved4, dmReserved5, dmReserved6, dmReserved7,
      dmReserved8, dmReserved9, dmReserved10, dmReserved11,
      dmReserved12, dmReserved13, dmReserved14, dmReserved15
   );
   TVisibility = set of TDetectionMechanism;
   {$POP}
   {$IF SIZEOF(TVisibility) <> SIZEOF(Word)}
     {$FATAL TVisibility size error.}
   {$ENDIF}

const
   dmNil = [];
   dmDetectable = [dmVisibleSpectrum]; // need one of these to get any data beyond what you can infer
   dmOwnership = [dmInference, dmVisibleSpectrum, dmInternals]; // anything you own is visible

type
   TDynastyNotes = record
   strict private
      FID: TAssetID; // 4 bytes
      FOldVisibility, FCurrentVisibility: TVisibility; // 2 bytes each
      function GetHasID(): Boolean; inline;
      function GetChanged(): Boolean; inline;
   public
      procedure Init(const AID: TAssetID);
      procedure InitFrom(const Other: TDynastyNotes);
      procedure Snapshot(); inline; // copies current visibility to old visibility, set current visibility to zero
      property HasID: Boolean read GetHasID;
      property AssetID: TAssetID read FID write FID;
      {$IFOPT C+} property OldVisibility: TVisibility read FOldVisibility write FOldVisibility; {$ENDIF}
      property Visibility: TVisibility read FCurrentVisibility write FCurrentVisibility;
      property Changed: Boolean read GetChanged;
   end;
   {$IF SIZEOF(TDynastyNotes) <> 8}
      {$FATAL TDynastyNotes size error.}
   {$ENDIF}

   // used to track the 24 bit IDs and the 8 bits of visibility information per dynasty for assets
   PDynastyNotesPackage = ^TDynastyNotesPackage;
   TDynastyNotesPackage = packed record
      const
         LongThreshold = 2; // two or more dynasties get allocated on the heap; 1 uses AsShortDynasties
      type
         PDynastyNotesArray = ^TDynastyNotesArray;
         TDynastyNotesArray = packed array[0..0] of TDynastyNotes;
         TShortDynastyNotesArray = packed array[0..LongThreshold-2] of TDynastyNotes;
      var
         case Integer of
            1: (AsShortDynasties: TShortDynastyNotesArray); // 1 dynasty
            2: (AsLongDynasties: PDynastyNotesArray); // 2 or more
   end;
   {$IF SIZEOF(TDynastyNotesPackage) <> SIZEOF(Pointer)}
      {$FATAL TDynastyNotesPackage size error.}
   {$ENDIF}

   // Used for tracking which dynasties know about materials.
   // TODO: This data structure is a per-dynasty boolean. So when
   // there is one instance of this per material, we end up using 64
   // bits per material even if there's only one dynasty (or any
   // number of dynasties 1-63); we should be using one bit per
   // material in that world.
   // TODO: consider the naming scheme in pile.pas
   PKnowledgeSummary = ^TKnowledgeSummary;
   TKnowledgeSummary = packed record
   private
      function IsLongMode(): Boolean; inline;
   public
      procedure Init(DynastyCount: Cardinal);
      procedure Done();
      procedure Reset();
      procedure SetEntry(DynastyIndex: Cardinal; Value: Boolean);
      function GetEntry(DynastyIndex: Cardinal): Boolean;
      const
         LongThreshold = 64;
      type
         PKnowledgeData = ^TKnowledgeData;
         TKnowledgeData = bitpacked array[0..0] of Boolean;
      var
         case Integer of
            1: (AsShortDynasties: bitpacked array[-1..LongThreshold-2] of Boolean); // 63 or fewer dynasties (bit -1 is used to mark that we're in short mode)
            2: (AsLongDynasties: PKnowledgeData); // 64 or more; this is a pointer to 4-byte aligned data so its top bit is always zero
            3: (AsRawPointer: Pointer);
   end;
   {$IF SIZEOF(TKnowledgeSummary) <> SIZEOF(Pointer)}
      {$FATAL TKnowledgeSummary size error.}
   {$ENDIF}

// BUS MESSAGES

type
   TInjectBusMessageResult = (
      irDeferred, // we're still going up the tree
      irRejected, // we've reached a node that said to give up on this message
      irInjected, // we did inject the message into a bus but it wasn't handled
      irHandled // the message got injected and handled
   );

   THandleBusMessageResult = (
      hrActive, // we're still walking down the tree
      hrShortcut, // we are skipping the remainder of the current asset
      hrHandled // we are done, the message was handled
   );

   TBusMessage = class abstract(TDebugObject) end;
   TPhysicalConnectionBusMessage = class abstract(TBusMessage) end; // orbits don't propagate these up
   // TODO: should we have some kind of bus message that is the kind of message that regions automatically manage and don't propagate

   TAssetManagementBusMessage = class abstract(TBusMessage) // automatically handled by root node
   end;

// RESEARCH
type
   // Researches have three identifiers:
   //  - 64 bit unsigned integer (PResearch): only valid within a specific process, used to access the research's data without copying it (memory pointer) (defined in systems.pas)
   //  - 32 bit signed integer (TResearchID): sparse, stable from run to run, used when serializing to disk, defined in the tech tree
   TResearchID = type Integer; // Negative values are internal. Positive values are from the tech tree. Integer range means we can use A-B to compare IDs, and use $FFFFFFFF as a sentinel.
   //  - 16 bit unsigned integer (TResearchIndex): packed, only valid within a specific process, used as the identifier when the specifics don't matter (array index)
   TResearchIndex = type Word;

   TWeight = Cardinal;
   TWeightDelta = Integer;

   PResearchHashSet = ^TResearchHashSet;
   TResearchHashSet = specialize TWordHashSet<TResearchIndex>;  
 
   TCompiledConditionTarget = specialize PlasticArray<Word, specialize IncomparableUtils<Word>>;
   
   TConditionAST = class abstract
   strict protected
      type
      TConditionConstant = (ccTrue, ccFalse, ccNotConstant);
      function ConstantValue(): TConditionConstant; virtual; abstract;
   public
      procedure Compile(var Target: TCompiledConditionTarget); virtual; abstract; // post-order traversal, push onto Target stack
      function GetOperandDescription(): Word; virtual; abstract;
      procedure CollectResearches(var Collection: TResearchHashSet; const Negated: Boolean = False); virtual; abstract;
   end;

   // CONDITIONS
   
   PResearchConditionEvaluationContext = ^TResearchConditionEvaluationContext;
   TCondition = record
   strict private
      function GetConditionProgram(): PWord;
   public
      procedure AssignConditionAST(Value: TConditionAST);
      procedure Compile(const Collection: PResearchHashSet);
      property ConditionProgram: PWord read GetConditionProgram;
      procedure Free();
   strict private
      class operator Initialize(var Rec: TCondition);
      case Integer of
        -3: (FRaw: PtrUInt);
        -2: (FRawPtr: Pointer);
        -1: (FConditionAST: PtrUInt); // last two bits %10
         0: (FCompiledCondition: PWord); // last two bits %00 (might be nil)
         1: (FPackedCondition: PtrUInt); // last bit %1
         2: (FWord1, FWord2, FWord3, FWord4: Word); // FWord1 last bit %1 (we're assuming little endian)
   end;
   {$IF SizeOf(TCondition) <> SizeOf(Pointer)} {$FATAL TCondition has an unexpected size} {$ENDIF}

   // TOPICS

   TTopic = class
   public
      type
         TArray = array of TTopic;
         TIndex = type Word;
         THashSet = specialize TWordHashSet<TIndex>;
         TIndexArray = array of TIndex;
         TIndexPlasticArray = specialize PlasticArray<TIndex, specialize IncomparableUtils<TIndex>>;
      const
         kNilIndex = High(TIndex);
   strict private
      FName: UTF8String;
      FIndex: TTopic.TIndex;
      FCondition: TCondition;
   public
      constructor Create(AName: UTF8String; AIndex: TTopic.TIndex; ACondition: TConditionAST);
      procedure Compile();
      destructor Destroy(); override;
      property Name: UTF8String read FName; // stable across runs
      property Index: TTopic.TIndex read FIndex; // process-specific
      property Condition: TCondition read FCondition;
   end;

   TTopicHashTable = class(specialize THashTable<UTF8String, TTopic, UTF8StringUtils>)
      constructor Create();
   end;

   TTopicHashSet = specialize TWordHashSet<TTopic.TIndex>;

   // SITUATIONS
   
   TSituation = type Word; // 0 is the "nil" value
   TSituationPlasticArray = specialize PlasticArray<TSituation, specialize IncomparableUtils<TSituation>>;
   TSituationHashSet = specialize TWordHashSet<TSituation>;

   TSituationHashTable = class(specialize THashTable<UTF8String, TSituation, UTF8StringUtils>)
      constructor Create();
   end;
      
   // RESEARCH BONUSES

   TBonus = record // 16 bytes
   public
      type
         TArray = array of TBonus;
   strict private
      FCondition: TCondition; // 8 bytes (+heap-allocated structure)
      FTimeFactor: Single; // 4 bytes
      FWeightDelta: TWeightDelta; // 4 bytes
   public
      constructor Create(ACondition: TConditionAST; ATimeFactor: Single; AWeightDelta: TWeightDelta);
      procedure Compile();
      procedure Free();
      property Condition: TCondition read FCondition;
      property TimeFactor: Single read FTimeFactor;
      property WeightDelta: TWeightDelta read FWeightDelta;
   end;
   {$IF SizeOf(TBonus) <> 16} {$FATAL TBonus has an unexpected size} {$ENDIF}

   TBonusPlasticArray = specialize PlasticArray<TBonus, specialize IncomparableUtils<TBonus>>;

   // CONDITION EVALUATION

   TResearchConditionEvaluationContext = record
      KnownResearches: TResearchHashSet;
      Situations: TSituationHashSet;
      SelectedTopic: TTopic.TIndex;
   end;

// HELPER FUNCTIONS
   
function UpdateDirtyKindsForAncestor(DirtyKinds: TDirtyKinds): TDirtyKinds;
function ResearchIDHash32(const Key: TResearchID): DWord;

implementation

uses
   sysutils, dateutils, exceptions, typedump, hashfunctions, math,
   conditions {$IFDEF DEBUG}, debug {$ENDIF};

function UpdateDirtyKindsForAncestor(DirtyKinds: TDirtyKinds): TDirtyKinds;
begin
   Result := DirtyKinds;
   if (dkNeedsHandleChanges in Result) then
   begin
      Exclude(Result, dkNeedsHandleChanges);
      Include(Result, dkDescendantNeedsHandleChanges);
   end;
   if (dkUpdateJournal in Result) then
   begin
      Exclude(Result, dkJournalNew); // may or may not be present
      Exclude(Result, dkUpdateJournal);
      Include(Result, dkDescendantUpdateJournal);
   end;
   Assert(not (dkJournalNew in Result)); // it should only be set if dkUpdateJournal is set
   if (dkUpdateClients in Result) then
   begin
      Exclude(Result, dkUpdateClients);
      Include(Result, dkDescendantUpdateClients);
   end;
   if (dkVisibilityDidChange in Result) then
   begin
      Include(Result, dkUpdateClients);
      Exclude(Result, dkVisibilityDidChange);
   end;
   if (dkVisibilityNew in Result) then
   begin
      Exclude(Result, dkVisibilityNew);
      Include(Result, dkDescendantsVisibilityNew);
   end;
   if (dkChildren in Result) then
   begin
      Exclude(Result, dkChildren);
   end;
   if (dkChildAffectsNames in Result) then
   begin
      Exclude(Result, dkChildAffectsNames);
   end;
   if (dkAffectsNames in Result) then
   begin
      Exclude(Result, dkAffectsNames);
      Include(Result, dkChildAffectsNames);
   end;
end;


function ResearchIDHash32(const Key: TResearchID): DWord;
begin
   Result := LongintHash32(Key);
end;


procedure TDynastyNotes.Init(const AID: TAssetID);
begin
   FID := AID;
   FOldVisibility := dmNil;
   FCurrentVisibility := dmNil;
end;

procedure TDynastyNotes.InitFrom(const Other: TDynastyNotes);
begin
   FID := Other.FID;
   FOldVisibility := Other.FCurrentVisibility;
   FCurrentVisibility := dmNil;
end;

function TDynastyNotes.GetHasID(): Boolean;
begin
   Result := FID > 0;
end;

function TDynastyNotes.GetChanged(): Boolean;
begin
   Result := FOldVisibility <> FCurrentVisibility;
end;

procedure TDynastyNotes.Snapshot();
begin
   FOldVisibility := FCurrentVisibility;
   FCurrentVisibility := dmNil;
end;


class operator TCondition.Initialize(var Rec: TCondition);
begin
   Rec.FRawPtr := nil;
end;

procedure TCondition.Free();
begin
   Assert(SizeOf(Pointer) = SizeOf(FConditionAST));
   case (FRaw and %11) of
      %00: if (Assigned(FCompiledCondition)) then FreeMem(FCompiledCondition);
      %10: TConditionAST(Pointer(FConditionAST and not %10)).Free(); // {BOGUS Hint: Conversion between ordinals and pointers is not portable}
 %01, %11: ; // entire program is compressed into the pointer
   end;
end;

function TCondition.GetConditionProgram(): PWord;
begin
   Assert(Assigned(FRawPtr));
   Assert((FRaw and %11) <> %10);
   if ((FRaw and %11) = 0) then
   begin
      Result := FCompiledCondition;
   end
   else
   begin
      // %01 or %11 (not %10)
      Result := @FWord1;
   end;
end;

procedure TCondition.AssignConditionAST(Value: TConditionAST);
begin
   Assert(not Assigned(FRawPtr));
   if (Assigned(Value)) then
      FConditionAST := PtrUInt(Value) or %10;
end;

procedure TCondition.Compile(const Collection: PResearchHashSet);
var
   AST: TConditionAST;
   CompiledProgram: TCompiledConditionTarget;
   Index, ActualLength: Cardinal;
   Allocate: Boolean;
begin
   if (Assigned(FRawPtr)) then
   begin
      Assert((FRaw and %11) = %10);
      Assert(SizeOf(Pointer) = SizeOf(FConditionAST));
      AST := TConditionAST(Pointer(FConditionAST and not %10)); // {BOGUS Hint: Conversion between ordinals and pointers is not portable}
      if (Assigned(Collection)) then
         AST.CollectResearches(Collection^);
      CompiledProgram.Prepare(4);
      AST.Compile(CompiledProgram);
      FreeAndNil(AST);
      ActualLength := CompiledProgram.Length;
      if (CompiledProgram.Length <= 4) then
      begin
         CompiledProgram.Length := 4;
         if (CompiledProgram[0] and OperatorBit > 0) then
         begin
            FWord1 := CompiledProgram[0] or Word(1);
            FWord2 := CompiledProgram[1];
            FWord3 := CompiledProgram[2];
            FWord4 := CompiledProgram[3];
            Assert(FPackedCondition and 1 > 0);
            Allocate := False;
         end
         else
         if (ActualLength <= 3) then
         begin
            FWord1 := OperatorSkip or 1;
            FWord2 := CompiledProgram[0];
            FWord3 := CompiledProgram[1];
            FWord4 := CompiledProgram[2];
            Allocate := False;
         end
         else
         begin
            Allocate := True;
         end;
      end
      else
         Allocate := True;
      if (Allocate) then
      begin
         FCompiledCondition := GetMem(SizeOf(Word) * CompiledProgram.Length); // $R-
         for Index := 0 to CompiledProgram.Length - 1 do // $R-
            FCompiledCondition[Index] := CompiledProgram[Index];
         Assert(FPackedCondition and 1 = 0);
      end
      else
         Assert(FPackedCondition and 1 > 0);
   end;
end;


constructor TBonus.Create(ACondition: TConditionAST; ATimeFactor: Single; AWeightDelta: TWeightDelta);
begin
   FCondition.AssignConditionAST(ACondition);
   FTimeFactor := ATimeFactor;
   FWeightDelta := AWeightDelta;
end;

procedure TBonus.Compile();
begin
   FCondition.Compile(nil);
end;

procedure TBonus.Free();
begin
   FCondition.Free();
end;

      
constructor TTopic.Create(AName: UTF8String; AIndex: TTopic.TIndex; ACondition: TConditionAST);
begin
   FName := AName;
   FIndex := AIndex;
   FCondition.AssignConditionAST(ACondition);
end;

procedure TTopic.Compile();
begin
   FCondition.Compile(nil);
end;

destructor TTopic.Destroy();
begin
   FCondition.Free();
   inherited;
end;


constructor TTopicHashTable.Create();
begin
   inherited Create(@UTF8StringHash32);
end;


constructor TSituationHashTable.Create();
begin
   inherited Create(@UTF8StringHash32);
end;


function TKnowledgeSummary.IsLongMode(): Boolean;
begin
   Assert(Assigned(AsRawPointer));
   Result := not AsShortDynasties[-1];
end;

procedure TKnowledgeSummary.Init(DynastyCount: Cardinal);
var
   RequiredSize: Cardinal;
begin
   if (DynastyCount >= LongThreshold) then
   begin
      RequiredSize := Ceil(DynastyCount / 8); // $R-
      if (Assigned(AsRawPointer) and IsLongMode) then
      begin
         if (MemSize(AsRawPointer) = RequiredSize) then
            exit;
         FreeMem(AsRawPointer);
      end;
      AsRawPointer := GetMem(RequiredSize);
      Assert(not AsShortDynasties[-1]);
      Assert(IsLongMode);
   end
   else
   begin
      if (Assigned(AsRawPointer) and IsLongMode) then
         FreeMem(AsRawPointer);
      AsShortDynasties[-1] := True;
      Assert(not IsLongMode);
   end;
   Reset();
end;

procedure TKnowledgeSummary.Done();
begin
   if (Assigned(AsRawPointer) and IsLongMode) then
      FreeMem(AsRawPointer);
   AsRawPointer := nil;
end;

procedure TKnowledgeSummary.Reset();
begin
   Assert(Assigned(AsRawPointer));
   if (IsLongMode) then
   begin
      FillByte(AsRawPointer^, MemSize(AsRawPointer), $00); // $R-
   end
   else
   begin
      AsRawPointer := Pointer($01); // zero all bits except the LSB, which is used to mark that we're in short mode
   end;
end;

procedure TKnowledgeSummary.SetEntry(DynastyIndex: Cardinal; Value: Boolean);
begin
   Assert(Assigned(AsRawPointer));
   if (IsLongMode()) then
   begin
      AsLongDynasties^[DynastyIndex] := Value;
   end
   else
   begin
      AsShortDynasties[DynastyIndex] := Value;
   end;
end;

function TKnowledgeSummary.GetEntry(DynastyIndex: Cardinal): Boolean;
begin
   Assert(Assigned(AsRawPointer));
   if (IsLongMode()) then
   begin
      Result := AsLongDynasties^[DynastyIndex];
   end
   else
   begin
      Result := AsShortDynasties[DynastyIndex];
   end;
end;

end.