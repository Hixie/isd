{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit systems;

interface

uses
   systemdynasty, configuration, hashtable, hashset, genericutils,
   icons, serverstream, stringstream, random, materials, basenetwork, time;

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
// old and new dynasties. Otherwise, it just calls
// TAssetNode.ResetVisibility on every asset. Then, it calls
// TAssetNode.ApplyVisibility for each asset, and finally it calls
// TAssetNode.CheckVisibilityChanged on each asset in tree order.
//
// TAssetNode.ResetDynastyNotes calls TFeatureNode.ResetDynastyNotes
// on every feature in the system, copies the IDs over from the old
// data to the new data, snapshots the visibility data, and sets the
// visibility data to zero.
//
// TAssetNode.ResetVisibility just calls TFeatureNode.ResetVisibility
// on every feature in the system, snapshots the visibility data, and
// sets the visibility data to zero.
//
// TAssetNode.ApplyVisibility sets dmOwnership on each asset node
// appropriately, then calls TFeatureNode.ApplyVisibility on each
// feature in the system. This is the mechanism to "see" things.
//
// TAssetNode.HandleVisibility is called by features during
// ApplyVisibility to inform assets that they have been detected. The
// asset calls TFeatureNode.HandleVisibility for each feature, which
// gives the features a chance to cloak themselves or track their own
// internal visibility state. The order of features matters here; a
// feature which hides the asset (e.g. a cloaking device) should come
// before a feature that records visibility status (e.g. structural
// features that track which materials are known by detecting
// entities).
//
// To add visibility data, code uses a TVisibilityHelper which is a
// wrapper around a pointer to the system. It has two main APIs:
//
//  * TVisibilityHelper.AddSpecificVisibility: marks an asset as
//    having a particular TVisibility (in addition to any that it
//    already has). In addition, it initializes the asset's dynasty
//    data (FDynastyNotes) if necessary, and marks the ancestor chain
//    as having inferred visibility (by calling the same API
//    recursively).
//
//  * TVisibilityHelper.AddBroadVisibility adds a particular
//    visibility for every dynasty, then marks the ancestor chain as
//    having inferred visibility.
//
// TAssetNode.CheckVisibilityChanged first calls
// TFeatureNode.CheckVisibilityChanged on all its features, then
// checks if the visibility changed since the last update, and calls
// MarkAsDirty as appropriate.
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
   dmDetectable = [dmVisibleSpectrum];
   dmOwnership = [dmInference, dmVisibleSpectrum, dmInternals];
   
type
   TAssetClass = class;
   TAssetNode = class;
   TFeatureNode = class;
   TSystem = class;

   TAssetClassID = LongInt; // signed because negative values are built-in, and positive values are in tech tree
   
   TDynastyIndexHashTable = class(specialize THashTable<TDynasty, Cardinal, TObjectUtils>)
      constructor Create();
   end;

   TDynastyHashSet = class(specialize THashSet<TDynasty, TObjectUtils>)
      constructor Create();
   end;

   TAssetClassHashTable = class(specialize THashTable<TAssetClassID, TAssetClass, IntegerUtils>)
      constructor Create();
   end;

   TAssetClassHashSet = class(specialize THashSet<TAssetClass, TObjectUtils>)
      constructor Create();
   end;

   TAssetNodeHashTable = class(specialize THashTable<PtrUInt, TAssetNode, PtrUIntUtils>)
      constructor Create();
   end;

   TAssetID = Cardinal; // 0 is reserved for placeholders or sentinels
   
   TDynastyNotes = record
   strict private
      FID: TAssetID; // 4 bytes
      FOldVisibilty, FCurrentVisibility: TVisibility; // 2 bytes each
      function GetHasID(): Boolean; inline;
      function GetChanged(): Boolean; inline;
   public
      procedure Snapshot(); inline; // copies current visibility to old visibility, set current visibility to zero
      constructor Init(const AID: TAssetID);
      constructor InitFrom(const Other: TDynastyNotes);
      property HasID: Boolean read GetHasID;
      property AssetID: TAssetID read FID write FID;
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
         LongThreshold = 2;
      type
         PDynastyNotesArray = ^TDynastyNotesArray;
         TDynastyNotesArray = packed array[0..0] of TDynastyNotes;
         TShortDynastyNotesArray = packed array[0..LongThreshold-2] of TDynastyNotes;
      var
         case Integer of
            1: (AsShortDynasties: TShortDynastyNotesArray); // 1 dynasty
            2: (AsLongDynasties: PDynastyNotesArray); // 2 or more
            3: (AsRawPointer: Pointer);
   end;
   {$IF SIZEOF(TDynastyNotesPackage) <> SIZEOF(Pointer)}
      {$FATAL TDynastyNotesPackage size error.}
   {$ENDIF}

   // used for tracking which dynasties know about materials
   PKnowledgeSummary = ^TKnowledgeSummary;
   TKnowledgeSummary = packed record
   private
      function IsLongMode(): Boolean; inline;
   public
      procedure Init(DynastyCount: Cardinal);
      procedure Done();
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

   TVisibilityHelper = record // 64 bits - frequently passed as an argument
   strict private
      FSystem: TSystem;
   private
      procedure Init(ASystem: TSystem); inline;
   public
      function GetDynastyIndex(Dynasty: TDynasty): Cardinal; inline;
      procedure AddSpecificVisibility(const Dynasty: TDynasty; const Visibility: TVisibility; const Asset: TAssetNode); inline;
      procedure AddSpecificVisibilityByIndex(const DynastyIndex: Cardinal; const Visibility: TVisibility; const Asset: TAssetNode);
      procedure AddBroadVisibility(const Visibility: TVisibility; const Asset: TAssetNode);
      property System: TSystem read FSystem;
   end;
   {$IF SIZEOF(TVisibilityHelper) <> SIZEOF(Pointer)}
      {$FATAL TVisibilityHelper unexpectedly large.}
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
      function ReadCardinal(): Cardinal;
      function ReadInt64(): Int64;
      function ReadUInt64(): UInt64;
      function ReadPtrUInt(): PtrUInt;
      function ReadDouble(): Double;
      function ReadString(): UTF8String;
      function ReadAssetChangeKind(): TAssetChangeKind;
      function ReadAssetNodeReference(): TAssetNode;
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
      procedure WriteCardinal(Value: Cardinal); // {BOGUS Hint: Value parameter "Value" is assigned but never used}
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

   TBusMessage = class abstract end;
   TPhysicalConnectionBusMessage = class abstract(TBusMessage) end;
   TAssetManagementBusMessage = class abstract(TBusMessage) end;

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

   FeatureClassReference = class of TFeatureClass;
   FeatureNodeReference = class of TFeatureNode;

   TFeatureClass = class abstract
   strict protected
      function GetFeatureNodeClass(): FeatureNodeReference; virtual; abstract;
   public
      function InitFeatureNode(): TFeatureNode; virtual; abstract;
      property FeatureNodeClass: FeatureNodeReference read GetFeatureNodeClass;
   end;
   
   TFeatureClassArray = array of TFeatureClass;

   TDirtyKind = (
      dkSelf, // this asset node is dirty, all ancestors have dkDescendant set*
      dkNew, // this asset node is newly created, dkSelf must also be set**
      dkDescendant, // one or more of this asset node's descendants has dkSelf set (if not set, all descendants have an empty FDirty)*
      dkChildren, // specifically this asset's node's children changed in some way (became visible, were added/removed, etc)*
      dkVisibilityDidChange, // one or more dynasties changed whether they can see this node (handled by CheckVisibilityChanged)
      dkAffectsTime, // system's time factor changed
      dkAffectsDynastyCount, // system needs to redo a dynasty census (requires dkAffectsVisibility)
      dkAffectsVisibility, // system needs to redo a visibility scan
      dkAffectsNames, // any nodes listening to names of descendants should consider itself dirty
      dkAffectsKnowledge // any nodes caching knowledge
   );
   TDirtyKinds = set of TDirtyKind;
   //  * dkSelf and dkChildren are unset when walking up the tree.
   //    When dkSelf is removed, dkDescendant is set, and dkChildren is set if dkVisibilityDidChange is present.
   // ** dkNew can't be used with MarkAsDirty.

const
   dkAll = [Low(TDirtyKind) .. High(TDirtyKind)];
   dkAffectsTreeStructure = [dkAffectsVisibility, dkAffectsNames, dkAffectsKnowledge, dkVisibilityDidChange, dkSelf, dkChildren];
   dkWillNeedChangesWalk = [dkChildren];
   
type
   ISensorsProvider = interface ['ISensorsProvider']
      // Returns whether the material is known by the target's owner
      // according to the knowledge bus at the target.
      //
      // This should only be called on the object in the stack frame
      // in which the object was provided.
      function Knows(Material: TMaterial): Boolean;
   end;
   
   TFeatureNode = class abstract
   strict private
      FParent: TAssetNode;
   private
      procedure SetParent(Asset: TAssetNode); inline;
      function GetParent(): TAssetNode; inline;
      function GetSystem(): TSystem; inline;
   protected
      constructor CreateFromJournal(Journal: TJournalReader; AFeatureClass: TFeatureClass; ASystem: TSystem); virtual;
      procedure AdoptChild(Child: TAssetNode); virtual;
      procedure DropChild(Child: TAssetNode); virtual;
      procedure MarkAsDirty(DirtyKinds: TDirtyKinds); virtual;
      function GetMass(): Double; virtual; // kg
      function GetSize(): Double; virtual; // m
      function GetFeatureName(): UTF8String; virtual;
      procedure Walk(PreCallback: TPreWalkCallback; PostCallback: TPostWalkCallback); virtual;
      function InjectBusMessage(Message: TBusMessage): Boolean;
      function ManageBusMessage(Message: TBusMessage): Boolean; virtual;
      function HandleBusMessage(Message: TBusMessage): Boolean; virtual;
      procedure ResetDynastyNotes(OldDynasties: TDynastyIndexHashTable; NewDynasties: TDynastyHashSet; CachedSystem: TSystem); virtual;
      procedure ResetVisibility(CachedSystem: TSystem); virtual;
      procedure ApplyVisibility(VisibilityHelper: TVisibilityHelper); virtual;
      procedure HandleVisibility(const DynastyIndex: Cardinal; var Visibility: TVisibility; const Sensors: ISensorsProvider; const VisibilityHelper: TVisibilityHelper); virtual;
      procedure CheckVisibilityChanged(VisibilityHelper: TVisibilityHelper); virtual;
      procedure Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter; CachedSystem: TSystem); virtual; abstract;
      procedure HandleChanges(); virtual;
      property System: TSystem read GetSystem;
   public
      destructor Destroy(); override;
      procedure UpdateJournal(Journal: TJournalWriter); virtual; abstract;
      procedure ApplyJournal(Journal: TJournalReader; CachedSystem: TSystem); virtual; abstract;
      function HandleCommand(Command: UTF8String; var Message: TMessage): Boolean; virtual;
      procedure DescribeExistentiality(var IsDefinitelyReal, IsDefinitelyGhost: Boolean); virtual;
      property Mass: Double read GetMass;
      property Size: Double read GetSize;
      property FeatureName: UTF8String read GetFeatureName;
      property Parent: TAssetNode read FParent;
   end;

   TFeatureNodeArray = array of TFeatureNode;

   TBuildEnvironment = (bePlanetRegion, beSpaceDock);
   TBuildEnvironments = set of TBuildEnvironment;
   
   TAssetClass = class
   private
      FID: TAssetClassID;
      FFeatures: TFeatureClassArray;
      FName, FAmbiguousName, FDescription: UTF8String;
      FIcon: TIcon;
      FBuildEnvironments: TBuildEnvironments;
      function GetFeature(Index: Cardinal): TFeatureClass;
      function GetFeatureCount(): Cardinal;
   public
      constructor Create(AID: TAssetClassID; AName, AAmbiguousName, ADescription: UTF8String; AFeatures: TFeatureClassArray; AIcon: TIcon; ABuildEnvironments: TBuildEnvironments);
      destructor Destroy(); override;
      function SpawnFeatureNodes(): TFeatureNodeArray; // some feature nodes _can't_ be spawned this way (e.g. TAssetNameFeatureNode)
      function SpawnFeatureNodesFromJournal(Journal: TJournalReader; CachedSystem: TSystem): TFeatureNodeArray;
      procedure ApplyFeatureNodesFromJournal(Journal: TJournalReader; AssetNode: TAssetNode; CachedSystem: TSystem);
      function Spawn(AOwner: TDynasty): TAssetNode; overload;
      function Spawn(AOwner: TDynasty; AFeatures: TFeatureNodeArray): TAssetNode; overload;
   public // encoded in knowledge
      procedure Serialize(Writer: TStringStreamWriter); overload;
      procedure Serialize(Writer: TServerStreamWriter); overload;
      procedure SerializeFor(AssetNode: TAssetNode; DynastyIndex: Cardinal; Writer: TServerStreamWriter; CachedSystem: TSystem);
      function CanBuild(BuildEnvironment: TBuildEnvironment): Boolean;
      property Features[Index: Cardinal]: TFeatureClass read GetFeature;
      property FeatureCount: Cardinal read GetFeatureCount;
      property Name: UTF8String read FName;
      property Description: UTF8String read FDescription;
      property Icon: TIcon read FIcon;
   public
      property ID: TAssetClassID read FID;
      property AmbiguousName: UTF8String read FAmbiguousName;
   end;

   TEncyclopediaView = class
   protected
      function GetAssetClass(ID: TAssetClassID): TAssetClass; virtual; abstract;
      function GetMaterial(ID: TMaterialID): TMaterial; virtual; abstract;
   public
      function Craterize(Diameter: Double; OldAsset, NewAsset: TAssetNode): TAssetNode; virtual; abstract;
      property AssetClasses[ID: TAssetClassID]: TAssetClass read GetAssetClass;
      property Materials[ID: TMaterialID]: TMaterial read GetMaterial;
   end;
   
   TAssetNode = class
   strict protected
      FAssetClass: TAssetClass;
      FOwner: TDynasty;
      FFeatures: TFeatureNodeArray;
   protected
      FParent: TFeatureNode;
      FDirty: TDirtyKinds;
      FDynastyNotes: TDynastyNotesPackage; // TDynastyNotesPackage is a 64 bit record, not a pointer to heap-allocated data
      constructor Create(AAssetClass: TAssetClass; AOwner: TDynasty; AFeatures: TFeatureNodeArray);
      function GetFeature(Index: Cardinal): TFeatureNode;
      function GetMass(): Double; // kg
      function GetSize(): Double; // m
      function GetDensity(): Double; // kg/m^3
      function GetAssetName(): UTF8String;
      procedure MarkAsDirty(DirtyKinds: TDirtyKinds); virtual;
      procedure ReportChildIsPermanentlyGone(Child: TAssetNode); virtual;
      function GetDebugName(): UTF8String;
   private
      procedure UpdateID(CachedSystem: TSystem; DynastyIndex: Cardinal; ID: TAssetID); // used from ApplyJournal
      function GetSystem(): TSystem; virtual;
   public
      ParentData: Pointer;
      constructor Create(Journal: TJournalReader; ASystem: TSystem);
      constructor Create(); unimplemented;
      destructor Destroy(); override;
      procedure ReportPermanentlyGone();
      function GetFeatureByClass(FeatureClass: FeatureClassReference): TFeatureNode; // returns nil if feature is absent
      procedure Walk(PreCallback: TPreWalkCallback; PostCallback: TPostWalkCallback);
      function InjectBusMessage(Message: TBusMessage): Boolean; // called by a node to send a message on the bus
      function HandleBusMessage(Message: TBusMessage): Boolean; // called by a bus to send a message down the tree
      procedure ResetDynastyNotes(OldDynasties: TDynastyIndexHashTable; NewDynasties: TDynastyHashSet; CachedSystem: TSystem);
      procedure ResetVisibility(CachedSystem: TSystem);
      procedure ApplyVisibility(VisibilityHelper: TVisibilityHelper);
      procedure HandleVisibility(const DynastyIndex: Cardinal; var Visibility: TVisibility; const Sensors: ISensorsProvider; const VisibilityHelper: TVisibilityHelper);
      procedure CheckVisibilityChanged(VisibilityHelper: TVisibilityHelper);
      function ReadVisibilityFor(DynastyIndex: Cardinal; CachedSystem: TSystem): TVisibility; inline;
      function IsVisibleFor(DynastyIndex: Cardinal; CachedSystem: TSystem): Boolean; inline;
      procedure HandleChanges();
      procedure Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter; CachedSystem: TSystem);
      procedure UpdateJournal(Journal: TJournalWriter);
      procedure ApplyJournal(Journal: TJournalReader; CachedSystem: TSystem);
      function ID(CachedSystem: TSystem; DynastyIndex: Cardinal; AllowZero: Boolean = False): TAssetID;
      procedure HandleCommand(Command: UTF8String; var Message: TMessage);
      function IsReal(): Boolean;
      property Parent: TFeatureNode read FParent;
      property Dirty: TDirtyKinds read FDirty;
      property AssetClass: TAssetClass read FAssetClass;
      property Owner: TDynasty read FOwner;
      property Features[Index: Cardinal]: TFeatureNode read GetFeature;
      property Mass: Double read GetMass; // kg
      property Size: Double read GetSize; // meters, must be greater than zero
      property Density: Double read GetDensity; // kg/m^3; computed from mass and size, assuming spherical shape
      property AssetName: UTF8String read GetAssetName;
      property DebugName: UTF8String read GetDebugName;
      property System: TSystem read GetSystem;
   end;

   TAssetNodeArray = array of TAssetNode;
   
   // pointers to these objects are not valid after the event has run or been canceled
   TSystemEvent = class
   private
      FTime: TTimeInMilliseconds;
      FCallback: TEventCallback;
      FData: Pointer;
      FSystem: TSystem;
   public
      constructor Create(ATime: TTimeInMilliseconds; ACallback: TEventCallback; AData: Pointer; ASystem: TSystem);
      destructor Cancel();
   end;

   TSystemEventSet = specialize THashSet<TSystemEvent, PointerUtils>;

   TSystem = class sealed
   strict private
      FServer: TBaseServer;
      FScheduledEvents: TSystemEventSet;
      FNextEvent: TSystemEvent;
      FNextEventHandle: PEvent;
      FDynastyDatabase: TDynastyDatabase;
      FEncyclopedia: TEncyclopediaView;
      FConfigurationDirectory: UTF8String;
      FSystemID: Cardinal;
      FRandomNumberGenerator: TRandomNumberGenerator;
      FX, FY: Double;
      FTimeOrigin: TDateTime;
      FTimeFactor: TTimeFactor;
      FRoot: TAssetNode;
      FChanges: TDirtyKinds;
      procedure Init(AConfigurationDirectory: UTF8String; ASystemID: Cardinal; ARootClass: TAssetClass; AServer: TBaseServer; ADynastyDatabase: TDynastyDatabase; AEncyclopedia: TEncyclopediaView);
      procedure ApplyJournal(FileName: UTF8String);
      procedure OpenJournal(FileName: UTF8String);
      procedure RecordUpdate();
      function GetDirty(): Boolean;
      procedure Clean();
      function GetIsLongVisibilityMode(): Boolean; inline;
      procedure UnwindDynastyNotesArenas(Arena: Pointer);
      procedure UpdateDynastyList(MaintainMaxIDs: Boolean);
      procedure RecomputeVisibility();
      procedure RunEvent(var Data);
      procedure ScheduleNextEvent();
      procedure RescheduleNextEvent(); // call this when the time factor changes
      function SelectNextEvent(): TSystemEvent;
      function GetNow(): TTimeInMilliseconds; inline;
      function GetDynastyCount(): Cardinal; inline;
      function GetDynastyIndex(Dynasty: TDynasty): Cardinal; inline;
   private
      FDynastyIndices: TDynastyIndexHashTable; // for index into visibility tables; used by TVisibilityHelper
      FDynastyMaxAssetIDs: array of TAssetID; // used by TVisibilityHelper
      FDynastyNotesBuffer: Pointer; // used by TVisibilityHelper // pointer to an arena that ends with a pointer to the next arena (or nil); size is N*M+8 bytes, where N=dynasty count and M=size of TDynastyNotes
      FDynastyNotesOffset: Cardinal; // used by TVisibilityHelper
      FJournalFile: File; // used by TJournalReader/TJournalWriter
      FJournalWriter: TJournalWriter;
      procedure CancelEvent(Event: TSystemEvent);
      procedure ReportChildIsPermanentlyGone(Child: TAssetNode);
   protected
      procedure MarkAsDirty(DirtyKinds: TDirtyKinds);
   public
      constructor Create(AConfigurationDirectory: UTF8String; ASystemID: Cardinal; AX, AY: Double; ARootClass: TAssetClass; AServer: TBaseServer; ADynastyDatabase: TDynastyDatabase; AEncyclopedia: TEncyclopediaView; Settings: PSettings);
      constructor CreateFromDisk(AConfigurationDirectory: UTF8String; ASystemID: Cardinal; ARootClass: TAssetClass; AServer: TBaseServer; ADynastyDatabase: TDynastyDatabase; AEncyclopedia: TEncyclopediaView);
      destructor Destroy(); override;
      function SerializeSystem(Dynasty: TDynasty; Writer: TServerStreamWriter; DirtyOnly: Boolean): Boolean; // true if anything was dkSelf dirty
      procedure ReportChanges();
      function HasDynasty(Dynasty: TDynasty): Boolean; inline;
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
      property Encyclopedia: TEncyclopediaView read FEncyclopedia; // used by TJournalReader/TJournalWriter
      property Journal: TJournalWriter read FJournalWriter;
      property Now: TTimeInMilliseconds read GetNow;
      property TimeFactor: TTimeFactor read FTimeFactor;
   end;
   
