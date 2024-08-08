{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit systems;

interface

uses
   systemdynasty, configuration, hashtable, hashset, genericutils, icons, serverstream;

type
   {$PUSH}
   {$PACKSET 1}
   TDetectionMechanism = (
      dmInference, // set on anything with a descendant with non-empty visibility
      dmVisibleSpectrum,
      dmClassKnown,
      dmInternals, // the dynasty can see internals (e.g. what happened last time the sensors triggered)
      dmReserved4, dmReserved5, dmReserved6, dmReserved7
   );
   TVisibility = set of TDetectionMechanism;
   {$POP}
   {$IF SIZEOF(TVisibility) <> SIZEOF(Byte)}
     {$FATAL TVisibility size error.}
   {$ENDIF}

const
   dmDetectable = [dmVisibleSpectrum];
   dmOwnership = [dmInference, dmVisibleSpectrum, dmInternals];
   
type
   TMaterial = class;
   TAssetClass = class;
   TAssetNode = class;
   TFeatureNode = class;
   TSystem = class;

   TAssetClassID = LongInt;
   
   TDynastyIndexHashTable = class(specialize THashTable<TDynasty, Cardinal, TObjectUtils>)
      constructor Create();
   end;

   TDynastyHashSet = class(specialize THashSet<TDynasty, TObjectUtils>)
      constructor Create();
   end;

   TMaterialHashTable = class(specialize THashTable<PtrUInt, TMaterial, PtrUIntUtils>)
      constructor Create();
   end;

   TAssetClassHashTable = class(specialize THashTable<TAssetClassID, TAssetClass, IntegerUtils>)
      constructor Create();
   end;

   TAssetNodeHashTable = class(specialize THashTable<PtrUInt, TAssetNode, PtrUIntUtils>)
      constructor Create();
   end;
   
   PVisibilitySummary = ^TVisibilitySummary;
   TVisibilitySummary = packed record
   const
      LongThreshold = 9;
   type
      PVisibilityData = ^TVisibilityData;
      TVisibilityData = packed array[0..0] of TVisibility;
   var
      case Integer of
         1: (ShortDynasties: array[0..7] of TVisibility); // 8 or fewer dynasties
         2: (LongDynasties: PVisibilityData); // 9 or more
         3: (RawPointer: Pointer);
   end;
   {$IF SIZEOF(TVisibilitySummary) <> SIZEOF(Pointer)}
     {$FATAL TVisibilitySummary size error.}
   {$ENDIF}

   TVisibilityHelper = record // 64 bits
   strict private
      FSystem: TSystem;
   private
      procedure Init(ASystem: TSystem); inline;
   public
      procedure AddSpecificVisibility(const Dynasty: TDynasty; const Visibility: TVisibility; const Asset: TAssetNode); inline;
      procedure AddSpecificVisibilityByIndex(const DynastyIndex: Cardinal; const Visibility: TVisibility; const Asset: TAssetNode);
      procedure AddBroadVisibility(const Visibility: TVisibility; const Asset: TAssetNode);
      property System: TSystem read FSystem;
   end;

   TAssetChangeKind = (ckAdd, ckRemove, ckMove);
   
   TJournalReader = class sealed
   private
      FSystem: TSystem;
      FAssetMap: TAssetNodeHashTable;
   public
      constructor Create(ASystem: TSystem);
      destructor Destroy(); override;
      function ReadCardinal(): Cardinal;
      function ReadPtrUInt(): PtrUInt;
      function ReadDouble(): Double;
      function ReadString(): UTF8String;
      function ReadAssetChangeKind(): TAssetChangeKind;
      function ReadAssetNodeReference(): TAssetNode;
      function ReadAssetClassReference(): TAssetClass;
      function ReadDynastyReference(): TDynasty;
   end;

   TJournalWriter = class sealed
   private
      FSystem: TSystem;
   public
      constructor Create(ASystem: TSystem);
      procedure WriteCardinal(Value: Cardinal); // {BOGUS Hint: Value parameter "Value" is assigned but never used}
      procedure WritePtrUInt(Value: PtrUInt); // {BOGUS Hint: Value parameter "Value" is assigned but never used}
      procedure WriteDouble(Value: Double); // {BOGUS Hint: Value parameter "Value" is assigned but never used}
      procedure WriteString(Value: UTF8String);
      procedure WriteAssetChangeKind(Value: TAssetChangeKind); // {BOGUS Hint: Value parameter "Value" is assigned but never used}
      procedure WriteAssetNodeReference(AssetNode: TAssetNode);
      procedure WriteAssetClassReference(AssetClass: TAssetClass);
      procedure WriteDynastyReference(Dynasty: TDynasty);
   end;

   TUnitKind = (
      ukBulkResource, // UI shows it in kilograms
      ukComponent // UI shows it as number of units
   );
   
   TMaterial = class
   protected
      FName, FAmbiguousName, FDescription: UTF8String;
      FIcon: TIcon;
      FUnitKind: TUnitKind;
      FMassPerUnit: Double; // kg
      FDensity: Double; // m^3
   public // encoded in knowledge
      property Name: UTF8String read FName;
      property Description: UTF8String read FDescription;
      property Icon: TIcon read FIcon;
      property UnitKind: TUnitKind read FUnitKind;
      property MassPerUnit: Double read FMassPerUnit; // kg
      property Density: Double read FDensity; // kg/m^3
   public // encoded inline
      function ID(System: TSystem): PtrUInt; inline;
      property AmbiguousName: UTF8String read FAmbiguousName;
   end;

   TMaterialLineItem = record // 24 bytes
      ComponentName: UTF8String;
      Material: TMaterial;
      Quantity: Cardinal; // units of material
   end;

   TMaterialLineItemArray = array of TMaterialLineItem;
   
   // The pre-walk callback is called for each asset in a depth-first
   // pre-order traversal of the asset/feature tree, and skips
   // children of nodes for which the callback returns false. The
   // post-walk callback is called after the children are processed
   // (or skipped).
   TPreWalkCallback = function(Asset: TAssetNode): Boolean is nested;
   TPostWalkCallback = procedure(Asset: TAssetNode) is nested;

   //FeatureClassReference = class of TFeatureClass;
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
      dkSelf, // this asset node is dirty, all ancestors have dkDescendant set
      dkNew, // this asset node is newly created
      dkDescendant // one or more of this asset node's descendants has dkSelf set (if not set, all descendants have an empty FDirty)
   );
   TDirtyKinds = set of TDirtyKind;
   TChangeKind = (
      ckAffectsDynastyCount, // system needs to redo a dynasty census (requires ckAffectsVisibility)
      ckAffectsVisibility, // system needs to redo a visibility scan
      ckAffectsNames // any nodes listening to names of descendants should consider itself dirty
   );
   TChangeKinds = set of TChangeKind;
   
   TFeatureNode = class abstract
   strict private
      FParent: TAssetNode;
   private
      procedure SetParent(Asset: TAssetNode); inline;
      function GetParent(): TAssetNode; inline;
   protected
      procedure AdoptChild(Child: TAssetNode); virtual;
      procedure DropChild(Child: TAssetNode); virtual;
      procedure MarkAsDirty(DirtyKinds: TDirtyKinds; ChangeKinds: TChangeKinds); virtual;
      function GetMass(): Double; virtual; abstract; // kg
      function GetSize(): Double; virtual; abstract; // m
      function GetFeatureName(): UTF8String; virtual; abstract;
      procedure Walk(PreCallback: TPreWalkCallback; PostCallback: TPostWalkCallback); virtual; abstract;
      procedure ApplyVisibility(VisibilityHelper: TVisibilityHelper); virtual; abstract;
      procedure InferVisibilityByIndex(DynastyIndex: Cardinal; VisibilityHelper: TVisibilityHelper); virtual;
      procedure Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter; System: TSystem); virtual; abstract;
      property Parent: TAssetNode read GetParent write SetParent;
      constructor CreateFromJournal(Journal: TJournalReader; AFeatureClass: TFeatureClass); virtual;
   public
      procedure RecordSnapshot(Journal: TJournalWriter); virtual; abstract;
      procedure ApplyJournal(Journal: TJournalReader); virtual; abstract;
      property Mass: Double read GetMass;
      property Size: Double read GetSize;
      property FeatureName: UTF8String read GetFeatureName;
   end;

   TFeatureNodeArray = array of TFeatureNode;
   
   TAssetClass = class
   private
      FID: TAssetClassID;
      FFeatures: TFeatureClassArray;
      FName, FAmbiguousName, FDescription: UTF8String;
      FIcon: TIcon;
      function GetFeature(Index: Cardinal): TFeatureClass;
      function GetFeatureCount(): Cardinal;
   public
      constructor Create(AID: TAssetClassID; AName, AAmbiguousName, ADescription: UTF8String; AFeatures: TFeatureClassArray; AIcon: TIcon);
      destructor Destroy(); override;
      function SpawnFeatureNodes(): TFeatureNodeArray; // some feature nodes _can't_ be spawned this way (e.g. TAssetNameFeatureNode)
      function SpawnFeatureNodesFromJournal(Journal: TJournalReader): TFeatureNodeArray;
      procedure ApplyFeatureNodesFromJournal(Journal: TJournalReader; AssetNode: TAssetNode);
      function Spawn(AOwner: TDynasty): TAssetNode; overload;
      function Spawn(AOwner: TDynasty; AFeatures: TFeatureNodeArray): TAssetNode; overload;
   public // encoded in knowledge
      procedure Serialize(AssetNode: TAssetNode; DynastyIndex: Cardinal; Writer: TServerStreamWriter; System: TSystem); virtual;
      property Features[Index: Cardinal]: TFeatureClass read GetFeature;
      property FeatureCount: Cardinal read GetFeatureCount;
      property Name: UTF8String read FName;
      property Description: UTF8String read FDescription;
      property Icon: TIcon read FIcon;
   public
      property ID: TAssetClassID read FID;
      property AmbiguousName: UTF8String read FAmbiguousName;
   end;

   TAssetClassDatabase = class
   protected
      function GetAssetClass(ID: TAssetClassID): TAssetClass; virtual; abstract;
   public
      property AssetClasses[ID: TAssetClassID]: TAssetClass read GetAssetClass;
   end;
   
   TAssetNode = class
   strict protected
      FAssetClass: TAssetClass;
      FOwner: TDynasty;
      FFeatures: TFeatureNodeArray;
   protected
      FParent: TFeatureNode;
      FDirty: TDirtyKinds;
      FVisibilitySummary: TVisibilitySummary;
      constructor Create(AAssetClass: TAssetClass; AOwner: TDynasty; AFeatures: TFeatureNodeArray);
      function GetFeature(Index: Cardinal): TFeatureNode;
      function GetMass(): Double; // kg
      function GetSize(): Double; // m
      function GetAssetName(): UTF8String;
      procedure MarkAsDirty(DirtyKinds: TDirtyKinds; ChangeKinds: TChangeKinds); virtual;
   public
      ParentData: Pointer;
      constructor Create(Journal: TJournalReader);
      constructor Create(); unimplemented;
      destructor Destroy(); override;
      procedure HandleImminentDeath();
      //function GetFeature(Key: FeatureClassReference): TFeatureNode;
      procedure Walk(PreCallback: TPreWalkCallback; PostCallback: TPostWalkCallback);
      procedure ApplyVisibility(VisibilityHelper: TVisibilityHelper);
      function ReadVisibilityFor(DynastyIndex: Cardinal; System: TSystem): TVisibility;
      procedure Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter; System: TSystem);
      procedure RecordSnapshot(Journal: TJournalWriter);
      procedure ApplyJournal(Journal: TJournalReader);
      function ID(System: TSystem): PtrUInt; inline;
      property Parent: TFeatureNode read FParent;
      property Dirty: TDirtyKinds read FDirty;
      property AssetClass: TAssetClass read FAssetClass;
      property Owner: TDynasty read FOwner;
      property Features[Index: Cardinal]: TFeatureNode read GetFeature;
      property Mass: Double read GetMass; // kg
      property Size: Double read GetSize; // meters
      property AssetName: UTF8String read GetAssetName;
   end;

   TSystem = class sealed
   strict private
      FDynastyDatabase: TDynastyDatabase;
      FAssetClassDatabase: TAssetClassDatabase;
      FAssets: TAssetNodeHashTable;
      FConfigurationDirectory: UTF8String;
      FSystemID: Cardinal;
      FX, FY: Double;
      FTimeOrigin: TDateTime;
      FTimeFactor: Double;
      FRoot: TAssetNode;
      FChanges: TChangeKinds;
      procedure Init(AConfigurationDirectory: UTF8String; ASystemID: Cardinal; ARootClass: TAssetClass; ADynastyDatabase: TDynastyDatabase; AAssetClassDatabase: TAssetClassDatabase);
      procedure ApplyJournal(FileName: UTF8String);
      procedure OpenJournal(FileName: UTF8String);
      procedure RecordUpdate();
      function GetDirty(): Boolean;
      procedure Clean();
      procedure RecomputeVisibility();
      function GetIsLongVisibilityMode(): Boolean; inline;
   private
      FDynastyIndices: TDynastyIndexHashTable; // for index into visibility tables; used by TVisibilityHelper
      FVisibilityBuffer: Pointer; // used by TVisibilityHelper
      FVisibilityOffset: Cardinal; // used by TVisibilityHelper
      FJournalFile: File; // used by TJournalReader/TJournalWriter
      FJournalWriter: TJournalWriter;
   protected
      procedure MarkAsDirty(ChangeKinds: TChangeKinds);
   public
      constructor Create(AConfigurationDirectory: UTF8String; ASystemID: Cardinal; AX, AY: Double; ARootClass: TAssetClass; ADynastyDatabase: TDynastyDatabase; AAssetClassDatabase: TAssetClassDatabase; Settings: PSettings);
      constructor CreateFromDisk(AConfigurationDirectory: UTF8String; ASystemID: Cardinal; ARootClass: TAssetClass; ADynastyDatabase: TDynastyDatabase; AAssetClassDatabase: TAssetClassDatabase);
      destructor Destroy(); override;
      function SerializeSystem(Dynasty: TDynasty; Writer: TServerStreamWriter; DirtyOnly: Boolean): Boolean; // true if anything was dkSelf dirty
      procedure ReportChanges();
      function HasDynasty(Dynasty: TDynasty): Boolean; inline;
      property RootNode: TAssetNode read FRoot;
      property Dirty: Boolean read GetDirty;
      property SystemID: Cardinal read FSystemID;
      property IsLongVisibilityMode: Boolean read GetIsLongVisibilityMode;
      property DynastyDatabase: TDynastyDatabase read FDynastyDatabase;
      property AssetClassDatabase: TAssetClassDatabase read FAssetClassDatabase; // used by TJournalReader/TJournalWriter
      property Journal: TJournalWriter read FJournalWriter;
   end;
   
