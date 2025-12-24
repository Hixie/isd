{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit systems;

interface

uses
   systemdynasty, configuration, hashtable, genericutils, isdprotocol,
   serverstream, stringstream, random, materials, basenetwork,
   time, tttokenizer, stringutils, hashsettight, rtlutils, plasticarrays;

// VISIBILITY
//
// Visibilty is determined via eight bits, the TDetectionMechanisms.
// The eight bits are a set known as TVisibility. An asset that is
// visible to a dynasty has a dynasty-specific ID, a TAssetID. The
// pairing of a TVisibility and a TAssetID is a TDynastyNotes.
//
// A TDynastyNotesPackage holds either a TDynastyNotes or a pointer to
// an array of TDynastyNotes if there are multiple dynasties in the
// system. The arrays, if used, are all stored in a buffer owner by
// the system (essentially an arena).
//
// Systems consider whether to TSystem.ReportChanges after each
// incoming message. If anything was marked as dkAffectsVisibility
// then the system calls TSystem.RecomputeVisibility. If the dynasties
// present changed, this renumbers all the dynasties, and calls
// TAssetNode.ResetDynastyNotes on every asset in the system with the
// old and new dynasties. Otherwise, it calls
// TAssetNode.ResetVisibility, TAssetNode.ApplyVisibility
// TAssetNode.CheckVisibilityChanged, and TAssetNode.ApplyKnowledge on
// each asset, walking the tree for each one in turn.
//
// TAssetNode.ResetDynastyNotes calls TFeatureNode.ResetDynastyNotes
// on every feature in the system, copies the IDs over from the old
// data to the new data, snapshots the visibility data, and sets the
// visibility data to zero.
//
// (TAssetNode.ResetDynastyNotes is also called after the node is
// created, with the first argument set to nil.)
//
// TAssetNode.ResetVisibility just calls TFeatureNode.ResetVisibility
// on every feature in the system, snapshots the visibility data, and
// sets the visibility data to zero.
//
// TAssetNode.ApplyVisibility sets dmOwnership on each asset node
// appropriately, then calls TFeatureNode.ApplyVisibility on each
// feature in the system. This is the mechanism to "see" things.
//
// TAssetNode.HandleVisibility is called by sensor features during
// ApplyVisibility to inform assets that they have been detected. The
// asset calls TFeatureNode.HandleVisibility for each feature, which
// gives the features a chance to cloak themselves or track their own
// internal visibility state. The order of features matters here; a
// feature which hides the asset (e.g. a cloaking device) should come
// before a feature that records visibility status (e.g. structural
// features that track which materials are known by detecting
// entities).
//
// To add visibility data, we have the following APIs on TSystem:
//
//  * AddSpecificVisibility: marks an asset as having a particular
//    TVisibility (in addition to any that it already has). In
//    addition, it initializes the asset's dynasty data
//    (FDynastyNotes) if necessary, and marks the ancestor chain as
//    having inferred visibility (by calling the same API
//    recursively).
//
//  * AddBroadVisibility adds a particular visibility for every
//    dynasty, then marks the ancestor chain as having inferred
//    visibility.
//
// TAssetNode.CheckVisibilityChanged first calls
// TFeatureNode.CheckVisibilityChanged on all its features, then
// checks if the visibility changed since the last update, and calls
// MarkAsDirty as appropriate (setting dkVisibilityDidChange).
//
// TAssetNode.ApplyKnowledge calls TFeatureNode.ApplyKnowledge on each
// feature in the system. This is the mechanism to determine what is
// known (materials and asset classes).
//
// TAssetNode.HandleKnowledge is called by sensor features during
// ApplyKnowledge to inform assets that they have been access to a
// databank. A link to an ISensorsProvider is passed along. The
// API exposed in this way must not be cached.
//
// Some features do special things with visibility:
//
//  * Orbit features and space features mark themselves as
//    dmClassKnown so that nobody needs to research orbits and space.
//
//  * Orbits forward inferred visibility to their primary child, and
//    make their visibility match their child's.
//
//  * Sensor nodes walk the tree.
//
//  * Stars and space nodes mark themselves as always visible to
//    everyone.
//
// There is currently no way to detect when visibility changes, only
// when it's been recomputed.

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
   TAssetClass = class;
   TAssetNode = class;
   TFeatureNode = class;
   TSystem = class;

   TDynastyIndexHashTable = class(specialize THashTable<TDynasty, Cardinal, TObjectUtils>)
      constructor Create();
   end;

   TDynastyHashSet = specialize TObjectSet<TDynasty>;

   TAssetClassIDHashTable = class(specialize THashTable<TAssetClassID, TAssetClass, IntegerUtils>)
      constructor Create();
   end;

   TAssetClassIdentifierHashTable = class(specialize THashTable<UTF8String, TAssetClass, UTF8StringUtils>)
      constructor Create();
   end;

   TAssetClassHashSet = specialize TObjectSet<TAssetClass>;

   TAssetNodeHashTable = class(specialize THashTable<PtrUInt, TAssetNode, PtrUIntUtils>)
      constructor Create();
   end;

   TAssetID = Cardinal; // 0 is reserved for placeholders or sentinels

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

   TAssetChangeKind = (ckAdd, ckChange, ckEndOfList);

   TJournalReader = class sealed
   private
      FSystem: TSystem;
      FAssetMap: TAssetNodeHashTable;
   public
      constructor Create(ASystem: TSystem);
      destructor Destroy(); override;
      function ReadBoolean(): Boolean;
      function ReadByte(): Byte;
      function ReadCardinal(): Cardinal;
      function ReadInt32(): Int32;
      function ReadInt64(): Int64;
      function ReadUInt64(): UInt64;
      function ReadPtrUInt(): PtrUInt;
      function ReadDouble(): Double;
      function ReadString(): UTF8String;
      function ReadAssetChangeKind(): TAssetChangeKind;
      function ReadAssetNodeReference(ASystem: TSystem): TAssetNode;
      function ReadAssetClassReference(): TAssetClass;
      function ReadDynastyReference(): TDynasty;
      function ReadMaterialReference(): TMaterial;
   end;

   TJournalWriter = class sealed
   private
      FSystem: TSystem;
   public
      constructor Create(ASystem: TSystem);
      procedure WriteBoolean(Value: Boolean); // {BOGUS Hint: Value parameter "Value" is assigned but never used}
      procedure WriteByte(Value: Byte); // {BOGUS Hint: Value parameter "Value" is assigned but never used}
      procedure WriteCardinal(Value: Cardinal); // {BOGUS Hint: Value parameter "Value" is assigned but never used}
      procedure WriteInt32(Value: Int32); // {BOGUS Hint: Value parameter "Value" is assigned but never used}
      procedure WriteInt64(Value: Int64); // {BOGUS Hint: Value parameter "Value" is assigned but never used}
      procedure WriteUInt64(Value: UInt64); // {BOGUS Hint: Value parameter "Value" is assigned but never used}
      procedure WritePtrUInt(Value: PtrUInt); // {BOGUS Hint: Value parameter "Value" is assigned but never used}
      procedure WriteDouble(Value: Double); // {BOGUS Hint: Value parameter "Value" is assigned but never used}
      procedure WriteString(Value: UTF8String);
      procedure WriteAssetChangeKind(Value: TAssetChangeKind); // {BOGUS Hint: Value parameter "Value" is assigned but never used}
      procedure WriteAssetNodeReference(AssetNode: TAssetNode);
      procedure WriteAssetClassReference(AssetClass: TAssetClass);
      procedure WriteDynastyReference(Dynasty: TDynasty);
      procedure WriteMaterialReference(Material: TMaterial);
   end;

   TInjectBusMessageResult = (
      irDeferred, // we're still going up the tree
      irRejected, // we've reached a node that said to give up on this message
      irInjected, // we did inject the message into a bus but it wasn't handled
      irHandled // the message got injected and handled
   );

   TBusMessage = class abstract(TDebugObject) end;
   TPhysicalConnectionBusMessage = class abstract(TBusMessage) end; // orbits don't propagate these up
   // TODO: should we have some kind of bus message that is the kind of message that regions automatically manage and don't propagate

   TAssetManagementBusMessage = class abstract(TBusMessage) // automatically handled by root node
   end;

   TAssetGoingAway = class(TAssetManagementBusMessage)
   private
      FAsset: TAssetNode;
   public
      constructor Create(AAsset: TAssetNode);
      property Asset: TAssetNode read FAsset;
   end;

   // The pre-walk callback is called for each asset in a depth-first
   // pre-order traversal of the asset/feature tree, and skips
   // children of nodes for which the callback returns false. The
   // post-walk callback is called after the children are processed
   // (or skipped).
   TPreWalkCallback = function(Asset: TAssetNode): Boolean is nested;
   TPostWalkCallback = procedure(Asset: TAssetNode) is nested;

   TScoreDirtyCallback = procedure(Dynasty: TDynasty) of object;

   FeatureClassReference = class of TFeatureClass;
   FeatureNodeReference = class of TFeatureNode;

   TWeight = Cardinal;
   TWeightDelta = Integer;

   TReward = record
   public
      type
         TArray = array of TReward;
         {$PUSH}
         {$PACKENUM 1}
         TRewardKind = (rkMessage = $00, rkAssetClass = $01, rkMaterial = $02);
         {$POP}
   strict private
      const
         TypeMask = $07;
         {$IF (High(TRewardKind) and not TypeMask) <> 0)} {$FATAL Reward kinds don't fit in alignment bits.} {$ENDIF}
      var
         FData: PtrUInt;
      function GetKind(): TRewardKind; inline;
      function GetMessage(): UTF8String; inline;
      function GetAssetClass(): TAssetClass; inline;
      function GetMaterial(): TMaterial; inline;
   public
      constructor CreateForMessage(var Message: UTF8String);
      constructor CreateForAssetClass(AssetClass: TAssetClass);
      constructor CreateForMaterial(Material: TMaterial);
      procedure Free();
      property Message: UTF8String read GetMessage;
      property AssetClass: TAssetClass read GetAssetClass;
      property Material: TMaterial read GetMaterial;
      property Kind: TRewardKind read GetKind;
   end;
   {$IF SizeOf(TReward) <> 8} {$FATAL TReward has an unexpected size} {$ENDIF}

   TNode = class(TDebugObject)
   public
      type
         TNodeArray = array of TNode;
   strict private
      FUnlocks: TNodeArray;
   private
      procedure PropagateRequirements(Requirements: TNodeArray);
   strict protected
      function GetIsRoot(): Boolean; virtual; abstract;
   public
      property IsRoot: Boolean read GetIsRoot;
      property Unlocks: TNodeArray read FUnlocks;
      function ToString(): UTF8String; override;
   end;

   TBonus = record // 24 bytes
   public
      type
         TArray = array of TBonus;
   strict private
      FNode: TNode; // 8 bytes
      FTimeDelta: TMillisecondsDuration; // 8 bytes
      FWeightDelta: TWeightDelta; // 4 bytes
      FNegate: Boolean; // 4 bytes (31 bits unused)
   public
      constructor Create(ANode: TNode; ATimeDelta: TMillisecondsDuration; AWeightDelta: TWeightDelta; ANegate: Boolean);
      function ToString(): UTF8String;
      property Node: TNode read FNode;
      property TimeDelta: TMillisecondsDuration read FTimeDelta;
      property WeightDelta: TWeightDelta read FWeightDelta;
      property Negate: Boolean read FNegate;
   end;
   {$IF SizeOf(TBonus) <> 24} {$FATAL TBonus has an unexpected size} {$ENDIF}

   TResearchID = Integer; // Negative values are internal. Positive values are from the tech tree. Integer range means we can use A-B to compare IDs, and use $FFFFFFFF as a sentinel.

   TResearch = class(TNode)
   public
      type
         TArray = array of TResearch;
      const
         kNil = Low(TResearchID);
   strict private
      FID: TResearchID;
      FDefaultTime: TMillisecondsDuration;
      FDefaultWeight: TWeight;
      FRequirements: TNode.TNodeArray;
      FBonuses: TBonus.TArray;
      FRewards: TReward.TArray;
   strict protected
      function GetIsRoot(): Boolean; override;
   public
      constructor Create(AID: TResearchID; ADefaultTime: TMillisecondsDuration; ADefaultWeight: TWeight; ARequirements: TNode.TNodeArray; ABonuses: TBonus.TArray; ARewards: TReward.TArray);
      destructor Destroy(); override;
      property ID: TResearchID read FID;
      property DefaultTime: TMillisecondsDuration read FDefaultTime;
      property DefaultWeight: TWeight read FDefaultWeight;
      property Requirements: TNode.TNodeArray read FRequirements; // do not mutate the array through this accessor
      property Bonuses: TBonus.TArray read FBonuses; // do not mutate the array through this accessor
      property Rewards: TReward.TArray read FRewards; // do not mutate the array through this accessor
      function ToString(): UTF8String; override;
   end;

   TResearchHashSet = specialize TObjectSet<TResearch>;

   TResearchIDHashTable = class(specialize THashTable<TResearchID, TResearch, IntegerUtils>)
      constructor Create();
   end;

   TWeightedResearchHashTable = class(specialize THashTable<TResearch, TWeight, TObjectUtils>)
      constructor Create();
   end;

   TTopic = class(TNode)
   public
      type
         TArray = array of TTopic;
   strict private
      FValue: UTF8String;
      FSelectable: Boolean;
      FRequirements: TResearch.TArray;
      FObsoletes: TTopic.TArray;
   strict protected
      function GetIsRoot(): Boolean; override;
   public
      constructor Create(AValue: UTF8String; ASelectable: Boolean; ARequirements: TResearch.TArray; AObsoletes: TTopic.TArray);
      property Value: UTF8String read FValue;
      property Selectable: Boolean read FSelectable;
      property Requirements: TResearch.TArray read FRequirements;
      property Obsoletes: TTopic.TArray read FObsoletes;
   end;

   TTopicHashTable = class(specialize THashTable<UTF8String, TTopic, UTF8StringUtils>)
      constructor Create();
   end;

   TTopicHashSet = specialize TObjectSet<TTopic>;

   // TODO: add materials and asset classes as possible TNodes, so that things/topics can unlock when you build partiular things or mine particular materials.

   TTechTreeReader = record
   strict private
      FTokenizer: TTokenizer;
      FAssetClasses: TAssetClassIdentifierHashTable;
      FMaterialNames: TMaterialNameHashTable;
      FTopics: TTopicHashTable;
      function GetAssetClass(Identifier: UTF8String): TAssetClass; inline;
      function GetMaterial(Name: UTF8String): TMaterial; inline;
      function GetTopic(Name: UTF8String): TTopic; inline;
   public
      constructor Create(ATokenizer: TTokenizer; AAssetClasses: TAssetClassIdentifierHashTable; AMaterialNames: TMaterialNameHashTable; ATopics: TTopicHashTable);
      property AssetClasses[Identifier: UTF8String]: TAssetClass read GetAssetClass;
      property Materials[Name: UTF8String]: TMaterial read GetMaterial;
      property Topics[Name: UTF8String]: TTopic read GetTopic;
      property Tokens: TTokenizer read FTokenizer;
   end;

   TFeatureClass = class abstract (TDebugObject)
   public
      type
         TArray = array of TFeatureClass;
   strict protected
      function GetFeatureNodeClass(): FeatureNodeReference; virtual; abstract;
      function GetDefaultSize(): Double; virtual;
   public
      constructor CreateFromTechnologyTree(Reader: TTechTreeReader); virtual; abstract;
      function InitFeatureNode(ASystem: TSystem): TFeatureNode; virtual; abstract;
      property FeatureNodeClass: FeatureNodeReference read GetFeatureNodeClass;
      property DefaultSize: Double read GetDefaultSize;
   end;

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
      dkVisibilityDidChange, dkAffectsVisibility, dkAffectsKnowledge,
      dkDescendantNeedsHandleChanges, dkDescendantUpdateClients, dkDescendantUpdateJournal
      // dkAffectsDynastyCount is set conditionally
   ];
   dkIdentityChanged = [
      dkUpdateClients, dkUpdateJournal, dkNeedsHandleChanges,
      dkAffectsNames, dkVisibilityDidChange, dkAffectsVisibility, dkAffectsKnowledge
   ];
   dkAffectsTreeStructure = [ // set on old/new parents when child's parent changes
      dkUpdateClients, dkUpdateJournal,
      dkAffectsVisibility, dkAffectsKnowledge,
      dkChildren, dkChildAffectsNames,
      dkMassChanged, dkHappinessChanged
   ];