implementation

uses
   sysutils, exceptions, hashfunctions, isdprotocol, providers, typedump, dateutils, math;
   
type
   TRootAssetNode = class(TAssetNode)
   protected
      FSystem: TSystem;
      function GetSystem(): TSystem; override;
      procedure MarkAsDirty(DirtyKinds: TDirtyKinds); override;
      procedure ReportChildIsPermanentlyGone(Child: TAssetNode); override;
   public
      constructor Create(AAssetClass: TAssetClass; ASystem: TSystem; AFeatures: TFeatureNodeArray);
   end;

function AssetClassHash32(const Key: TAssetClass): DWord;
begin
   Result := ObjectHash32(Key);
end;

constructor TDynastyIndexHashTable.Create();
begin
   inherited Create(@DynastyHash32);
end;

constructor TDynastyHashSet.Create();
begin
   inherited Create(@DynastyHash32);
end;

constructor TAssetClassHashTable.Create();
begin
   inherited Create(@LongIntHash32);
end;

constructor TAssetClassHashSet.Create();
begin
   inherited Create(@AssetClassHash32);
end;

constructor TAssetNodeHashTable.Create();
begin
   inherited Create(@PtrUIntHash32);
end;

function SystemEventHash32(const Key: TSystemEvent): DWord;
begin
   Result := ObjectHash32(Key);
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
end;