implementation

uses
   sysutils, exceptions, hashfunctions, isdprotocol, providers, typedump, basenetwork, dateutils;

type
   TRootAssetNode = class(TAssetNode)
   protected
      FSystem: TSystem;
      procedure MarkAsDirty(DirtyKinds: TDirtyKinds; ChangeKinds: TChangeKinds); override;
   public
      constructor Create(AAssetClass: TAssetClass; ASystem: TSystem; AFeatures: TFeatureNodeArray);
   end;

function DynastyHash32(const Key: TDynasty): DWord;
begin
   Result := PtrUIntHash32(PtrUInt(Key));
end;

constructor TDynastyIndexHashTable.Create();
begin
   inherited Create(@DynastyHash32);
end;

constructor TDynastyHashSet.Create();
begin
   inherited Create(@DynastyHash32);
end;

constructor TMaterialHashTable.Create();
begin
   inherited Create(@PtrUIntHash32);
end;

constructor TAssetClassHashTable.Create();
begin
   inherited Create(@LongIntHash32);
end;

constructor TAssetNodeHashTable.Create();
begin
   inherited Create(@PtrUIntHash32);
end;


const
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

function TJournalReader.ReadCardinal(): Cardinal;
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
   Result := FSystem.AssetClassDatabase.AssetClasses[ID];
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