type
   TKnowledgeFilter = function(AssetClass: TAssetClass): Boolean is nested;
   TAssetNodeArray = array of TAssetNode;
   TAssetClassArray = array of TAssetClass;

   ISensorsProvider = interface ['ISensorsProvider']
      // Returns whether the material or asset class is known by the
      // target's owner according to the knowledge bus at the target.
      //
      // This should only be called on the object in the stack frame
      // in which the object was provided.
      function Knows(AssetClass: TAssetClass): Boolean;
      function Knows(Material: TMaterial): Boolean;
      function CollectMatchingAssetClasses(Filter: TKnowledgeFilter): TAssetClassArray;
      function GetOreKnowledge(): TOreFilter;
      function GetDebugName(): UTF8String; // TODO: make this debug-only
      property OreKnowledge: TOreFilter read GetOreKnowledge;
      property DebugName: UTF8String read GetDebugName;
   end;

   TFeatureNode = class abstract (TDebugObject)
   public
      type
         TArray = array of TFeatureNode;
   strict private
      FParent: TAssetNode;
      FSystem: TSystem;
   private
      procedure SetParent(Asset: TAssetNode); inline;
      function GetParent(): TAssetNode; inline;
      function GetIsAttached(): Boolean; inline;
      function GetSystem(): TSystem; inline;
      function GetDebugName(): UTF8String;
   protected
      constructor CreateFromJournal(Journal: TJournalReader; AFeatureClass: TFeatureClass; ASystem: TSystem); virtual;
      procedure AssetCreated(); virtual; // called when we are associated with an asset after the asset is created; Parent is still nil
      procedure Attaching(); virtual; // called when we are newly in a subtree rooted in a system
      procedure Detaching(); virtual; // called when an ancestor is about to lose its Parent
      procedure MarkAsDirty(DirtyKinds: TDirtyKinds); inline; // Utility function, calls Parent.MarkAsDirty().
      procedure ParentMarkedAsDirty(ParentDirtyKinds, NewDirtyKinds: TDirtyKinds); virtual; // Called when the parent is marked as dirty.
      function GetMass(): Double; virtual; // kg
      function GetMassFlowRate(): TRate; virtual; // kg/s
      function GetSize(): Double; virtual; // m
      function GetFeatureName(): UTF8String; virtual;
      function GetHappiness(): Double; virtual;
      procedure Walk(PreCallback: TPreWalkCallback; PostCallback: TPostWalkCallback); virtual;
      function InjectBusMessage(Message: TBusMessage): TInjectBusMessageResult; // (send message up the tree) returns true if message found a bus
      function ManageBusMessage(Message: TBusMessage): TInjectBusMessageResult; virtual; // (consider sending message down the tree) returns true if feature was a bus for this message or should stop propagation
      function DeferOrHandleBusMessage(Message: TBusMessage): TInjectBusMessageResult; // convenience function for ManageBusMessage that tries to inject it higher, and if that rejects, has the asset handle it (typically used for management buses)
      function HandleBusMessage(Message: TBusMessage): Boolean; virtual; // (send message down the tree) returns true if feature handled the message or should stop propagation
      procedure ResetDynastyNotes(OldDynasties: TDynastyIndexHashTable; NewDynasties: TDynasty.TArray); virtual; // OldDynasties is nil the first time this is called
      procedure ResetVisibility(); virtual;
      procedure ApplyVisibility(); virtual;
      procedure HandleVisibility(const DynastyIndex: Cardinal; var Visibility: TVisibility); virtual;
      procedure CheckVisibilityChanged(); virtual;
      procedure ApplyKnowledge(); virtual;
      procedure HandleKnowledge(const DynastyIndex: Cardinal; const Sensors: ISensorsProvider); virtual;
      procedure Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter); virtual;
      procedure HandleChanges(); virtual;
      property System: TSystem read GetSystem;
   public
      constructor Create(ASystem: TSystem);
      constructor Create(); unimplemented;
      destructor Destroy(); override;
      procedure AdoptChild(Child: TAssetNode); virtual;
      procedure DropChild(Child: TAssetNode); virtual;
      procedure UpdateJournal(Journal: TJournalWriter); virtual;
      procedure ApplyJournal(Journal: TJournalReader); virtual;
      function HandleCommand(Command: UTF8String; var Message: TMessage): Boolean; virtual; // return true if command is handled (prevents further handling)
      procedure DescribeExistentiality(var IsDefinitelyReal, IsDefinitelyGhost: Boolean); virtual;
      property Mass: Double read GetMass; // kg
      property MassFlowRate: TRate read GetMassFlowRate; // kg/s
      property Size: Double read GetSize; // m
      property FeatureName: UTF8String read GetFeatureName;
      property Happiness: Double read GetHappiness;
      property Parent: TAssetNode read GetParent;
      property IsAttached: Boolean read GetIsAttached;
      property DebugName: UTF8String read GetDebugName;
   end;

   TBuildEnvironment = (bePlanetRegion, beSpaceDock);
   TBuildEnvironments = set of TBuildEnvironment;

   TAssetClass = class(TDebugObject)
   public
      type
         TArray = array of TAssetClass;
         TPlasticArray = specialize PlasticArray<TAssetClass, TObjectUtils>;
   private
      FID: TAssetClassID;
      FFeatures: TFeatureClass.TArray;
      FName, FAmbiguousName, FDescription: UTF8String;
      FIcon: TIcon;
      FBuildEnvironments: TBuildEnvironments;
      function GetFeature(Index: Cardinal): TFeatureClass;
      function GetFeatureCount(): Cardinal;
      function GetDefaultSize(): Double;
   public
      constructor Create(AID: TAssetClassID; AName, AAmbiguousName, ADescription: UTF8String; AFeatures: TFeatureClass.TArray; AIcon: TIcon; ABuildEnvironments: TBuildEnvironments);
      destructor Destroy(); override;
      function SpawnFeatureNodes(ASystem: TSystem): TFeatureNode.TArray; // some feature nodes _can't_ be spawned this way (e.g. TAssetNameFeatureNode)
      function SpawnFeatureNodesFromJournal(Journal: TJournalReader; System: TSystem): TFeatureNode.TArray;
      procedure ApplyFeatureNodesFromJournal(Journal: TJournalReader; AssetNode: TAssetNode);
      function Spawn(AOwner: TDynasty; ASystem: TSystem): TAssetNode; overload;
      function Spawn(AOwner: TDynasty; ASystem: TSystem; AFeatures: TFeatureNode.TArray): TAssetNode; overload;
   public // encoded in knowledge
      procedure Serialize(Writer: TStringStreamWriter); overload;
      procedure Serialize(Writer: TServerStreamWriter); overload;
      procedure SerializeFor(AssetNode: TAssetNode; DynastyIndex: Cardinal; Writer: TServerStreamWriter);
      function CanBuild(BuildEnvironment: TBuildEnvironment): Boolean;
      property Features[Index: Cardinal]: TFeatureClass read GetFeature;
      property FeatureCount: Cardinal read GetFeatureCount;
      property Name: UTF8String read FName;
      property Description: UTF8String read FDescription;
      property Icon: TIcon read FIcon;
      property DefaultSize: Double read GetDefaultSize;
   public
      property ID: TAssetClassID read FID;
      property AmbiguousName: UTF8String read FAmbiguousName;
   end;

   TEncyclopediaView = class(TMaterialEncyclopedia)
   protected
      function GetAssetClass(ID: TAssetClassID): TAssetClass; virtual; abstract;
      function GetResearch(ID: TResearchID): TResearch; virtual; abstract;
      function GetTopic(Name: UTF8String): TTopic; virtual; abstract;
      function GetMinMassPerOreUnit(): Double; virtual; abstract;
   public
      function Craterize(Diameter: Double; OldAssets: TAssetNodeArray; NewAsset: TAssetNode): TAssetNode; virtual; abstract;
      function HandleBusMessage(Asset: TAssetNode; Message: TBusMessage): Boolean; virtual; abstract; // return true to skip this asset
      procedure Dismantle(Asset: TAssetNode; Message: TMessage); virtual; abstract;
      property AssetClasses[ID: TAssetClassID]: TAssetClass read GetAssetClass;
      property Researches[ID: TResearchID]: TResearch read GetResearch;
      property Topics[Name: UTF8String]: TTopic read GetTopic;
      property MinMassPerOreUnit: Double read GetMinMassPerOreUnit;
   end;

   TAssetNode = class(TDebugObject)
   public
      type
         TArray = array of TAssetNode;
         TPlasticArray = specialize PlasticArray<TAssetNode, TObjectUtils>;
   strict private
      const
         AttachedBit = $01;
      var
         FParent: PtrUInt; // TFeatureNode with top bit tracking attachment status
         FSystem: TSystem;
   strict protected
      FAssetClass: TAssetClass;
      FOwner: TDynasty; // TODO: if this changes value, some features are going to get very confused (e.g. the builder bus)
      FFeatures: TFeatureNode.TArray;
   protected
      FDirty: TDirtyKinds;
      FDynastyNotes: TDynastyNotesPackage; // TDynastyNotesPackage is 64 bits for one dynasty, and a pointer into the heap for more than one
      function GetFeature(Index: Cardinal): TFeatureNode;
      function GetMass(): Double; // kg
      function GetMassFlowRate(): TRate; // kg/s
      function GetSize(): Double; // m
      function GetDensity(): Double; // kg/m^3
      function GetAssetName(): UTF8String;
      function GetAssetOrClassName(): UTF8String;
      function GetHappiness(): Double;
      function GetDebugName(): UTF8String;
   private
      procedure SetParent(AParent: TFeatureNode); inline;
      function GetParent(): TFeatureNode; inline;
      function GetHasParent(): Boolean; inline;
      function GetIsAttached(): Boolean; virtual;
      procedure SetOwner(NewOwner: TDynasty);
      procedure UpdateID(DynastyIndex: Cardinal; ID: TAssetID); // used from ApplyJournal
      function GetSystem(): TSystem; virtual;
   public
      ParentData: Pointer;
      constructor Create(ASystem: TSystem; AAssetClass: TAssetClass; AOwner: TDynasty; AFeatures: TFeatureNode.TArray);
      constructor CreateFromJournal(ASystem: TSystem);
      procedure InitFromJournal(Journal: TJournalReader);
      constructor Create(); unimplemented;
      destructor Destroy(); override;
      procedure Become(AAssetClass: TAssetClass);
      procedure ReportPermanentlyGone();
      function GetFeatureByClass(FeatureClass: FeatureClassReference): TFeatureNode; // returns nil if feature is absent
      procedure Walk(PreCallback: TPreWalkCallback; PostCallback: TPostWalkCallback);
      function InjectBusMessage(Message: TBusMessage): TInjectBusMessageResult; // called by a node to send a message up the tree to a bus (ManageBusMessage); returns true if bus was found
      function HandleBusMessage(Message: TBusMessage): Boolean; // called by a bus (ManageBusMessage) to send a message down the tree; returs true if message was handled
      procedure MarkAsDirty(DirtyKinds: TDirtyKinds); virtual;
      procedure ResetDynastyNotes(OldDynasties: TDynastyIndexHashTable; NewDynasties: TDynasty.TArray); // OldDynasties is nil the first time this is called
      procedure ResetVisibility();
      procedure ApplyVisibility();
      procedure HandleVisibility(const DynastyIndex: Cardinal; var Visibility: TVisibility);
      procedure CheckVisibilityChanged();
      procedure ApplyKnowledge();
      procedure HandleKnowledge(const DynastyIndex: Cardinal; const Sensors: ISensorsProvider);
      function ReadVisibilityFor(DynastyIndex: Cardinal): TVisibility; inline;
      function IsVisibleFor(DynastyIndex: Cardinal): Boolean; inline;
      procedure HandleChanges();
      procedure Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter);
      procedure UpdateJournal(Journal: TJournalWriter);
      procedure ApplyJournal(Journal: TJournalReader);
      function ID(DynastyIndex: Cardinal; AllowZero: Boolean = False): TAssetID;
      procedure HandleCommand(Command: UTF8String; var Message: TMessage);
      function IsReal(): Boolean;
      property Parent: TFeatureNode read GetParent;
      property HasParent: Boolean read GetHasParent;
      property IsAttached: Boolean read GetIsAttached;
      property Dirty: TDirtyKinds read FDirty;
      property AssetClass: TAssetClass read FAssetClass;
      property Owner: TDynasty read FOwner write SetOwner;
      property Features[Index: Cardinal]: TFeatureNode read GetFeature;
      property Mass: Double read GetMass; // kg
      property MassFlowRate: TRate read GetMassFlowRate; // kg/s
      property Size: Double read GetSize; // meters, must be greater than zero
      property Density: Double read GetDensity; // kg/m^3; computed from mass and size, assuming spherical shape
      property AssetName: UTF8String read GetAssetName;
      property AssetOrClassName: UTF8String read GetAssetOrClassName;
      property Happiness: Double read GetHappiness;
      property DebugName: UTF8String read GetDebugName;
      property System: TSystem read GetSystem;
   end;

   // pointers to these objects are not valid after the event has run or been canceled
   TSystemEvent = class(TDebugObject)
   private
      FTime: TTimeInMilliseconds;
      FCallback: TEventCallback;
      FData: Pointer;
      FSystem: TSystem;
      {$PUSH}
      {$WARN 3019 OFF} // (it wants the destructor to be public for some reason)
      destructor Cancel();
      {$POP}
   public
      constructor Create(ATime: TTimeInMilliseconds; ACallback: TEventCallback; AData: Pointer; ASystem: TSystem);
   end;

   TSystemEventSet = specialize TTightHashSet<TSystemEvent, TTightHashUtilsPtr>; // TODO: consider using regular THashSet instead, as we do a lot of removes from this set
   // TSystemEventSet = specialize THashSet<TSystemEvent, PointerUtils>;

   TSystem = class sealed
   strict private
      FServer: TBaseServer;
      FOnScoreDirty: TScoreDirtyCallback;
      FScheduledEvents: TSystemEventSet;
      FNextEvent: TSystemEvent;
      FNextEventHandle: PEvent;
      FCurrentEventTime, FLastTime: TTimeInMilliseconds;
      FDynastyDatabase: TDynastyDatabase;
      FDynasties: TDynasty.TArray; // in index order
      FEncyclopedia: TEncyclopediaView;
      FConfigurationDirectory: UTF8String;
      FSystemID: Cardinal;
      FRandomNumberGenerator: TRandomNumberGenerator;
      FX, FY: Double;
      FTimeOrigin: TDateTime;
      FTimeFactor: TTimeFactor;
      FRoot: TAssetNode;
      FChanges: TDirtyKinds;
      procedure Init(AConfigurationDirectory: UTF8String; ASystemID: Cardinal; ARootClass: TAssetClass; AServer: TBaseServer; ADynastyDatabase: TDynastyDatabase; AEncyclopedia: TEncyclopediaView; AOnScoreDirty: TScoreDirtyCallback);
      procedure ApplyJournal(FileName: UTF8String);
      procedure OpenJournal(FileName: UTF8String);
      procedure RecordUpdate(DynastyCountChanged: Boolean);
      function GetDirty(): Boolean;
      procedure Clean();
      function GetIsLongVisibilityMode(): Boolean; inline;
      procedure UnwindDynastyNotesArenas(Arena: Pointer);
      procedure UpdateDynastyList(MaintainMaxIDs: Boolean);
      procedure RecomputeVisibility(DynastyCountChanged, HaveNewNodes: Boolean);
      procedure RunEvent(var Data);
      procedure ScheduleNextEvent();
      procedure RescheduleNextEvent(); // call this when the time factor changes
      function SelectNextEvent(): TSystemEvent;
      function GetNow(): TTimeInMilliseconds; inline;
      function GetDynastyCount(): Cardinal; inline;
      function GetDynastyIndex(Dynasty: TDynasty): Cardinal; inline;
      function GetDynastyByIndex(Index: Cardinal): TDynasty; inline;
   private
      FDynastyIndices: TDynastyIndexHashTable; // for index into visibility tables
      FDynastyMaxAssetIDs: array of TAssetID;
      FDynastyNotesBuffer: Pointer; // pointer to an arena that ends with a pointer to the next arena (or nil); size is N*M+8 bytes, where N=dynasty count and M=size of TDynastyNotes
      FDynastyNotesOffset: Cardinal;
      FJournalFile: File; // used by TJournalReader/TJournalWriter
      FJournalWriter: TJournalWriter;
      procedure CancelEvent(Event: TSystemEvent);
      procedure ReportChildIsPermanentlyGone(Child: TAssetNode);
   protected
      procedure MarkAsDirty(DirtyKinds: TDirtyKinds);
      function AllocateFromDynastyNotesArena(Size: SizeInt): Pointer;
      procedure ScoreChangedFor(Dynasty: TDynasty);
   public
      constructor Create(AConfigurationDirectory: UTF8String; ASystemID: Cardinal; AX, AY: Double; ARootClass: TAssetClass; AServer: TBaseServer; ADynastyDatabase: TDynastyDatabase; AEncyclopedia: TEncyclopediaView; Settings: PSettings; AOnScoreDirty: TScoreDirtyCallback);
      constructor CreateFromDisk(AConfigurationDirectory: UTF8String; ASystemID: Cardinal; ARootClass: TAssetClass; AServer: TBaseServer; ADynastyDatabase: TDynastyDatabase; AEncyclopedia: TEncyclopediaView; AOnScoreDirty: TScoreDirtyCallback);
      destructor Destroy(); override;
      function SerializeSystem(Dynasty: TDynasty; Writer: TServerStreamWriter; DirtyOnly: Boolean): Boolean; // true if anything was dkUpdateClients dirty
      procedure ReportChanges();
      function HasDynasty(Dynasty: TDynasty): Boolean; inline;
      function SubtreeHasNewDynasty(Child: TAssetNode): Boolean;
      function ComputeScoreFor(Dynasty: TDynasty): Double;
      function ScheduleEvent(TimeDelta: TMillisecondsDuration; Callback: TEventCallback; var Data): TSystemEvent;
      function TimeUntilNext(TimeOrigin: TTimeInMilliseconds; Period: TMillisecondsDuration): TMillisecondsDuration;
      function FindCommandTarget(Dynasty: TDynasty; AssetID: TAssetID): TAssetNode;
      property RootNode: TAssetNode read FRoot;
      property Dirty: Boolean read GetDirty;
      property SystemID: Cardinal read FSystemID;
      property RandomNumberGenerator: TRandomNumberGenerator read FRandomNumberGenerator;
      property IsLongVisibilityMode: Boolean read GetIsLongVisibilityMode;
      property DynastyDatabase: TDynastyDatabase read FDynastyDatabase;
      property DynastyCount: Cardinal read GetDynastyCount;
      property DynastyIndex[Dynasty: TDynasty]: Cardinal read GetDynastyIndex;
      property DynastyByIndex[Index: Cardinal]: TDynasty read GetDynastyByIndex;
      property Encyclopedia: TEncyclopediaView read FEncyclopedia; // used by TJournalReader/TJournalWriter
      property Journal: TJournalWriter read FJournalWriter;
      property Now: TTimeInMilliseconds read GetNow;
      property TimeFactor: TTimeFactor read FTimeFactor; // if this ever supports being changed, we need to be super careful about code that checks Now around the time it updates (e.g. to write a time to disk, read it back from disk, etc), and need to make sure Now doesn't ever go backwards or forwards in time discontinuously
      property Server: TBaseServer read FServer;
   public // Visibility API
      procedure AddSpecificVisibility(const Dynasty: TDynasty; const Visibility: TVisibility; const Asset: TAssetNode); inline;
      procedure AddSpecificVisibilityByIndex(const Index: Cardinal; const Visibility: TVisibility; const Asset: TAssetNode);
      procedure AddBroadVisibility(const Visibility: TVisibility; const Asset: TAssetNode);
   end;