function TJournalReader.ReadCardinal(): Cardinal;
begin
   BlockRead(FSystem.FJournalFile, Result, SizeOf(Result)); {BOGUS Hint: Function result variable does not seem to be initialized}
end;

function TJournalReader.ReadInt64(): Int64;
begin
   BlockRead(FSystem.FJournalFile, Result, SizeOf(Result)); {BOGUS Hint: Function result variable does not seem to be initialized}
end;

function TJournalReader.ReadUInt64(): UInt64;
begin
   BlockRead(FSystem.FJournalFile, Result, SizeOf(Result)); {BOGUS Hint: Function result variable does not seem to be initialized}
end;

function TJournalReader.ReadPtrUInt(): PtrUInt;
begin
   BlockRead(FSystem.FJournalFile, Result, SizeOf(Result)); {BOGUS Hint: Function result variable does not seem to be initialized}
end;

function TJournalReader.ReadDouble(): Double;
begin
   BlockRead(FSystem.FJournalFile, Result, SizeOf(Result)); {BOGUS Hint: Function result variable does not seem to be initialized}
end;

function TJournalReader.ReadString(): UTF8String;
var
   Size: Cardinal;
begin
   Size := ReadCardinal();
   SetLength(Result, Size); {BOGUS Hint: Function result variable of a managed type does not seem to be initialized}
   if (Size > 0) then
      BlockRead(FSystem.FJournalFile, Result[1], Size);
end;

function TJournalReader.ReadAssetChangeKind(): TAssetChangeKind;
begin
   BlockRead(FSystem.FJournalFile, Result, SizeOf(Result)); {BOGUS Hint: Function result variable does not seem to be initialized}
end;

function TJournalReader.ReadAssetNodeReference(): TAssetNode;
var
   ID: PtrUInt;
begin
   ID := ReadPtrUInt();
   if (ID > 0) then
   begin
      Assert(FAssetMap.Has(ID));
      Result := FAssetMap[ID];
   end
   else
   begin
      Result := nil;
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
   end
   else
      Result := nil;
end;

function TJournalReader.ReadDynastyReference(): TDynasty;
var
   ID: Cardinal;