constructor TJournalWriter.Create(ASystem: TSystem);
begin
   inherited Create();
   FSystem := ASystem;
end;

procedure TJournalWriter.WriteCardinal(Value: Cardinal);
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
      WritePtrUInt(AssetNode.ID(FSystem));
   end
   else
   begin
      WritePtrUInt(0);
   end;
end;

procedure TJournalWriter.WriteAssetClassReference(AssetClass: TAssetClass);
begin
   Assert(Assigned(AssetClass));
   Assert(AssetClass.ID <> 0);
   WriteCardinal(Cardinal(AssetClass.ID));
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


constructor TFeatureNode.CreateFromJournal(Journal: TJournalReader; AFeatureClass: TFeatureClass);
begin
   inherited Create();
   ApplyJournal(Journal);
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

procedure TFeatureNode.AdoptChild(Child: TAssetNode);
begin
   Assert(not Assigned(Child.Parent));
   Assert(not Assigned(Child.ParentData));
   Child.FParent := Self;
   MarkAsDirty([dkSelf, dkDescendant], [ckAffectsDynastyCount, ckAffectsVisibility]);
end;

procedure TFeatureNode.DropChild(Child: TAssetNode);
begin
   Assert(Child.FParent = Self);
   Child.FParent := nil;
   Assert(not Assigned(Child.ParentData)); // subclass is responsible for freeing child's parent data
   MarkAsDirty([dkSelf], [ckAffectsDynastyCount, ckAffectsVisibility]);
