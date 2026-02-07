{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit encyclopedia;

interface

uses
   techtree, internals, systems, configuration, astronomy, materials,
   random, systemdynasty, space, basenetwork, masses;

type
   TEncyclopedia = class(TEncyclopediaView)
   private
      // these are the owned references
      FMaterials: TMaterialIDHashTable;
      FAssetClasses: TAssetClassIDHashTable;
      FResearches: TResearch.TArray;
      FTopics: TTopic.TArray;
      // cached values and lookup tables
      FResearchesByID: TResearchHashTable;
      FTopicsByName: TTopicHashTable;
      FProtoplanetaryMaterials: TMaterial.TArray; // order matters, it's used in protoplanetary generation
      FMinMassPerOreUnit: TMassPerUnit; // cached value based on ores in materials passed to constructor
      function GetStarClass(Category: TStarCategory): TAssetClass;
   protected
      function GetAssetClass(ID: Integer): TAssetClass; override;
      function GetMaterial(ID: TMaterialID): TMaterial; override;
      function GetResearchByIndex(Index: TResearchIndex): TResearch; override;
      function GetResearchById(ID: TResearchID): TResearch; override;
      function GetTopicByName(Name: UTF8String): TTopic; override;
      function GetTopicByIndex(Index: TTopic.TIndex): TTopic; override;
      function GetMinMassPerOreUnit(): TMassPerUnit; override;
      procedure RegisterAssetClass(AssetClass: TAssetClass);
   public
      constructor Create(Settings: PSettings; const AMaterials: TMaterial.TArray; TechTree: TTechnologyTree); // AMaterials must contain all TOres
      destructor Destroy(); override;
      procedure RegisterMaterials(const AMaterials: TMaterialHashSet);
      procedure RegisterMaterials(const AMaterials: TMaterial.TArray);
      procedure ProcessTechTree(TechTree: TTechnologyTree);
      function WrapAssetForOrbit(Child: TAssetNode): TAssetNode;
      function CreateLoneStar(StarID: TStarID; System: TSystem): TAssetNode;
      procedure CondenseProtoplanetaryDisks(Space: TSolarSystemFeatureNode; System: TSystem);
      procedure FindTemperatureEquilibria(System: TSystem);
      procedure SpawnColonyShip(Dynasty: TDynasty; System: TSystem);
      property MinMassPerOreUnit: TMassPerUnit read FMinMassPerOreUnit;
   public
      function HandleBusMessage(Asset: TAssetNode; Message: TBusMessage): THandleBusMessageResult; override;
      function CreateRegion(CellSize: Double; Dimension: Cardinal; System: TSystem): TAssetNode; override;
      procedure Dismantle(Asset: TAssetNode; Message: TMessage); override;
      function Craterize(Diameter: Double; OldAssets: TAssetNode.TArray; NewAsset: TAssetNode): TAssetNode; override;
   public // intrinsic asset classes
      property SpaceClass: TAssetClass index -1 read GetAssetClass; // used to bootstrap TSystem
   private
      const
         kStarIDBase = -100; // subtract star category from this number to get star asset class
      property Orbit: TAssetClass index -2 read GetAssetClass; // used by WrapAssetForOrbit
      property PlanetaryBody: TAssetClass index -3 read GetAssetClass; // used by CondenseProtoplanetaryDisks
      property Region: TAssetClass index -4 read GetAssetClass; // used by CreateRegion
      property Crater: TAssetClass index -5 read GetAssetClass; // used by Craterize
      property RubblePile: TAssetClass index -6 read GetAssetClass; // used by Dismantle
      property ColonyShip: TAssetClass index -8 read GetAssetClass; // used by SpawnColonyShip
   end;

implementation

uses
   sysutils, math, floatutils, exceptions, isdnumbers, protoplanetary,
   time, isdprotocol, gossip, commonbuses, systemnetwork, ttparser,
   // this must import every feature, so they get registered:
   assetpile, builders, factory, grid, gridsensor, internalsensor,
   knowledge, materialpile, messages, mining, name, onoff, orbit,
   orepile, peoplebus, planetary, plot, population, proxy, refining,
   region, research, rubble, sample, size, spacesensor, staffing,
   stellar, structure, surface;
   
function RoundAboveZero(Value: Double): Cardinal;
begin
   Assert(Value < High(Result));
   Assert(Value >= 0.0);
   Result := Round(Value); // $R-
   if (Result = 0) then
      Result := 1;
end;


constructor TEncyclopedia.Create(Settings: PSettings; const AMaterials: TMaterial.TArray; TechTree: TTechnologyTree);
var
   Ore: TOres;
begin
   inherited Create();
   FMaterials := TMaterialIDHashTable.Create();
   FProtoplanetaryMaterials := AMaterials;
   RegisterMaterials(FProtoplanetaryMaterials);
   FMinMassPerOreUnit := TMassPerUnit.Infinity;
   for Ore in TOres do
   begin
      Assert(FMaterials.Has(Ore), HexStr(FMaterials) + ' does not have ore ' + IntToStr(Ore));
      if (FMaterials[Ore].MassPerUnit < FMinMassPerOreUnit) then
         FMinMassPerOreUnit := FMaterials[Ore].MassPerUnit;
   end;
   FAssetClasses := TAssetClassIDHashTable.Create();
   FResearchesByID := TResearchHashTable.Create();
   FTopicsByName := TTopicHashTable.Create();
   ProcessTechTree(TechTree);
end;

destructor TEncyclopedia.Destroy();
var
   AssetClass: TAssetClass;
   Research: TResearch;
   Material: TMaterial;
   Topic: TTopic;
begin
   for Research in FResearches do
      Research.Free();
   FResearchesByID.Free();
   for Material in FMaterials.Values do
      Material.Free();
   FMaterials.Free();
   for AssetClass in FAssetClasses.Values do
      AssetClass.Free();
   FAssetClasses.Free();
   for Topic in FTopics do
      Topic.Free();
   FTopicsByName.Free();
   inherited;
end;

procedure TEncyclopedia.RegisterMaterials(const AMaterials: TMaterialHashSet);
var
   Material: TMaterial;
begin
   for Material in AMaterials do
      FMaterials[Material.ID] := Material;
end;

procedure TEncyclopedia.RegisterMaterials(const AMaterials: TMaterial.TArray);
var
   Material: TMaterial;
begin
   for Material in AMaterials do
      FMaterials[Material.ID] := Material;
end;

procedure TEncyclopedia.ProcessTechTree(TechTree: TTechnologyTree);
var
   TechTreeMaterials: TMaterial.TArray;
   Material: TMaterial;
   TechTreeAssetClasses: TAssetClass.TArray;
   AssetClass: TAssetClass;
   Research: TResearch;
   Topic: TTopic;
begin
   TechTreeMaterials := TechTree.ExtractMaterials();
   for Material in TechTreeMaterials do
      FMaterials[Material.ID] := Material;
   TechTreeAssetClasses := TechTree.ExtractAssetClasses();
   for AssetClass in TechTreeAssetClasses do
      FAssetClasses[AssetClass.ID] := AssetClass;
   FResearches := TechTree.ExtractResearches();
   for Research in FResearches do
      FResearchesByID[Research.ID] := Research;
   FTopics := TechTree.ExtractTopics();
   for Topic in FTopics do
      FTopicsByName[Topic.Name] := Topic;
end;

function TEncyclopedia.GetAssetClass(ID: Integer): TAssetClass;
begin
   Result := FAssetClasses[ID];
   Assert(Result.ID = ID);
end;

function TEncyclopedia.GetMaterial(ID: TMaterialID): TMaterial;
begin
   Result := FMaterials[ID];
   Assert((Assigned(Result)) xor (ID = 0));
   Assert((not Assigned(Result)) or (Result.ID = ID));
end;

function TEncyclopedia.GetResearchByIndex(Index: TResearchIndex): TResearch;
begin
   Result := FResearches[Index];
   Assert(Assigned(Result));
   Assert(Result.Index = Index);
end;

function TEncyclopedia.GetResearchByID(ID: TResearchID): TResearch;
begin
   Assert(FResearchesByID.Has(ID));
   Result := FResearchesById[ID];
   Assert(Result.ID = ID);
end;

function TEncyclopedia.GetTopicByName(Name: UTF8String): TTopic;
begin
   Result := FTopicsByName[Name];
   Assert(Result.Name = Name);
end;

function TEncyclopedia.GetTopicByIndex(Index: TTopic.TIndex): TTopic;
begin
   Result := FTopics[Index - 1];
   Assert(Result.Index = Index);
end;

function TEncyclopedia.GetMinMassPerOreUnit(): TMassPerUnit;
begin
   Result := FMinMassPerOreUnit;
end;

procedure TEncyclopedia.RegisterAssetClass(AssetClass: TAssetClass);
begin
   Assert(Assigned(AssetClass));
   Assert(not FAssetClasses.Has(AssetClass.ID));
   FAssetClasses[AssetClass.ID] := AssetClass;
end;

function TEncyclopedia.GetStarClass(Category: TStarCategory): TAssetClass;
begin
   Result := AssetClasses[kStarIDBase - Category]; // $R-
end;

function TEncyclopedia.WrapAssetForOrbit(Child: TAssetNode): TAssetNode;
var
   OrbitFeature: TOrbitFeatureNode;
   Overrides: TFeatureNodeOverrides;
begin
   OrbitFeature := TOrbitFeatureNode.Create(Child.System);
   SetLength(Overrides, 1);
   Overrides[0].FeatureClass := TOrbitFeatureClass;
   Overrides[0].FeatureNode := OrbitFeature;
   Result := Orbit.Spawn(nil { orbits have no owner }, Child.System, Overrides);
   OrbitFeature.SetPrimaryChild(Child);
end;

function TEncyclopedia.CreateLoneStar(StarID: TStarID; System: TSystem): TAssetNode;
var
   Category: TStarCategory;
   Overrides: TFeatureNodeOverrides;
begin
   Category := CategoryOf(StarID);
   SetLength(Overrides, 2);
   Overrides[0].FeatureClass := TStarFeatureClass;
   Overrides[0].FeatureNode := TStarFeatureNode.Create(System, StarID);
   Overrides[1].FeatureClass := TAssetNameFeatureClass;
   Overrides[1].FeatureNode := TAssetNameFeatureNode.Create(System, StarNameOf(StarID));
   Result := AssetClasses[kStarIDBase - Category].Spawn(nil { no owner }, System, Overrides); // $R-
end;

procedure TEncyclopedia.CondenseProtoplanetaryDisks(Space: TSolarSystemFeatureNode; System: TSystem);

   function CreateBodyNode(const Body: TBody): TAssetNode;
   var
      Index, Count: Cardinal;
      TotalVolume, TotalRelativeVolume: Double;
      BodyComposition: TBodyComposition;
      AssetComposition: TOreFractions;
      Overrides: TFeatureNodeOverrides;
   begin
      TotalRelativeVolume := 0.0;
      Count := 0;
      for BodyComposition in Body.Composition do
      begin
         if (BodyComposition.RelativeVolume > 0) then
         begin
            TotalRelativeVolume := TotalRelativeVolume + BodyComposition.RelativeVolume;
            Inc(Count);
         end;
      end;
      Assert(Count > 0);
      Assert(TotalRelativeVolume > 0.0);
      TotalVolume := Body.Radius * Body.Radius * Body.Radius * Pi * 4.0 / 3.0; // $R-
      Index := 0;
      Assert(TotalVolume > 0);
      for Index := Low(AssetComposition) to High(AssetComposition) do
         AssetComposition[Index].ResetToZero(); // {BOGUS Warning: Local variable "AssetComposition" does not seem to be initialized}
      for BodyComposition in Body.Composition do
      begin
         if (BodyComposition.RelativeVolume > 0) then
         begin
            Assert(BodyComposition.Material.ID >= Low(TOres));
            Assert(BodyComposition.Material.ID <= High(TOres));
            Assert(BodyComposition.RelativeVolume > 0);
            Assert(BodyComposition.Material.MassPerUnit.IsPositive);
            Assert(BodyComposition.Material.Density > 0);
            Assert(AssetComposition[BodyComposition.Material.ID].IsZero);
            AssetComposition[BodyComposition.Material.ID] := Fraction32.FromDouble((BodyComposition.RelativeVolume / TotalRelativeVolume) * TotalVolume * BodyComposition.Material.Density / Body.ApproximateMass.ToSIUnits());
            // This might end up being zero, if the RelativeVolume is very very low (but non-zero). That's fine, the default is zero anyway.
         end;
      end;
      Fraction32.NormalizeArray(@AssetComposition[Low(AssetComposition)], Length(AssetComposition));
      SetLength(Overrides, 1);
      Overrides[0].FeatureClass := TPlanetaryBodyFeatureClass;
      Overrides[0].FeatureNode := TPlanetaryBodyFeatureNode.Create(
         System,
         Body.Seed,
         Body.Radius * 2.0, // diameter of body
         Body.Temperature,
         AssetComposition,
         Body.ApproximateMass,
         Body.Habitable // whether to consider this body when selecting a crash landing point
      ); // $R-
      Result := PlanetaryBody.Spawn(nil { no owner }, System, Overrides);
   end;

   procedure AddBody(const Body: TBody; Orbit: TOrbitFeatureNode);
   var
      Node, OrbitNode: TAssetNode;
      Satellite: TBody;
   begin
      Node := CreateBodyNode(Body);
      Assert(ApproximatelyEqual(Node.Mass.ToSIUnits(), WeighBody(Body).ToSIUnits()), 'Node.Mass = ' + Node.Mass.ToString() + '; WeighBody = ' + WeighBody(Body).ToString());
      Assert(Node.Size < Orbit.PrimaryChild.Size);
      OrbitNode := WrapAssetForOrbit(Node);
      Orbit.AddOrbitingChild(
         OrbitNode,
         Body.Distance,
         Body.Eccentricity,
         System.RandomNumberGenerator.GetDouble(0.0, 2.0 * Pi), // Omega // $R-
         TTimeInMilliseconds.FromMilliseconds(0), // TimeOrigin // TODO: make this a random point in the body's period
         Body.Clockwise
      );
      if (Assigned(Body.Moons)) then
      begin
         for Satellite in Body.Moons^ do
         begin
            AddBody(Satellite, OrbitNode.GetFeatureByClass(TOrbitFeatureClass) as TOrbitFeatureNode);
         end;
         Dispose(Body.Moons);
      end;
   end;

var
   Index: Cardinal;
   StarOrbit, Star: TAssetNode;
   StarHillDiameter: Double;
   Planets: TBodyArray;
   Body: TBody;
   StarOrbitFeature: TOrbitFeatureNode;
   StarFeature: TStarFeatureNode;
begin
   Assert(Space.ChildCount > 0);
   for Index := 0 to Space.ChildCount - 1 do // $R-
   begin
      StarOrbit := Space.Children[Index];
      StarOrbitFeature := StarOrbit.GetFeatureByClass(TOrbitFeatureClass) as TOrbitFeatureNode;
      Star := StarOrbitFeature.PrimaryChild;
      StarFeature := Star.GetFeatureByClass(TStarFeatureClass) as TStarFeatureNode;
      StarHillDiameter := Space.GetHillDiameter(StarOrbit, Star.Mass);
      if (StarHillDiameter > Star.Size) then
      begin
         CondenseProtoplanetaryDisk(Star.Mass, Star.Size / 2.0, StarHillDiameter / 2.0, StarFeature.Temperature, FProtoplanetaryMaterials, System, Planets);
         for Body in Planets do
         begin
            AddBody(Body, StarOrbitFeature);
         end;
      end;
   end;
end;

function TEncyclopedia.CreateRegion(CellSize: Double; Dimension: Cardinal; System: TSystem): TAssetNode;
var
   Overrides: TFeatureNodeOverrides;
begin
   SetLength(Overrides, 1);
   Overrides[0].FeatureClass := TGridFeatureClass;
   Overrides[0].FeatureNode := TGridFeatureNode.Create(System, bePlanetRegion, CellSize, Dimension);
   Result := Region.Spawn(nil { no owner }, System, Overrides);
end;

procedure TEncyclopedia.FindTemperatureEquilibria(System: TSystem);

   function FindSuns(Asset: TAssetNode): Boolean;
   var
      SunOrbit: TOrbitFeatureNode;
      Sun: TStarFeatureNode;
      SunTemperature, SunRadius: Double;

      function ComputeAverageDistance(Asset: TAssetNode): Double;
      begin
         while (Asset.Parent <> SunOrbit) do
            Asset := Asset.Parent.Parent;
         Result := SunOrbit.GetAverageDistance(Asset);
      end;

      function FindPlanets(Asset: TAssetNode): Boolean;
      var
         PlanetOrbit: TOrbitFeatureNode;
         Planet: TPlanetaryBodyFeatureNode;
         PlanetAverageOrbitalDistance, PlanetBondAlbedo, PlanetTemperature: Double;
      begin
         PlanetOrbit := Asset.GetFeatureByClass(TOrbitFeatureClass) as TOrbitFeatureNode;
         if (Assigned(PlanetOrbit)) then
         begin
            Assert(Assigned(PlanetOrbit.PrimaryChild));
            Planet := PlanetOrbit.PrimaryChild.GetFeatureByClass(TPlanetaryBodyFeatureClass) as TPlanetaryBodyFeatureNode;
            if (Assigned(Planet)) then
            begin
               PlanetAverageOrbitalDistance := ComputeAverageDistance(Asset);
               PlanetBondAlbedo := Planet.BondAlbedo;
               PlanetTemperature := SunTemperature * SqRt(SunRadius / (2.0 * PlanetAverageOrbitalDistance)) * Power(1 - PlanetBondAlbedo, 1.0 / 4.0); // $R-
               Assert(PlanetTemperature >= 0.0);
               Assert(PlanetTemperature <= SunTemperature);
               Planet.SetTemperature(PlanetTemperature);
            end;
            Result := True;
         end
         else
            Result := False;
      end;

   begin
      SunOrbit := Asset.GetFeatureByClass(TOrbitFeatureClass) as TOrbitFeatureNode;
      if (Assigned(SunOrbit)) then
      begin
         Assert(Assigned(SunOrbit.PrimaryChild));
         Sun := SunOrbit.PrimaryChild.GetFeatureByClass(TStarFeatureClass) as TStarFeatureNode;
         if (Assigned(Sun)) then
         begin
            SunTemperature := Sun.Temperature;
            SunRadius := Sun.Size / 2.0;
            Asset.Walk(@FindPlanets, nil);
         end;
         Result := False;
      end
      else
         Result := True;
   end;

begin
   System.RootNode.Walk(@FindSuns, nil);
end;

procedure TEncyclopedia.SpawnColonyShip(Dynasty: TDynasty; System: TSystem);

   function FindHome(System: TSystem): TAssetNode;
   var
      Home: TAssetNode;
      Count: Cardinal;

      function Consider(Asset: TAssetNode): Boolean;
      var
         Planet: TPlanetaryBodyFeatureNode;
         N: Cardinal;
      begin
         Planet := Asset.GetFeatureByClass(TPlanetaryBodyFeatureClass) as TPlanetaryBodyFeatureNode;
         N := 1;
         if (Assigned(Planet) and Planet.ConsiderForDynastyStart) then
         begin
            if ((not Assigned(Home)) or (System.RandomNumberGenerator.GetBoolean(1/N))) then
               Home := Asset;
            Result := False; // we don't walk into planets
            Inc(N);
         end
         else
            Result := True;
         Inc(Count);
      end;

   begin
      Count := 0;
      Home := nil;
      System.RootNode.Walk(@Consider, nil);
      Result := Home;
   end;

const
   GameStartTime: TWallMillisecondsDuration = (Value: 30000);
var
   Period: TMillisecondsDuration;
   A, PeriodOverTwoPi, Omega: Double;
   Home, Ship: TAssetNode;
   Overrides: TFeatureNodeOverrides;
   Instabuild: TInstabuildBusMessage;
begin
   Home := FindHome(System);
   // We pick a period that should mean that the ship is at the
   // apoapsis and will reach periapsis in GameStartTime of
   // real-world time, i.e. a period that is twice GameStartTime.
   // We then figure out what the semi-major axis is for that
   // orbit, using the normal equation for orbital period, solved
   // for the semi-major axis.
   Period := (GameStartTime * System.TimeFactor).Scale(3.0);
   PeriodOverTwoPi := Period.ToSIUnits() / (2 * Pi); // $R-
   A := Power(PeriodOverTwoPi * PeriodOverTwoPi * G * Home.Mass.ToSIUnits(), 1/3); // $R-
   Omega := System.RandomNumberGenerator.GetDouble(0.0, 2.0 * Pi); // $R-
   SetLength(Overrides, 1);
   Overrides[0].FeatureClass := TDynastyOriginalColonyShipFeatureClass;
   Overrides[0].FeatureNode := TDynastyOriginalColonyShipFeatureNode.Create(System, Dynasty);
   Ship := ColonyShip.Spawn(Dynasty, System, Overrides);
   Instabuild := TInstabuildBusMessage.Create();
   Ship.HandleBusMessage(Instabuild);
   FreeAndNil(Instabuild);
   (Home.Parent as TOrbitFeatureNode).AddOrbitingChild(
      WrapAssetForOrbit(Ship),
      A,
      0.95, // Eccentricity
      Omega,
      System.Now - (Period - GameStartTime * System.TimeFactor), // TimeOffset
      System.RandomNumberGenerator.GetBoolean(0.5) // Clockwise (really doesn't matter, it's going in more or less a straight line)
   );
end;

function TEncyclopedia.Craterize(Diameter: Double; OldAssets: TAssetNode.TArray; NewAsset: TAssetNode): TAssetNode;
var
   OldAsset: TAssetNode;
   CompositionTable: TMaterialQuantityHashTable;
   Composition: TMaterialQuantity64Array;
   RubbleCollectionMessage: TRubbleCollectionMessage;
   Index: Cardinal;
   Material: TMaterial;
   Overrides: TFeatureNodeOverrides;
begin
   Assert(Assigned(NewAsset));
   Assert(Diameter >= NewAsset.Size);
   // TODO: skip this if OldAssets is empty
   CompositionTable := TMaterialQuantityHashTable.Create();
   try
      for OldAsset in OldAssets do
      begin
         Assert(Diameter >= OldAsset.Size);
         RubbleCollectionMessage := TRubbleCollectionMessage.Create();
         try
            OldAsset.HandleBusMessage(RubbleCollectionMessage);
            if (Length(RubbleCollectionMessage.Composition) > 0) then
            begin
               for Index := Low(RubbleCollectionMessage.Composition) to High(RubbleCollectionMessage.Composition) do // $R-
                  CompositionTable.Inc(RubbleCollectionMessage.Composition[Index].Material, RubbleCollectionMessage.Composition[Index].Quantity);
            end;
         finally
            FreeAndNil(RubbleCollectionMessage);
         end;
      end;
      SetLength(Composition, CompositionTable.Count);
      Index := 0;
      for Material in CompositionTable do
      begin
         Composition[Index].Material := Material;
         Composition[Index].Quantity := CompositionTable[Material];
         Inc(Index);
      end;
   finally
      FreeAndNil(CompositionTable);
   end;
   for OldAsset in OldAssets do
   begin
      OldAsset.ReportPermanentlyGone();
      OldAsset.Parent.DropChild(OldAsset);
      OldAsset.System.Server.ScheduleDemolition(OldAsset);
   end;
   SetLength(Overrides, 2);
   Overrides[0].FeatureClass := TProxyFeatureClass;
   Overrides[0].FeatureNode := TProxyFeatureNode.Create(NewAsset.System, NewAsset);
   Overrides[1].FeatureClass := TRubblePileFeatureClass;
   Overrides[1].FeatureNode := TRubblePileFeatureNode.Create(NewAsset.System, Diameter, Composition);
   Result := Crater.Spawn(nil { no owner }, NewAsset.System, Overrides);
end;

function TEncyclopedia.HandleBusMessage(Asset: TAssetNode; Message: TBusMessage): THandleBusMessageResult;
var
   DismantleMessage: TDismantleMessage;
begin
   // be careful when adding new branches -- TPhysicalConnectionWithExclusionBusMessage is a superclass of other message types
   if (Message is TPhysicalConnectionWithExclusionBusMessage) then
   begin
      // This is used for TStoreMaterialBusMessage when dismantling
      // (TDismantleMessage) to prevent us from trying to store things
      // in the asset being dismantled.
      if ((Message as TPhysicalConnectionWithExclusionBusMessage).Asset = Asset) then
      begin
         Result := hrShortcut;
         exit;
      end;
   end
   else
   if (Message is TDismantleMessage) then
   begin
      DismantleMessage := Message as TDismantleMessage;
      if (Assigned(Asset.Owner) and (DismantleMessage.Owner <> Asset.Owner)) then
      begin
         DismantleMessage.AddExcessAsset(Asset);
         Result := hrShortcut;
         exit;
      end;
   end;
   Result := hrActive;
end;

procedure TEncyclopedia.Dismantle(Asset: TAssetNode; Message: TMessage);
var
   DismantleMessage: TDismantleMessage;

   function CleanGossip(Child: TAssetNode): Boolean;
   begin
      DismantleMessage.HandleAssetGoingAway(Child);
      Result := True;
   end;

var
   FindDestructors: TFindDestructorsMessage;
   ExcessAssets: TAssetNode.TArray;
   ExcessMaterials: TMaterialQuantityHashTable;
   RubbleComposition: TMaterialQuantity64Array;
   Child: TAssetNode;
   Material: TMaterial;
   Index: Cardinal;
   Handled: THandleBusMessageResult;
   PlayerDynasty: TDynasty;
   OldSize: Double;
   Gossip: TGossipHashTable;
begin
   if (Message.CloseInput()) then
   begin
      Message.Reply();
      PlayerDynasty := (Message.Connection as TConnection).PlayerDynasty;
      if (Assigned(Asset.Owner) and (PlayerDynasty <> Asset.Owner)) then
      begin
         Message.Error(ieNotOwner);
      end
      else
      begin
         Writeln('DISMANTLE LOGIC CALLED');
         Writeln('TARGET: ', Asset.DebugName);
         if (Asset.Mass.IsNotZero) then
         begin
            Writeln('SEARCHING FOR DESTRUCTORS');
            FindDestructors := TFindDestructorsMessage.Create(PlayerDynasty);
            try
               if (Asset.InjectBusMessage(FindDestructors) <> irHandled) then
               begin
                  Writeln('NO DESTRUCTOR DETECTED');
                  Message.Error(ieNoDestructors);
                  exit;
               end;
            finally
               FreeAndNil(FindDestructors);
            end;
         end;
         OldSize := Asset.Size;
         Writeln('DESTRUCTOR DETECTED');
         DismantleMessage := TDismantleMessage.Create(PlayerDynasty, Asset, Asset.System.Now);
         Writeln('SENDING DISMANTLE MESSAGE');
         Handled := Asset.HandleBusMessage(DismantleMessage);
         Assert(Handled <> hrHandled, 'TDismantleMessage must not be marked as handled');
         if (DismantleMessage.HasExcess) then
         begin
            Writeln('EXCESS DETECTED');
            ExcessAssets := DismantleMessage.ExtractExcessAssets();
            for Child in ExcessAssets do
               Child.Parent.DropChild(Child);
            if (not Assigned(Asset.Owner)) then
            begin
               Asset.MarkAsDirty([dkAffectsDynastyCount]);
               Asset.Owner := PlayerDynasty;
            end;
            Assert(Asset.Owner = PlayerDynasty);
            Asset.Walk(@CleanGossip, nil);
            Asset.Become(RubblePile);
            if (DismantleMessage.ExcessPopulation > 0) then
            begin
               Writeln('POPULATION PLACED ON RUBBLE ', DismantleMessage.ExcessPopulation);
               Gossip := DismantleMessage.ExtractGossip();
               if (Gossip.Allocated) then
                  Writeln('GOSSIP DETECTED');
               (Asset.Features[0] as TPopulationFeatureNode).AbsorbPopulation(DismantleMessage.ExtractPopulation(), Gossip);
               Gossip.Free();
            end;
            (Asset.Features[1] as TRubblePileFeatureNode).Resize(OldSize);
            if (DismantleMessage.HasExcessMaterials) then
            begin
               ExcessMaterials := DismantleMessage.ExtractExcessMaterials();
               SetLength(RubbleComposition, ExcessMaterials.Count);
               Index := 0;
               for Material in ExcessMaterials do
               begin
                  Writeln('RUBBLE CONTENTS: ', Material.Name, ' ', (ExcessMaterials[Material] * Material.MassPerUnit).ToString());
                  RubbleComposition[Index].Init(Material, ExcessMaterials[Material]);
                  Inc(Index);
               end;
               FreeAndNil(ExcessMaterials);
               (Asset.Features[1] as TRubblePileFeatureNode).AbsorbRubble(RubbleComposition);
            end;
            for Child in ExcessAssets do
            begin
               (Asset.Features[2] as TAssetPileFeatureNode).AdoptChild(Child);
               Writeln('RUBBLE CONTENTS: ', Child.DebugName);
            end;
            // TODO: send dkMassChanged if the mass changed
         end
         else
         begin
            Writeln('ASSET DESTRUCTION AUTHORIZED');
            // MarkAsDirty([dkAffectsDynastyCount]); // TODO: add this in if it's possible for this to be relevant (currently it shouldn't be possible)
            Asset.ReportPermanentlyGone();
            Asset.Parent.DropChild(Asset);
            Asset.System.Server.ScheduleDemolition(Asset);
            // TODO: handle the case of removing an orbit's primary child
         end;
         FreeAndNil(DismantleMessage);
         Writeln('DISMANTLE LOGIC COMPLETED');
         Message.CloseOutput();
      end;
   end;
end;

end.