begin
   ID := ReadCardinal();
   if (ID > 0) then
   begin
      Result := FSystem.DynastyDatabase.GetDynastyFromDisk(ID);
   end
   else
   begin
      Result := nil;
   end;
end;

function TJournalReader.ReadMaterialReference(): TMaterial;
var
   ID: TMaterialID;
begin
   Assert(SizeOf(Cardinal) = SizeOf(TMaterialID));
   ID := TMaterialID(ReadCardinal());
   Result := FSystem.Encyclopedia.Materials[ID];
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

procedure TJournalWriter.WriteCardinal(Value: Cardinal);
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


constructor TFeatureNode.CreateFromJournal(Journal: TJournalReader; AFeatureClass: TFeatureClass; ASystem: TSystem);
begin
   inherited Create();
   try
      ApplyJournal(Journal, ASystem);
   except
      ReportCurrentException();
      raise;
   end;
end;

procedure TFeatureNode.SetParent(Asset: TAssetNode);
begin
   Assert(Assigned(Asset));
   Assert(not Assigned(FParent));
   FParent := Asset;
end;

function TFeatureNode.GetParent(): TAssetNode;
begin
   Assert(Assigned(FParent));
   Result := FParent;
end;

function TFeatureNode.GetSystem(): TSystem;
begin
   Assert(Assigned(FParent));
   Result := FParent.System;
end;

procedure TFeatureNode.AdoptChild(Child: TAssetNode);
var
   DirtyKinds: TDirtyKinds;
begin
   if (Assigned(Child.Parent)) then
      Child.Parent.DropChild(Child);
   Assert(not Assigned(Child.ParentData));
   Child.FParent := Self;
   DirtyKinds := dkAffectsTreeStructure + [dkDescendant];
   // TODO: find a way to skip the following if System.HasDynasty(Child.Owner) - but while reading journal, we don't have the system
   Include(DirtyKinds, dkAffectsDynastyCount);
   MarkAsDirty(DirtyKinds);
end;

procedure TFeatureNode.DropChild(Child: TAssetNode);
var
   DirtyKinds: TDirtyKinds;
begin
   Assert(Child.FParent = Self);
   Child.FParent := nil;
   Assert(not Assigned(Child.ParentData)); // subclass is responsible for freeing child's parent data
   DirtyKinds := dkAffectsTreeStructure;
   Assert(Assigned(FParent));
   // TODO: check subtree to see if it contains any dynasties that aren't in the rest of the system before doing the following
   Include(DirtyKinds, dkAffectsDynastyCount);
   MarkAsDirty(DirtyKinds);
end;

procedure TFeatureNode.MarkAsDirty(DirtyKinds: TDirtyKinds);
begin
   if (Assigned(FParent)) then
      FParent.MarkAsDirty(DirtyKinds);
end;

function TFeatureNode.GetMass(): Double;
begin
   Result := 0.0;
end;

function TFeatureNode.GetSize(): Double;
begin
   // Result := 1.0e-8;
   Result := 50.0;
end;

function TFeatureNode.GetFeatureName(): UTF8String;
begin
   Result := '';
end;

procedure TFeatureNode.Walk(PreCallback: TPreWalkCallback; PostCallback: TPostWalkCallback);
begin
end;

function TFeatureNode.HandleBusMessage(Message: TBusMessage): Boolean;
begin
   Result := False;
end;

function TFeatureNode.InjectBusMessage(Message: TBusMessage): Boolean;
begin
   Result := Parent.InjectBusMessage(Message);
end;

function TFeatureNode.ManageBusMessage(Message: TBusMessage): Boolean;
begin
   Result := False;
end;

procedure TFeatureNode.ResetDynastyNotes(OldDynasties: TDynastyIndexHashTable; NewDynasties: TDynastyHashSet; CachedSystem: TSystem);
begin
end;

procedure TFeatureNode.ResetVisibility(CachedSystem: TSystem);
begin
end;

procedure TFeatureNode.ApplyVisibility(VisibilityHelper: TVisibilityHelper);
begin
end;

procedure TFeatureNode.HandleVisibility(const DynastyIndex: Cardinal; var Visibility: TVisibility; const Sensors: ISensorsProvider; const VisibilityHelper: TVisibilityHelper);
begin
end;

procedure TFeatureNode.CheckVisibilityChanged(VisibilityHelper: TVisibilityHelper);
begin
end;

procedure TFeatureNode.HandleChanges();
begin
end;

function TFeatureNode.HandleCommand(Command: UTF8String; var Message: TMessage): Boolean;
begin
   Result := False;
end;

procedure TFeatureNode.DescribeExistentiality(var IsDefinitelyReal, IsDefinitelyGhost: Boolean);
begin
end;

destructor TFeatureNode.Destroy();
begin
   inherited;
end;


constructor TAssetClass.Create(AID: TAssetClassID; AName, AAmbiguousName, ADescription: UTF8String; AFeatures: TFeatureClassArray; AIcon: TIcon; ABuildEnvironments: TBuildEnvironments);
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
         FFeatures[Index].Free();
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

function TAssetClass.SpawnFeatureNodes(): TFeatureNodeArray;
var
   FeatureNodes: TFeatureNodeArray;
   Index: Cardinal;
begin
   SetLength(FeatureNodes, Length(FFeatures));
   if (Length(FeatureNodes) > 0) then
      for Index := 0 to High(FFeatures) do // $R-
         FeatureNodes[Index] := FFeatures[Index].InitFeatureNode();
   Result := FeatureNodes;
end;

function TAssetClass.SpawnFeatureNodesFromJournal(Journal: TJournalReader; CachedSystem: TSystem): TFeatureNodeArray;
var
   Index, FallbackIndex: Cardinal;
   Value: Cardinal;
begin
   SetLength(Result, Length(FFeatures)); {BOGUS Warning: Function result variable of a managed type does not seem to be initialized}
   if (Length(Result) > 0) then
   begin
      for Index := Low(FFeatures) to High(FFeatures) do // $R-
      begin
         case (Journal.ReadCardinal()) of
            jcStartOfFeature:
               begin
                  Result[Index] := FFeatures[Index].FeatureNodeClass.CreateFromJournal(Journal, FFeatures[Index], CachedSystem);
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
                     Result[Index] := FFeatures[Index].InitFeatureNode(); // this will fail for some features nodes...
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

procedure TAssetClass.ApplyFeatureNodesFromJournal(Journal: TJournalReader; AssetNode: TAssetNode; CachedSystem: TSystem);
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
                  AssetNode.Features[Index].ApplyJournal(Journal, CachedSystem);
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

function TAssetClass.Spawn(AOwner: TDynasty): TAssetNode;
begin
   Result := TAssetNode.Create(Self, AOwner, SpawnFeatureNodes());
end;

function TAssetClass.Spawn(AOwner: TDynasty; AFeatures: TFeatureNodeArray): TAssetNode;
begin
   Result := TAssetNode.Create(Self, AOwner, AFeatures);
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
   Writer.WriteInt32(FID);
   Writer.WriteStringReference(FIcon);
   Writer.WriteStringReference(FName);
   Writer.WriteStringReference(FDescription);
end;

procedure TAssetClass.SerializeFor(AssetNode: TAssetNode; DynastyIndex: Cardinal; Writer: TServerStreamWriter; CachedSystem: TSystem);
var
   Visibility: TVisibility;
   ReportedClassID: TAssetClassID;
   Detectable, Recognizable: Boolean;
   ReportedIcon, ReportedName, ReportedDescription: UTF8String;
begin
   Visibility := AssetNode.ReadVisibilityFor(DynastyIndex, CachedSystem);
   Detectable := dmDetectable * Visibility <> [];
   Recognizable := dmClassKnown in Visibility;
   // TODO: optionally get the description from the node rather than the class
   // TODO: e.g. planets and planetary regions should self-describe rather than using the region class description
   if (Detectable and Recognizable) then
   begin
      ReportedClassID := FID;
      ReportedIcon := FIcon;
      ReportedName := FName;
      ReportedDescription := FDescription;
   end
   else
   begin
      ReportedClassID := 0;
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
   end;
   Writer.WriteInt32(ReportedClassID);
   Writer.WriteStringReference(ReportedIcon);
   Writer.WriteStringReference(ReportedName);
   Assert(ReportedDescription <> '');
   Writer.WriteStringReference(ReportedDescription);
end;

function TAssetClass.CanBuild(BuildEnvironment: TBuildEnvironment): Boolean;
begin
   Result := BuildEnvironment in FBuildEnvironments;
end;