end;

procedure TFeatureNode.MarkAsDirty(DirtyKinds: TDirtyKinds; ChangeKinds: TChangeKinds);
begin
   if (Assigned(FParent)) then
      FParent.MarkAsDirty(DirtyKinds, ChangeKinds);
end;


function TMaterial.ID(System: TSystem): PtrUInt;
begin
   Result := PtrUInt(Self) xor PtrUInt(System);
end;


procedure TFeatureNode.InferVisibilityByIndex(DynastyIndex: Cardinal; VisibilityHelper: TVisibilityHelper);
begin
   VisibilityHelper.AddSpecificVisibilityByIndex(DynastyIndex, [dmInference], Parent);
end;


constructor TAssetClass.Create(AID: TAssetClassID; AName, AAmbiguousName, ADescription: UTF8String; AFeatures: TFeatureClassArray; AIcon: TIcon);
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
end;

destructor TAssetClass.Destroy();
var
   Index: Cardinal;
begin
   if (Length(FFeatures) > 0) then
      for Index := 0 to High(FFeatures) do // $R-
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

function TAssetClass.SpawnFeatureNodesFromJournal(Journal: TJournalReader): TFeatureNodeArray;
var
   Index, FallbackIndex: Cardinal;
begin
   SetLength(Result, Length(FFeatures)); {BOGUS Warning: Function result variable of a managed type does not seem to be initialized}
   if (Length(Result) > 0) then
   begin
      for Index := Low(FFeatures) to High(FFeatures) do // $R-
      begin
         case (Journal.ReadCardinal()) of
            jcStartOfFeature:
               begin
                  Result[Index] := FFeatures[Index].FeatureNodeClass.CreateFromJournal(Journal, FFeatures[Index]);
                  if (Journal.ReadCardinal() <> jcEndOfFeature) then
                  begin
                     raise EJournalError.Create('missing end of feature marker (0x' + HexStr(jcEndOfFeature, 8) + ')');
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
   if (Journal.ReadCardinal() <> jcEndOfFeatures) then
   begin
      raise EJournalError.Create('missing end of features marker (0x' + HexStr(jcEndOfFeatures, 8) + ')');
   end;
end;

procedure TAssetClass.ApplyFeatureNodesFromJournal(Journal: TJournalReader; AssetNode: TAssetNode);
var
   Index: Cardinal;
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
   if (Journal.ReadCardinal() <> jcEndOfFeatures) then
   begin
      raise EJournalError.Create('missing end of features marker (0x' + HexStr(jcEndOfFeatures, 8) + ')');
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