function ResearchIDHash32(const Key: TResearchID): DWord;
function ResearchHash32(const Key: TResearch): DWord;

procedure CancelEvent(var Event: TSystemEvent);

implementation

uses
   sysutils, dateutils,
   exceptions, typedump,
   hashfunctions,
   math, {$IFDEF DEBUG} debug, {$ENDIF}
   providers;

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


type
   TRootAssetNode = class(TAssetNode)
   private
      function GetIsAttached(): Boolean; override;
   public
      procedure MarkAsDirty(DirtyKinds: TDirtyKinds); override;
   end;

function TRootAssetNode.GetIsAttached(): Boolean;
begin
   Result := True;
end;

procedure TRootAssetNode.MarkAsDirty(DirtyKinds: TDirtyKinds);
begin
   inherited;
   System.MarkAsDirty(UpdateDirtyKindsForAncestor(DirtyKinds));
end;


function AssetClassHash32(const Key: TAssetClass): DWord;
begin
   Result := ObjectHash32(Key);
end;

constructor TDynastyIndexHashTable.Create();
begin
   inherited Create(@DynastyHash32);
end;

constructor TAssetClassIDHashTable.Create();
begin
   inherited Create(@LongIntHash32);
end;

constructor TAssetClassIdentifierHashTable.Create();
begin
   inherited Create(@UTF8StringHash32);
end;

constructor TAssetNodeHashTable.Create();
begin
   inherited Create(@PtrUIntHash32);
end;

function SystemEventHash32(const Key: TSystemEvent): DWord;
begin
   Result := ObjectHash32(Key);
end;


constructor TReward.CreateForMessage(var Message: UTF8String);
begin
   Assert((PtrUInt(Message) and TypeMask) = $00);
   if (not IsStringConstant(Message)) then
   begin
      {$IFOPT C+} AssertStringIsReffed(Message, 1); {$ENDIF}
      IncRefCount(Message);
   end;
   FData := PtrUInt(Message) or PtrUInt(rkMessage);
end;

constructor TReward.CreateForAssetClass(AssetClass: TAssetClass);
begin
   Assert((PtrUInt(AssetClass) and TypeMask) = $00);
   FData := PtrUInt(AssetClass) or PtrUInt(rkAssetClass);
end;

constructor TReward.CreateForMaterial(Material: TMaterial);
begin
   Assert((PtrUInt(Material) and TypeMask) = $00);
   FData := PtrUInt(Material) or PtrUInt(rkMaterial);
end;

procedure TReward.Free();
var
   Value: UTF8String;
begin
   case GetKind() of
      rkMessage:
         begin
            Value := GetMessage();
            if (not IsStringConstant(Message)) then
            begin
               DecRefCount(Value);
               {$IFOPT C+} AssertStringIsReffed(Message, 0); {$ENDIF}
            end;
         end;
      rkAssetClass,
      rkMaterial: ; // these are references, we don't own them
   end;
   {$IFOPT C+}
   FData := PtrUInt(not 0);
   {$ENDIF}
end;

function TReward.GetKind(): TRewardKind;
begin
   Result := TRewardKind(FData and TypeMask);
end;

function TReward.GetMessage(): UTF8String;
begin
   Assert((PtrUInt(FData) and TypeMask) = PtrUInt(rkMessage));
   Result := UTF8String(Pointer(FData and not TypeMask)); // {BOGUS Hint: Conversion between ordinals and pointers is not portable}
   // If we get random crashes, consider if maybe this needs to increase the ref count
end;

function TReward.GetAssetClass(): TAssetClass;
begin
   Assert((PtrUInt(FData) and TypeMask) = PtrUInt(rkAssetClass));
   Result := TAssetClass(Pointer(FData and not TypeMask)); // {BOGUS Hint: Conversion between ordinals and pointers is not portable}
end;

function TReward.GetMaterial(): TMaterial;
begin
   Assert((PtrUInt(FData) and TypeMask) = PtrUInt(rkMaterial));
   Result := TMaterial(Pointer(FData and not TypeMask)); // {BOGUS Hint: Conversion between ordinals and pointers is not portable}
end;


procedure TNode.PropagateRequirements(Requirements: TNodeArray);
var
   Requirement: TNode;
begin
   for Requirement in Requirements do
   begin
      SetLength(Requirement.FUnlocks, Length(Requirement.FUnlocks) + 1);
      Requirement.FUnlocks[High(Requirement.FUnlocks)] := Self;
   end;
end;

function TNode.ToString(): UTF8String;
begin
   Result := '<TNode: ' + ClassName + '>';
end;


constructor TBonus.Create(ANode: TNode; ATimeDelta: TMillisecondsDuration; AWeightDelta: TWeightDelta; ANegate: Boolean);
begin
   FNode := ANode;
   FTimeDelta := ATimeDelta;
   FWeightDelta := AWeightDelta;
   FNegate := ANegate;
end;

function TBonus.ToString(): UTF8String;
begin
   Result := '<TBonus: ' + Node.ToString() + '; ' + IntToStr(TimeDelta.AsInt64) + 'ms; ' + IntToStr(WeightDelta) + ' weight; negate=' + HexStr(LongInt(Negate), 8) + '>';
end;


constructor TResearch.Create(AID: TResearchID; ADefaultTime: TMillisecondsDuration; ADefaultWeight: TWeight; ARequirements: TNode.TNodeArray; ABonuses: TBonus.TArray; ARewards: TReward.TArray);
begin
   inherited Create();
   FID := AID;
   FDefaultTime := ADefaultTime;
   FDefaultWeight := ADefaultWeight;
   FRequirements := ARequirements;
   FBonuses := ABonuses;
   FRewards := ARewards;
   PropagateRequirements(FRequirements);
end;

destructor TResearch.Destroy();
var
   Reward: TReward;
begin
   for Reward in FRewards do
      Reward.Free();
   inherited;
end;

function TResearch.GetIsRoot(): Boolean;
begin
   Result := Length(FRequirements) = 0;
end;

function TResearch.ToString(): UTF8String;
var
   Bonus: TBonus;
   Unlock: TNode;
begin
   Result := '<Research ' + IntToStr(FID) + '; time=' + IntToStr(FDefaultTime.AsInt64) + 'ms; weight=' + IntToStr(FDefaultTime.AsInt64) + '; ' + IntToStr(Length(FRequirements)) + ' reqs; ' + IntToStr(Length(FBonuses)) + ' bonuses>';
   for Bonus in FBonuses do
      Result := Result + #$0A + '  bonus: ' + Bonus.ToString();
   for Unlock in Unlocks do
      Result := Result + #$0A + '  unlock: ' + Unlock.ToString();
end;


function ResearchHash32(const Key: TResearch): DWord;
begin
   Result := ObjectHash32(Key);
end;

function ResearchIDHash32(const Key: TResearchID): DWord;
begin
   Result := LongintHash32(Key);
end;

constructor TResearchIDHashTable.Create();
begin
   inherited Create(@ResearchIDHash32);
end;

constructor TWeightedResearchHashTable.Create();
begin
   inherited Create(@ResearchHash32);
end;


constructor TTopic.Create(AValue: UTF8String; ASelectable: Boolean; ARequirements: TResearch.TArray; AObsoletes: TTopic.TArray);
begin
   inherited Create();
   Assert((not ASelectable) or (AValue <> ''), 'Unnamed topics cannot be selectable.');
   FValue := AValue;
   FSelectable := ASelectable;
   FRequirements := ARequirements;
   FObsoletes := AObsoletes;
   PropagateRequirements(TNode.TNodeArray(FRequirements));
end;

function TTopic.GetIsRoot(): Boolean;
begin
   Result := Length(FRequirements) = 0;
end;



constructor TTopicHashTable.Create();
begin
   inherited Create(@UTF8StringHash32);
end;



constructor TTechTreeReader.Create(ATokenizer: TTokenizer; AAssetClasses: TAssetClassIdentifierHashTable; AMaterialNames: TMaterialNameHashTable; ATopics: TTopicHashTable);
begin
   FTokenizer := ATokenizer;
   FAssetClasses := AAssetClasses;
   FMaterialNames := AMaterialNames;
   FTopics := ATopics;
end;

function TTechTreeReader.GetAssetClass(Identifier: UTF8String): TAssetClass;
begin
   Result := FAssetClasses[Identifier];
end;

function TTechTreeReader.GetMaterial(Name: UTF8String): TMaterial;
begin
   Result := FMaterialNames[Name];
end;

function TTechTreeReader.GetTopic(Name: UTF8String): TTopic;
begin
   Result := FTopics[Name];
end;


const
   jcSystemUpdate = $00EDD1E5; // (in the space-time continuum)
   jcIDUpdates = $0FACADE5;
   jcAssetDestroyed = $DECEA5ED;
   jcNewAsset = $000A55E7;
   jcAssetChange = $000D317A;
   jcEndOfAsset = $CAB005ED;
   jcStartOfFeature = $00D00DAD;
   jcEndOfFeature = $0DA151E5;
   jcEndOfFeatures = $C0D1F1ED;

type
   EJournalError = class(Exception) end;

constructor TJournalReader.Create(ASystem: TSystem);
begin
   inherited Create();
   FSystem := ASystem;
   FAssetMap := TAssetNodeHashTable.Create();
end;

destructor TJournalReader.Destroy();
begin
   FAssetMap.Free();
   inherited Destroy();
end;

function TJournalReader.ReadBoolean(): Boolean;
begin
   BlockRead(FSystem.FJournalFile, Result, SizeOf(Result)); {BOGUS Hint: Function result variable does not seem to be initialized}
   {$IFDEF VERBOSE_JOURNAL} Writeln('ReadBoolean: ', Result); {$ENDIF}
end;

function TJournalReader.ReadByte(): Byte;
begin
   BlockRead(FSystem.FJournalFile, Result, SizeOf(Result)); {BOGUS Hint: Function result variable does not seem to be initialized}
   {$IFDEF VERBOSE_JOURNAL} Writeln('ReadByte: ', Result); {$ENDIF}
end;

function TJournalReader.ReadCardinal(): Cardinal;
begin
   BlockRead(FSystem.FJournalFile, Result, SizeOf(Result)); {BOGUS Hint: Function result variable does not seem to be initialized}
   {$IFDEF VERBOSE_JOURNAL} Writeln('ReadCardinal: ', Result, ' $', HexStr(Result, 8)); {$ENDIF}
end;

function TJournalReader.ReadInt32(): Int32;
begin
   BlockRead(FSystem.FJournalFile, Result, SizeOf(Result)); {BOGUS Hint: Function result variable does not seem to be initialized}
   {$IFDEF VERBOSE_JOURNAL} Writeln('ReadInt32: ', Result); {$ENDIF}
end;

function TJournalReader.ReadInt64(): Int64;
begin
   BlockRead(FSystem.FJournalFile, Result, SizeOf(Result)); {BOGUS Hint: Function result variable does not seem to be initialized}
   {$IFDEF VERBOSE_JOURNAL} Writeln('ReadInt64: ', Result); {$ENDIF}
end;

function TJournalReader.ReadUInt64(): UInt64;
begin
   BlockRead(FSystem.FJournalFile, Result, SizeOf(Result)); {BOGUS Hint: Function result variable does not seem to be initialized}
   {$IFDEF VERBOSE_JOURNAL} Writeln('ReadUInt64: ', Result); {$ENDIF}
end;

function TJournalReader.ReadPtrUInt(): PtrUInt;
begin
   BlockRead(FSystem.FJournalFile, Result, SizeOf(Result)); {BOGUS Hint: Function result variable does not seem to be initialized}
   {$IFDEF VERBOSE_JOURNAL} Writeln('ReadPtrUInt: ', Result, ' $', HexStr(Result, 16)); {$ENDIF}
end;

function TJournalReader.ReadDouble(): Double;
begin
   BlockRead(FSystem.FJournalFile, Result, SizeOf(Result)); {BOGUS Hint: Function result variable does not seem to be initialized}
   {$IFDEF VERBOSE_JOURNAL} Writeln('ReadDouble: ', Result); {$ENDIF}
end;

function TJournalReader.ReadString(): UTF8String;
var
   Size: Cardinal;
begin
   Size := ReadCardinal();
   SetLength(Result, Size); {BOGUS Hint: Function result variable of a managed type does not seem to be initialized}
   if (Size > 0) then
      BlockRead(FSystem.FJournalFile, Result[1], Size);
   {$IFDEF VERBOSE_JOURNAL} Writeln('ReadString: ', Result); {$ENDIF}
