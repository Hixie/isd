{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit model;

interface

uses
   hashtable, binarystream, genericutils, isdprotocol, plasticarrays, unixutils, stringutils;

type
   TModelSystem = class;
   TModelAsset = class;
   TModelFeature = class;
   TAssetList = array of TModelAsset;
   TFeatureList = array of TModelFeature;

   TAssetPredicate = reference to function(Asset: TModelAsset): Boolean;
   TAssetWalkChildrenCallback = procedure(Asset: TModelAsset) is nested;

   PArena = ^TArena;
   TArena = packed record
   private
      type
         Placeholder = record end;
      var
         FModelSystem: TModelSystem;
         FPrevious: PArena;
         FTop: Pointer; // next thing we can allocate
         FBottom: Placeholder; // first thing in arena
   public
      class function FromPointer(Ptr: Pointer): PArena; static; inline;
      class function AllocateArena(ModelSystem: TModelSystem): PArena; static;
      class procedure FreeArena(var Arena: PArena); static;
      class function AllocateObject(var Arena: PArena; Size: PtrUInt): Pointer; static;
      class procedure FreeObject(Arena: PArena; Instance: Pointer); static;
      property ModelSystem: TModelSystem read FModelSystem;
   end;

   PAssetClass = ^TAssetClass;
   TAssetClass = record
      ID: Int32;
      Icon: UTF8String;
      Name: UTF8String;
      Description: UTF8String;
   end;

   TServerStreamReader = class(TBinaryStreamReader)
   private
      FModel: TModelSystem;
   public
      constructor Create(const Input: RawByteString; AModel: TModelSystem);
      function ReadStringReference(): UTF8String;
      function ReadAssetClass(ZeroIndicatesNil: Boolean): PAssetClass;
   end;

   TModelSystem = class
   strict private
      type
         TStringHashTable = specialize THashTable<UInt32, UTF8String, CardinalUtils>;
         TAssetClassHashTable = specialize THashTable<Int32, TAssetClass, LongintUtils>;
         TModelAssetHashTable = specialize THashTable<UInt32, TModelAsset, CardinalUtils>;
         TModelAssetArray = specialize PlasticArray<TModelAsset, TObjectUtils>;
      var
         FAssets: TModelAssetHashTable;
         FUpdates: TModelAssetArray;
         FLastUpdates: TAssetList;
      function GetAsset(ID: UInt32): TModelAsset;
      function GetUpdatesLength(): Cardinal; inline;
   private
      var
         FArena: PArena;
         FStrings: TStringHashTable;
         FAssetClasses: TAssetClassHashTable;
         FUnknownAssetClasses: specialize PlasticArray<PAssetClass, PointerUtils>;
   public
      constructor Create();
      destructor Destroy(); override;
      procedure UpdateFrom(Stream: TServerStreamReader);
      property UpdateCount: Cardinal read GetUpdatesLength;
      function GetUpdatedAssets(): TAssetList;
      function DescribeSystem(): UTF8String;
   public
      SystemID: UInt32;
      CurrentTime: Int64;
      TimeFactor: Double;
      RootAsset: UInt32;
      X, Y: Double;
      property Assets[ID: UInt32]: TModelAsset read GetAsset;
      function FindAssets(Predicate: TAssetPredicate): TAssetList;
   end;

   TModelFeatureClass = class of TModelFeature;

   {$PUSH}
   {$M+}
   TModelAsset = class
   strict private
      FID: UInt32;
      FFeatures: specialize PlasticArray <TModelFeature, TObjectUtils>;
      function GetFeature(FeatureClass: TModelFeatureClass): TModelFeature;
      function GetFeatureCount(): Cardinal; inline;
      function GetModelSystem(): TModelSystem; inline;
      function GetParent(): TModelAsset; inline;
   private
      FParent: TModelFeature;
   protected
      procedure WalkChildren(Callback: TAssetWalkChildrenCallback);
   public
      constructor Create(AID: UInt32);
      class function NewInstance(): TModelAsset; override;
      procedure FreeInstance(); override;
      class function CreateFor(System: TModelSystem; AID: UInt32): TModelAsset;
      destructor Destroy(); override;
      procedure UpdateFrom(Stream: TServerStreamReader);
      property ModelSystem: TModelSystem read GetModelSystem;
   strict private
      FOwner: UInt32; // dynasty ID
      FMass: Double;
      FMassFlowRate: Double;
      FSize: Double;
      FName: UTF8String;
      FAssetClass: PAssetClass;
   published
      property Owner: UInt32 read FOwner write FOwner;
      property Mass: Double read FMass write FMass;
      property MassFlowRate: Double read FMassFlowRate write FMassFlowRate;
      property Size: Double read FSize write FSize;
      property Name: UTF8String read FName write FName;
   public
      function HasFeature(FeatureClass: TModelFeatureClass): Boolean;
      property ID: UInt32 read FID;
      property Parent: TModelAsset read GetParent;
      property Features[FeatureClass: TModelFeatureClass]: TModelFeature read GetFeature;
      function GetFeatures(): TFeatureList;
      property FeatureCount: Cardinal read GetFeatureCount;
      function ToString(): UTF8String; override;
      procedure Describe(var Output: specialize PlasticArray<UTF8String, UTF8StringUtils>; Indent: UTF8String = '');
      property AssetClass: PAssetClass read FAssetClass write FAssetClass;
   end;

   TModelFeature = class abstract
   private
      FParent: TModelAsset;
   protected
      procedure ResetChildren(); virtual;
      procedure WalkChildren(Callback: TAssetWalkChildrenCallback); virtual;
      function GetModelSystem(): TModelSystem; inline;
   public
      constructor Create(AParent: TModelAsset); virtual;
      class function NewInstance(): TModelFeature; override;
      procedure FreeInstance(); override;
      class function CreateFor(System: TModelSystem; Parent: TModelAsset): TModelFeature; virtual;
      procedure UpdateFrom(Stream: TServerStreamReader); virtual; abstract;
      property Parent: TModelAsset read FParent;
      property ModelSystem: TModelSystem read GetModelSystem;
      procedure Describe(var Output: specialize PlasticArray<UTF8String, UTF8StringUtils>; Indent: UTF8String = ''); virtual;
   end;
   {$POP}

   TModelStarFeature = class (TModelFeature)
   public
      procedure UpdateFrom(Stream: TServerStreamReader); override;
   strict private
      FStarID: UInt32;
   published
      property StarID: UInt32 read FStarID write FStarID;
   end;

   TModelSpaceFeature = class (TModelFeature)
   public
      type
         TChild = record
            AssetID: UInt32;
            X, Y: Double;
         end;
   protected
      procedure ResetChildren(); override;
      procedure WalkChildren(Callback: TAssetWalkChildrenCallback); override;
   public
      procedure UpdateFrom(Stream: TServerStreamReader); override;
   public
      Children: specialize PlasticArray <TChild, specialize IncomparableUtils<TChild>>;
   end;

   TModelOrbitFeature = class (TModelFeature)
   public
      type
         TChild = record
            AssetID: UInt32;
            SemiMajorAxis, Eccentricity, Omega: Double;
            TimeOrigin: Int64;
            Clockwise: Boolean;
         end;
   protected
      procedure ResetChildren(); override;
      procedure WalkChildren(Callback: TAssetWalkChildrenCallback); override;
   public
      procedure UpdateFrom(Stream: TServerStreamReader); override;
   strict private
      FPrimaryAssetID: UInt32;
   public
      Children: specialize PlasticArray <TChild, specialize IncomparableUtils<TChild>>;
   published
      property PrimaryAssetID: UInt32 read FPrimaryAssetID write FPrimaryAssetID;
   end;

   TModelStructureFeature = class (TModelFeature)
   public
      type
         TMaterialLineItem = record
            Max: UInt32;
            ComponentName, MaterialName: UTF8String;
            MaterialID: Int32;
         end;
      procedure UpdateFrom(Stream: TServerStreamReader); override;
   public
      LineItems: specialize PlasticArray <TMaterialLineItem, specialize IncomparableUtils<TMaterialLineItem>>;
   strict private
      FBuilderID: UInt32;
      FQuantity: UInt32;
      FQuantityRate: Double;
      FHp: UInt32;
      FHpRate: Double;
      FMinHp: UInt32;
   published
      property BuilderID: UInt32 read FBuilderID write FBuilderID;
      property Quantity: UInt32 read FQuantity write FQuantity;
      property QuantityRate: Double read FQuantityRate write FQuantityRate;
      property Hp: UInt32 read FHp write FHp;
      property HpRate: Double read FHpRate write FHpRate;
      property MinHp: UInt32 read FMinHp write FMinHp;
   end;

   TModelSpaceSensorFeature = class (TModelFeature)
   public
      procedure UpdateFrom(Stream: TServerStreamReader); override;
   strict private
      FDisabledReasons: Cardinal;
      FReach, FUp, FDown: UInt32;
      FResolution: Double;
   published
      property DisabledReasons: Cardinal read FDisabledReasons write FDisabledReasons;
      property Reach: UInt32 read FReach write FReach;
      property Up: UInt32 read FUp write FUp;
      property Down: UInt32 read FDown write FDown;
      property Resolution: Double read FResolution write FResolution;
   end;

   TModelSpaceSensorStatusFeature = class (TModelFeature)
   public
      procedure UpdateFrom(Stream: TServerStreamReader); override;
   strict private
      FNearestOrbitAssetID, FTopOrbitAssetID: UInt32;
      FCount: UInt32;
   published
      property NearestOrbitAssetID: UInt32 read FNearestOrbitAssetID write FNearestOrbitAssetID;
      property TopOrbitAssetID: UInt32 read FTopOrbitAssetID write FTopOrbitAssetID;
      property Count: UInt32 read FCount write FCount;
   end;

   TModelPlanetaryBodyFeature = class (TModelFeature)
   public
      procedure UpdateFrom(Stream: TServerStreamReader); override;
   strict private
      FSeed: UInt32;
   published
      property Seed: UInt32 read FSeed write FSeed;
   end;

   TModelPlotControlFeature = class (TModelFeature)
   public
      procedure UpdateFrom(Stream: TServerStreamReader); override;
   strict private
      FKind: UInt32;
   published
      property Kind: UInt32 read FKind write FKind;
   end;

   TModelSurfaceFeature = class (TModelFeature)
   public
      type
         TChild = record
            AssetID: UInt32;
            X, Y: Double;
         end;
   protected
      procedure ResetChildren(); override;
      procedure WalkChildren(Callback: TAssetWalkChildrenCallback); override;
   public
      procedure UpdateFrom(Stream: TServerStreamReader); override;
   public
      Children: specialize PlasticArray <TChild, specialize IncomparableUtils<TChild>>;
   end;

   TModelGridFeature = class (TModelFeature)
   public
      type
         TChild = record
            AssetID: UInt32;
            X, Y: UInt32;
            Size: UInt8;
         end;
         TBuildable = record
            AssetClass: PAssetClass;
            Size: UInt8;
         end;
   protected
      procedure ResetChildren(); override;
      procedure WalkChildren(Callback: TAssetWalkChildrenCallback); override;
   public
      procedure UpdateFrom(Stream: TServerStreamReader); override;
   strict private
      FCellSize: Double;
      FDimension: UInt32;
   public
      Children: specialize PlasticArray <TChild, specialize IncomparableUtils<TChild>>;
      Buildables: specialize PlasticArray <TBuildable, specialize IncomparableUtils<TBuildable>>;
   published
      property CellSize: Double read FCellSize write FCellSize;
      property Dimension: UInt32 read FDimension write FDimension;
   end;

   TModelPopulationFeature = class (TModelFeature)
   public
      type
         TGossip = record
            Message: UTF8String;
            Source: UInt32;
            Timestamp: Int64;
            Duration: UInt64;
            HappinessImpact: Double;
            PopulationAnchorTime: Int64;
            SpreadRate: Double;
            AffectedPeople: Cardinal;
         end;
         TGossipArray = array of TGossip;
   public
      procedure UpdateFrom(Stream: TServerStreamReader); override;
   strict private
      FDisabledReasons: Cardinal;
      FTotal, FMax: Cardinal;
      FJobs: Cardinal;
      FGossip: TGossipArray;
   public
      property Gossip: TGossipArray read FGossip;
   published
      property DisabledReasons: Cardinal read FDisabledReasons write FDisabledReasons;
      property Total: Cardinal read FTotal write FTotal;
      property Max: Cardinal read FMax write FMax;
      property Jobs: Cardinal read FJobs write FJobs;
   end;

   TModelMessageBoardFeature = class (TModelFeature)
   protected
      procedure ResetChildren(); override;
      procedure WalkChildren(Callback: TAssetWalkChildrenCallback); override;
   public
      procedure UpdateFrom(Stream: TServerStreamReader); override;
   public
      Children: specialize PlasticArray <UInt32, specialize IncomparableUtils<UInt32>>;
   end;

   TModelMessageFeature = class (TModelFeature)
   public
      procedure UpdateFrom(Stream: TServerStreamReader); override;
   strict private
      FSource: UInt32;
      FTimestamp: Int64;
      FFlags: Byte;
      FBody: UTF8String;
   published
      property Source: UInt32 read FSource write FSource;
      property Timestamp: Int64 read FTimestamp write FTimestamp;
      property Flags: Byte read FFlags write FFlags;
      property Body: UTF8String read FBody write FBody;
   end;

   TModelRubblePileFeature = class (TModelFeature)
   public
      type
         TContents = record
            MaterialID: Int32;
            Quantity: UInt64;
         end;
      procedure UpdateFrom(Stream: TServerStreamReader); override;
   public
      KnownContents: specialize PlasticArray <TContents, specialize IncomparableUtils<TContents>>;
   strict private
      FRemainingQuantity: UInt64;
   published
      property RemainingQuantity: UInt64 read FRemainingQuantity write FRemainingQuantity;
   end;

   TModelProxyFeature = class (TModelFeature)
   protected
      procedure ResetChildren(); override;
      procedure WalkChildren(Callback: TAssetWalkChildrenCallback); override;
   public
      procedure UpdateFrom(Stream: TServerStreamReader); override;
   strict private
      FChild: UInt32;
   published
      property Child: UInt32 read FChild write FChild;
   end;

   TModelKnowledgeFeature = class (TModelFeature)
   public
      type
         TKnowledge = class abstract
            procedure UpdateFrom(Stream: TServerStreamReader); virtual; abstract;
         end;
         TAssetKnowledge = class (TKnowledge)
         public
            procedure UpdateFrom(Stream: TServerStreamReader); override;
         public
            AssetClass: PAssetClass;
         end;
         TMaterialKnowledge = class (TKnowledge)
         public
            procedure UpdateFrom(Stream: TServerStreamReader); override;
         public
            MaterialID: Int32;
            Icon, Name, Description: UTF8String;
            Flags: UInt64;
            MassPerUnit, MassPerVolume: Double;
         end;
   public
      procedure UpdateFrom(Stream: TServerStreamReader); override;
      destructor Destroy(); override;
   public
      Knowledge: specialize PlasticArray <TKnowledge, specialize IncomparableUtils<TKnowledge>>;
   end;

   TModelResearchFeature = class (TModelFeature)
   public
      procedure UpdateFrom(Stream: TServerStreamReader); override;
   strict private
      FDisabledReasons: Cardinal;
      FTopic: UTF8String;
      FProgress: Byte;
   public
      FTopics: specialize PlasticArray <UTF8String, specialize DefaultUtils<UTF8String>>;
   published
      property DisabledReasons: Cardinal read FDisabledReasons write FDisabledReasons;
      property Topic: UTF8String read FTopic write FTopic;
      property Progress: Byte read FProgress write FProgress;
   end;

   TModelMiningFeature = class (TModelFeature)
   public
      procedure UpdateFrom(Stream: TServerStreamReader); override;
   strict private
      FMaxRate: Double;
      FDisabledReasons: Cardinal;
      FCurrentRate: Double;
   published
      property MaxRate: Double read FMaxRate write FMaxRate;
      property DisabledReasons: Cardinal read FDisabledReasons write FDisabledReasons;
      property CurrentRate: Double read FCurrentRate write FCurrentRate;
   end;

   TModelOrePileFeature = class (TModelFeature)
   public
      procedure UpdateFrom(Stream: TServerStreamReader); override;
   strict private
      FPileMass: Double;
      FPileMassFlowRate: Double;
      FCapacity: Double;
   public
      Materials: specialize PlasticArray <Int32, specialize IncomparableUtils<Int32>>;
   published
      property PileMass: Double read FPileMass write FPileMass;
      property PileMassFlowRate: Double read FPileMassFlowRate write FPileMassFlowRate;
      property Capacity: Double read FCapacity write FCapacity;
   end;

   TModelRegionFeature = class (TModelFeature)
   public
      procedure UpdateFrom(Stream: TServerStreamReader); override;
   strict private
      FFlags: Byte;
   published
      property Flags: Byte read FFlags write FFlags;
   end;

   TModelRefiningFeature = class (TModelFeature)
   public
      procedure UpdateFrom(Stream: TServerStreamReader); override;
   strict private
      FOre: Int32;
      FMaxRate: Double;
      FDisabledReasons: Cardinal;
      FCurrentRate: Double;
   published
      property Ore: Int32 read FOre write FOre;
      property MaxRate: Double read FMaxRate write FMaxRate;
      property DisabledReasons: Cardinal read FDisabledReasons write FDisabledReasons;
      property CurrentRate: Double read FCurrentRate write FCurrentRate;
   end;

   TModelMaterialPileFeature = class (TModelFeature)
   public
      procedure UpdateFrom(Stream: TServerStreamReader); override;
   strict private
      FPileMass: Double;
      FPileMassFlowRate: Double;
      FCapacity: Double;
      FMaterialName: UTF8String;
      FMaterialID: Int32;
   published
      property PileMass: Double read FPileMass write FPileMass;
      property PileMassFlowRate: Double read FPileMassFlowRate write FPileMassFlowRate;
      property Capacity: Double read FCapacity write FCapacity;
      property MaterialName: UTF8String read FMaterialName write FMaterialName;
      property MaterialID: Int32 read FMaterialID write FMaterialID;
   end;

   TModelMaterialStackFeature = class (TModelFeature)
   public
      procedure UpdateFrom(Stream: TServerStreamReader); override;
   strict private
      FQuantity: UInt64;
      FPileMassFlowRate: Double;
      FCapacity: UInt64;
      FMaterialName: UTF8String;
      FMaterialID: Int32;
   published
      property Quantity: UInt64 read FQuantity write FQuantity;
      property PileMassFlowRate: Double read FPileMassFlowRate write FPileMassFlowRate;
      property Capacity: UInt64 read FCapacity write FCapacity;
      property MaterialName: UTF8String read FMaterialName write FMaterialName;
      property MaterialID: Int32 read FMaterialID write FMaterialID;
   end;

   TModelGridSensorFeature = class (TModelFeature)
   public
      procedure UpdateFrom(Stream: TServerStreamReader); override;
   strict private
      FDisabledReasons: Cardinal;
   published
      property DisabledReasons: Cardinal read FDisabledReasons write FDisabledReasons;
   end;

   TModelGridSensorStatusFeature = class (TModelFeature)
   public
      procedure UpdateFrom(Stream: TServerStreamReader); override;
   strict private
      FGridAssetID: UInt32;
      FCount: UInt32;
   published
      property GridAssetID: UInt32 read FGridAssetID write FGridAssetID;
      property Count: UInt32 read FCount write FCount;
   end;

   TModelBuilderFeature = class (TModelFeature)
   public
      procedure UpdateFrom(Stream: TServerStreamReader); override;
   strict private
      FCapacity: UInt32;
      FRate: Double;
      FDisabledReasons: Cardinal;
   public
      Structures: specialize PlasticArray <UInt32, specialize IncomparableUtils<UInt32>>;
   published
      property Capacity: UInt32 read FCapacity write FCapacity;
      property Rate: Double read FRate write FRate;
      property DisabledReasons: Cardinal read FDisabledReasons write FDisabledReasons;
   end;

   TModelInternalSensorFeature = class (TModelFeature)
   public
      procedure UpdateFrom(Stream: TServerStreamReader); override;
   strict private
      FDisabledReasons: Cardinal;
   published
      property DisabledReasons: Cardinal read FDisabledReasons write FDisabledReasons;
   end;

   TModelInternalSensorStatusFeature = class (TModelFeature)
   public
      procedure UpdateFrom(Stream: TServerStreamReader); override;
   strict private
      FCount: UInt32;
   published
      property Count: UInt32 read FCount write FCount;
   end;

   TModelOnOffFeature = class (TModelFeature)
   public
      procedure UpdateFrom(Stream: TServerStreamReader); override;
   strict private
      FEnabled: Boolean;
   published
      property Enabled: Boolean read FEnabled write FEnabled;
   end;

   TModelStaffingFeature = class (TModelFeature)
   public
      procedure UpdateFrom(Stream: TServerStreamReader); override;
   strict private
      FJobs, FWorkers: Cardinal;
   published
      property Jobs: Cardinal read FJobs write FJobs;
      property Workers: Cardinal read FWorkers write FWorkers;
   end;

   TModelAssetPileFeature = class (TModelFeature)
   protected
      procedure ResetChildren(); override;
      procedure WalkChildren(Callback: TAssetWalkChildrenCallback); override;
   public
      procedure UpdateFrom(Stream: TServerStreamReader); override;
   public
      Children: specialize PlasticArray <UInt32, specialize IncomparableUtils<UInt32>>;
   end;

   TModelFactoryFeature = class (TModelFeature)
   public
      procedure UpdateFrom(Stream: TServerStreamReader); override;
   public
      type
         TFactoryEntry = record
            MaterialID: Int32;
            Quantity: UInt32;
         end;
   public
      FInputs, FOutputs: array of TFactoryEntry;
   strict private
      FMaxRate, FConfiguredRate, FCurrentRate: Double;
      FDisabledReasons: Cardinal;
   published
      property MaxRate: Double read FMaxRate write FMaxRate;
      property ConfiguredRate: Double read FConfiguredRate write FConfiguredRate;
      property CurrentRate: Double read FCurrentRate write FCurrentRate;
      property DisabledReasons: Cardinal read FDisabledReasons write FDisabledReasons;
   end;

   TModelSampleFeature = class (TModelFeature)
   public
      procedure UpdateFrom(Stream: TServerStreamReader); override;
   strict private
      FMode: Byte; // 0, 1, 2, 3
      FSize, FMass, FMassFlowRate: Double; // (1, 2, 3)
      FData: Int32; // material id (1, 2) or child asset id (3)
   published
      property Mode: Byte read FMode write FMode;
      property Size: Double read FSize write FSize;
      property Mass: Double read FMass write FMass;
      property MassFlowRate: Double read FMassFlowRate write FMassFlowRate;
      property Data: Int32 read FData write FData;
   end;

const
   ModelFeatureClasses: array[1..fcHighestKnownFeatureCode] of TModelFeatureClass = (
     TModelStarFeature,
     TModelSpaceFeature,
     TModelOrbitFeature,
     TModelStructureFeature,
     TModelSpaceSensorFeature,
     TModelSpaceSensorStatusFeature,
     TModelPlanetaryBodyFeature,
     TModelPlotControlFeature,
     TModelSurfaceFeature,
     TModelGridFeature,
     TModelPopulationFeature,
     TModelMessageBoardFeature,
     TModelMessageFeature,
     TModelRubblePileFeature,
     TModelProxyFeature,
     TModelKnowledgeFeature,
     TModelResearchFeature,
     TModelMiningFeature,
     TModelOrePileFeature,
     TModelRegionFeature,
     TModelRefiningFeature,
     TModelMaterialPileFeature,
     TModelMaterialStackFeature,
     TModelGridSensorFeature,
     TModelGridSensorStatusFeature,
     TModelBuilderFeature,
     TModelInternalSensorFeature,
     TModelInternalSensorStatusFeature,
     TModelOnOffFeature,
     TModelStaffingFeature,
     TModelAssetPileFeature,
     TModelFactoryFeature,
     TModelSampleFeature
  );

implementation

uses
   sysutils, hashfunctions, typinfo, exceptions;

function GetPropertyAsString(Target: TObject; PropertyInfo: PPropInfo): UTF8String;
begin
   case (PropertyInfo^.PropType^.Kind) of
    tkUnknown: Result := '<?>';
    tkInteger: Result := IntToStr(GetOrdProp(Target, PropertyInfo));
    tkChar: Result := Chr(GetOrdProp(Target, PropertyInfo));
    tkEnumeration: Result := GetEnumProp(Target, PropertyInfo);
    tkFloat: Result := FloatToStrF(GetFloatProp(Target, PropertyInfo), ffGeneral, 15, 4, FloatFormat);
    tkSet: Result := GetSetProp(Target, PropertyInfo, False);
    tkMethod: Result := '<method>';
    tkSString: Result := GetStrProp(Target, PropertyInfo);
    tkLString: Result := '<lstring>';
    tkAString: Result := GetStrProp(Target, PropertyInfo);
    tkWString: Result := '<wstring>'; // GetWideStrProp(Target, PropertyInfo);
    tkVariant: Result := '<variant>';
    tkArray: Result := '<array>';
    tkRecord: Result := '<record>';
    tkInterface: Result := '<interface>';
    tkClass: Result := '<class>';
    tkObject: Result := '<object>';
    tkWChar: Result := '<widechar>';
    tkBool: Result := IntToStr(GetOrdProp(Target, PropertyInfo));
    tkInt64: Result := IntToStr(GetInt64Prop(Target, PropertyInfo));
    tkQWord: Result := IntToStr(QWord(GetOrdProp(Target, PropertyInfo)));
    tkDynArray: Result := '<dynamic array>';
    tkInterfaceRaw: Result := '<raw interface>';
    tkProcVar: Result := '<procedure variable>';
    tkUString: Result := '<ustring>'; // GetUnicodeStrProp(Target, PropertyInfo);
    tkUChar: Result := '<unicodechar>';
    tkHelper: Result := '<helper>';
    tkFile: Result := '<file>';
    tkClassRef: Result := '<class reference>';
    tkPointer: Result := '<pointer>';
   end;
end;

procedure AddProperties(Target: TObject; var Output: specialize PlasticArray<UTF8String, UTF8StringUtils>; Indent: UTF8String = '');
var
   Properties: PPropList;
   Count: SizeInt;
   Index: Cardinal;
begin
   Count := GetPropList(Target.ClassInfo, Properties);
   if (Count > 0) then
      for Index := 0 to Count-1 do // $R-
      begin
         Output.Push(Indent + Properties^[Index]^.Name + ': ' + GetPropertyAsString(Target, Properties^[Index]));
      end;
   FreeMem(Properties);
end;

class function TArena.FromPointer(Ptr: Pointer): PArena;
begin
   Assert(PopCnt(GetPageSize()) = 1);
   Result := PArena(PtrUInt(Ptr) and not (GetPageSize() - 1));
end;

class function TArena.AllocateArena(ModelSystem: TModelSystem): PArena;
var
   NewPage: Pointer;
begin
   Assert(PopCnt(QWord(GetPageSize())) = 1);
   NewPage := AllocPage();
   Assert(FromPointer(NewPage) = NewPage);
   Assert(FromPointer(NewPage + 1) = NewPage);
   Result := PArena(NewPage);
   Result^.FModelSystem := ModelSystem;
   Assert(not Assigned(Result^.FPrevious));
   Result^.FTop := @Result^.FBottom;
   Assert(PtrUInt(Result^.FTop) < PtrUInt(Result) + GetPageSize());
end;

class procedure TArena.FreeArena(var Arena: PArena);
var
   CurrentArena: Pointer;
   PreviousArena: PArena;
begin
   CurrentArena := Arena;
   while (Assigned(CurrentArena)) do
   begin
      PreviousArena := PArena(CurrentArena)^.FPrevious;
      FreePage(CurrentArena);
      CurrentArena := PreviousArena;
   end;
   Arena := nil;
end;

class function TArena.AllocateObject(var Arena: PArena; Size: PtrUInt): Pointer;
var
   NewArena: PArena;
begin
   if (PtrUInt(Arena^.FTop) + Size > PtrUInt(Arena) + GetPageSize()) then
   begin
      NewArena := AllocateArena(Arena^.ModelSystem);
      NewArena^.FPrevious := Arena;
      Arena := NewArena;
   end;
   Assert(PtrUInt(Arena^.FTop) + Size <= PtrUInt(Arena) + GetPageSize());
   Result := Arena^.FTop;
   Inc(Arena^.FTop, Size);
end;

class procedure TArena.FreeObject(Arena: PArena; Instance: Pointer);
begin
   // ignored for now
   // TODO: implement deallocation
end;


constructor TServerStreamReader.Create(const Input: RawByteString; AModel: TModelSystem);
begin
   inherited Create(Input);
   FModel := AModel;
end;

function TServerStreamReader.ReadStringReference(): UTF8String;
var
   Code: Cardinal;
   Value: UTF8String;
begin
   Code := ReadCardinal();
   if (Code = 0) then
   begin
      Result := '';
      exit;
   end;
   if (not FModel.FStrings.Has(Code)) then
   begin
      Value := ReadString();
      FModel.FStrings[Code] := Value;
   end;
   Result := FModel.FStrings[Code];
end;

function TServerStreamReader.ReadAssetClass(ZeroIndicatesNil: Boolean): PAssetClass;
var
   ID: Longint;
begin
   ID := ReadInt32();
   if (ID = 0) then
   begin
      if (ZeroIndicatesNil) then
      begin
         Result := nil;
      end
      else
      begin
         New(Result);
         FModel.FUnknownAssetClasses.Push(Result);
         Result^.ID := ID;
         Result^.Icon := ReadStringReference();
         Result^.Name := ReadStringReference();
         Result^.Description := ReadStringReference();
      end;
   end
   else
   if (not FModel.FAssetClasses.Has(ID)) then
   begin
      FModel.FAssetClasses.AddDefault(ID);
      Result := FModel.FAssetClasses.ItemsPtr[ID];
      Result^.ID := ID;
      Result^.Icon := ReadStringReference();
      Result^.Name := ReadStringReference();
      Result^.Description := ReadStringReference();
   end
   else
   begin
      Result := FModel.FAssetClasses.ItemsPtr[ID];
      Assert(Result^.ID = ID);
   end;
end;


constructor TModelSystem.Create();
begin
   inherited;
   FArena := TArena.AllocateArena(Self);
   FStrings := TStringHashTable.Create(@Integer32Hash32);
   FAssetClasses := TAssetClassHashTable.Create(@LongintHash32);
   FAssets := TModelAssetHashTable.Create(@Integer32Hash32, 8);
end;

destructor TModelSystem.Destroy();
var
   Asset: TModelAsset;
   AssetClass: PAssetClass;
begin
   if (Assigned(FAssets)) then
      for Asset in FAssets.Values do
         Asset.Free();
   FreeAndNil(FAssets);
   FreeAndNil(FAssetClasses);
   FreeAndNil(FStrings);
   for AssetClass in FUnknownAssetClasses do
      Dispose(AssetClass);
   TArena.FreeArena(FArena);
   inherited;
end;

function TModelSystem.DescribeSystem(): UTF8String;
var
   Lines: specialize PlasticArray<UTF8String, UTF8StringUtils>;

   procedure GetDescription(Asset: TModelAsset);
   begin
      if (not Assigned(Asset)) then
      begin
         Lines.Push(' - <nil>');
      end
      else
      begin
         Lines.Push(' - #' + IntToStr(Asset.ID) + ' ' + Asset.ToString() + ' (' + IntToStr(Asset.FeatureCount) + ' features)');
         Asset.Describe(Lines, '   ');
         Lines.Push('');
         Asset.WalkChildren(@GetDescription);
      end;
   end;

var
   Size: Cardinal;
   Index: Cardinal;
   S: UTF8String;
begin
   GetDescription(FAssets[RootAsset]);
   Assert(Lines.Length > 0);
   Size := 0;
   for Index := 0 to Lines.Length - 1 do // $R-
      Inc(Size, Length(Lines[Index]) + 1);
   Result := '';
   SetLength(Result, Size);
   Size := 1;
   for Index := 0 to Lines.Length - 1 do // $R-
   begin
      S := Lines[Index];
      if (Length(S) > 0) then
      begin
         Move(S[1], Result[Size], Length(S));
         Inc(Size, Length(S));
      end;
      Result[Size] := #10;
      Inc(Size);
   end;
end;

function TModelSystem.GetAsset(ID: UInt32): TModelAsset;
begin
   Assert(ID > 0);
   if (not FAssets.Has(ID)) then
      FAssets[ID] := TModelAsset.CreateFor(Self, ID);
   Result := FAssets[ID];
end;

procedure TModelSystem.UpdateFrom(Stream: TServerStreamReader);
var
   AssetID: Cardinal;
   Asset: TModelAsset;
begin
   FUpdates.Empty();
   SystemID := Stream.ReadCardinal();
   CurrentTime := Stream.ReadInt64();
   TimeFactor := Stream.ReadDouble();
   RootAsset := Stream.ReadCardinal();
   X := Stream.ReadDouble();
   Y := Stream.ReadDouble();
   AssetID := Stream.ReadCardinal();
   while (AssetID <> 0) do
   begin
      Asset := Assets[AssetID];
      FUpdates.Push(Asset);
      Asset.UpdateFrom(Stream);
      AssetID := Stream.ReadCardinal();
   end;
   FLastUpdates := FUpdates.Distill();
end;

function TModelSystem.GetUpdatesLength(): Cardinal;
begin
   Result := Length(FLastUpdates); // $R-
end;

function TModelSystem.GetUpdatedAssets(): TAssetList;
begin
   Result := FLastUpdates;
end;

function TModelSystem.FindAssets(Predicate: TAssetPredicate): TAssetList;
var
   Results: specialize PlasticArray<TModelAsset, TObjectUtils>;

   procedure Search(Asset: TModelAsset);
   begin
      if (Predicate(Asset)) then
         Results.Push(Asset);
      Asset.WalkChildren(@Search);
   end;

var
   Root: TModelAsset;
begin
   Results.Prepare(8);
   Root := Assets[RootAsset];
   Root.WalkChildren(@Search);
   Result := Results.Distill();
end;


constructor TModelAsset.Create(AID: UInt32);
begin
   inherited Create();
   Assert(Assigned(TArena.FromPointer(Self)^.ModelSystem));
   FID := AID;
end;

class function TModelAsset.NewInstance(): TModelAsset; // {BOGUS Warning: Function result does not seem to be set}
begin
   raise Exception.CreateFmt('Use CreateFor to create %s instances.', [ClassName]);
end;

procedure TModelAsset.FreeInstance();
var
   Arena: PArena;
begin
   CleanupInstance();
   Arena := TArena.FromPointer(Self);
   Arena^.FreeObject(Arena, Self);
end;

class function TModelAsset.CreateFor(System: TModelSystem; AID: UInt32): TModelAsset;
var
   P: Pointer;
   Asset: TModelAsset;
begin
   P := TArena.AllocateObject(System.FArena, InstanceSize); // $R-
   Asset := TModelAsset(InitInstance(P));
   Asset.Create(AID);
   Result := Asset; // don't set Result earlier, otherwise Free might be called incorrectly in the event of an exception
end;

destructor TModelAsset.Destroy();
var
   Feature: TModelFeature;
begin
   for Feature in FFeatures do
      Feature.Free();
   FFeatures.Empty();
   inherited;
end;

function TModelAsset.HasFeature(FeatureClass: TModelFeatureClass): Boolean;
var
   Feature: TModelFeature;
begin
   for Feature in FFeatures do
      if (Feature is FeatureClass) then
      begin
         Result := True;
         exit;
      end;
   Result := False;
end;

function TModelAsset.GetFeature(FeatureClass: TModelFeatureClass): TModelFeature;
var
   Feature: TModelFeature;
begin
   for Feature in FFeatures do
      if (Feature is FeatureClass) then
      begin
         Result := Feature;
         exit;
      end;
   Result := nil;
end;

function TModelAsset.GetFeatures(): TFeatureList;
begin
   Result := FFeatures.Copy();
end;

function TModelAsset.GetFeatureCount(): Cardinal;
begin
   Result := FFeatures.Length;
end;

function TModelAsset.GetModelSystem(): TModelSystem;
begin
   Result := TArena.FromPointer(Self)^.ModelSystem;
end;

function TModelAsset.GetParent(): TModelAsset;
begin
   Result := FParent.FParent;
end;

procedure TModelAsset.UpdateFrom(Stream: TServerStreamReader);
var
   FeatureCode: UInt32;
   Index, Count: Cardinal;
begin
   Owner := Stream.ReadCardinal();
   Mass := Stream.ReadDouble();
   MassFlowRate := Stream.ReadDouble();
   Size := Stream.ReadDouble();
   Name := Stream.ReadStringReference();
   AssetClass := Stream.ReadAssetClass(False);
   Index := 0;
   FeatureCode := Stream.ReadCardinal();
   while (FeatureCode <> 0) do
   begin
      if (Index >= FFeatures.Length) then
      begin
         FFeatures.Push(ModelFeatureClasses[FeatureCode].CreateFor(ModelSystem, Self));
      end
      else
      if (FFeatures[Index].ClassType <> ModelFeatureClasses[FeatureCode]) then
      begin
         FFeatures[Index].Free();
         FFeatures[Index] := ModelFeatureClasses[FeatureCode].CreateFor(ModelSystem, Self);
      end;
      FFeatures[Index].UpdateFrom(Stream);
      Inc(Index);
      FeatureCode := Stream.ReadCardinal();
   end;
   Assert(FFeatures.Length >= Index);
   Count := Index;
   while (Index < FFeatures.Length) do
   begin
      FFeatures[Index].Free();
      Inc(Index);
   end;
   FFeatures.Length := Count;
end;

procedure TModelAsset.WalkChildren(Callback: TAssetWalkChildrenCallback);
var
   Feature: TModelFeature;
begin
   for Feature in FFeatures do
      Feature.WalkChildren(Callback);
end;

function TModelAsset.ToString(): UTF8String;
begin
   Result := AssetClass^.Name;
   if (Name <> '') then
      Result := Result + ' ' + Name;
end;

procedure TModelAsset.Describe(var Output: specialize PlasticArray<UTF8String, UTF8StringUtils>; Indent: UTF8String = '');
var
   Feature: TModelFeature;
begin
   AddProperties(Self, Output, Indent);
   for Feature in FFeatures do
      Feature.Describe(Output, Indent + '  ');
end;


constructor TModelFeature.Create(AParent: TModelAsset);
begin
   inherited Create();
   FParent := AParent;
   Assert(Assigned(TArena.FromPointer(Self)^.ModelSystem));
end;

class function TModelFeature.NewInstance(): TModelFeature; // {BOGUS Warning: Function result does not seem to be set}
begin
   raise Exception.CreateFmt('Use CreateFor to create %s instances.', [ClassName]);
end;

procedure TModelFeature.FreeInstance();
var
   Arena: PArena;
begin
   CleanupInstance();
   Arena := TArena.FromPointer(Self);
   Arena^.FreeObject(Arena, Self);
end;

class function TModelFeature.CreateFor(System: TModelSystem; Parent: TModelAsset): TModelFeature;
var
   Feature: TModelFeature;
begin
   Feature := TModelFeature(InitInstance(TArena.AllocateObject(System.FArena, InstanceSize))); // $R-
   {$PUSH}
   {$WARNINGS OFF}
   {$HINTS OFF}
   Feature.Create(Parent);
   {$POP}
   Result := Feature; // don't set Result earlier, otherwise Free might be called incorrectly in the event of an exception
end;

function TModelFeature.GetModelSystem(): TModelSystem;
begin
   Result := TArena.FromPointer(Self)^.ModelSystem;
end;

procedure TModelFeature.ResetChildren();

   procedure ResetParent(Child: TModelAsset);
   begin
      if (Child.FParent = Self) then
         Child.FParent := nil;
   end;

begin
   WalkChildren(@ResetParent);
end;

procedure TModelFeature.WalkChildren(Callback: TAssetWalkChildrenCallback);
begin
end;

procedure TModelFeature.Describe(var Output: specialize PlasticArray<UTF8String, UTF8StringUtils>; Indent: UTF8String = '');
begin
   Output.Push(Indent + '* ' + ClassName);
   AddProperties(Self, Output, Indent + '  ');
end;


procedure TModelStarFeature.UpdateFrom(Stream: TServerStreamReader);
begin
   StarID := Stream.ReadCardinal();
end;


procedure TModelSpaceFeature.UpdateFrom(Stream: TServerStreamReader);
var
   Child: TChild;
begin
   ResetChildren();
   Child.AssetID := Stream.ReadCardinal();
   Child.X := 0;
   Child.Y := 0;
   Children.Push(Child);
   while (True) do
   begin
      Child.AssetID := Stream.ReadCardinal();
      if (Child.AssetID = 0) then
         break;
      Child.X := Stream.ReadDouble();
      Child.Y := Stream.ReadDouble();
      ModelSystem.Assets[Child.AssetID].FParent := Self;
      Children.Push(Child);
   end;
end;

procedure TModelSpaceFeature.ResetChildren();
begin
   inherited;
   Children.Empty();
end;

procedure TModelSpaceFeature.WalkChildren(Callback: TAssetWalkChildrenCallback);
var
   Index: Cardinal;
   System: TModelSystem;
begin
   System := ModelSystem;
   if (not Children.IsEmpty) then
      for Index := 0 to Children.Length - 1 do // $R-
         Callback(System.Assets[Children[Index].AssetID]);
end;


procedure TModelOrbitFeature.UpdateFrom(Stream: TServerStreamReader);
var
   Child: TChild;
begin
   ResetChildren();
   PrimaryAssetId := Stream.ReadCardinal();
   Assert(PrimaryAssetId > 0);
   ModelSystem.Assets[PrimaryAssetId].FParent := Self;
   while (True) do
   begin
      Child.AssetID := Stream.ReadCardinal();
      if (Child.AssetID = 0) then
         break;
      Child.SemiMajorAxis := Stream.ReadDouble();
      Child.Eccentricity := Stream.ReadDouble();
      Child.Omega := Stream.ReadDouble();
      Child.TimeOrigin := Stream.ReadInt64();
      Child.Clockwise := Stream.ReadBoolean();
      ModelSystem.Assets[Child.AssetID].FParent := Self;
      Children.Push(Child);
   end;
end;

procedure TModelOrbitFeature.ResetChildren();
begin
   inherited;
   PrimaryAssetId := 0;
   Children.Empty();
end;

procedure TModelOrbitFeature.WalkChildren(Callback: TAssetWalkChildrenCallback);
var
   Index: Cardinal;
   System: TModelSystem;
begin
   System := ModelSystem;
   if (PrimaryAssetId > 0) then
      Callback(System.Assets[PrimaryAssetId]);
   if (not Children.IsEmpty) then
      for Index := 0 to Children.Length - 1 do // $R-
         Callback(System.Assets[Children[Index].AssetID]);
end;


procedure TModelStructureFeature.UpdateFrom(Stream: TServerStreamReader);
var
   MaterialLineItem: TMaterialLineItem;
begin
   LineItems.Empty();
   while (True) do
   begin
      MaterialLineItem.Max := Stream.ReadCardinal();
      if (MaterialLineItem.Max = 0) then
         break;
      MaterialLineItem.ComponentName := Stream.ReadStringReference();
      MaterialLineItem.MaterialName := Stream.ReadStringReference();
      MaterialLineItem.MaterialID := Stream.ReadInt32();
      LineItems.Push(MaterialLineItem);
   end;
   BuilderID := Stream.ReadCardinal();
   Quantity := Stream.ReadCardinal();
   QuantityRate := Stream.ReadDouble();
   Hp := Stream.ReadCardinal();
   HpRate := Stream.ReadDouble();
   MinHp := Stream.ReadCardinal();
end;


procedure TModelSpaceSensorFeature.UpdateFrom(Stream: TServerStreamReader);
begin
   DisabledReasons := Stream.ReadCardinal();
   Reach := Stream.ReadCardinal();
   Up := Stream.ReadCardinal();
   Down := Stream.ReadCardinal();
   Resolution := Stream.ReadDouble();
end;


procedure TModelSpaceSensorStatusFeature.UpdateFrom(Stream: TServerStreamReader);
begin
   NearestOrbitAssetID := Stream.ReadCardinal();
   TopOrbitAssetID := Stream.ReadCardinal();
   Count := Stream.ReadCardinal();
end;


procedure TModelPlanetaryBodyFeature.UpdateFrom(Stream: TServerStreamReader);
begin
   Seed := Stream.ReadCardinal();
end;


procedure TModelPlotControlFeature.UpdateFrom(Stream: TServerStreamReader);
begin
   Kind := Stream.ReadCardinal();
end;


procedure TModelSurfaceFeature.UpdateFrom(Stream: TServerStreamReader);
var
   Child: TChild;
begin
   ResetChildren();
   while (True) do
   begin
      Child.AssetID := Stream.ReadCardinal();
      if (Child.AssetID = 0) then
         break;
      Child.X := Stream.ReadDouble();
      Child.Y := Stream.ReadDouble();
      ModelSystem.Assets[Child.AssetID].FParent := Self;
      Children.Push(Child);
   end;
end;

procedure TModelSurfaceFeature.ResetChildren();
begin
   inherited;
   Children.Empty();
end;

procedure TModelSurfaceFeature.WalkChildren(Callback: TAssetWalkChildrenCallback);
var
   Index: Cardinal;
   System: TModelSystem;
begin
   System := ModelSystem;
   if (not Children.IsEmpty) then
      for Index := 0 to Children.Length - 1 do // $R-
         Callback(System.Assets[Children[Index].AssetID]);
end;


procedure TModelGridFeature.UpdateFrom(Stream: TServerStreamReader);
var
   Child: TChild;
   AssetClass: PAssetClass;
   Buildable: TBuildable;
begin
   ResetChildren();
   CellSize := Stream.ReadDouble();
   Dimension := Stream.ReadCardinal();
   while (True) do
   begin
      Child.AssetID := Stream.ReadCardinal();
      if (Child.AssetID = 0) then
         break;
      Child.X := Stream.ReadCardinal();
      Child.Y := Stream.ReadCardinal();
      Child.Size := Stream.ReadByte();
      ModelSystem.Assets[Child.AssetID].FParent := Self;
      Children.Push(Child);
   end;
   Buildables.Empty();
   while (True) do
   begin
      AssetClass := Stream.ReadAssetClass(True);
      if (Assigned(AssetClass)) then
      begin
         Buildable.AssetClass := AssetClass;
         Buildable.Size := Stream.ReadByte();
         Buildables.Push(Buildable);
      end
      else
         break;
   end;
end;

procedure TModelGridFeature.ResetChildren();
begin
   inherited;
   Children.Empty();
end;

procedure TModelGridFeature.WalkChildren(Callback: TAssetWalkChildrenCallback);
var
   Index: Cardinal;
   System: TModelSystem;
begin
   System := ModelSystem;
   if (not Children.IsEmpty) then
      for Index := 0 to Children.Length - 1 do // $R-
         Callback(System.Assets[Children[Index].AssetID]);
end;


procedure TModelPopulationFeature.UpdateFrom(Stream: TServerStreamReader);
var
   Message: UTF8String;
begin
   DisabledReasons := Stream.ReadCardinal();
   Total := Stream.ReadCardinal();
   Max := Stream.ReadCardinal();
   Jobs := Stream.ReadCardinal();
   SetLength(FGossip, 0);
   while (True) do
   begin
      Message := Stream.ReadStringReference();
      if (Message = '') then
         break;
      SetLength(FGossip, Length(FGossip) + 1);
      FGossip[High(FGossip)].Message := Message;
      FGossip[High(FGossip)].Source := Stream.ReadCardinal();
      FGossip[High(FGossip)].Timestamp := Stream.ReadInt64();
      FGossip[High(FGossip)].HappinessImpact := Stream.ReadDouble();
      FGossip[High(FGossip)].Duration := Stream.ReadUInt64();
      FGossip[High(FGossip)].PopulationAnchorTime := Stream.ReadInt64();
      FGossip[High(FGossip)].AffectedPeople := Stream.ReadCardinal();
      FGossip[High(FGossip)].SpreadRate := Stream.ReadDouble();
   end;
end;


procedure TModelMessageBoardFeature.UpdateFrom(Stream: TServerStreamReader);
var
   Child: Cardinal;
begin
   ResetChildren();
   while (True) do
   begin
      Child := Stream.ReadCardinal();
      if (Child = 0) then
         break;
      ModelSystem.Assets[Child].FParent := Self;
      Children.Push(Child);
   end;
end;

procedure TModelMessageBoardFeature.ResetChildren();
begin
   inherited;
   Children.Empty();
end;

procedure TModelMessageBoardFeature.WalkChildren(Callback: TAssetWalkChildrenCallback);
var
   Index: Cardinal;
   System: TModelSystem;
begin
   System := ModelSystem;
   if (not Children.IsEmpty) then
      for Index := 0 to Children.Length - 1 do // $R-
         Callback(System.Assets[Children[Index]]);
end;


procedure TModelMessageFeature.UpdateFrom(Stream: TServerStreamReader);
begin
   Source := Stream.ReadCardinal();
   Timestamp := Stream.ReadInt64();
   Flags := Stream.ReadByte();
   Body := Stream.ReadStringReference();
end;


procedure TModelRubblePileFeature.UpdateFrom(Stream: TServerStreamReader);
var
   Contents: TContents;
begin
   KnownContents.Empty();
   while (True) do
   begin
      Contents.MaterialID := Stream.ReadInt32();
      if (Contents.MaterialID = 0) then
         break;
      Contents.Quantity := Stream.ReadUInt64();
      KnownContents.Push(Contents);
   end;
   RemainingQuantity := Stream.ReadUInt64();
end;


procedure TModelProxyFeature.UpdateFrom(Stream: TServerStreamReader);
begin
   Child := Stream.ReadCardinal();
   ModelSystem.Assets[Child].FParent := Self;
end;

procedure TModelProxyFeature.ResetChildren();
begin
   inherited;
   Child := 0;
end;

procedure TModelProxyFeature.WalkChildren(Callback: TAssetWalkChildrenCallback);
var
   System: TModelSystem;
begin
   System := ModelSystem;
   Callback(System.Assets[Child]);
end;


procedure TModelKnowledgeFeature.TAssetKnowledge.UpdateFrom(Stream: TServerStreamReader);
begin
   AssetClass := Stream.ReadAssetClass(True);
   Assert(Assigned(AssetClass));
end;


procedure TModelKnowledgeFeature.TMaterialKnowledge.UpdateFrom(Stream: TServerStreamReader);
begin
   MaterialID := Stream.ReadInt32();
   Icon := Stream.ReadStringReference();
   Name := Stream.ReadStringReference();
   Description := Stream.ReadStringReference();
   Flags := Stream.ReadUInt64();
   MassPerUnit := Stream.ReadDouble();
   MassPerVolume := Stream.ReadDouble();
end;


procedure TModelKnowledgeFeature.UpdateFrom(Stream: TServerStreamReader);
var
   Code: Byte;
   KnowledgeItem: TKnowledge;
begin
   // TODO: consider just updating in-place
   for KnowledgeItem in Knowledge do
      KnowledgeItem.Free();
   Knowledge.Empty();
   while (True) do
   begin
      Code := Stream.ReadByte();
      case Code of
         $00: break;
         $01: KnowledgeItem := TAssetKnowledge.Create();
         $02: KnowledgeItem := TMaterialKnowledge.Create();
      else
         raise EBinaryStreamError.CreateFmt('Unknown knowledge type %d.', [Code]);
      end;
      KnowledgeItem.UpdateFrom(Stream);
      Knowledge.Push(KnowledgeItem);
   end;
end;

destructor TModelKnowledgeFeature.Destroy();
var
   KnowledgeItem: TKnowledge;
begin
   for KnowledgeItem in Knowledge do
      KnowledgeItem.Free();
   Knowledge.Empty();
   inherited;
end;


procedure TModelResearchFeature.UpdateFrom(Stream: TServerStreamReader);
var
   NextTopic: String;
begin
   DisabledReasons := Stream.ReadCardinal();
   FTopics.Empty();
   repeat
      NextTopic := Stream.ReadStringReference();
      if (NextTopic <> '') then
      begin
         FTopics.Push(NextTopic);
      end;
   until NextTopic = '';
   Topic := Stream.ReadStringReference();
   Progress := Stream.ReadByte();
end;


procedure TModelMiningFeature.UpdateFrom(Stream: TServerStreamReader);
begin
   MaxRate := Stream.ReadDouble();
   DisabledReasons := Stream.ReadCardinal();
   CurrentRate := Stream.ReadDouble();
end;


procedure TModelOrePileFeature.UpdateFrom(Stream: TServerStreamReader);
var
   Material: Int32;
begin
   PileMass := Stream.ReadDouble();
   PileMassFlowRate := Stream.ReadDouble();
   Capacity := Stream.ReadDouble();
   Materials.Empty();
   while True do
   begin
      Material := Stream.ReadInt32();
      if (Material = 0) then
         break;
      Materials.Push(Material);
   end;
end;


procedure TModelRegionFeature.UpdateFrom(Stream: TServerStreamReader);
begin
   Flags := Stream.ReadByte();
end;


procedure TModelRefiningFeature.UpdateFrom(Stream: TServerStreamReader);
begin
   Ore := Stream.ReadInt32();
   MaxRate := Stream.ReadDouble();
   DisabledReasons := Stream.ReadCardinal();
   CurrentRate := Stream.ReadDouble();
end;


procedure TModelMaterialPileFeature.UpdateFrom(Stream: TServerStreamReader);
begin
   PileMass := Stream.ReadDouble();
   PileMassFlowRate := Stream.ReadDouble();
   Capacity := Stream.ReadDouble();
   MaterialName := Stream.ReadStringReference();
   MaterialID := Stream.ReadInt32();
end;


procedure TModelMaterialStackFeature.UpdateFrom(Stream: TServerStreamReader);
begin
   Quantity := Stream.ReadUInt64();
   PileMassFlowRate := Stream.ReadDouble();
   Capacity := Stream.ReadUInt64();
   MaterialName := Stream.ReadStringReference();
   MaterialID := Stream.ReadInt32();
end;


procedure TModelGridSensorFeature.UpdateFrom(Stream: TServerStreamReader);
begin
   DisabledReasons := Stream.ReadCardinal();
end;


procedure TModelGridSensorStatusFeature.UpdateFrom(Stream: TServerStreamReader);
begin
   GridAssetID := Stream.ReadCardinal();
   Count := Stream.ReadCardinal();
end;


procedure TModelBuilderFeature.UpdateFrom(Stream: TServerStreamReader);
var
   Structure: Cardinal;
begin
   Capacity := Stream.ReadCardinal();
   Rate := Stream.ReadDouble();
   DisabledReasons := Stream.ReadCardinal();
   Structures.Empty();
   while True do
   begin
      Structure := Stream.ReadCardinal();
      if (Structure = 0) then
         break;
      Structures.Push(Structure);
   end;
end;


procedure TModelInternalSensorFeature.UpdateFrom(Stream: TServerStreamReader);
begin
   DisabledReasons := Stream.ReadCardinal();
end;


procedure TModelInternalSensorStatusFeature.UpdateFrom(Stream: TServerStreamReader);
begin
   Count := Stream.ReadCardinal();
end;


procedure TModelOnOffFeature.UpdateFrom(Stream: TServerStreamReader);
begin
   Enabled := Stream.ReadBoolean();
end;


procedure TModelStaffingFeature.UpdateFrom(Stream: TServerStreamReader);
begin
   FJobs := Stream.ReadCardinal();
   FWorkers := Stream.ReadCardinal();
end;


procedure TModelAssetPileFeature.UpdateFrom(Stream: TServerStreamReader);
var
   Child: Cardinal;
begin
   ResetChildren();
   while (True) do
   begin
      Child := Stream.ReadCardinal();
      if (Child = 0) then
         break;
      ModelSystem.Assets[Child].FParent := Self;
      Children.Push(Child);
   end;
end;

procedure TModelAssetPileFeature.ResetChildren();
begin
   inherited;
   Children.Empty();
end;

procedure TModelAssetPileFeature.WalkChildren(Callback: TAssetWalkChildrenCallback);
var
   Index: Cardinal;
   System: TModelSystem;
begin
   System := ModelSystem;
   if (not Children.IsEmpty) then
      for Index := 0 to Children.Length - 1 do // $R-
         Callback(System.Assets[Children[Index]]);
end;



procedure TModelFactoryFeature.UpdateFrom(Stream: TServerStreamReader);
type
   TFactoryEntryArray = array of TFactoryEntry;
   
   procedure ReadManifest(var Manifest: TFactoryEntryArray);
   var
      ID: Int32;
   begin
      SetLength(Manifest, 0);
      ID := Stream.ReadInt32();
      while (ID <> 0) do
      begin
         SetLength(Manifest, Length(Manifest) + 1);
         Manifest[High(Manifest)].MaterialID := ID;
         Manifest[High(Manifest)].Quantity := Stream.ReadCardinal();
         ID := Stream.ReadInt32();
      end;
   end;
   
begin
   ReadManifest(FInputs);
   ReadManifest(FOutputs);
   FMaxRate := Stream.ReadDouble();
   FConfiguredRate := Stream.ReadDouble();
   FCurrentRate := Stream.ReadDouble();
   FDisabledReasons := Stream.ReadCardinal();
end;


procedure TModelSampleFeature.UpdateFrom(Stream: TServerStreamReader);
begin
   FMode := Stream.ReadByte();
   FSize := Stream.ReadDouble();
   FMass := Stream.ReadDouble();
   FMassFlowRate := Stream.ReadDouble();
   FData := Stream.ReadInt32();
end;

end.