procedure TAssetClass.Serialize(AssetNode: TAssetNode; DynastyIndex: Cardinal; Writer: TServerStreamWriter; System: TSystem);
var
   Visibility: TVisibility;
   Detectable, Recognizable: Boolean;
   ReportedIcon, ReportedName, ReportedDescription: UTF8String;
begin
   Visibility := AssetNode.ReadVisibilityFor(DynastyIndex, System);
   Detectable := dmDetectable * Visibility <> [];
   Recognizable := dmClassKnown in Visibility;
   ReportedIcon := FIcon;
   if (Detectable and Recognizable) then
   begin
      ReportedName := FName;
      ReportedDescription := FDescription;
   end
   else
   begin
      ReportedName := FAmbiguousName;
      if (Detectable) then
      begin
         Assert(not Recognizable);
         ReportedDescription := 'Unknown object type.';
      end
      else
      begin
         ReportedDescription := 'Not currently visible or otherwise detectable.';
      end;
   end;
   Writer.WriteStringReference(ReportedIcon);
   Writer.WriteStringReference(ReportedName);
   Assert(ReportedDescription <> '');
   Writer.WriteStringReference(ReportedDescription);
end;
   

constructor TAssetNode.Create(AAssetClass: TAssetClass; AOwner: TDynasty; AFeatures: TFeatureNodeArray);
var
   Feature: TFeatureNode;
begin
   inherited Create();
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
   FDirty := [dkNew, dkSelf, dkDescendant];
end;

constructor TAssetNode.Create(Journal: TJournalReader);
begin
   inherited Create();
   ApplyJournal(Journal);
end;

constructor TAssetNode.Create();
begin
   Writeln('Invalid constructor call for ', ClassName, '.');
   raise Exception.Create('Invalid constructor call');
end;

destructor TAssetNode.Destroy();
var
   Index: Cardinal;
begin
   if (Length(FFeatures) > 0) then
      for Index := 0 to High(FFeatures) do // $R-
         FFeatures[Index].Free();
   inherited;
end;

procedure TAssetNode.HandleImminentDeath();
begin
   if (Assigned(FOwner)) then
      FOwner.DecRef();
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

procedure TAssetNode.MarkAsDirty(DirtyKinds: TDirtyKinds; ChangeKinds: TChangeKinds);
begin
   FDirty := FDirty + DirtyKinds;
   if (Assigned(FParent)) then
   begin
      Exclude(DirtyKinds, dkSelf);
      Include(DirtyKinds, dkDescendant);
      FParent.Parent.MarkAsDirty(DirtyKinds, ChangeKinds);
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

procedure TAssetNode.ApplyVisibility(VisibilityHelper: TVisibilityHelper);
var
   Feature: TFeatureNode;
begin
   if (Assigned(FOwner)) then
      VisibilityHelper.AddSpecificVisibility(FOwner, dmOwnership, Self);
   for Feature in FFeatures do
      Feature.ApplyVisibility(VisibilityHelper);
end;

function TAssetNode.ReadVisibilityFor(DynastyIndex: Cardinal; System: TSystem): TVisibility;
begin
   if (System.IsLongVisibilityMode) then
   begin
      Result := FVisibilitySummary.LongDynasties^[DynastyIndex];
   end
   else
   begin
      Result := FVisibilitySummary.ShortDynasties[DynastyIndex];
   end;
end;

procedure TAssetNode.Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter; System: TSystem);
var
   Feature: TFeatureNode;
begin
   Writer.WritePtrUInt(ID(System));
   if (Assigned(FOwner)) then
   begin
      Writer.WriteCardinal(FOwner.DynastyID);
   end
   else
   begin
      Writer.WriteCardinal(0);
   end;
   Writer.WriteDouble(Mass);
   Writer.WriteDouble(Size);
   Writer.WriteStringReference(AssetName);
   FAssetClass.Serialize(Self, DynastyIndex, Writer, System);
   for Feature in FFeatures do
      Feature.Serialize(DynastyIndex, Writer, System);
   Writer.WriteCardinal(fcTerminator);
end;

procedure TAssetNode.RecordSnapshot(Journal: TJournalWriter);
var
   Feature: TFeatureNode;
begin
   Journal.WriteAssetClassReference(FAssetClass);
   Journal.WriteDynastyReference(FOwner);
   for Feature in FFeatures do
   begin
      Journal.WriteCardinal(jcStartOfFeature);
      Feature.RecordSnapshot(Journal);
      Journal.WriteCardinal(jcEndOfFeature);
   end;
   Journal.WriteCardinal(jcEndOfFeatures);
   Journal.WriteCardinal(jcEndOfAsset);
end;

procedure TAssetNode.ApplyJournal(Journal: TJournalReader);
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
      FFeatures := FAssetClass.SpawnFeatureNodesFromJournal(Journal);
      for Feature in FFeatures do
         Feature.SetParent(Self);
   end
   else
   begin
      FAssetClass.ApplyFeatureNodesFromJournal(Journal, Self);
   end;
   if (Journal.ReadCardinal() <> jcEndOfAsset) then
   begin
      raise EJournalError.Create('missing end of asset marker (0x' + HexStr(jcEndOfAsset, 8) + ')');
   end;