end;

function TJournalReader.ReadAssetChangeKind(): TAssetChangeKind;
begin
   BlockRead(FSystem.FJournalFile, Result, SizeOf(Result)); {BOGUS Hint: Function result variable does not seem to be initialized}
   {$IFDEF VERBOSE_JOURNAL} Writeln('ReadAssetChangeKind: ', specialize EnumToString<TAssetChangeKind>(Result)); {$ENDIF}
end;

function TJournalReader.ReadAssetNodeReference(ASystem: TSystem): TAssetNode;
var
   ID: PtrUInt;
begin
   ID := ReadPtrUInt();
   if (ID > 0) then
   begin
      Result := FAssetMap[ID];
      if (not Assigned(Result)) then
      begin
         {$IFDEF VERBOSE_JOURNAL} Writeln('ReadAssetNodeReference: creating new asset'); {$ENDIF}
         Result := TAssetNode.CreateFromJournal(ASystem);
         FAssetMap[ID] := Result;
      end;
   end
   else
   begin
      Result := nil;
      {$IFDEF VERBOSE_JOURNAL} Writeln('ReadAssetNodeReference: nil'); {$ENDIF}
   end;
end;

function TJournalReader.ReadAssetClassReference(): TAssetClass;
var
   ID: TAssetClassID;
begin
   Assert(SizeOf(Cardinal) = SizeOf(TAssetClassID));
   ID := TAssetClassID(ReadCardinal());
   if (ID <> 0) then
   begin
      Result := FSystem.Encyclopedia.AssetClasses[ID];
      {$IFDEF VERBOSE_JOURNAL}
      if (Assigned(Result)) then
         Writeln('ReadAssetClassReference: ', Result.Name)
      else
         Writeln('ReadAssetClassReference: nil UNEXPECTED');
      {$ENDIF}
   end
   else
   begin
      Result := nil;
      {$IFDEF VERBOSE_JOURNAL} Writeln('ReadAssetClassReference: nil'); {$ENDIF}
   end;
end;

function TJournalReader.ReadDynastyReference(): TDynasty;
var
   ID: Cardinal;
begin
   ID := ReadCardinal();
   if (ID > 0) then
   begin
      Result := FSystem.DynastyDatabase.GetDynastyFromDisk(ID);
      {$IFDEF VERBOSE_JOURNAL} Writeln('ReadDynastyReference: ', Result.DynastyID); {$ENDIF}
   end
   else
   begin
      Result := nil;
      {$IFDEF VERBOSE_JOURNAL} Writeln('ReadDynastyReference: nil'); {$ENDIF}
   end;
end;

function TJournalReader.ReadMaterialReference(): TMaterial;
var
   ID: TMaterialID;
begin
   Assert(SizeOf(Cardinal) = SizeOf(TMaterialID));
   ID := TMaterialID(ReadCardinal());
   Result := FSystem.Encyclopedia.Materials[ID];
   {$IFDEF VERBOSE_JOURNAL} Writeln('ReadMaterialReference: ', Result.Name); {$ENDIF}
end;


constructor TJournalWriter.Create(ASystem: TSystem);
begin
   inherited Create();
   FSystem := ASystem;
end;

procedure TJournalWriter.WriteBoolean(Value: Boolean);
begin
   BlockWrite(FSystem.FJournalFile, Value, SizeOf(Value));
end;

procedure TJournalWriter.WriteByte(Value: Byte);
begin
   BlockWrite(FSystem.FJournalFile, Value, SizeOf(Value));
end;

procedure TJournalWriter.WriteCardinal(Value: Cardinal);
begin
   BlockWrite(FSystem.FJournalFile, Value, SizeOf(Value));
end;

procedure TJournalWriter.WriteInt32(Value: Int32);
begin
   BlockWrite(FSystem.FJournalFile, Value, SizeOf(Value));
end;

procedure TJournalWriter.WriteInt64(Value: Int64);
begin
   BlockWrite(FSystem.FJournalFile, Value, SizeOf(Value));
end;

procedure TJournalWriter.WriteUInt64(Value: UInt64);
begin
   BlockWrite(FSystem.FJournalFile, Value, SizeOf(Value));
end;

procedure TJournalWriter.WritePtrUInt(Value: PtrUInt);
begin
   BlockWrite(FSystem.FJournalFile, Value, SizeOf(Value));
end;

procedure TJournalWriter.WriteDouble(Value: Double);
begin
   BlockWrite(FSystem.FJournalFile, Value, SizeOf(Value));
end;

procedure TJournalWriter.WriteString(Value: UTF8String);
begin
   WriteCardinal(Length(Value));
   if (Value <> '') then
      BlockWrite(FSystem.FJournalFile, Value[1], Length(Value)); // $R-
end;

procedure TJournalWriter.WriteAssetChangeKind(Value: TAssetChangeKind);
begin
   BlockWrite(FSystem.FJournalFile, Value, SizeOf(Value));
end;

procedure TJournalWriter.WriteAssetNodeReference(AssetNode: TAssetNode);
begin
   if (Assigned(AssetNode)) then
   begin
      WritePtrUInt(PtrUInt(AssetNode));
   end
   else
   begin
      WritePtrUInt(0);
   end;
end;

procedure TJournalWriter.WriteAssetClassReference(AssetClass: TAssetClass);
begin
   if (Assigned(AssetClass)) then
   begin
      WriteCardinal(Cardinal(AssetClass.ID));
   end
   else
   begin
      WriteCardinal(0);
   end;
end;

procedure TJournalWriter.WriteDynastyReference(Dynasty: TDynasty);
begin
   if (Assigned(Dynasty)) then
   begin
      WriteCardinal(Dynasty.DynastyID);
   end
   else
   begin
      WriteCardinal(0);
   end;
end;

procedure TJournalWriter.WriteMaterialReference(Material: TMaterial);
begin
   Assert(Assigned(Material));
   Assert(Material.ID <> 0);
   WriteCardinal(Cardinal(Material.ID));
end;


constructor TAssetGoingAway.Create(AAsset: TAssetNode);
begin
   inherited Create();
   FAsset := AAsset;
end;


function TFeatureClass.GetDefaultSize(): Double;
begin
   Result := 0.0;
end;


constructor TFeatureNode.CreateFromJournal(Journal: TJournalReader; AFeatureClass: TFeatureClass; ASystem: TSystem);
begin
   inherited Create();
   Assert(Assigned(ASystem));
   FSystem := ASystem;
   try
      ApplyJournal(Journal);
   except
      ReportCurrentException();
      raise;
   end;
end;

constructor TFeatureNode.Create(ASystem: TSystem);
begin
   inherited Create();
   Assert(Assigned(ASystem));
   FSystem := ASystem;
end;

constructor TFeatureNode.Create();
begin
   Writeln('Invalid constructor call for ', ClassName, '.');
   raise Exception.Create('Invalid constructor call');
end;

procedure TFeatureNode.SetParent(Asset: TAssetNode);
begin
   Assert(Assigned(Asset));
   Assert(not Assigned(FParent));
   FParent := Asset;
   AssetCreated();
end;

function TFeatureNode.GetParent(): TAssetNode;
begin
   Assert(Assigned(FParent));
   Result := FParent;
end;

function TFeatureNode.GetSystem(): TSystem;
begin
   Assert(Assigned(FSystem));
   Result := FSystem;
end;

function TFeatureNode.GetIsAttached(): Boolean;
begin
   Result := Assigned(FParent) and FParent.IsAttached;
end;

procedure TFeatureNode.AssetCreated();
begin
end;

procedure TFeatureNode.Attaching();
begin
end;

procedure TFeatureNode.Detaching();
begin
end;

procedure TFeatureNode.AdoptChild(Child: TAssetNode);
var
   DirtyKinds: TDirtyKinds;
begin
   if (Assigned(Child.Parent)) then
      Child.Parent.DropChild(Child);
   Assert(not Assigned(Child.ParentData)); // DropChild is responsible for freeing it; subclass is responsible for allocating this after calling us
   Child.SetParent(Self);
   DirtyKinds := dkAffectsTreeStructure + UpdateDirtyKindsForAncestor(Child.Dirty);
   if (System.SubtreeHasNewDynasty(Child)) then
      Include(DirtyKinds, dkAffectsDynastyCount);
   MarkAsDirty(DirtyKinds);
end;

procedure TFeatureNode.DropChild(Child: TAssetNode);
var
   DirtyKinds: TDirtyKinds;
begin
   Assert(Assigned(FParent));
   Assert(Child.Parent = Self);
   Child.SetParent(nil);
   Assert(not Assigned(Child.ParentData)); // subclass is responsible for freeing child's parent data before calling us
   DirtyKinds := dkAffectsTreeStructure;
   // TODO: should detect when a dynasty is gone entirely, and set dkAffectsDynastyCount
   MarkAsDirty(DirtyKinds);
end;

procedure TFeatureNode.MarkAsDirty(DirtyKinds: TDirtyKinds);
begin
   if (Assigned(FParent)) then
      FParent.MarkAsDirty(DirtyKinds);
end;

procedure TFeatureNode.ParentMarkedAsDirty(ParentDirtyKinds, NewDirtyKinds: TDirtyKinds);
begin
end;

function TFeatureNode.GetMass(): Double; // kg
begin
   Result := 0.0;
end;

function TFeatureNode.GetMassFlowRate(): TRate; // kg/s
begin
   Result := TRate.Zero;
end;

function TFeatureNode.GetSize(): Double; // m
begin
   Result := 0.0;
end;

function TFeatureNode.GetFeatureName(): UTF8String;
begin
   Result := '';
end;

function TFeatureNode.GetHappiness(): Double;
begin
   Result := 0.0;
end;

procedure TFeatureNode.Walk(PreCallback: TPreWalkCallback; PostCallback: TPostWalkCallback);
begin
end;

function TFeatureNode.HandleBusMessage(Message: TBusMessage): Boolean;
begin
   Assert(
      TMethod(@Self.HandleBusMessage).Code = Pointer(@TFeatureNode.HandleBusMessage),
      'If you override HandleBusMessage, there''s no need to call the inherited method. Just default to false.'
   );
   // TODO: should this use Walk and subclasses call this, instead of subclasses having to duplicate walk logic?
   Result := False;
end;

function TFeatureNode.InjectBusMessage(Message: TBusMessage): TInjectBusMessageResult;
begin
   Result := Parent.InjectBusMessage(Message);
end;

function TFeatureNode.ManageBusMessage(Message: TBusMessage): TInjectBusMessageResult;
begin
   // InjectBusMessage calls this on each feature until it finds one that doesn't defer.
   // If they all defer, it goes up to the parent asset and tries again.
   Result := irDeferred;
end;

function TFeatureNode.DeferOrHandleBusMessage(Message: TBusMessage): TInjectBusMessageResult;
var
   Handled: Boolean;
begin
   Result := irRejected;
   if (Assigned(Parent.Parent)) then
      Result := Parent.Parent.InjectBusMessage(Message);
   Assert(Result <> irDeferred);
   if (Result = irRejected) then
   begin
      Handled := Parent.HandleBusMessage(Message);
      if (Handled) then
         Result := irHandled
      else
         Result := irInjected;
   end;
end;

procedure TFeatureNode.ResetDynastyNotes(OldDynasties: TDynastyIndexHashTable; NewDynasties: TDynasty.TArray);
begin
end;

procedure TFeatureNode.ResetVisibility();
begin
end;

procedure TFeatureNode.ApplyVisibility();
begin
end;

procedure TFeatureNode.HandleVisibility(const DynastyIndex: Cardinal; var Visibility: TVisibility);
begin
end;

procedure TFeatureNode.CheckVisibilityChanged();
begin
end;

procedure TFeatureNode.ApplyKnowledge();
begin
end;

procedure TFeatureNode.HandleKnowledge(const DynastyIndex: Cardinal; const Sensors: ISensorsProvider);
begin
end;

procedure TFeatureNode.HandleChanges();
begin
end;

procedure TFeatureNode.Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter);
begin
end;

procedure TFeatureNode.UpdateJournal(Journal: TJournalWriter);
begin
end;

procedure TFeatureNode.ApplyJournal(Journal: TJournalReader);
begin
end;

function TFeatureNode.HandleCommand(Command: UTF8String; var Message: TMessage): Boolean;
begin
   Assert(
      TMethod(@Self.HandleCommand).Code = Pointer(@TFeatureNode.HandleCommand),
      'If you override HandleCommand, there''s no need to call the inherited method. Just default to false.'
   );
   Result := False;
end;

procedure TFeatureNode.DescribeExistentiality(var IsDefinitelyReal, IsDefinitelyGhost: Boolean);
begin
end;

function TFeatureNode.GetDebugName(): UTF8String;
begin
   if (Assigned(FParent)) then
   begin
      Result := Parent.DebugName + '-<' + ClassName + ' ' + '@' + HexStr(Self) + '>';
   end
   else
   begin
      Result := '<nil>-<' + ClassName + ' @' + HexStr(Self) + '>';
   end;
end;

destructor TFeatureNode.Destroy();
begin
   inherited;
end;


constructor TAssetClass.Create(AID: TAssetClassID; AName, AAmbiguousName, ADescription: UTF8String; AFeatures: TFeatureClass.TArray; AIcon: TIcon; ABuildEnvironments: TBuildEnvironments);
begin
   inherited Create();
   FID := AID;
   FName := AName;
   Assert(FName <> '');
   FAmbiguousName := AAmbiguousName;
   Assert(FAmbiguousName <> '');
   FDescription := ADescription;
   Assert(FDescription <> '');
   FFeatures := AFeatures;
   FIcon := AIcon;
   Assert(FIcon <> '');
   FBuildEnvironments := ABuildEnvironments;
end;

destructor TAssetClass.Destroy();
var
   Index: Cardinal;
begin
   if (Length(FFeatures) > 0) then
      for Index := Low(FFeatures) to High(FFeatures) do // $R-
         FreeAndNil(FFeatures[Index]);
   inherited;
end;

function TAssetClass.GetFeature(Index: Cardinal): TFeatureClass;
begin
   Result := FFeatures[Index];
end;

function TAssetClass.GetFeatureCount(): Cardinal;
begin
   Result := Length(FFeatures); // $R-
end;

function TAssetClass.GetDefaultSize(): Double;
var
   Feature: TFeatureClass;
   Size: Double;
begin
   Result := 0.0;
   for Feature in FFeatures do
   begin
      Assert(Assigned(Feature), Name + ' has bad features');
      Size := Feature.DefaultSize;
      if (Size > Result) then
         Result := Size;
   end;
end;

function TAssetClass.SpawnFeatureNodes(ASystem: TSystem): TFeatureNode.TArray;
var
   FeatureNodes: TFeatureNode.TArray;
   Index: Cardinal;
begin
   SetLength(FeatureNodes, Length(FFeatures));
   if (Length(FeatureNodes) > 0) then
      for Index := 0 to High(FFeatures) do // $R-
         FeatureNodes[Index] := FFeatures[Index].InitFeatureNode(ASystem);
   Result := FeatureNodes;
end;

function TAssetClass.SpawnFeatureNodesFromJournal(Journal: TJournalReader; System: TSystem): TFeatureNode.TArray;
var
   Index, FallbackIndex: Cardinal;
   Value: Cardinal;
   {$IFDEF DEBUG} HeapInfo: THeapInfo; {$ENDIF}