constructor TAssetNode.Create(AAssetClass: TAssetClass; AOwner: TDynasty; AFeatures: TFeatureNodeArray);
var
   Feature: TFeatureNode;
begin
   inherited Create();
   try
      FAssetClass := AAssetClass;
      FOwner := AOwner;
      if (Assigned(FOwner)) then
         FOwner.IncRef();
      Assert(Length(AFeatures) = FAssetClass.FeatureCount);
      FFeatures := AFeatures;
      for Feature in FFeatures do
      begin
         Feature.SetParent(Self);
      end;
      FDirty := dkAll;
   except
      ReportCurrentException();
      raise;
   end;
end;

constructor TAssetNode.Create(Journal: TJournalReader; ASystem: TSystem);
begin
   inherited Create();
   try
      ApplyJournal(Journal, ASystem);
      FDirty := dkAll;
   except
      ReportCurrentException();
      raise;
   end;
end;

constructor TAssetNode.Create();
begin
   Writeln('Invalid constructor call for ', ClassName, '.');
   raise Exception.Create('Invalid constructor call');
end;

destructor TAssetNode.Destroy();
var
   Feature: TFeatureNode;
begin
   for Feature in FFeatures do
      Feature.Free();
   SetLength(FFeatures, 0);
   if (Assigned(Parent)) then
      Parent.DropChild(Self);
   inherited;
end;

procedure TAssetNode.ReportPermanentlyGone();
var
   Message: TAssetGoingAway;
   Handled: Boolean;
begin
   if (Assigned(FOwner)) then
      FOwner.DecRef();
   Message := TAssetGoingAway.Create(Self);
   Handled := InjectBusMessage(Message);
   Assert(not Handled, 'TAssetGoingAway should never be marked as handled.');
   FreeAndNil(Message);
   ReportChildIsPermanentlyGone(Self);
end;

function TAssetNode.GetFeatureByClass(FeatureClass: FeatureClassReference): TFeatureNode;
var
   Index: Cardinal;
begin
   Assert(FAssetClass.FeatureCount > 0); // at a minimum you need a feature to give the asset a size
   for Index := 0 to FAssetClass.FeatureCount - 1 do // $R-
   begin
      if (FAssetClass.Features[Index] is FeatureClass) then
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
   Assert(Result > 0.0, 'Asset "' + AssetName + '" of class "' + FAssetClass.Name + '" has zero size.');
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

procedure TAssetNode.MarkAsDirty(DirtyKinds: TDirtyKinds);
begin
   Assert(not (dkNew in DirtyKinds));
   if (DirtyKinds - FDirty <> []) then
   begin
      FDirty := FDirty + DirtyKinds;
      if (Assigned(FParent)) then
      begin
         Exclude(DirtyKinds, dkChildren);
         if (dkSelf in DirtyKinds) then
         begin
            Exclude(DirtyKinds, dkSelf);
            Include(DirtyKinds, dkDescendant);
            if (dkVisibilityDidChange in DirtyKinds) then
               Include(DirtyKinds, dkChildren);
         end;
         FParent.Parent.MarkAsDirty(DirtyKinds);
      end;
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

function TAssetNode.InjectBusMessage(Message: TBusMessage): Boolean;
var
   Feature: TFeatureNode;
   Handled: Boolean;
begin
   Result := False;
   for Feature in FFeatures do
   begin
      Result := Feature.ManageBusMessage(Message);
      if (Result) then
         exit;
   end;
   if (Assigned(FParent)) then
   begin
      Result := FParent.InjectBusMessage(Message);
   end
   else
   begin
      if (Message is TAssetManagementBusMessage) then
      begin
         Handled := HandleBusMessage(Message);
         Assert(not Handled);
         Result := True;
      end
      else
      begin
         Result := False;
      end;
   end;
end;

function TAssetNode.HandleBusMessage(Message: TBusMessage): Boolean;
var
   Feature: TFeatureNode;
begin
   for Feature in FFeatures do
   begin
      Result := Feature.HandleBusMessage(Message);
      if (Result) then
         exit;
   end;
   Result := False;
end;

procedure TAssetNode.ResetDynastyNotes(OldDynasties: TDynastyIndexHashTable; NewDynasties: TDynastyHashSet; CachedSystem: TSystem);
var
   Dynasty: TDynasty;
   Feature: TFeatureNode;
   Source, Target: TDynastyNotesPackage.PDynastyNotesArray;
   Buffer: TDynastyNotesPackage.TShortDynastyNotesArray;
   Index: Cardinal;
begin
   if (OldDynasties.Count >= TDynastyNotesPackage.LongThreshold) then
   begin
      Source := FDynastyNotes.AsLongDynasties;
   end
   else
   begin
      Buffer := FDynastyNotes.AsShortDynasties;
      Source := TDynastyNotesPackage.PDynastyNotesArray(@Buffer);
   end;
   if (NewDynasties.Count >= TDynastyNotesPackage.LongThreshold) then
   begin
      Assert(Assigned(CachedSystem.FDynastyNotesBuffer));
      Target := CachedSystem.FDynastyNotesBuffer + CachedSystem.FDynastyNotesOffset;
      Inc(CachedSystem.FDynastyNotesOffset, SizeOf(TDynastyNotes) * NewDynasties.Count);
      FDynastyNotes.AsLongDynasties := Target;
   end
   else
   begin
      Target := TDynastyNotesPackage.PDynastyNotesArray(@FDynastyNotes.AsShortDynasties);
   end;
   Index := 0;
   for Dynasty in NewDynasties do
   begin
      if (OldDynasties.Has(Dynasty) and (Source^[OldDynasties[Dynasty]].HasID)) then
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
      Feature.ResetDynastyNotes(OldDynasties, NewDynasties, CachedSystem);
end;

procedure TAssetNode.ResetVisibility(CachedSystem: TSystem);
var
   Feature: TFeatureNode;
   Target: TDynastyNotesPackage.PDynastyNotesArray;
   Index, Count: Cardinal;
begin
   if (CachedSystem.IsLongVisibilityMode) then
   begin
      Target := FDynastyNotes.AsLongDynasties;
   end
   else
   begin
      Target := TDynastyNotesPackage.PDynastyNotesArray(@FDynastyNotes.AsShortDynasties);
   end;
   Count := CachedSystem.DynastyCount;
   if (Count > 0) then
   begin
      for Index := 0 to Count - 1 do // $R-
      begin
         Target^[Index].Snapshot();
      end;
   end;
   for Feature in FFeatures do
      Feature.ResetVisibility(CachedSystem);
end;

procedure TAssetNode.ApplyVisibility(VisibilityHelper: TVisibilityHelper);
var
   Feature: TFeatureNode;
begin
   if (Assigned(FOwner)) then
      VisibilityHelper.AddSpecificVisibility(FOwner, dmOwnership, Self);
   for Feature in FFeatures do
      Feature.ApplyVisibility(VisibilityHelper);
end;

procedure TAssetNode.HandleVisibility(const DynastyIndex: Cardinal; var Visibility: TVisibility; const Sensors: ISensorsProvider; const VisibilityHelper: TVisibilityHelper);
var
   Feature: TFeatureNode;
begin
   Assert((not Assigned(Owner)) or (VisibilityHelper.GetDynastyIndex(Owner) = DynastyIndex) or IsReal());
   for Feature in FFeatures do
      Feature.HandleVisibility(DynastyIndex, Visibility, Sensors, VisibilityHelper);
   if (Visibility <> []) then
      VisibilityHelper.AddSpecificVisibilityByIndex(DynastyIndex, Visibility, Self);
end;

procedure TAssetNode.CheckVisibilityChanged(VisibilityHelper: TVisibilityHelper);

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
               Inc(VisibilityHelper.System.FDynastyMaxAssetIDs[DynastyIndex]);
               Notes.AssetID := VisibilityHelper.System.FDynastyMaxAssetIDs[DynastyIndex];
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
      Feature.CheckVisibilityChanged(VisibilityHelper);
   if (VisibilityHelper.System.DynastyCount > 0) then
   begin
      Changed := False;
      for DynastyIndex := 0 to VisibilityHelper.System.DynastyCount - 1 do // $R-
      begin
         if (VisibilityHelper.System.IsLongVisibilityMode) then
         begin
            Changed := Changed or HandleChanged(DynastyIndex, FDynastyNotes.AsLongDynasties^[DynastyIndex]);
         end
         else
         begin
            Changed := Changed or HandleChanged(DynastyIndex, FDynastyNotes.AsShortDynasties[DynastyIndex]);
         end;
      end;
      if (Changed) then
      begin
         MarkAsDirty([dkSelf, dkVisibilityDidChange]);
      end;
   end;