end;

function TAssetNode.ID(System: TSystem): PtrUInt;
begin
   Result := PtrUInt(Self) xor PtrUInt(System);
end;


constructor TSystem.Create(AConfigurationDirectory: UTF8String; ASystemID: Cardinal; AX, AY: Double; ARootClass: TAssetClass; ADynastyDatabase: TDynastyDatabase; AAssetClassDatabase: TAssetClassDatabase; Settings: PSettings);
begin
   inherited Create();
   Init(AConfigurationDirectory, ASystemID, ARootClass, ADynastyDatabase, AAssetClassDatabase);
   FX := AX;
   FY := AY;
   FTimeOrigin := Now();
   FTimeFactor := Settings^.DefaultTimeRate;
   try
      Assert(not DirectoryExists(FConfigurationDirectory));
      MkDir(FConfigurationDirectory);
   except
      ReportCurrentException();
      raise;
   end;
   OpenJournal(FConfigurationDirectory + JournalDatabaseFileName);
end;

constructor TSystem.CreateFromDisk(AConfigurationDirectory: UTF8String; ASystemID: Cardinal; ARootClass: TAssetClass; ADynastyDatabase: TDynastyDatabase; AAssetClassDatabase: TAssetClassDatabase);
begin
   Init(AConfigurationDirectory, ASystemID, ARootClass, ADynastyDatabase, AAssetClassDatabase);
   ApplyJournal(FConfigurationDirectory + JournalDatabaseFileName);
   OpenJournal(FConfigurationDirectory + JournalDatabaseFileName);
end;

procedure TSystem.Init(AConfigurationDirectory: UTF8String; ASystemID: Cardinal; ARootClass: TAssetClass; ADynastyDatabase: TDynastyDatabase; AAssetClassDatabase: TAssetClassDatabase);
begin
   FConfigurationDirectory := AConfigurationDirectory;
   FSystemID := ASystemID;
   FDynastyDatabase := ADynastyDatabase;
   FDynastyIndices := TDynastyIndexHashTable.Create();
   FAssetClassDatabase := AAssetClassDatabase;
   FRoot := TRootAssetNode.Create(ARootClass, Self, ARootClass.SpawnFeatureNodes());
   FAssets := TAssetNodeHashTable.Create();
   FAssets.Add(FRoot.ID(Self), FRoot);
end;

destructor TSystem.Destroy();
begin
   if (Assigned(FJournalWriter)) then
   begin
      FJournalWriter.Free();
      Close(FJournalFile);
   end;
   FAssets.Free();
   FRoot.Free();
   FDynastyIndices.Free();
   if (Assigned(FVisibilityBuffer)) then
   begin
      FreeMem(FVisibilityBuffer);
      FVisibilityBuffer := nil;
   end;
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
   Code: Cardinal;
begin
   Assign(FJournalFile, FileName);
   FileMode := 0;
   Reset(FJournalFile, 1);
   JournalReader := TJournalReader.Create(Self);
   ID := JournalReader.ReadPtrUInt();
   FX := JournalReader.ReadDouble();
   FY := JournalReader.ReadDouble();
   FTimeOrigin := TDateTime(JournalReader.ReadDouble());
   FTimeFactor := JournalReader.ReadDouble();
   JournalReader.FAssetMap[ID] := FRoot;
   while (not EOF(FJournalFile)) do
   begin
      Code := JournalReader.ReadCardinal();
      ID := JournalReader.ReadPtrUInt();
      case (Code) of
         jcNewAsset: begin
            Asset := TAssetNode.Create(JournalReader);
            JournalReader.FAssetMap[ID] := Asset;
         end;
         jcAssetChange: begin
            Asset := JournalReader.FAssetMap[ID];
            Asset.ApplyJournal(JournalReader);               
         end;
      else
         raise EJournalError.Create('Unknown operation code in system journal (0x' + HexStr(Code, 8) + '), expected either new asset (0x' + HexStr(jcNewAsset, 8) + ') or asset change (0x' + HexStr(jcAssetChange, 8) + ') marker');
      end;
   end;
   JournalReader.Free();
   Close(FJournalFile);
   FRoot.Walk(nil, @IncRefDynasties);
   RecomputeVisibility();
end;

procedure TSystem.OpenJournal(FileName: UTF8String);
var
   JournalWriter: TJournalWriter;

   procedure RecordAsset(Asset: TAssetNode);
   begin
      if (Asset = FRoot) then
      begin
         JournalWriter.WriteCardinal(jcAssetChange);
      end
      else
      begin
         JournalWriter.WriteCardinal(jcNewAsset);
      end;
      JournalWriter.WritePtrUInt(Asset.ID(Self));
      Asset.RecordSnapshot(JournalWriter);
   end;
   