begin
   SetLength(Result, Length(FFeatures)); {BOGUS Warning: Function result variable of a managed type does not seem to be initialized}
   if (Length(Result) > 0) then
   begin
      for Index := Low(FFeatures) to High(FFeatures) do // $R-
      begin
         case (Journal.ReadCardinal()) of
            jcStartOfFeature:
               begin
                  {$IFDEF DEBUG} HeapInfo := SetHeapInfoTruncated(FFeatures[Index].FeatureNodeClass.ClassName); {$ENDIF}
                  Result[Index] := FFeatures[Index].FeatureNodeClass.CreateFromJournal(Journal, FFeatures[Index], System);
                  {$IFDEF DEBUG} SetHeapInfo(HeapInfo); {$ENDIF}
                  if (Journal.ReadCardinal() <> jcEndOfFeature) then
                  begin
                     raise EJournalError.Create('missing end of feature marker (0x' + HexStr(jcEndOfFeature, 8) + ') when reading ' + FFeatures[Index].ClassName);
                  end;
               end;
            jcEndOfFeatures:
               begin
                  for FallbackIndex := Index to High(FFeatures) do // $R-
                  begin
                     Writeln('Migrating asset class ', FName, '; using default values for ', FFeatures[Index].ClassName);
                     Result[Index] := FFeatures[Index].InitFeatureNode(System); // this will fail for some features nodes...
                  end;
                  exit;
               end;
            else
               raise EJournalError.Create('missing start of feature (0x' + HexStr(jcStartOfFeature, 8) + ') or end of features (0x' + HexStr(jcEndOfFeatures, 8) + ') marker');
         end;
      end;
   end;
   Value := Journal.ReadCardinal();
   if (Value <> jcEndOfFeatures) then
   begin
      raise EJournalError.Create('missing end of features marker (0x' + HexStr(jcEndOfFeatures, 8) + ') while reading asset with class "' + Name + '", instead read 0x' + HexStr(Value, 8));
   end;
end;

procedure TAssetClass.ApplyFeatureNodesFromJournal(Journal: TJournalReader; AssetNode: TAssetNode);
var
   Index: Cardinal;
   Value: Cardinal;
begin
   if (Length(FFeatures) > 0) then
   begin
      for Index := Low(FFeatures) to High(FFeatures) do // $R-
      begin
         case (Journal.ReadCardinal()) of
            jcStartOfFeature:
               begin
                  AssetNode.Features[Index].ApplyJournal(Journal);
                  if (Journal.ReadCardinal() <> jcEndOfFeature) then
                  begin
                     raise EJournalError.Create('missing end of feature marker (0x' + HexStr(jcEndOfFeature, 8) + ')');
                  end;
               end;
            jcEndOfFeatures:
               exit;
            else
               raise EJournalError.Create('missing start of feature (0x' + HexStr(jcStartOfFeature, 8) + ') or end of features (0x' + HexStr(jcEndOfFeatures, 8) + ') marker');
         end;
      end;
   end;
   Value := Journal.ReadCardinal();
   if (Value <> jcEndOfFeatures) then
   begin
      raise EJournalError.Create('missing end of features marker (0x' + HexStr(jcEndOfFeatures, 8) + '), instead read 0x' + HexStr(Value, 8));
   end;
end;

function TAssetClass.Spawn(AOwner: TDynasty; ASystem: TSystem): TAssetNode;
begin
   Result := TAssetNode.Create(ASystem, Self, AOwner, SpawnFeatureNodes(ASystem));
end;

function TAssetClass.Spawn(AOwner: TDynasty; ASystem: TSystem; AFeatures: TFeatureNode.TArray): TAssetNode;
begin
   Result := TAssetNode.Create(ASystem, Self, AOwner, AFeatures);
end;

procedure TAssetClass.Serialize(Writer: TStringStreamWriter);
begin
   Writer.WriteLongint(FID);
   Writer.WriteString(FIcon);
   Writer.WriteString(FName);
   Writer.WriteString(FDescription);
end;

procedure TAssetClass.Serialize(Writer: TServerStreamWriter);
begin
   if (Writer.WriteAssetClassID(FID)) then
   begin
      Writer.WriteStringReference(FIcon);
      Writer.WriteStringReference(FName);
      Writer.WriteStringReference(FDescription);
   end;
end;

procedure TAssetClass.SerializeFor(AssetNode: TAssetNode; DynastyIndex: Cardinal; Writer: TServerStreamWriter);
var
   Visibility: TVisibility;
   Detectable, Recognizable: Boolean;
   ReportedIcon, ReportedName, ReportedDescription: UTF8String;
begin
   Visibility := AssetNode.ReadVisibilityFor(DynastyIndex);
   Detectable := dmDetectable * Visibility <> [];
   Recognizable := dmClassKnown in Visibility;
   // TODO: optionally get the description from the node rather than the class
   // TODO: e.g. planets and planetary regions should self-describe rather than using the region class description
   if (Detectable and Recognizable) then
   begin
      Serialize(Writer);
   end
   else
   begin
      if (Detectable) then
      begin
         Assert(not Recognizable);
         ReportedIcon := FIcon;
         ReportedName := FAmbiguousName;
         ReportedDescription := 'Unknown object type.';
      end
      else
      begin
         Assert(dmInference in Visibility); // otherwise how else can we get here?
         ReportedIcon := UnknownIcon;
         ReportedName := 'Unknown';
         ReportedDescription := 'We can infer that something must be here, but cannot detect it.';
      end;
      Writer.WriteInt32(0);
      Writer.WriteStringReference(ReportedIcon);
      Writer.WriteStringReference(ReportedName);
      Assert(ReportedDescription <> '');
      Writer.WriteStringReference(ReportedDescription);
   end;
end;

function TAssetClass.CanBuild(BuildEnvironment: TBuildEnvironment): Boolean;
begin
   Result := BuildEnvironment in FBuildEnvironments;
end;


constructor TAssetNode.Create(ASystem: TSystem; AAssetClass: TAssetClass; AOwner: TDynasty; AFeatures: TFeatureNode.TArray);
var
   Feature: TFeatureNode;
begin
   inherited Create();
   Assert(Assigned(ASystem));
   try
      FSystem := ASystem;
      FAssetClass := AAssetClass;
      FOwner := AOwner;
      if (Assigned(FOwner)) then
         FOwner.IncRef();
      Assert(Length(AFeatures) = FAssetClass.FeatureCount);
      FFeatures := AFeatures;
      for Feature in FFeatures do
         Feature.SetParent(Self);
      FDirty := dkNewNode;
   except
      ReportCurrentException();
      raise;
   end;
   Assert(Assigned(FAssetClass));
end;

constructor TAssetNode.CreateFromJournal(ASystem: TSystem);
begin
   inherited Create();
   Assert(Assigned(ASystem));
   FSystem := ASystem;
   Assert(not Assigned(FAssetClass));
end;

procedure TAssetNode.InitFromJournal(Journal: TJournalReader);
begin
   Assert(not Assigned(FAssetClass));
   ApplyJournal(Journal);
   FDirty := dkNewNode;
   Assert(Assigned(FAssetClass));
end;

constructor TAssetNode.Create();
begin
   Writeln('Invalid constructor call for ', ClassName, '.');
   raise Exception.Create('Invalid constructor call');
end;

destructor TAssetNode.Destroy();
var
   OldFeatures: TFeatureNode.TArray;
   Feature: TFeatureNode;
begin
   OldFeatures := FFeatures;
   SetLength(FFeatures, 0);
   for Feature in OldFeatures do
      Feature.Free();
   if (Assigned(Parent)) then // TODO: should move this above the features getting destroyed, then move all features' Destroy logic into Detaching
      Parent.DropChild(Self);
   inherited;
end;

procedure TAssetNode.Become(AAssetClass: TAssetClass);
var
   Children: TAssetNode.TPlasticArray;

   function CollectChildren(Child: TAssetNode): Boolean;
   begin
      if (Child <> Self) then
      begin
         Children.Push(Child);
         Result := False;
      end
      else
         Result := True;
   end;

var
   Child: TAssetNode;
   Feature: TFeatureNode;
begin
   Walk(@CollectChildren, nil);
   for Child in Children do
   begin
      Child.ReportPermanentlyGone();
      Child.Parent.DropChild(Child);
      FreeAndNil(Child);
   end;
   FAssetClass := AAssetClass;
   for Feature in FFeatures do
      System.Server.ScheduleDemolition(Feature);
   FFeatures := AssetClass.SpawnFeatureNodes(System);
   for Feature in FFeatures do
      Feature.SetParent(Self);
   MarkAsDirty(dkIdentityChanged);
end;

procedure TAssetNode.ReportPermanentlyGone();

   function PropagateToChildren(Child: TAssetNode): Boolean;
   begin
      if (Child <> Self) then
      begin
         Child.ReportPermanentlyGone();
         Result := False;
      end
      else
         Result := True;
   end;

var
   Message: TAssetGoingAway;
   Injected: TInjectBusMessageResult;
begin
   if (Assigned(FOwner)) then
      FOwner.DecRef();
   Message := TAssetGoingAway.Create(Self);
   Injected := InjectBusMessage(Message);
   Assert(Injected = irInjected, 'TAssetGoingAway should always be injected but not marked handled.');
   FreeAndNil(Message);
   System.ReportChildIsPermanentlyGone(Self);
   Walk(@PropagateToChildren, nil);
end;

function TAssetNode.GetFeatureByClass(FeatureClass: FeatureClassReference): TFeatureNode;
var
   Index: Cardinal;
begin
   Assert(AssetClass.FeatureCount > 0); // at a minimum you need a feature to give the asset a size
   for Index := 0 to AssetClass.FeatureCount - 1 do // $R-
   begin
      if (AssetClass.Features[Index] is FeatureClass) then
      begin
         Result := FFeatures[Index];
         exit;
      end;
   end;
   Result := nil;
end;

function TAssetNode.GetFeature(Index: Cardinal): TFeatureNode;
begin
   Result := FFeatures[Index];
end;

function TAssetNode.GetMass(): Double; // kg
var
   Feature: TFeatureNode;
begin
   Result := 0.0;
   for Feature in FFeatures do
      Result := Result + Feature.Mass;
end;

function TAssetNode.GetMassFlowRate(): TRate; // kg/s
var
   Rate: TRate;
   Feature: TFeatureNode;
   {$IFOPT C+}
   DebugFeatures: array of UTF8String;
   Line: UTF8String;
   {$ENDIF}
begin
   Result := TRate.Zero;
   {$IFOPT C+} DebugFeatures := []; {$ENDIF}
   for Feature in FFeatures do
   begin
      Rate := Feature.MassFlowRate;
      Result := Result + Rate;
      {$IFOPT C+}
      //if (Rate.IsNotZero) then
      begin
         SetLength(DebugFeatures, Length(DebugFeatures) + 1);
         DebugFeatures[High(DebugFeatures)] := Feature.ClassName + ': ' + Rate.ToString('kg');
      end;
      {$ENDIF}
   end;
   {$IFOPT C+}
   if (Result.IsNotZero) then
   begin
      if (Length(DebugFeatures) > 1) then
      begin
         Writeln('! ', DebugName, ' has mass flow rate ', Result.ToString('kg'), ' coming from:');
         for Line in DebugFeatures do
         begin
            Writeln('!    ', Line);
         end;
      end
      else
      if (Length(DebugFeatures) > 0) then
      begin
         Writeln('! ', DebugName, ' has mass flow rate ', Result.ToString('kg'), ' coming from ', DebugFeatures[0]);
      end;
   end;
   {$ENDIF}
end;

function TAssetNode.GetSize(): Double; // m
var
   Feature: TFeatureNode;
   Candidate: Double;
begin
   Result := 0.0;
   for Feature in FFeatures do
   begin
      Candidate := Feature.Size;
      if (Candidate > Result) then
         Result := Candidate;
   end;
end;

function TAssetNode.GetDensity(): Double;
var
   Radius: Double;
begin
   Radius := Size / 2.0;
   Assert(Radius > 0);
   Result := Mass / (4.0 / 3.0 * Pi * Radius * Radius * Radius); // $R-
end;

function TAssetNode.GetAssetName(): UTF8String;
var
   Feature: TFeatureNode;
begin
   for Feature in FFeatures do
   begin
      if (Feature is IAssetNameProvider) then
      begin
         Result := (Feature as IAssetNameProvider).GetAssetName();
         exit;
      end;
   end;
   Result := '';
end;

function TAssetNode.GetAssetOrClassName(): UTF8String;
begin
   Result := AssetName;
   if (Result = '') then
      Result := AssetClass.Name;
end;

function TAssetNode.GetHappiness(): Double;
var
   Feature: TFeatureNode;
begin
   Result := 0.0;
   for Feature in FFeatures do
      Result := Result + Feature.Happiness;
end;

procedure TAssetNode.MarkAsDirty(DirtyKinds: TDirtyKinds);
var
   Feature: TFeatureNode;
   NewFlags: TDirtyKinds;
begin
   Assert(not (dkJournalNew in DirtyKinds));
   Assert(not (dkVisibilityNew in DirtyKinds));
   if (DirtyKinds - FDirty <> []) then
   begin
      NewFlags := DirtyKinds - FDirty;
      FDirty := FDirty + DirtyKinds;
      for Feature in FFeatures do
         Feature.ParentMarkedAsDirty(FDirty, NewFlags); // might call us re-entrantly // TODO: can this just return what needs to change?
      if (IsAttached and (dkHappinessChanged in NewFlags) and Assigned(Owner)) then
         System.ScoreChangedFor(Owner);
      if (HasParent) then
         Parent.MarkAsDirty(UpdateDirtyKindsForAncestor(DirtyKinds));
   end;
end;

procedure TAssetNode.Walk(PreCallback: TPreWalkCallback; PostCallback: TPostWalkCallback);
var
   Feature: TFeatureNode;
begin
   if ((not Assigned(PreCallback)) or PreCallback(Self)) then
      for Feature in FFeatures do
         Feature.Walk(PreCallback, PostCallback);
   if (Assigned(PostCallback)) then
      PostCallback(Self);
end;

function TAssetNode.InjectBusMessage(Message: TBusMessage): TInjectBusMessageResult;
var
   Feature: TFeatureNode;
   Handled: Boolean;
begin
   for Feature in FFeatures do
   begin
      Result := Feature.ManageBusMessage(Message);
      if (Result <> irDeferred) then
      begin
         exit;
      end;
   end;
   if (HasParent) then
   begin
      Result := Parent.InjectBusMessage(Message);
   end
   else
   begin
      if (Message is TAssetManagementBusMessage) then
      begin
         Handled := HandleBusMessage(Message);
         Assert(not Handled, 'TAssetManagementBusMessages should not be marked as handled');
         Result := irInjected;
      end
      else
      begin
         Result := irRejected;
      end;
   end;
end;

function TAssetNode.HandleBusMessage(Message: TBusMessage): Boolean;
var
   Feature: TFeatureNode;
begin
   if (System.Encyclopedia.HandleBusMessage(Self, Message)) then
   begin
      Result := False;
      exit;
   end;
   for Feature in FFeatures do
   begin
      Result := Feature.HandleBusMessage(Message); // propagates message down the tree
      if (Result) then
         exit;
   end;
   Result := False;
end;

procedure TAssetNode.ResetDynastyNotes(OldDynasties: TDynastyIndexHashTable; NewDynasties: TDynasty.TArray);
var
   Dynasty: TDynasty;
   Feature: TFeatureNode;
   Source, Target: TDynastyNotesPackage.PDynastyNotesArray;
   Index: Cardinal;
begin
   if (Assigned(OldDynasties)) then
   begin
      if (OldDynasties.Count >= TDynastyNotesPackage.LongThreshold) then
      begin
         Source := FDynastyNotes.AsLongDynasties;
      end
      else
      begin
         Source := TDynastyNotesPackage.PDynastyNotesArray(@FDynastyNotes.AsShortDynasties);
      end;
   end;
   if (Length(NewDynasties) >= TDynastyNotesPackage.LongThreshold) then
   begin
      Target := System.AllocateFromDynastyNotesArena(SizeOf(TDynastyNotes) * Length(NewDynasties));
      FDynastyNotes.AsLongDynasties := Target;
   end
   else
   begin
      Target := TDynastyNotesPackage.PDynastyNotesArray(@FDynastyNotes.AsShortDynasties);
   end;
   Index := 0;
   for Dynasty in NewDynasties do
   begin
      if (Assigned(OldDynasties) and OldDynasties.Has(Dynasty) and Source^[OldDynasties[Dynasty]].HasID) then
      begin
         Target^[Index].InitFrom(Source^[OldDynasties[Dynasty]]);
      end
      else
      begin
         Target^[Index].Init(0);
      end;
      Inc(Index);
   end;
   for Feature in FFeatures do
      Feature.ResetDynastyNotes(OldDynasties, NewDynasties);
end;

procedure TAssetNode.ResetVisibility();
var
   Feature: TFeatureNode;
   Target: TDynastyNotesPackage.PDynastyNotesArray;
   Index, Count: Cardinal;