end;

function TAssetNode.ReadVisibilityFor(DynastyIndex: Cardinal; CachedSystem: TSystem): TVisibility;
begin
   if (CachedSystem.IsLongVisibilityMode) then
   begin
      Result := FDynastyNotes.AsLongDynasties^[DynastyIndex].Visibility;
   end
   else
   begin
      Result := FDynastyNotes.AsShortDynasties[DynastyIndex].Visibility;
   end;
end;

function TAssetNode.IsVisibleFor(DynastyIndex: Cardinal; CachedSystem: TSystem): Boolean;
begin
   Result := ReadVisibilityFor(DynastyIndex, CachedSystem) <> [];
end;

procedure TAssetNode.HandleChanges();
var
   Feature: TFeatureNode;
begin
   for Feature in FFeatures do
      Feature.HandleChanges();
end;

procedure TAssetNode.Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter; CachedSystem: TSystem);
var
   Feature: TFeatureNode;
begin
   if (IsVisibleFor(DynastyIndex, CachedSystem)) then
   begin
      Writer.WriteCardinal(ID(CachedSystem, DynastyIndex));
      if (Assigned(FOwner)) then
      begin
         Writer.WriteCardinal(FOwner.DynastyID);
      end
      else
      begin
         Writer.WriteCardinal(0);
      end;
      Writer.WriteDouble(Mass);
      Assert(Size > 0.0);
      Writer.WriteDouble(Size);
      Writer.WriteStringReference(AssetName);
      FAssetClass.SerializeFor(Self, DynastyIndex, Writer, CachedSystem);
      for Feature in FFeatures do
         Feature.Serialize(DynastyIndex, Writer, CachedSystem);
      Writer.WriteCardinal(fcTerminator);
   end;
end;

procedure TAssetNode.UpdateJournal(Journal: TJournalWriter);
var
   Feature: TFeatureNode;
begin
   if (dkNew in FDirty) then
   begin
      Assert(dkSelf in FDirty);
      Journal.WriteCardinal(jcNewAsset);
   end
   else
   begin
      Journal.WriteCardinal(jcAssetChange);
   end;
   Journal.WriteAssetNodeReference(Self);
   Journal.WriteAssetClassReference(FAssetClass);
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

procedure TAssetNode.ApplyJournal(Journal: TJournalReader; CachedSystem: TSystem);
var
   NewAssetClass: TAssetClass;
   Feature: TFeatureNode;
   SpawnFeatures: Boolean;
begin
   NewAssetClass := Journal.ReadAssetClassReference();
   if (not Assigned(AssetClass)) then
   begin
      FAssetClass := NewAssetClass;
      SpawnFeatures := True;
   end
   else
   begin
      Assert(NewAssetClass = AssetClass);
      SpawnFeatures := False;
   end;
   FOwner := Journal.ReadDynastyReference();
   if (SpawnFeatures) then
   begin
      Assert(Length(FFeatures) = 0);
      FFeatures := FAssetClass.SpawnFeatureNodesFromJournal(Journal, CachedSystem);
      for Feature in FFeatures do
         Feature.SetParent(Self);
   end
   else
   begin
      FAssetClass.ApplyFeatureNodesFromJournal(Journal, Self, CachedSystem);
   end;
   if (Journal.ReadCardinal() <> jcEndOfAsset) then
   begin
      raise EJournalError.Create('missing end of asset marker (0x' + HexStr(jcEndOfAsset, 8) + ')');
   end;
end;

procedure TAssetNode.ReportChildIsPermanentlyGone(Child: TAssetNode);
begin
   Assert(Assigned(FParent));
   Parent.Parent.ReportChildIsPermanentlyGone(Child);
end;

function TAssetNode.ID(CachedSystem: TSystem; DynastyIndex: Cardinal; AllowZero: Boolean = False): TAssetID;
begin
   if (CachedSystem.IsLongVisibilityMode) then
   begin
      Result := FDynastyNotes.AsLongDynasties^[DynastyIndex].AssetID;
   end
   else
   begin
      Result := FDynastyNotes.AsShortDynasties[DynastyIndex].AssetID;
   end;
   Assert(AllowZero or (Result > 0));
end;

procedure TAssetNode.UpdateID(CachedSystem: TSystem; DynastyIndex: Cardinal; ID: TAssetID);
begin
   if (CachedSystem.IsLongVisibilityMode) then
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
   Result := Parent.System;
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
   IsDefinitelyReal, IsDefinitelyGhost: Boolean;
   Feature: TFeatureNode;
begin
   IsDefinitelyReal := False;
   IsDefinitelyGhost := False;
   for Feature in FFeatures do
   begin
      Feature.DescribeExistentiality(IsDefinitelyReal, IsDefinitelyGhost);
      if (IsDefinitelyReal) then
      begin
         Result := True;
         exit;
      end;
      if (IsDefinitelyGhost) then
      begin
         Assert(Mass = 0);
         Result := False;
         exit;
      end;
   end;
   Result := True;
end;

function TAssetNode.GetDebugName(): UTF8String;
begin
   Result := '<' + AssetClass.Name + ' @ ' + HexStr(Self) + ' "' + AssetName + '"' + '>';
end;


constructor TSystem.Create(AConfigurationDirectory: UTF8String; ASystemID: Cardinal; AX, AY: Double; ARootClass: TAssetClass; AServer: TBaseServer; ADynastyDatabase: TDynastyDatabase; AEncyclopedia: TEncyclopediaView; Settings: PSettings);
begin
   inherited Create();
   Init(AConfigurationDirectory, ASystemID, ARootClass, AServer, ADynastyDatabase, AEncyclopedia);
   FX := AX;
   FY := AY;
   FTimeOrigin := FServer.Clock.Now();
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

constructor TSystem.CreateFromDisk(AConfigurationDirectory: UTF8String; ASystemID: Cardinal; ARootClass: TAssetClass; AServer: TBaseServer; ADynastyDatabase: TDynastyDatabase; AEncyclopedia: TEncyclopediaView);
begin
   Init(AConfigurationDirectory, ASystemID, ARootClass, AServer, ADynastyDatabase, AEncyclopedia);
   ApplyJournal(FConfigurationDirectory + JournalDatabaseFileName);
   OpenJournal(FConfigurationDirectory + JournalDatabaseFileName); // This walks the entire tree, updates everything, writes it all to the journal, and cleans the dirty flags.
end;

procedure TSystem.Init(AConfigurationDirectory: UTF8String; ASystemID: Cardinal; ARootClass: TAssetClass; AServer: TBaseServer; ADynastyDatabase: TDynastyDatabase; AEncyclopedia: TEncyclopediaView);
begin
   FChanges := dkAll;
   FConfigurationDirectory := AConfigurationDirectory;
   FSystemID := ASystemID;
   FRandomNumberGenerator := TRandomNumberGenerator.Create(FSystemID);
   FServer := AServer;
   FDynastyDatabase := ADynastyDatabase;
   FDynastyIndices := TDynastyIndexHashTable.Create();
   FScheduledEvents := TSystemEventSet.Create(@SystemEventHash32);
   FEncyclopedia := AEncyclopedia;
   FRoot := TRootAssetNode.Create(ARootClass, Self, ARootClass.SpawnFeatureNodes());
   Exclude(FRoot.FDirty, dkNew);
end;

destructor TSystem.Destroy();
begin
   if (Assigned(FJournalWriter)) then
   begin
      FJournalWriter.Free();
      Close(FJournalFile);
   end;
   FRoot.Free();
   FScheduledEvents.Free();
   FDynastyIndices.Free();
   UnwindDynastyNotesArenas(FDynastyNotesBuffer);
   FRandomNumberGenerator.Free();
   inherited Destroy();
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
begin
   Assign(FJournalFile, FileName);
   FileMode := 0;
   Reset(FJournalFile, 1);
   JournalReader := TJournalReader.Create(Self);
   ID := JournalReader.ReadPtrUInt();
   FX := JournalReader.ReadDouble();
   FY := JournalReader.ReadDouble();
   FTimeOrigin := TDateTime(JournalReader.ReadDouble());
   JournalReader.FAssetMap[ID] := FRoot;
   try
      while (not EOF(FJournalFile)) do
      begin
         Code := JournalReader.ReadCardinal();
         case (Code) of
            jcSystemUpdate: begin
               try
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
                  while True do
                  begin
                     Asset := JournalReader.ReadAssetNodeReference();
                     if (not Assigned(Asset)) then
                        break;
                     if (FDynastyIndices.Count > 0) then
                        for Index := 0 to FDynastyIndices.Count - 1 do // $R-
                        begin
                           AssetID := TAssetID(JournalReader.ReadCardinal());
                           Asset.UpdateID(Self, Index, AssetID);
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
                  ID := JournalReader.ReadPtrUInt();
                  Asset := TAssetNode.Create(JournalReader, Self);
                  JournalReader.FAssetMap[ID] := Asset;
               except
                  ReportCurrentException();
                  raise;
               end;
            end;
            jcAssetChange: begin
               try
                  Asset := JournalReader.ReadAssetNodeReference();
                  Assert(Assigned(Asset));
                  Asset.ApplyJournal(JournalReader, Self);               
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
                  // The actual freeing will happen below when we clear out orphans.
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
      for Asset in JournalReader.FAssetMap.Values do
         if ((Asset <> FRoot) and not Assigned(Asset.Parent)) then
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
      FJournalWriter.WriteDouble(FTimeOrigin);
      FJournalWriter.WriteCardinal(jcSystemUpdate);
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