begin
   try
      Assign(FJournalFile, FileName + TemporaryExtension);
      FileMode := 1;
      Rewrite(FJournalFile, 1);
      JournalWriter := TJournalWriter.Create(Self);
      JournalWriter.WritePtrUInt(FRoot.ID(Self));
      JournalWriter.WriteDouble(FX);
      JournalWriter.WriteDouble(FY);
      JournalWriter.WriteDouble(FTimeOrigin);
      JournalWriter.WriteDouble(FTimeFactor);
      FRoot.Walk(nil, @RecordAsset);
      Close(FJournalFile);
      DeleteFile(FileName);
      RenameFile(FileName + TemporaryExtension, FileName);
      Clean();
      Assign(FJournalFile, FileName);
      FileMode := 2;
      Reset(FJournalFile, 1);
      Seek(FJournalFile, FileSize(FJournalFile));
      FJournalWriter := JournalWriter;
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
      begin
         if (dkNew in Asset.Dirty) then
         begin
            Journal.WriteCardinal(jcNewAsset);
         end
         else
         begin
            Journal.WriteCardinal(jcAssetChange);
         end;
         Journal.WritePtrUInt(Asset.ID(Self));
         Asset.RecordSnapshot(Journal);
      end;
   end;
   
begin
   FRoot.Walk(@SkipCleanChildren, @RecordDirtyAsset);
end;

procedure TSystem.MarkAsDirty(ChangeKinds: TChangeKinds);
begin
   FChanges := FChanges + ChangeKinds;
end;

function TSystem.GetDirty(): Boolean;
begin
   Result := FRoot.Dirty <> [];
end;

function TSystem.SerializeSystem(Dynasty: TDynasty; Writer: TServerStreamWriter; DirtyOnly: Boolean): Boolean;
var
   FoundASelfDirty: Boolean;
   DynastyIndex: Cardinal;
   
   function Serialize(Asset: TAssetNode): Boolean;
   var
      Visibility: TVisibility;
   begin
      Visibility := Asset.ReadVisibilityFor(DynastyIndex, Self);
      if (Visibility <> []) then
      begin
         if ((dkSelf in Asset.FDirty) or not DirtyOnly) then
         begin
            FoundASelfDirty := True;
            Asset.Serialize(DynastyIndex, Writer, Self);
         end;
         Result := (dkDescendant in Asset.FDirty) or not DirtyOnly;
      end
      else
         Result := False;
   end;

begin
   FoundASelfDirty := False;
   Assert(FDynastyIndices.Has(Dynasty));
   DynastyIndex := FDynastyIndices[Dynasty];
   Writer.WriteCardinal(SystemID);
   Writer.WriteInt64(MillisecondsBetween(Now() * FTimeFactor, FTimeOrigin * FTimeFactor));
   Writer.WriteDouble(FTimeFactor);
   Writer.WritePtrUInt(FRoot.ID(Self));
   Writer.WriteDouble(FX);
   Writer.WriteDouble(FY);
   FRoot.Walk(@Serialize, nil);
   Writer.WritePtrUInt(0); // asset ID 0 marks end of system
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
end;

function TSystem.GetIsLongVisibilityMode(): Boolean;
begin
   Result := FDynastyIndices.Count >= TVisibilitySummary.LongThreshold;
end;

procedure TSystem.RecomputeVisibility();
var
   Dynasties: TDynastyHashSet;
   NodeCount: Cardinal;
   
   function TrackDynasties(Asset: TAssetNode): Boolean;
   begin
      if (Assigned(Asset.Owner)) then
         Dynasties.Add(Asset.Owner);
      Inc(NodeCount);
      Asset.FVisibilitySummary.RawPointer := nil;
      Result := True;
   end;

var
   VisibilityHelper: TVisibilityHelper;

   function UpdateVisibility(Asset: TAssetNode): Boolean;
   begin
      Asset.ApplyVisibility(VisibilityHelper);
      Result := True;
   end;
   
var
   Index, BufferSize: Cardinal;
   Dynasty: TDynasty;
begin
   if (ckAffectsDynastyCount in FChanges) then
   begin
      NodeCount := 0;
      Dynasties := TDynastyHashSet.Create();
      FRoot.Walk(@TrackDynasties, nil);
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
   if (Assigned(FVisibilityBuffer)) then
   begin
      FreeMem(FVisibilityBuffer);
      FVisibilityBuffer := nil;
   end;
   if (IsLongVisibilityMode) then
   begin
      Assert(SizeOf(TVisibility) = 1);
      Assert(FDynastyIndices.Count < High(Cardinal) div NodeCount);
      BufferSize := FDynastyIndices.Count * SizeOf(TVisibility) * NodeCount; // $R-
      FVisibilityBuffer := GetMem(BufferSize);
      FillByte(FVisibilityBuffer^, BufferSize, 0);
   end;
   VisibilityHelper.Init(Self);
   FRoot.Walk(@UpdateVisibility, nil);
   FChanges := FChanges - [ckAffectsDynastyCount, ckAffectsVisibility];
end;

procedure TSystem.ReportChanges();
var
   Dynasty: TDynasty;

   procedure ReportChange(Connection: TBaseIncomingCapableConnection; Writer: Pointer);
   begin
      Assert(TServerStreamWriter(Writer).BufferLength = 0);
      SerializeSystem(Dynasty, TServerStreamWriter(Writer), True);
      Connection.Write(TServerStreamWriter(Writer).Serialize(False));
      TServerStreamWriter(Writer).Clear();
   end;      