begin
   if (System.IsLongVisibilityMode) then
   begin
      Target := FDynastyNotes.AsLongDynasties;
   end
   else
   begin
      Target := TDynastyNotesPackage.PDynastyNotesArray(@FDynastyNotes.AsShortDynasties);
   end;
   Count := System.DynastyCount;
   if (Count > 0) then
   begin
      for Index := 0 to Count - 1 do // $R-
      begin
         Target^[Index].Snapshot();
      end;
   end;
   for Feature in FFeatures do
      Feature.ResetVisibility();
end;

procedure TAssetNode.ApplyVisibility();
var
   Feature: TFeatureNode;
begin
   if (Assigned(FOwner)) then
      System.AddSpecificVisibility(FOwner, dmOwnership, Self);
   for Feature in FFeatures do
      Feature.ApplyVisibility();
end;

procedure TAssetNode.HandleVisibility(const DynastyIndex: Cardinal; var Visibility: TVisibility);
var
   Feature: TFeatureNode;
begin
   Assert((not Assigned(Owner)) or (System.DynastyIndex[Owner] = DynastyIndex) or IsReal());
   for Feature in FFeatures do
      Feature.HandleVisibility(DynastyIndex, Visibility);
   if (Visibility <> []) then
      System.AddSpecificVisibilityByIndex(DynastyIndex, Visibility, Self);
end;

procedure TAssetNode.CheckVisibilityChanged();

   function HandleChanged(const DynastyIndex: Cardinal; var Notes: TDynastyNotes): Boolean;
   begin
      Result := Notes.Changed;
      if (Result) then
      begin
         if (Notes.Visibility = dmNil) then
         begin
            if (Notes.HasID) then
            begin
               Notes.AssetID := 0;
            end;
         end
         else
         begin
            if (not Notes.HasID) then
            begin
               Assert(System.FDynastyMaxAssetIDs[DynastyIndex] < High(TAssetID)); // TODO: re-use expired IDs! (but not on some update!)
               Inc(System.FDynastyMaxAssetIDs[DynastyIndex]);
               Notes.AssetID := System.FDynastyMaxAssetIDs[DynastyIndex];
            end;
         end;
      end;
   end;

var
   DynastyIndex: Cardinal;
   Changed: Boolean;
   Feature: TFeatureNode;
begin
   for Feature in FFeatures do
      Feature.CheckVisibilityChanged();
   if (System.DynastyCount > 0) then
   begin
      Changed := False;
      for DynastyIndex := 0 to System.DynastyCount - 1 do // $R-
      begin
         if (System.IsLongVisibilityMode) then
         begin
            Changed := HandleChanged(DynastyIndex, FDynastyNotes.AsLongDynasties^[DynastyIndex]) or Changed;
         end
         else
         begin
            Changed := HandleChanged(DynastyIndex, FDynastyNotes.AsShortDynasties[DynastyIndex]) or Changed;
         end;
      end;
      if (Changed) then
      begin
         MarkAsDirty([dkUpdateClients, dkVisibilityDidChange]);
      end;
   end;
end;

procedure TAssetNode.ApplyKnowledge();
var
   Feature: TFeatureNode;
begin
   for Feature in FFeatures do
      Feature.ApplyKnowledge();
end;

procedure TAssetNode.HandleKnowledge(const DynastyIndex: Cardinal; const Sensors: ISensorsProvider);
var
   Feature: TFeatureNode;
begin
   if (Sensors.Knows(AssetClass)) then
   begin
      System.AddSpecificVisibilityByIndex(DynastyIndex, [dmClassKnown], Self);
   end;
   for Feature in FFeatures do
      Feature.HandleKnowledge(DynastyIndex, Sensors);
end;

function TAssetNode.ReadVisibilityFor(DynastyIndex: Cardinal): TVisibility;
begin
   if (System.IsLongVisibilityMode) then
   begin
      Result := FDynastyNotes.AsLongDynasties^[DynastyIndex].Visibility;
   end
   else
   begin
      Result := FDynastyNotes.AsShortDynasties[DynastyIndex].Visibility;
   end;
end;

function TAssetNode.IsVisibleFor(DynastyIndex: Cardinal): Boolean;
begin
   Result := ReadVisibilityFor(DynastyIndex) <> [];
end;

procedure TAssetNode.HandleChanges();
var
   Feature: TFeatureNode;
begin
   for Feature in FFeatures do
      Feature.HandleChanges();
end;

procedure TAssetNode.Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter);
var
   Feature: TFeatureNode;
begin
   if (IsVisibleFor(DynastyIndex)) then
   begin
      Writer.WriteCardinal(ID(DynastyIndex));
      if (Assigned(FOwner)) then
      begin
         Writer.WriteCardinal(FOwner.DynastyID);
      end
      else
      begin
         Writer.WriteCardinal(0);
      end;
      Assert(Mass >= -0.000001);
      Writer.WriteDouble(Mass);
      Writer.WriteDouble(MassFlowRate.AsDouble);
      Assert(Size >= 0.0);
      Writer.WriteDouble(Size);
      Writer.WriteStringReference(AssetName);
      AssetClass.SerializeFor(Self, DynastyIndex, Writer);
      for Feature in FFeatures do
         Feature.Serialize(DynastyIndex, Writer);
      Writer.WriteCardinal(fcTerminator);
   end;
end;

procedure TAssetNode.UpdateJournal(Journal: TJournalWriter);
var
   Feature: TFeatureNode;
begin
   if (dkJournalNew in Dirty) then
   begin
      Assert(dkUpdateJournal in Dirty);
      Journal.WriteCardinal(jcNewAsset);
   end
   else
   begin
      Journal.WriteCardinal(jcAssetChange);
   end;
   Journal.WriteAssetNodeReference(Self);
   Journal.WriteAssetClassReference(AssetClass);
   Journal.WriteDynastyReference(FOwner);
   for Feature in FFeatures do
   begin
      Journal.WriteCardinal(jcStartOfFeature);
      Feature.UpdateJournal(Journal);
      Journal.WriteCardinal(jcEndOfFeature);
   end;
   Journal.WriteCardinal(jcEndOfFeatures);
   Journal.WriteCardinal(jcEndOfAsset);
end;

procedure TAssetNode.ApplyJournal(Journal: TJournalReader);
var
   OldAssetClass: TAssetClass;
   Feature: TFeatureNode;
   SpawnFeatures: Boolean;
begin
   OldAssetClass := AssetClass;
   FAssetClass := Journal.ReadAssetClassReference();
   SpawnFeatures := AssetClass <> OldAssetClass;
   FOwner := Journal.ReadDynastyReference(); // IncRef/DecRef is done in TSystem.ApplyJournal
   if (SpawnFeatures) then
   begin
      if (Length(FFeatures) > 0) then
      begin
         for Feature in FFeatures do
         begin
            Feature.Free();
         end;
      end;
      FFeatures := AssetClass.SpawnFeatureNodesFromJournal(Journal, System);
      for Feature in FFeatures do
      begin
         Feature.SetParent(Self);
      end;
   end
   else
   begin
      AssetClass.ApplyFeatureNodesFromJournal(Journal, Self);
   end;
   if (Journal.ReadCardinal() <> jcEndOfAsset) then
   begin
      raise EJournalError.Create('missing end of asset marker (0x' + HexStr(jcEndOfAsset, 8) + ')');
   end;
end;

function TAssetNode.ID(DynastyIndex: Cardinal; AllowZero: Boolean = False): TAssetID;
begin
   Assert(Assigned(System));
   if (System.IsLongVisibilityMode) then
   begin
      Result := FDynastyNotes.AsLongDynasties^[DynastyIndex].AssetID;
   end
   else
   begin
      Result := FDynastyNotes.AsShortDynasties[DynastyIndex].AssetID;
   end;
   Assert(AllowZero or (Result > 0), 'Was forced to report a zero asset ID despite zero not being allowed in this context');
end;

procedure TAssetNode.SetParent(AParent: TFeatureNode);

   procedure Attach(Asset: TAssetNode);
   var
      Feature: TFeatureNode;
   begin
      Asset.FParent := Asset.FParent or AttachedBit;
      for Feature in Asset.FFeatures do
         Feature.Attaching();
      if (Asset.Dirty <> []) then
      begin
         Asset.Parent.MarkAsDirty(UpdateDirtyKindsForAncestor(Asset.Dirty));
      end;
   end;

   procedure Detach(Asset: TAssetNode);
   var
      Feature: TFeatureNode;
   begin
      Asset.FParent := Asset.FParent and not AttachedBit;
      for Feature in Asset.FFeatures do
         Feature.Detaching();
   end;

begin
   Assert(HasParent <> Assigned(AParent)); // must be dropped being before claimed
   if (IsAttached) then
      Walk(nil, @Detach);
   FParent := PtrUInt(AParent);
   if (Assigned(AParent) and Parent.IsAttached) then
   begin
      FParent := FParent or AttachedBit;
      Walk(nil, @Attach);
   end;
end;

function TAssetNode.GetHasParent(): Boolean;
begin
   Result := FParent <> 0;
end;

function TAssetNode.GetParent(): TFeatureNode;
begin
   Result := TFeatureNode(FParent and not AttachedBit);
end;

function TAssetNode.GetIsAttached(): Boolean;
begin
   Result := FParent and AttachedBit > 0;
end;

procedure TAssetNode.SetOwner(NewOwner: TDynasty);
var
   OldOwner: TDynasty;
begin
   Assert(NewOwner <> FOwner);
   OldOwner := FOwner;
   if (Assigned(FOwner)) then
   begin
      FOwner.DecRef();
   end;
   if (not System.HasDynasty(NewOwner)) then
      MarkAsDirty([dkAffectsDynastyCount]);
   FOwner := NewOwner;
   if (not System.HasDynasty(OldOwner)) then
      MarkAsDirty([dkAffectsDynastyCount]);
   if (Assigned(FOwner)) then
   begin
      FOwner.IncRef();
   end;
end;

procedure TAssetNode.UpdateID(DynastyIndex: Cardinal; ID: TAssetID);
begin
   if (System.IsLongVisibilityMode) then
   begin
      FDynastyNotes.AsLongDynasties^[DynastyIndex].AssetID := ID;
   end
   else
   begin
      FDynastyNotes.AsShortDynasties[DynastyIndex].AssetID := ID;
   end;
end;

function TAssetNode.GetSystem(): TSystem;
begin
   Assert(Assigned(FSystem));
   Result := FSystem;
end;

procedure TAssetNode.HandleCommand(Command: UTF8String; var Message: TMessage);
var
   Feature: TFeatureNode;
begin
   for Feature in FFeatures do
   begin
      if (Feature.HandleCommand(Command, Message)) then
         exit;
   end;
end;

function TAssetNode.IsReal(): Boolean;
var
   IsDefinitelyReal, IsDefinitelyGhost, HaveAnswer: Boolean;
   Feature: TFeatureNode;