procedure TSystem.RecordUpdate();

   function SkipCleanChildren(Asset: TAssetNode): Boolean;
   begin
      Result := dkDescendant in Asset.Dirty;
   end;

   procedure RecordDirtyAsset(Asset: TAssetNode);
   begin
      if (dkSelf in Asset.Dirty) then
         Asset.UpdateJournal(Journal);
   end;

   function RecordAssetIDs(Asset: TAssetNode): Boolean;
   var
      Dynasty: TDynasty;
   begin
      Journal.WriteAssetNodeReference(Asset);
      for Dynasty in FDynastyIndices do
         Journal.WriteCardinal(Asset.ID(Self, FDynastyIndices[Dynasty], True {AllowZero}));
      Result := True;
   end;
   
begin
   if (dkAffectsTime in FChanges) then
   begin
      Journal.WriteCardinal(jcSystemUpdate);
      Journal.WriteUInt64(FRandomNumberGenerator.State);
      Journal.WriteDouble(FTimeFactor.AsDouble);
   end;
   FRoot.Walk(@SkipCleanChildren, @RecordDirtyAsset);
   if (dkAffectsDynastyCount in FChanges) then
   begin
      Journal.WriteCardinal(jcIDUpdates);
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
      Visibility := Asset.ReadVisibilityFor(CachedDynastyIndex, Self);
      if (Visibility <> []) then
      begin
         if ((dkSelf in Asset.FDirty) or not DirtyOnly) then
         begin
            FoundASelfDirty := True;
            Asset.Serialize(CachedDynastyIndex, Writer, Self);
         end;
         Result := (dkDescendant in Asset.FDirty) or not DirtyOnly;
      end
      else
         Result := False;
   end;

begin
   FoundASelfDirty := False;
   Assert(FDynastyIndices.Has(Dynasty));
   CachedDynastyIndex := DynastyIndex[Dynasty];
   Writer.WriteCardinal(SystemID);
   Writer.WriteInt64(Now.AsInt64);
   Writer.WriteDouble(FTimeFactor.AsDouble);
   Writer.WriteCardinal(FRoot.ID(Self, CachedDynastyIndex));
   Writer.WriteDouble(FX);
   Writer.WriteDouble(FY);
   FRoot.Walk(@Serialize, nil);
   Writer.WriteCardinal(0); // asset ID 0 marks end of system
   Result := FoundASelfDirty;
end;

procedure TSystem.Clean();

   function CleanAsset(Asset: TAssetNode): Boolean;
   begin
      Result := dkDescendant in Asset.FDirty;
      Asset.FDirty := [];
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
   Result := FDynastyIndices.Count;
end;

function TSystem.GetDynastyIndex(Dynasty: TDynasty): Cardinal;
begin
   Assert(FDynastyIndices.Has(Dynasty));
   Result := FDynastyIndices.Items[Dynasty];
end;

procedure TSystem.UnwindDynastyNotesArenas(Arena: Pointer);
begin
   if (Assigned(Arena)) then
   begin
      UnwindDynastyNotesArenas(Arena + MemSize(Arena) - SizeOf(Pointer));
      FreeMem(Arena);
   end;
end;

procedure TSystem.UpdateDynastyList(MaintainMaxIDs: Boolean);
var
   Dynasties: TDynastyHashSet;
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
      Asset.ResetDynastyNotes(FDynastyIndices, Dynasties, Self);
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
            FDynastyMaxAssetIDs[Index] := OldIDs[FDynastyIndices[Dynasty]]
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
   FRoot.Walk(@ResetDynasties, nil);
   Assert(((not Assigned(FDynastyNotesBuffer)) and (FDynastyNotesOffset = 0)) or (FDynastyNotesOffset = MemSize(FDynastyNotesBuffer) - SizeOf(Pointer)), 'FDynastyNotesOffset = ' + IntToStr(PtrUInt(FDynastyNotesBuffer)) + '; MemSize(FDynastyNotesOffset) = ' + IntToStr(MemSize(FDynastyNotesBuffer)));
   if (Assigned(OldBuffer)) then
      UnwindDynastyNotesArenas(OldBuffer);
   FDynastyIndices.Empty();
   Index := 0;
   for Dynasty in Dynasties do
   begin
      FDynastyIndices[Dynasty] := Index;
      Inc(Index);
   end;
   Assert(Index = Dynasties.Count);
   Assert(Index = FDynastyIndices.Count);
   FreeAndNil(Dynasties);
end;

procedure TSystem.RecomputeVisibility();
var
   VisibilityHelper: TVisibilityHelper;

   function ResetVisibility(Asset: TAssetNode): Boolean;
   begin
      Asset.ResetVisibility(Self);
      Result := True;
   end;

   function UpdateVisibility(Asset: TAssetNode): Boolean;
   begin
      Asset.ApplyVisibility(VisibilityHelper);
      Result := True;
   end;

   function CheckVisibility(Asset: TAssetNode): Boolean;
   begin
      Asset.CheckVisibilityChanged(VisibilityHelper);
      Result := True;
   end;
   
begin
   if (dkAffectsDynastyCount in FChanges) then
   begin
      UpdateDynastyList(True); // True means we maintain the FDynastyMaxAssetIDs
   end
   else
   begin
      FRoot.Walk(@ResetVisibility, nil);
   end;
   VisibilityHelper.Init(Self);
   FRoot.Walk(@UpdateVisibility, nil);
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
      SerializeSystem(Dynasty, TServerStreamWriter(Writer), True);
      Message := TServerStreamWriter(Writer).Serialize(False);
      Connection.WriteFrame(Message[1], Length(Message)); // $R-
      TServerStreamWriter(Writer).Clear();
   end;      

   function HandleChanges(Asset: TAssetNode): Boolean;
   begin
      Asset.HandleChanges();
      Result := (dkWillNeedChangesWalk * Asset.FDirty <> []) and (dkDescendant in Asset.FDirty);
   end;

begin
   if (not Dirty) then
      exit;
   Assert((dkAffectsVisibility in FChanges) or not (dkAffectsDynastyCount in FChanges)); // dkAffectsDynastyCount requires dkAffectsVisibility
   if (dkAffectsVisibility in FChanges) then
      RecomputeVisibility();
   if (dkWillNeedChangesWalk * FChanges <> []) then
      FRoot.Walk(@HandleChanges, nil);
   RecordUpdate();
   // TODO: tell the clients if anything stopped being visible? or is that implied?
   // TODO: tell the clients if _everything_ stopped being visible
   for Dynasty in FDynastyIndices do
   begin
      Dynasty.ForEachConnection(@ReportChange);
   end;
   Clean();
end;

function TSystem.HasDynasty(Dynasty: TDynasty): Boolean;
begin
   Result := FDynastyIndices.Has(Dynasty);
end;

procedure TSystem.RunEvent(var Data);
var
   Event: TSystemEvent;
begin
   Event := TSystemEvent(Data);
   Assert(Assigned(Event));
   Assert(FScheduledEvents.Has(Event));
   Assert(FNextEvent = Event);
   Assert(Assigned(FNextEventHandle));
   FScheduledEvents.Remove(Event);
   FNextEvent := nil;
   FNextEventHandle := nil;
   Event.FCallback(Event.FData);
   FreeAndNil(Event);
   if (not Assigned(FNextEvent)) then
   begin
      FNextEvent := SelectNextEvent();
      if (Assigned(FNextEvent)) then
         ScheduleNextEvent();
   end;
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
end;   

function TSystem.SelectNextEvent(): TSystemEvent;
var
   Event: TSystemEvent;