begin
   if (not Dirty) then
      exit;
   Assert((ckAffectsVisibility in FChanges) or not (ckAffectsDynastyCount in FChanges)); // ckAffectsDynastyCount requires ckAffectsVisibility
   RecordUpdate();
   if (ckAffectsVisibility in FChanges) then
      RecomputeVisibility();
   // TODO: tell the clients if anything stopped being visible
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


procedure TVisibilityHelper.Init(ASystem: TSystem);
begin
   FSystem := ASystem;
   FSystem.FVisibilityOffset := 0;
end;

procedure TVisibilityHelper.AddSpecificVisibilityByIndex(const DynastyIndex: Cardinal; const Visibility: TVisibility; const Asset: TAssetNode);
var
   Current: TVisibility;
begin
   Assert(Visibility <> []);
   if (FSystem.IsLongVisibilityMode) then
   begin
      if (not Assigned(Asset.FVisibilitySummary.LongDynasties)) then
      begin
         Assert(Assigned(FSystem.FVisibilityBuffer));
         Asset.FVisibilitySummary.RawPointer := FSystem.FVisibilityBuffer + FSystem.FVisibilityOffset;
         Inc(FSystem.FVisibilityOffset, SizeOf(TVisibility) * FSystem.FDynastyIndices.Count);
      end;
      Current := Asset.FVisibilitySummary.LongDynasties^[DynastyIndex];
      Asset.FVisibilitySummary.LongDynasties^[DynastyIndex] := Current + Visibility;
   end
   else
   begin
      Assert(DynastyIndex >= Low(Asset.FVisibilitySummary.ShortDynasties));
      Assert(DynastyIndex <= High(Asset.FVisibilitySummary.ShortDynasties));
      Current := Asset.FVisibilitySummary.ShortDynasties[DynastyIndex];
      Asset.FVisibilitySummary.ShortDynasties[DynastyIndex] := Current + Visibility;
   end;
   if ((not (dmInference in Current)) and Assigned(Asset.Parent)) then
   begin
      Asset.Parent.InferVisibilityByIndex(DynastyIndex, Self);
   end;
end;

procedure TVisibilityHelper.AddSpecificVisibility(const Dynasty: TDynasty; const Visibility: TVisibility; const Asset: TAssetNode);
begin
   AddSpecificVisibilityByIndex(FSystem.FDynastyIndices.Items[Dynasty], Visibility, Asset);
end;

procedure TVisibilityHelper.AddBroadVisibility(const Visibility: TVisibility; const Asset: TAssetNode);
var
   DynastyIndex, DynastyCount: Cardinal;
   Current: TVisibility;
begin
   Assert(Visibility <> []);
   Assert(Assigned(Asset));
   DynastyCount := FSystem.FDynastyIndices.Count;
   if (DynastyCount = 0) then
      exit;
   if (FSystem.IsLongVisibilityMode) then
   begin
      if (not Assigned(Asset.FVisibilitySummary.LongDynasties)) then
      begin
         Assert(Assigned(FSystem.FVisibilityBuffer));
         Asset.FVisibilitySummary.RawPointer := FSystem.FVisibilityBuffer + FSystem.FVisibilityOffset;
         Inc(FSystem.FVisibilityOffset, SizeOf(TVisibility) * FSystem.FDynastyIndices.Count);
         FillByte(Asset.FVisibilitySummary.RawPointer^, DynastyCount, Byte(Visibility));
         AddBroadVisibility([dmInference], Asset.Parent.Parent);
      end
      else
      begin
         for DynastyIndex := 0 to DynastyCount - 1 do // $R-
         begin
            Current := Asset.FVisibilitySummary.LongDynasties^[DynastyIndex];
            if (not (dmInference in Current)) then
               AddSpecificVisibilityByIndex(DynastyIndex, [dmInference], Asset.Parent.Parent);
            Asset.FVisibilitySummary.LongDynasties^[DynastyIndex] := Current + Visibility;
         end;
      end;
   end
   else
   begin
      for DynastyIndex := 0 to DynastyCount - 1 do // $R-
      begin
         Current := Asset.FVisibilitySummary.ShortDynasties[DynastyIndex];
         if ((not (dmInference in Current)) and (Assigned(Asset.Parent))) then
            AddSpecificVisibilityByIndex(DynastyIndex, [dmInference], Asset.Parent.Parent);
         Asset.FVisibilitySummary.ShortDynasties[DynastyIndex] := Current + Visibility;
      end;
   end;
end;


constructor TRootAssetNode.Create(AAssetClass: TAssetClass; ASystem: TSystem; AFeatures: TFeatureNodeArray);
begin
   inherited Create(AAssetClass, nil, AFeatures);
   Assert(Assigned(ASystem));
   FSystem := ASystem;
end;

procedure TRootAssetNode.MarkAsDirty(DirtyKinds: TDirtyKinds; ChangeKinds: TChangeKinds);
begin
   inherited;
   FSystem.MarkAsDirty(ChangeKinds);
end;

end.