begin
   {$IFOPT C-} {$IFDEF VERBOSE} {$FATAL Can't be verbose without asserts.} {$ENDIF} {$ENDIF}
   HaveAnswer := False;
   IsDefinitelyReal := False;
   IsDefinitelyGhost := False;
   {$IFDEF VERBOSE} Writeln(DebugName, ' existentiality report:'); {$ENDIF}
   for Feature in FFeatures do
   begin
      Feature.DescribeExistentiality(IsDefinitelyReal, IsDefinitelyGhost);
      {$IFDEF VERBOSE} Writeln('  ', Feature.ClassName, ': ', IsDefinitelyReal, ' ', IsDefinitelyGhost); {$ENDIF}
      Assert((not IsDefinitelyReal) or (not IsDefinitelyGhost));
      if (IsDefinitelyReal) then
      begin
         Assert((not HaveAnswer) or Result, 'This asset is having an existential crisis: ' + DebugName); {BOGUS Warning: Function result variable does not seem to be initialized}
         Result := True;
         HaveAnswer := True;
      end
      else
      if (IsDefinitelyGhost) then
      begin
         Assert((not HaveAnswer) or not Result, 'This asset is having an existential crisis: ' + DebugName); {BOGUS Warning: Function result variable does not seem to be initialized}
         Assert(Mass = 0, DebugName + ' has mass but is definitely real according to ' + Feature.ClassName);
         Result := False;
         HaveAnswer := True;
      end;
      {$IFOPT C-}
      if (HaveAnswer) then
         exit;
      {$ELSE}
      IsDefinitelyReal := False;
      IsDefinitelyGhost := False;
      {$ENDIF}
   end;
   {$IFOPT C+} if (not HaveAnswer) then {$ENDIF}
      Result := True;
   {$IFDEF VERBOSE} Writeln('  Conclusion: ', Result); {$ENDIF}
end;

function TAssetNode.GetDebugName(): UTF8String;
begin
   Result := '<' + AssetClass.Name + ' @' + HexStr(Self);
   if (AssetName <> '') then
      Result := Result + ' "' + AssetName + '"';
   if (Assigned(Owner)) then
      Result := Result + ' of dynasty ' + IntToStr(Owner.DynastyID);
   Result := Result + '>';
end;


constructor TSystem.Create(AConfigurationDirectory: UTF8String; ASystemID: Cardinal; AX, AY: Double; ARootClass: TAssetClass; AServer: TBaseServer; ADynastyDatabase: TDynastyDatabase; AEncyclopedia: TEncyclopediaView; Settings: PSettings; AOnScoreDirty: TScoreDirtyCallback);
begin
   inherited Create();
   Init(AConfigurationDirectory, ASystemID, ARootClass, AServer, ADynastyDatabase, AEncyclopedia, AOnScoreDirty);
   FX := AX;
   FY := AY;
   FTimeOrigin := FServer.Clock.Now() - 0; // 0 is the age of the system so far
   FTimeFactor := Settings^.DefaultTimeRate;
   try
      Assert(not DirectoryExists(FConfigurationDirectory));
      MkDir(FConfigurationDirectory);
   except
      ReportCurrentException();
      raise;
   end;
   OpenJournal(FConfigurationDirectory + JournalDatabaseFileName); // This walks the entire tree, updates everything, writes it all to the journal, and cleans the dirty flags.
end;

constructor TSystem.CreateFromDisk(AConfigurationDirectory: UTF8String; ASystemID: Cardinal; ARootClass: TAssetClass; AServer: TBaseServer; ADynastyDatabase: TDynastyDatabase; AEncyclopedia: TEncyclopediaView; AOnScoreDirty: TScoreDirtyCallback);
begin
   Writeln('Recreating system ', ASystemID, ' from journal...');
   Init(AConfigurationDirectory, ASystemID, ARootClass, AServer, ADynastyDatabase, AEncyclopedia, AOnScoreDirty);
   ApplyJournal(FConfigurationDirectory + JournalDatabaseFileName);
   OpenJournal(FConfigurationDirectory + JournalDatabaseFileName); // This walks the entire tree, updates everything, writes it all to the journal, and cleans the dirty flags.
end;

procedure TSystem.Init(AConfigurationDirectory: UTF8String; ASystemID: Cardinal; ARootClass: TAssetClass; AServer: TBaseServer; ADynastyDatabase: TDynastyDatabase; AEncyclopedia: TEncyclopediaView; AOnScoreDirty: TScoreDirtyCallback);
begin
   FConfigurationDirectory := AConfigurationDirectory;
   FSystemID := ASystemID;
   FRandomNumberGenerator := TRandomNumberGenerator.Create(FSystemID);
   FServer := AServer;
   FDynastyDatabase := ADynastyDatabase;
   FDynastyIndices := TDynastyIndexHashTable.Create();
   FScheduledEvents := TSystemEventSet.Create();
   FCurrentEventTime := TTimeInMilliseconds.Infinity;
   FLastTime := TTimeInMilliseconds.NegInfinity;
   FEncyclopedia := AEncyclopedia;
   FOnScoreDirty := AOnScoreDirty;
   FRoot := TRootAssetNode.Create(Self, ARootClass, nil, ARootClass.SpawnFeatureNodes(Self));
   Exclude(FRoot.FDirty, dkJournalNew); // we always create this node ourselves, even when reading from the journal, so don't tell the journal to create it
   FChanges := dkAffectsTreeStructure + UpdateDirtyKindsForAncestor(FRoot.Dirty);
end;

destructor TSystem.Destroy();
begin
   if (Assigned(FJournalWriter)) then
   begin
      FJournalWriter.Free();
      Close(FJournalFile);
   end;
   FRoot.Free();
   Assert(FScheduledEvents.IsEmpty);
   FScheduledEvents.Free();
   FDynastyIndices.Free();
   UnwindDynastyNotesArenas(FDynastyNotesBuffer);
   FRandomNumberGenerator.Free();
   inherited;
end;

procedure TSystem.ApplyJournal(FileName: UTF8String);

   procedure IncRefDynasties(Child: TAssetNode);
   begin
      if (Assigned(Child.Owner)) then
         Child.Owner.IncRef();
   end;

var
   JournalReader: TJournalReader;
   ID: PtrUInt;
   Asset: TAssetNode;
   Code, Index: Cardinal;
   AssetID: TAssetID;
   Orphans: TAssetNode.TPlasticArray;
begin
   Assign(FJournalFile, FileName);
   FileMode := 0;
   Reset(FJournalFile, 1);
   JournalReader := TJournalReader.Create(Self);
   ID := JournalReader.ReadPtrUInt();
   FX := JournalReader.ReadDouble();
   FY := JournalReader.ReadDouble();
   JournalReader.FAssetMap[ID] := FRoot;
   try
      while (not EOF(FJournalFile)) do
      begin
         Code := JournalReader.ReadCardinal();
         case (Code) of
            jcSystemUpdate: begin
               try
                  FTimeOrigin := FServer.Clock.Now() - TDateTime(JournalReader.ReadDouble());
                  FRandomNumberGenerator.Reset(JournalReader.ReadUInt64());
                  FTimeFactor := TTimeFactor(JournalReader.ReadDouble());
                  RescheduleNextEvent();
               except
                  ReportCurrentException();
                  raise;
               end;
            end;
            jcIDUpdates: begin
               try
                  UpdateDynastyList(False); // the False resets the FDynastyMaxAssetIDs to zero
                  Index := JournalReader.ReadCardinal();
                  if (FDynastyIndices.Count <> Index) then
                     raise EJournalError.CreateFmt('Dynasty count inconsistent (journal=%d, measured=%d)', [Index, FDynastyIndices.Count]);
                  while True do
                  begin
                     Asset := JournalReader.ReadAssetNodeReference(Self);
                     if (not Assigned(Asset)) then
                        break;
                     if (FDynastyIndices.Count > 0) then
                        for Index := 0 to FDynastyIndices.Count - 1 do // $R-
                        begin
                           AssetID := TAssetID(JournalReader.ReadCardinal());
                           Asset.UpdateID(Index, AssetID);
                           if (FDynastyMaxAssetIDs[Index] < AssetID) then
                              FDynastyMaxAssetIDs[Index] := AssetID;
                        end;
                  end;
               except
                  ReportCurrentException();
                  raise;
               end;
            end;
            jcNewAsset: begin
               try
                  Asset := JournalReader.ReadAssetNodeReference(Self);
                  Asset.InitFromJournal(JournalReader);
               except
                  ReportCurrentException();
                  raise;
               end;
            end;
            jcAssetChange: begin
               try
                  Asset := JournalReader.ReadAssetNodeReference(Self);
                  Assert(Assigned(Asset));
                  Asset.ApplyJournal(JournalReader);
               except
                  ReportCurrentException();
                  raise;
               end;
            end;
            jcAssetDestroyed: begin
               try
                  ID := JournalReader.ReadPtrUInt();
                  Asset := JournalReader.FAssetMap[ID];
                  Asset.Parent.DropChild(Asset);
                  Orphans.Push(Asset); // these are freed below
                  JournalReader.FAssetMap.Remove(ID);
                  // we don't have to worry about notifying anyone
                  // else, because the nodes don't have time to set up
                  // relationships while reading the journal; that
                  // happens later during the change updates.
               except
                  ReportCurrentException();
                  raise;
               end;
            end;
         else
            raise EJournalError.Create('Unknown operation code in system journal (0x' + HexStr(Code, 8) + '), expected either new asset (0x' + HexStr(jcNewAsset, 8) + ') or asset change (0x' + HexStr(jcAssetChange, 8) + ') marker');
         end;
      end;
      // Clear orphans.
      for Asset in Orphans do
         Asset.Free();
   finally
      JournalReader.Free();
      Close(FJournalFile);
   end;
   FRoot.Walk(nil, @IncRefDynasties);
end;

procedure TSystem.OpenJournal(FileName: UTF8String);
begin
   try
      Assign(FJournalFile, FileName + TemporaryExtension);
      FileMode := 1;
      Rewrite(FJournalFile, 1);
      FJournalWriter := TJournalWriter.Create(Self);
      FJournalWriter.WriteAssetNodeReference(FRoot);
      FJournalWriter.WriteDouble(FX);
      FJournalWriter.WriteDouble(FY);
      FJournalWriter.WriteCardinal(jcSystemUpdate);
      FJournalWriter.WriteDouble(FServer.Clock.Now() - FTimeOrigin); // age of server
      FJournalWriter.WriteUInt64(FRandomNumberGenerator.State);
      FJournalWriter.WriteDouble(FTimeFactor.AsDouble);
      ReportChanges(); // This walks the entire tree, updates everything, writes it all to the journal, and cleans the dirty flags.
      Close(FJournalFile);
      DeleteFile(FileName);
      RenameFile(FileName + TemporaryExtension, FileName);
      Assign(FJournalFile, FileName);
      FileMode := 2;
      Reset(FJournalFile, 1);
      Seek(FJournalFile, FileSize(FJournalFile));
   except
      ReportCurrentException();
      raise;
   end;
end;

procedure TSystem.RecordUpdate(DynastyCountChanged: Boolean);

   function SkipCleanChildren(Asset: TAssetNode): Boolean;
   begin
      Result := dkDescendantUpdateJournal in Asset.Dirty;
      {$IFOPT C+}
      Exclude(Asset.FDirty, dkDescendantUpdateJournal);
      {$ENDIF}
   end;

   procedure RecordDirtyAsset(Asset: TAssetNode);
   begin
      if (dkUpdateJournal in Asset.Dirty) then
      begin
         Asset.UpdateJournal(Journal);
         {$IFOPT C+}
         Exclude(Asset.FDirty, dkJournalNew);
         Exclude(Asset.FDirty, dkUpdateJournal);
         {$ENDIF}
      end;
   end;

   function RecordAssetIDs(Asset: TAssetNode): Boolean;
   var
      Dynasty: TDynasty;
   begin
      Assert(not (dkJournalNew in Asset.Dirty));
      Assert(not (dkUpdateJournal in Asset.Dirty));
      Assert(not (dkDescendantUpdateJournal in Asset.Dirty));
      Journal.WriteAssetNodeReference(Asset);
      for Dynasty in FDynastyIndices do
      begin
         Journal.WriteCardinal(Asset.ID(FDynastyIndices[Dynasty], True {AllowZero}));
      end;
      Result := True;
   end;

begin
   Journal.WriteCardinal(jcSystemUpdate);
   Journal.WriteDouble(FServer.Clock.Now() - FTimeOrigin); // age of server
   Journal.WriteUInt64(FRandomNumberGenerator.State);
   Journal.WriteDouble(FTimeFactor.AsDouble);
   // TODO: consider tracking FLastTime as well
   FRoot.Walk(@SkipCleanChildren, @RecordDirtyAsset);
   if (DynastyCountChanged) then
   begin
      Journal.WriteCardinal(jcIDUpdates);
      Journal.WriteCardinal(FDynastyIndices.Count); // sanity check
      FRoot.Walk(@RecordAssetIDs, nil);
      Journal.WriteUInt64(0);
   end;
end;

procedure TSystem.ReportChildIsPermanentlyGone(Child: TAssetNode);
begin
   Journal.WriteCardinal(jcAssetDestroyed);
   Journal.WriteAssetNodeReference(Child);
end;

procedure TSystem.MarkAsDirty(DirtyKinds: TDirtyKinds);
begin
   Assert(not (dkNeedsHandleChanges in DirtyKinds)); // should be converted to dkDescendantNeedsHandleChanges by now
   FChanges := FChanges + DirtyKinds;
end;

function TSystem.GetDirty(): Boolean;
begin
   Result := FRoot.Dirty <> [];
end;

function TSystem.SerializeSystem(Dynasty: TDynasty; Writer: TServerStreamWriter; DirtyOnly: Boolean): Boolean;
var
   FoundASelfDirty: Boolean;
   CachedDynastyIndex: Cardinal;

   function Serialize(Asset: TAssetNode): Boolean;
   var
      Visibility: TVisibility;
   begin
      Visibility := Asset.ReadVisibilityFor(CachedDynastyIndex);
      if (Visibility <> []) then
      begin
         if ((dkUpdateClients in Asset.Dirty) or not DirtyOnly) then
         begin
            FoundASelfDirty := True;
            Asset.Serialize(CachedDynastyIndex, Writer);
         end;
         Result := (dkDescendantUpdateClients in Asset.Dirty) or not DirtyOnly;
      end
      else
         Result := False;
   end;

begin
   // This is what we send to clients in a binary frame when there's an update.
   FoundASelfDirty := False;
   Assert(FDynastyIndices.Has(Dynasty));
   CachedDynastyIndex := DynastyIndex[Dynasty];
   Writer.WriteCardinal(SystemID);
   Writer.WriteInt64(Now.AsInt64);
   Writer.WriteDouble(FTimeFactor.AsDouble);
   Writer.WriteCardinal(FRoot.ID(CachedDynastyIndex));
   Writer.WriteDouble(FX);
   Writer.WriteDouble(FY);
   FRoot.Walk(@Serialize, nil);
   Writer.WriteCardinal(0); // asset ID 0 marks end of system
   Result := FoundASelfDirty;
end;

procedure TSystem.Clean();

   function CleanAsset(Asset: TAssetNode): Boolean;
   begin
      Asset.FDirty := [];
      Result := True;
   end;

begin
   FRoot.Walk(@CleanAsset, nil);
   FChanges := [];
end;

function TSystem.GetIsLongVisibilityMode(): Boolean;
begin
   Result := FDynastyIndices.Count >= TDynastyNotesPackage.LongThreshold;
end;

function TSystem.GetDynastyCount(): Cardinal;
begin
   Assert(Assigned(FDynastyIndices));
   Result := FDynastyIndices.Count;
end;

function TSystem.GetDynastyIndex(Dynasty: TDynasty): Cardinal;
begin
   Assert(FDynastyIndices.Has(Dynasty));
   Result := FDynastyIndices.Items[Dynasty];
end;

function TSystem.GetDynastyByIndex(Index: Cardinal): TDynasty;
begin
   Assert(Index < Length(FDynasties));
   Result := FDynasties[Index];
end;

procedure TSystem.UnwindDynastyNotesArenas(Arena: Pointer);
begin
   if (Assigned(Arena)) then
   begin
      UnwindDynastyNotesArenas(Arena + MemSize(Arena) - SizeOf(Pointer));
      FreeMem(Arena);
   end;
end;

function TSystem.AllocateFromDynastyNotesArena(Size: SizeInt): Pointer;
var
   NewBuffer: Pointer;
begin
   // TODO: putting the back pointer at the start of the block instead of the end would simplify the logic
   Assert(Assigned(FDynastyNotesBuffer));
   if (FDynastyNotesOffset + Size > MemSize(FDynastyNotesBuffer) - SizeOf(Pointer)) then
   begin
      NewBuffer := GetMem(MemSize(FDynastyNotesBuffer));
      Assert(MemSize(NewBuffer) mod SizeOf(DWord) = 0);
      FillDWord(NewBuffer^, MemSize(NewBuffer) div SizeOf(DWord), 0); // $R-
      PPointer(NewBuffer + MemSize(NewBuffer) - SizeOf(Pointer))^ := FDynastyNotesBuffer;
      FDynastyNotesBuffer := NewBuffer;
      FDynastyNotesOffset := 0;
   end;
   Result := FDynastyNotesBuffer + FDynastyNotesOffset;
   Inc(FDynastyNotesOffset, Size);
end;

procedure TSystem.ScoreChangedFor(Dynasty: TDynasty);
begin
   FOnScoreDirty(Dynasty);
end;

procedure TSystem.UpdateDynastyList(MaintainMaxIDs: Boolean);
var
   Dynasties: TDynastyHashSet;
   NewDynasties: TDynasty.TArray;
   NodeCount: Cardinal;

   function TrackDynasties(Asset: TAssetNode): Boolean;
   begin
      if (Assigned(Asset.Owner) and not Dynasties.Has(Asset.Owner)) then
         Dynasties.Add(Asset.Owner);
      Inc(NodeCount);
      Result := True;
   end;

   function ResetDynasties(Asset: TAssetNode): Boolean;
   begin
      if (dkVisibilityNew in Asset.Dirty) then
      begin
         Asset.ResetDynastyNotes(nil, NewDynasties);
         Exclude(Asset.FDirty, dkVisibilityNew);
      end
      else
      begin
         Asset.ResetDynastyNotes(FDynastyIndices, NewDynasties);
      end;
      Include(Asset.FDirty, dkUpdateClients);
      Include(Asset.FDirty, dkDescendantUpdateClients);
      Exclude(Asset.FDirty, dkAffectsVisibility);
      Exclude(Asset.FDirty, dkDescendantsVisibilityNew);
      Result := True;
   end;

var
   Index, BufferSize: Cardinal;
   Dynasty: TDynasty;
   OldBuffer: Pointer;
   OldIDs: array of TAssetID;
begin
   NodeCount := 0;
   Dynasties := TDynastyHashSet.Create();
   FRoot.Walk(@TrackDynasties, nil);
   if (Assigned(FDynastyNotesBuffer)) then
   begin
      OldBuffer := FDynastyNotesBuffer;
      FDynastyNotesBuffer := nil;
   end
   else
      OldBuffer := nil;
   if (Dynasties.Count >= TDynastyNotesPackage.LongThreshold) then
   begin
      Assert(SizeOf(TDynastyNotes) = 4);
      Assert(FDynastyIndices.Count * SizeOf(TDynastyNotes) < High(Cardinal) div NodeCount);
      BufferSize := FDynastyIndices.Count * SizeOf(TDynastyNotes) * NodeCount; // $R-
      FDynastyNotesBuffer := GetMem(BufferSize + SizeOf(Pointer)); // $R-
      Assert(MemSize(FDynastyNotesBuffer) mod SizeOf(DWord) = 0);
      FillDWord(FDynastyNotesBuffer^, MemSize(FDynastyNotesBuffer) div SizeOf(DWord), 0); // $R-
      FDynastyNotesOffset := 0;
   end;
   if (MaintainMaxIDs) then
   begin
      OldIDs := FDynastyMaxAssetIDs;
      SetLength(FDynastyMaxAssetIDs, Dynasties.Count);
      Index := 0;
      for Dynasty in Dynasties do
      begin
         if (FDynastyIndices.Has(Dynasty)) then
            FDynastyMaxAssetIDs[Index] := OldIDs[FDynastyIndices[Dynasty]] // here, FDynastyIndices is the old indices still
         else
            FDynastyMaxAssetIDs[Index] := 0;
         Inc(Index);
      end;
   end
   else
   begin
      SetLength(FDynastyMaxAssetIDs, 0);
      SetLength(FDynastyMaxAssetIDs, Dynasties.Count);
   end;
   SetLength(NewDynasties, Dynasties.Count);
   Index := 0;
   for Dynasty in Dynasties do
   begin
      NewDynasties[Index] := Dynasty;
      Inc(Index);
   end;
   FRoot.Walk(@ResetDynasties, nil);
   Include(FChanges, dkDescendantUpdateClients);
   // check that either we didn't use the buffer, or we used all of it:
   Assert(((not Assigned(FDynastyNotesBuffer)) and (FDynastyNotesOffset = 0)) or
          (FDynastyNotesOffset = MemSize(FDynastyNotesBuffer) - SizeOf(Pointer)),
          'FDynastyNotesOffset = ' + IntToStr(PtrUInt(FDynastyNotesBuffer)) + '; MemSize(FDynastyNotesOffset) = ' + IntToStr(MemSize(FDynastyNotesBuffer)));
   if (Assigned(OldBuffer)) then
      UnwindDynastyNotesArenas(OldBuffer);
   FDynasties := NewDynasties;
   FDynastyIndices.Empty();
   Index := 0;
   for Dynasty in FDynasties do
   begin
      FDynastyIndices[Dynasty] := Index; // here we update the FDynastyIndices to the new indices
      Inc(Index);
   end;
   Assert(Index = Dynasties.Count);
   Assert(Index = Length(FDynasties));
   Assert(Index = FDynastyIndices.Count);
   FreeAndNil(Dynasties);
end;

procedure TSystem.RecomputeVisibility(DynastyCountChanged, HaveNewNodes: Boolean);

   function ResetDynastyNotesForNewNodes(Asset: TAssetNode): Boolean;
   begin
      if (dkVisibilityNew in Asset.Dirty) then
      begin
         Asset.ResetDynastyNotes(nil, FDynasties);
         Assert(dkUpdateClients in Asset.Dirty);
         // dkVisibilityNew is removed during ResetVisibility below
      end;
      Result := dkDescendantsVisibilityNew in Asset.Dirty;
      if (Result) then
      begin
         Exclude(Asset.FDirty, dkDescendantsVisibilityNew);
         Include(Asset.FDirty, dkDescendantUpdateClients);
      end;
   end;

   function ResetVisibility(Asset: TAssetNode): Boolean;
   begin
      if (dkVisibilityNew in Asset.Dirty) then
      begin
         Exclude(Asset.FDirty, dkVisibilityNew);
      end
      else
      begin
         Asset.ResetVisibility();
      end;
      Exclude(Asset.FDirty, dkAffectsVisibility);
      Assert(not (dkDescendantsVisibilityNew in Asset.FDirty));
      Result := True;
   end;

   function ApplyVisibility(Asset: TAssetNode): Boolean;
   begin
      Asset.ApplyVisibility();
      Result := True;
   end;

   function CheckVisibility(Asset: TAssetNode): Boolean;
   begin
      Asset.CheckVisibilityChanged();
      Result := True;
   end;

   function ApplyKnowledge(Asset: TAssetNode): Boolean;
   begin
      Asset.ApplyKnowledge();
      Result := True;
   end;

begin
   if (DynastyCountChanged) then
   begin
      UpdateDynastyList(True); // True means we maintain the FDynastyMaxAssetIDs
   end
   else
   begin
      if (HaveNewNodes) then
         FRoot.Walk(@ResetDynastyNotesForNewNodes, nil);
      FRoot.Walk(@ResetVisibility, nil);
   end;
   FRoot.Walk(@ApplyVisibility, nil);
   FRoot.Walk(@ApplyKnowledge, nil);
   FRoot.Walk(@CheckVisibility, nil);
end;

procedure TSystem.ReportChanges();
var
   Dynasty: TDynasty;

   procedure ReportChange(Connection: TBaseIncomingCapableConnection; Writer: Pointer);
   var
      Message: RawByteString;
   begin
      Assert(TServerStreamWriter(Writer).BufferLength = 0);
      SerializeSystem(Dynasty, TServerStreamWriter(Writer), True); // this walks the tree
      Message := TServerStreamWriter(Writer).Serialize(False);
      Connection.WriteFrame(Message[1], Length(Message)); // $R-
      TServerStreamWriter(Writer).Clear();
   end;

   function SkipCleanChildren(Asset: TAssetNode): Boolean;
   begin
      Result := dkDescendantNeedsHandleChanges in Asset.Dirty;
      Exclude(Asset.FDirty, dkDescendantNeedsHandleChanges);
   end;

   procedure HandleChanges(Asset: TAssetNode);
   begin
      if (dkNeedsHandleChanges in Asset.Dirty) then
      begin
         Exclude(Asset.FDirty, dkNeedsHandleChanges);
         Asset.HandleChanges();
      end;
   end;

var
   LastChanges, AllChanges: TDirtyKinds;
   DynastyCountChanged: Boolean;
begin
   if (not Dirty) then
      exit;
   Writeln('== Processing changes for system ', FSystemID, ' (', HexStr(FSystemID, 6), ') ==');
   Assert((dkAffectsVisibility in FChanges) or not (dkAffectsDynastyCount in FChanges)); // dkAffectsDynastyCount requires dkAffectsVisibility
   AllChanges := [];
   repeat
      Writeln('System changes: ', specialize SetToString<TDirtyKinds>(FChanges));
      LastChanges := FChanges;
      AllChanges := AllChanges + FChanges;
      FChanges := [];
      if (dkAffectsVisibility in LastChanges) then
      begin
         Writeln('Recomputing visibility...');
         if (dkAffectsDynastyCount in LastChanges) then
         begin
            Writeln('  dynasty count changed!');
            DynastyCountChanged := True;
         end;
         RecomputeVisibility(dkAffectsDynastyCount in LastChanges, dkDescendantsVisibilityNew in LastChanges);
      end;
      if (dkDescendantNeedsHandleChanges in LastChanges) then
      begin
         Writeln('Handling changes...');
         FRoot.Walk(@SkipCleanChildren, @HandleChanges);
      end;
   until FChanges = [];
   if (dkDescendantUpdateJournal in AllChanges) then
   begin
      Writeln('Updating journal...');
      RecordUpdate(DynastyCountChanged);
   end;
   // TODO: tell the clients if _everything_ stopped being visible
   if (dkDescendantUpdateClients in AllChanges) then
   begin
      Writeln('Updating clients...');
      for Dynasty in FDynasties do
      begin
         Dynasty.ForEachConnection(@ReportChange);
      end;
   end;
   Clean();
   Writeln('Done processing changes.');
end;

function TSystem.HasDynasty(Dynasty: TDynasty): Boolean;
begin
   Result := FDynastyIndices.Has(Dynasty);
end;

function TSystem.SubtreeHasNewDynasty(Child: TAssetNode): Boolean;
var
   FoundAny: Boolean;

   function CheckForNewDynasty(Asset: TAssetNode): Boolean;
   begin
      if (Assigned(Asset.Owner) and not HasDynasty(Asset.Owner)) then
         FoundAny := True;
      Result := FoundAny;
   end;

begin
   FoundAny := False;
   Child.Walk(@CheckForNewDynasty, nil);
   Result := FoundAny;
end;

function TSystem.ComputeScoreFor(Dynasty: TDynasty): Double;

   procedure RecomputeScores(Asset: TAssetNode);
   begin
      if (Asset.Owner = Dynasty) then
         Result := Result + Asset.Happiness;
   end;

begin
   Result := 0.0;
   FRoot.Walk(nil, @RecomputeScores);
end;


procedure TSystem.RunEvent(var Data);
var
   Event: TSystemEvent;
begin
   Writeln('System ', SystemID, ' running event...');
   Event := TSystemEvent(Data);
   Assert(Assigned(Event));
   Assert(FScheduledEvents.Has(Event));
   Assert(FNextEvent = Event);
   Assert(Assigned(FNextEventHandle));
   FScheduledEvents.Remove(Event);
   FNextEvent := SelectNextEvent();
   FNextEventHandle := nil;
   FCurrentEventTime := Event.FTime;
   Assert(FCurrentEventTime >= FLastTime);
   FLastTime := FCurrentEventTime;
   Event.FCallback(Event.FData); // (could call ScheduleEvent and thus set FNextEvent)
   FCurrentEventTime := TTimeInMilliseconds.Infinity;
   FreeAndNil(Event);
   if (Assigned(FNextEvent) and not Assigned(FNextEventHandle)) then
      ScheduleNextEvent();
   Assert(Assigned(FNextEvent) = Assigned(FNextEventHandle));
   Assert(Assigned(FNextEvent) = FScheduledEvents.IsNotEmpty);
end;

procedure TSystem.ScheduleNextEvent();
var
   SystemNow: TTimeInMilliseconds;
   SystemTarget: TTimeInMilliseconds;
   RealDelta: TWallMillisecondsDuration;
begin
   Assert(Assigned(FNextEvent));
   Assert(not Assigned(FNextEventHandle));
   SystemNow := Now;
   SystemTarget := FNextEvent.FTime;
   RealDelta := (SystemTarget - SystemNow) div FTimeFactor;
   FNextEventHandle := FServer.ScheduleEvent(FServer.Clock.Now() + RealDelta, @RunEvent, FNextEvent);
   Assert(Assigned(FNextEvent) = Assigned(FNextEventHandle));
   Assert(Assigned(FNextEvent) = FScheduledEvents.IsNotEmpty);
end;

procedure TSystem.RescheduleNextEvent();
begin
   Assert(Assigned(FNextEvent) = Assigned(FNextEventHandle));
   Assert(Assigned(FNextEvent) = FScheduledEvents.IsNotEmpty);
   if (Assigned(FNextEvent)) then
   begin
      FServer.CancelEvent(FNextEventHandle);
      Assert(not Assigned(FNextEventHandle));
      ScheduleNextEvent();
   end;
   Assert(Assigned(FNextEvent) = Assigned(FNextEventHandle));
   Assert(Assigned(FNextEvent) = FScheduledEvents.IsNotEmpty);
end;

function TSystem.SelectNextEvent(): TSystemEvent;
var
   Event: TSystemEvent;
begin
   Result := nil;
   if (FScheduledEvents.IsNotEmpty) then
   begin
      for Event in FScheduledEvents do
      begin
         if (not Assigned(Result) or (Event.FTime < Result.FTime)) then
            Result := Event;
      end;
   end;
end;

function TSystem.ScheduleEvent(TimeDelta: TMillisecondsDuration; Callback: TEventCallback; var Data): TSystemEvent;
begin
   // Assigned(FNextEvent) and Assigned(FNextEventHandle) might not be in sync here, if we're handling an event and it schedules its own event
   Assert(Assigned(FNextEvent) = FScheduledEvents.IsNotEmpty);
   Result := TSystemEvent.Create(
      Now + TimeDelta,
      Callback,
      Pointer(Data),
      Self
   );
   FScheduledEvents.Add(Result);
   if ((not Assigned(FNextEvent)) or (Result.FTime <= FNextEvent.FTime)) then
   begin
      if (Assigned(FNextEventHandle)) then
      begin
         FServer.CancelEvent(FNextEventHandle);
      end;
      Assert(not Assigned(FNextEventHandle));
      FNextEvent := Result;
      ScheduleNextEvent();
   end;
   Assert(Assigned(FNextEvent) = FScheduledEvents.IsNotEmpty);
end;

procedure TSystem.CancelEvent(Event: TSystemEvent);
begin
   Assert(Assigned(Event));
   Assert(FScheduledEvents.Has(Event));
   FScheduledEvents.Remove(Event);
   if (Event = FNextEvent) then
   begin
      if (Assigned(FNextEventHandle)) then
      begin
         // FNextEventHandle might be nil if we're already handling an event
         FServer.CancelEvent(FNextEventHandle);
      end;
      Assert(not Assigned(FNextEventHandle));
      if (FScheduledEvents.IsNotEmpty) then
      begin
         FNextEvent := SelectNextEvent();
         ScheduleNextEvent();
      end
      else
      begin
         FNextEvent := nil;
      end;
   end;
end;

function TSystem.TimeUntilNext(TimeOrigin: TTimeInMilliseconds; Period: TMillisecondsDuration): TMillisecondsDuration;
begin
   Result := Period - ((Now - TimeOrigin) mod Period);
end;

function TSystem.GetNow(): TTimeInMilliseconds;
begin
   if (FCurrentEventTime.IsInfinite) then
   begin
      Result := TTimeInMilliseconds.FromDurationSinceOrigin(TWallMillisecondsDuration.FromDateTimes(FServer.Clock.Now(), FTimeOrigin) * FTimeFactor);
   end
   else
   begin
      // We do this because otherwise FTimeFactor introduces an error into the current time and we
      // end up running events at slightly the wrong time, which can affect computations.
      Result := FCurrentEventTime;
   end;
   // Ensure that we never go backwards in time.
   // This is not usually a risk but every now and then floating point
   // errors in computing the current time would take us a few
   // milliseconds back from the last event time. (Basically, this is
   // the flip side of why we use FCurrentEventTime, see just above.)
   if (Result < FLastTime) then
      Result := FLastTime;
   FLastTime := Result;
end;

function TSystem.FindCommandTarget(Dynasty: TDynasty; AssetID: TAssetID): TAssetNode;
var
   CachedDynastyIndex: Cardinal;
   FoundAsset: TAssetNode;

   function Search(Asset: TAssetNode): Boolean;
   begin
      // TODO: change this to be that you can send the message so long as you can see it (not necessarily own it)
      if (((not Assigned(Asset.Owner)) or (Asset.Owner = Dynasty)) and (Asset.ID(CachedDynastyIndex, True {AllowZero}) = AssetID)) then
      begin
         FoundAsset := Asset;
      end;
      Result := not Assigned(FoundAsset);
   end;

begin
   if (not HasDynasty(Dynasty)) then
   begin
      Result := nil;
      exit;
   end;
   CachedDynastyIndex := DynastyIndex[Dynasty];
   FoundAsset := nil;
   FRoot.Walk(@Search, nil);
   Result := FoundAsset;
end;

procedure TSystem.AddSpecificVisibilityByIndex(const Index: Cardinal; const Visibility: TVisibility; const Asset: TAssetNode);
var
   Current: TVisibility;
begin
   Assert(Assigned(Asset.Owner) or Asset.IsReal());
   Assert((FDynastyIndices.Items[Asset.Owner] = Index) or Asset.IsReal());
   Assert(Visibility <> []);
   if (IsLongVisibilityMode) then
   begin
      Current := Asset.FDynastyNotes.AsLongDynasties^[Index].Visibility;
      Asset.FDynastyNotes.AsLongDynasties^[Index].Visibility := Current + Visibility;
   end
   else
   begin
      Assert(Index >= Low(Asset.FDynastyNotes.AsShortDynasties));
      Assert(Index <= High(Asset.FDynastyNotes.AsShortDynasties));
      Current := Asset.FDynastyNotes.AsShortDynasties[Index].Visibility;
      Asset.FDynastyNotes.AsShortDynasties[Index].Visibility := Current + Visibility;
   end;
   if ((not (dmInference in Current)) and Assigned(Asset.Parent)) then
   begin
      AddSpecificVisibilityByIndex(Index, [dmInference], Asset.Parent.Parent);
   end;
end;

procedure TSystem.AddSpecificVisibility(const Dynasty: TDynasty; const Visibility: TVisibility; const Asset: TAssetNode);
begin
   AddSpecificVisibilityByIndex(GetDynastyIndex(Dynasty), Visibility, Asset);
end;

procedure TSystem.AddBroadVisibility(const Visibility: TVisibility; const Asset: TAssetNode);
var
   Index, Count: Cardinal;
   Current: TVisibility;
begin
   Assert(Visibility <> []);
   Assert(Assigned(Asset));
   Assert(Asset.IsReal());
   Count := DynastyCount;
   if (Count = 0) then
      exit;
   if (IsLongVisibilityMode) then
   begin
      for Index := 0 to Count - 1 do // $R-
      begin
         Current := Asset.FDynastyNotes.AsLongDynasties^[Index].Visibility;
         Asset.FDynastyNotes.AsLongDynasties^[Index].Visibility := Current + Visibility;
      end;
   end
   else
   begin
      for Index := 0 to Count - 1 do // $R-
      begin
         Current := Asset.FDynastyNotes.AsShortDynasties[Index].Visibility;
         Asset.FDynastyNotes.AsShortDynasties[Index].Visibility := Current + Visibility;
      end;
   end;
   if ((not (dmInference in Current)) and Assigned(Asset.Parent)) then
   begin
      for Index := 0 to Count - 1 do // $R-
      begin
         AddSpecificVisibilityByIndex(Index, [dmInference], Asset.Parent.Parent);
      end;
   end;
end;


constructor TSystemEvent.Create(ATime: TTimeInMilliseconds; ACallback: TEventCallback; AData: Pointer; ASystem: TSystem);
begin
   inherited Create();
   FTime := ATime;
   FCallback := ACallback;
   FData := AData;
   FSystem := ASystem;
end;

destructor TSystemEvent.Cancel();
begin
   FSystem.CancelEvent(Self);
   inherited Destroy();
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
      if (IsLongMode) then
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


procedure CancelEvent(var Event: TSystemEvent);
begin
   Assert(Assigned(Event));
   Event.Cancel();
   Event := nil;
end;

end.