begin
   Result := nil;
   if (FScheduledEvents.IsNotEmpty) then
   begin
      Result := nil;
      for Event in FScheduledEvents do
      begin
         if (not Assigned(Result) or (Event.FTime < Result.FTime)) then
            Result := Event;
      end;
   end;
end;   

function TSystem.ScheduleEvent(TimeDelta: TMillisecondsDuration; Callback: TEventCallback; var Data): TSystemEvent;
begin
   Assert(Assigned(FNextEvent) = Assigned(FNextEventHandle));
   Assert(Assigned(FNextEvent) = FScheduledEvents.IsNotEmpty);
   Result := TSystemEvent.Create(
      Now + TimeDelta,
      Callback,
      Pointer(Data),
      Self
   );
   FScheduledEvents.Add(Result);
   if ((not Assigned(FNextEvent)) or (FNextEvent.FTime <= Result.FTime)) then
   begin
      if (Assigned(FNextEvent)) then
         FServer.CancelEvent(FNextEventHandle);
      Assert(not Assigned(FNextEventHandle));
      FNextEvent := Result;
      ScheduleNextEvent();
   end;
end;

procedure TSystem.CancelEvent(Event: TSystemEvent);
begin
   Assert(Assigned(Event));
   Assert(FScheduledEvents.Has(Event));
   FScheduledEvents.Remove(Event);
   if (Event = FNextEvent) then
   begin
      Assert(Assigned(FNextEventHandle));
      FServer.CancelEvent(FNextEventHandle);
      Assert(not Assigned(FNextEventHandle));
      if (FScheduledEvents.IsNotEmpty) then
      begin
         FNextEvent := SelectNextEvent();
         ScheduleNextEvent();
      end;
   end;
end;

function TSystem.TimeUntilNext(TimeOrigin: TTimeInMilliseconds; Period: TMillisecondsDuration): TMillisecondsDuration;
begin
   Result := Period - ((Now - TimeOrigin) mod Period);
end;

function TSystem.GetNow(): TTimeInMilliseconds;
begin
   Result := TTimeInMilliseconds(0) + TWallMillisecondsDuration(MillisecondsBetween(FServer.Clock.Now(), FTimeOrigin)) * FTimeFactor;
end;

function TSystem.FindCommandTarget(Dynasty: TDynasty; AssetID: TAssetID): TAssetNode;
var
   CachedDynastyIndex: Cardinal;
   FoundAsset: TAssetNode;
   
   function Search(Asset: TAssetNode): Boolean;
   begin
      if (((not Assigned(Asset.Owner)) or (Asset.Owner = Dynasty)) and (Asset.ID(Self, CachedDynastyIndex, True {AllowZero}) = AssetID)) then
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


constructor TDynastyNotes.Init(const AID: TAssetID);
begin
   FID := AID;
   FOldVisibilty := dmNil;
   FCurrentVisibility := dmNil;
end;
   
constructor TDynastyNotes.InitFrom(const Other: TDynastyNotes);
begin
   FID := Other.FID;
   FOldVisibilty := Other.FCurrentVisibility;
   FCurrentVisibility := dmNil;
end;

function TDynastyNotes.GetHasID(): Boolean;
begin
   Result := FID > 0;
end;

function TDynastyNotes.GetChanged(): Boolean;
begin
   Result := FOldVisibilty <> FCurrentVisibility;
end;

procedure TDynastyNotes.Snapshot();
begin
   FOldVisibilty := FCurrentVisibility;
   FCurrentVisibility := dmNil;
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
      if (IsLongMode) then
         FreeMem(AsRawPointer);
      AsShortDynasties[-1] := True;
      Assert(not IsLongMode);
   end;
end;
   
procedure TKnowledgeSummary.Done();
begin
   if (IsLongMode) then
      FreeMem(AsRawPointer);
   AsRawPointer := nil;
end;

function TKnowledgeSummary.IsLongMode(): Boolean;
begin
   Result := not AsShortDynasties[-1];
end;

procedure TKnowledgeSummary.SetEntry(DynastyIndex: Cardinal; Value: Boolean);
begin
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
   if (IsLongMode()) then
   begin
      Result := AsLongDynasties^[DynastyIndex];
   end
   else
   begin
      Result := AsShortDynasties[DynastyIndex];
   end;
end;


procedure TVisibilityHelper.Init(ASystem: TSystem);
begin
   FSystem := ASystem;
end;

function TVisibilityHelper.GetDynastyIndex(Dynasty: TDynasty): Cardinal;
begin
   Assert(FSystem.FDynastyIndices.Has(Dynasty));
   Result := FSystem.FDynastyIndices.Items[Dynasty];
end;

procedure TVisibilityHelper.AddSpecificVisibilityByIndex(const DynastyIndex: Cardinal; const Visibility: TVisibility; const Asset: TAssetNode);
var
   Current: TVisibility;
begin
   Assert(Assigned(Asset.Owner) or Asset.IsReal());
   Assert((FSystem.FDynastyIndices.Items[Asset.Owner] = DynastyIndex) or Asset.IsReal());
   Assert(Visibility <> []);
   if (FSystem.IsLongVisibilityMode) then
   begin
      Current := Asset.FDynastyNotes.AsLongDynasties^[DynastyIndex].Visibility;
      Asset.FDynastyNotes.AsLongDynasties^[DynastyIndex].Visibility := Current + Visibility;
   end
   else
   begin
      Assert(DynastyIndex >= Low(Asset.FDynastyNotes.AsShortDynasties));
      Assert(DynastyIndex <= High(Asset.FDynastyNotes.AsShortDynasties));
      Current := Asset.FDynastyNotes.AsShortDynasties[DynastyIndex].Visibility;
      Asset.FDynastyNotes.AsShortDynasties[DynastyIndex].Visibility := Current + Visibility;
   end;
   if ((not (dmInference in Current)) and Assigned(Asset.Parent)) then
   begin
      AddSpecificVisibilityByIndex(DynastyIndex, [dmInference], Asset.Parent.Parent);
   end;
end;

procedure TVisibilityHelper.AddSpecificVisibility(const Dynasty: TDynasty; const Visibility: TVisibility; const Asset: TAssetNode);
begin
   AddSpecificVisibilityByIndex(GetDynastyIndex(Dynasty), Visibility, Asset);
end;

procedure TVisibilityHelper.AddBroadVisibility(const Visibility: TVisibility; const Asset: TAssetNode);
var
   DynastyIndex, DynastyCount: Cardinal;
   Current: TVisibility;
begin
   Assert(Visibility <> []);
   Assert(Assigned(Asset));
   Assert(Asset.IsReal());
   DynastyCount := FSystem.FDynastyIndices.Count;
   if (DynastyCount = 0) then
      exit;
   if (FSystem.IsLongVisibilityMode) then
   begin
      for DynastyIndex := 0 to DynastyCount - 1 do // $R-
      begin
         Current := Asset.FDynastyNotes.AsLongDynasties^[DynastyIndex].Visibility;
         Asset.FDynastyNotes.AsLongDynasties^[DynastyIndex].Visibility := Current + Visibility;
      end;
   end
   else
   begin
      for DynastyIndex := 0 to DynastyCount - 1 do // $R-
      begin
         Current := Asset.FDynastyNotes.AsShortDynasties[DynastyIndex].Visibility;
         Asset.FDynastyNotes.AsShortDynasties[DynastyIndex].Visibility := Current + Visibility;
      end;
   end;
   if ((not (dmInference in Current)) and Assigned(Asset.Parent)) then
   begin
      for DynastyIndex := 0 to DynastyCount - 1 do // $R-
      begin
         AddSpecificVisibilityByIndex(DynastyIndex, [dmInference], Asset.Parent.Parent);
      end;
   end;
end;


constructor TRootAssetNode.Create(AAssetClass: TAssetClass; ASystem: TSystem; AFeatures: TFeatureNodeArray);
begin
   inherited Create(AAssetClass, nil, AFeatures);
   Assert(Assigned(ASystem));
   FSystem := ASystem;
end;

procedure TRootAssetNode.MarkAsDirty(DirtyKinds: TDirtyKinds);
begin
   inherited;
   FSystem.MarkAsDirty(DirtyKinds);
end;

procedure TRootAssetNode.ReportChildIsPermanentlyGone(Child: TAssetNode);
begin
   Assert(not Assigned(FParent));
   FSystem.ReportChildIsPermanentlyGone(Child);
end;

function TRootAssetNode.GetSystem(): TSystem;
begin
   Result := FSystem;
end;

end. 