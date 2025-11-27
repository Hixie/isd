{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit encyclopedia;

interface

uses
   techtree, systems, configuration, astronomy, materials,
   random, systemdynasty, space, basenetwork;

type
   TEncyclopedia = class(TEncyclopediaView)
   private
      var
         FMaterials: TMaterialIDHashTable;
         FAssetClasses: TAssetClassIDHashTable;
         FResearches: TResearchIDHashTable;
         FTopics: TTopicHashTable;
         FSpace, FOrbits: TAssetClass;
         FPlaceholderShip: TAssetClass;
         FPlaceholderShipInstructionManual: TResearch;
         FCrater, FRubblePile: TAssetClass;
         FMessage: TAssetClass;
         FStars: array[TStarCategory] of TAssetClass;
         FPlanetaryBody, FRegion: TAssetClass;
         FProtoplanetaryMaterials: TMaterial.TArray; // order matters, it's used in protoplanetary generation
         FDarkMatter: TMaterial;
         FMinMassPerOreUnit: Double; // cached value based on ores in materials passed to constructor
      function GetStarClass(Category: TStarCategory): TAssetClass;
      function CreateRegion(CellSize: Double; Dimension: Cardinal; System: TSystem): TAssetNode;
   protected
      function GetAssetClass(ID: Integer): TAssetClass; override;
      function GetMaterial(ID: TMaterialID): TMaterial; override;
      function GetResearch(ID: TResearchID): TResearch; override;
      function GetTopic(Name: UTF8String): TTopic; override;
      function GetMinMassPerOreUnit(): Double; override;
      procedure RegisterAssetClass(AssetClass: TAssetClass);
   public
      constructor Create(Settings: PSettings; const AMaterials: TMaterial.TArray; TechTree: TTechnologyTree); // AMaterials must contain all TOres
      destructor Destroy(); override;
      procedure RegisterMaterials(const AMaterials: TMaterialHashSet);
      procedure RegisterMaterials(const AMaterials: TMaterial.TArray);
      procedure ProcessTechTree(TechTree: TTechnologyTree);
      property PlaceholderShipInstructionManual: TResearch read FPlaceholderShipInstructionManual;
      function WrapAssetForOrbit(Child: TAssetNode): TAssetNode;
      function CreateLoneStar(StarID: TStarID; System: TSystem): TAssetNode;
      procedure CondenseProtoplanetaryDisks(Space: TSolarSystemFeatureNode; System: TSystem);
      procedure FindTemperatureEquilibria(System: TSystem);
      procedure SpawnColonyShip(Dynasty: TDynasty; System: TSystem);
      function Craterize(Diameter: Double; OldAssets: TAssetNode.TArray; NewAsset: TAssetNode): TAssetNode; override;
      function HandleBusMessage(Asset: TAssetNode; Message: TBusMessage): Boolean; override;
      procedure Dismantle(Asset: TAssetNode; Message: TMessage); override;
      property MinMassPerOreUnit: Double read FMinMassPerOreUnit;
   public // built-in asset classes
      property SpaceClass: TAssetClass read FSpace;
      property PlaceholderShip: TAssetClass read FPlaceholderShip;
      property RegionClass: TAssetClass read FRegion;
      property MessageClass: TAssetClass read FMessage;
      property RubblePile: TAssetClass read FRubblePile;
      property StarClass[Category: TStarCategory]: TAssetClass read GetStarClass;
   end;

implementation

uses
   sysutils, math, floatutils, exceptions, isdnumbers, protoplanetary,
   time, isdprotocol, commonbuses, systemnetwork,
   // this must import every feature, so they get registered:
   assetpile, builders, food, grid, gridsensor, internalsensor,
   knowledge, materialpile, messages, mining, name, onoff, orbit,
   orepile, peoplebus, planetary, plot, population, proxy, refining,
   region, research, rubble, size, spacesensor, staffing, stellar,
   structure, surface;

var
   // TODO: find a way to get this to the client
   InstructionManualText: UTF8String =
      'Congratulations on your purchase of a Interstellar Dynasty Colony Ship.'#10 +
      'This ship will take you and your party of up to 1000 colonists to your new world, ' +
      'thus saving you from our planet''s impending doom.'#10 +
      'While your Interstellar Dynasty Colony Ship is largely automated and ' +
      'requires only minimal maintenance, in this manual you will find basic ' +
      'instructions for the operation of your colony ship and various elementary ' +
      'procedures that you may find useful upon arrival at your new home.'#10 +
      'From all of us here at Interstellar Dynasties, we wish you a pleasant ' +
      'settlement and a wonderful new life!';

function RoundAboveZero(Value: Double): Cardinal;
begin
   Assert(Value < High(Result));
   Assert(Value >= 0.0);
   Result := Round(Value); // $R-
   if (Result = 0) then
      Result := 1;
end;


constructor TEncyclopedia.Create(Settings: PSettings; const AMaterials: TMaterial.TArray; TechTree: TTechnologyTree);

   function CreateStarFeatures(): TFeatureClass.TArray;
   begin
      Result := [ TStarFeatureClass.Create(), TAssetNameFeatureClass.Create() ];
   end;

var
   AssetClass: TAssetClass;
   Ore: TOres;
begin
   inherited Create();

   FMaterials := TMaterialIDHashTable.Create();
   FProtoplanetaryMaterials := AMaterials;
   RegisterMaterials(FProtoplanetaryMaterials);
   {$PUSH} {$IEEEERRORS OFF} FMinMassPerOreUnit := Infinity; {$POP}
   for Ore in TOres do
   begin
      Assert(FMaterials.Has(Ore));
      if (FMaterials[Ore].MassPerUnit < FMinMassPerOreUnit) then
         FMinMassPerOreUnit := FMaterials[Ore].MassPerUnit;
   end;

   FAssetClasses := TAssetClassIDHashTable.Create();
   FResearches := TResearchIDHashTable.Create();
   FTopics := TTopicHashTable.Create();
   ProcessTechTree(TechTree);

   FSpace := TAssetClass.Create(
      idSpace,
      'Space',
      'Space',
      'A region of outer space.',
      [ TSolarSystemFeatureClass.Create(Settings^.StarGroupingThreshold, Settings^.GravitionalInfluenceConstant) ],
      SpaceIcon,
      []
   );
   RegisterAssetClass(FSpace);

   FOrbits := TAssetClass.Create(
      idOrbits,
      'Orbit',
      'Orbit',
      'Objects in space are attracted to each other in a way that makes them spin around each other.',
      [ TOrbitFeatureClass.Create() ],
      OrbitIcon,
      []
   );
   RegisterAssetClass(FOrbits);

   // TODO: move these names and descriptions into TStarFeatureNode
   FStars[2] := TAssetClass.Create(idStars - 2,
                                   'Brown dwarf star', 'Star',
                                   'A late class M star. Class M stars are among the coldest stars in the galaxy at around 3000K. ' +
                                   'This star is at the lower end of the temperature scale for M stars.',
                                   CreateStarFeatures(), Star2Icon, []);
   FStars[3] := TAssetClass.Create(idStars - 3,
                                   'Red dwarf star', 'Star',
                                   'A class M star. Class M stars are among the coldest stars in the galaxy at around 3000K.',
                                   CreateStarFeatures(), Star3Icon, []);
   FStars[8] := TAssetClass.Create(idStars - 8,
                                   'K-type main-sequence star', 'Star',
                                   'A class K star. Class K stars are around 4000K.',
                                   CreateStarFeatures(), Star8Icon, []);
   FStars[4] := TAssetClass.Create(idStars - 4,
                                   'G-type main-sequence star', 'Star',
                                   'A class G star. This whiteish-colored star is around 6000K.',
                                   CreateStarFeatures(), Star4Icon, []);
   FStars[5] := TAssetClass.Create(idStars - 5,
                                   'F-type main-sequence star', 'Star',
                                   'A class F star. Class F stars are around 7000K.',
                                   CreateStarFeatures(), Star5Icon, []);
   FStars[9] := TAssetClass.Create(idStars - 9,
                                   'A-type main-sequence star', 'Star',
                                   'A class A star. Class A stars can reach temperatures of up to 10000K.',
                                   CreateStarFeatures(), Star9Icon, []);
   FStars[6] := TAssetClass.Create(idStars - 6,
                                   'B-type main-sequence star', 'Star',
                                   'A class B star. Class B stars are extremely hot, around 20000K.',
                                   CreateStarFeatures(), Star6Icon, []);
   FStars[7] := TAssetClass.Create(idStars - 7,
                                   'O-type main-sequence star', 'Star',
                                   'A class O star. Class O stars are the brightest and hottest stars in the galaxy, over 30000K.',
                                   CreateStarFeatures(), Star7Icon, []);
   FStars[10] := TAssetClass.Create(idStars - 10,
                                   'Red hypergiant star', 'Star',
                                   'A very large, very bright star.',
                                   CreateStarFeatures(), Star10Icon, []);
   for AssetClass in FStars do
      if (Assigned(AssetClass)) then
         RegisterAssetClass(AssetClass);

   FDarkMatter := TMaterial.Create(
      idDarkMatter,
      'Dark Matter',
      'A murky black material',
      'The most fundamental and least useful material in the universe, used only for placeholders.',
      DarkMatterIcon,
      ukBulkResource,
      1e-3, // smallest unit is 1 gram
      1.0, // kg per m^3
      0.0,
      [], // tags
      ZeroAbundance // abundances
   );
   FMaterials.Add(FDarkMatter.ID, FDarkMatter);

   FPlanetaryBody := TAssetClass.Create(
      idPlanetaryBody,
      'Planetary body',
      'Really big rock',
      'A cold gravitionally-bound astronomical object. (Cold when compared to a star, at least.)',
      [
         TPlanetaryBodyFeatureClass.Create(),
         TSurfaceFeatureClass.Create(1000.0 { cell size }, 3, 9, @CreateRegion)
      ],
      PlanetIcon,
      []
   );
   RegisterAssetClass(FPlanetaryBody);

   FCrater := TAssetClass.Create(
      idCrater,
      'Crater',
      'Hole',
      'A hole containing the remnants of an area where something else crashed.',
      [
         TProxyFeatureClass.Create(),
         TRubblePileFeatureClass.Create()
      ],
      CraterIcon,
      []
   );
   RegisterAssetClass(FCrater);

   FRubblePile := TAssetClass.Create(
      idRubblePile,
      'Rubble pile',
      'Rubble pile',
      'The remains of some form of destruction.',
      [
         TPopulationFeatureClass.Create(True, 0),
         TRubblePileFeatureClass.Create(),
         TAssetPileFeatureClass.Create()
      ],
      RubblePileIcon,
      []
   );
   RegisterAssetClass(FRubblePile);

   FRegion := TAssetClass.Create(
      idRegion,
      'Geological region',
      'Region',
      'An area of a planetary body.',
      [
         TRegionFeatureClass.Create(1, 10, High(UInt64)),
         TKnowledgeBusFeatureClass.Create(),
         TFoodBusFeatureClass.Create(),
         TBuilderBusFeatureClass.Create(),
         TPeopleBusFeatureClass.Create(),
         TGenericGridFeatureClass.Create() // must be after the busses, so that they don't defer to something in the grid
      ],
      PlanetRegionIcon,
      []
   );
   RegisterAssetClass(FRegion);

   FMessage := TAssetClass.Create(
      idMessage,
      'Message', 'Some sort of text',
      'A notification.',
      [
         TMessageFeatureClass.Create(),
         TKnowledgeFeatureClass.Create()
      ],
      MessageIcon,
      []
   );
   RegisterAssetClass(FMessage);

   FPlaceholderShip := TAssetClass.Create(
      idPlaceholderShip,
      'Colony Ship', 'Unidentified Flying Object',
      'A ship that people used to escape their dying star.',
      [
         TSpaceSensorFeatureClass.Create(10 { max steps to orbit }, 3 { steps up from orbit }, 2 { steps down from top }, 2e5 { min size (meters) }, [dmVisibleSpectrum]),
         TGridSensorFeatureClass.Create([dmVisibleSpectrum]),
         TStructureFeatureClass.Create([TMaterialLineItem.Create('Shell', FDarkMatter, 10000 { mass in units (g): 10kg })], 1 { min functional quantity }, 500.0 { default diameter, m }),
         TDynastyOriginalColonyShipFeatureClass.Create(),
         TPopulationFeatureClass.Create(False, 2000),
         TMessageBoardFeatureClass.Create(FMessage),
         TKnowledgeBusFeatureClass.Create(),
         TFoodBusFeatureClass.Create(),
         TFoodGenerationFeatureClass.Create(100),
         TPeopleBusFeatureClass.Create(),
         TResearchFeatureClass.Create(),
         TInternalSensorFeatureClass.Create([dmVisibleSpectrum]),
         TKnowledgeFeatureClass.Create(), // the instruction manual, ziptied to the ship
         TOnOffFeatureClass.Create()
      ],
      ColonyShipIcon,
      [beSpaceDock]
   );
   RegisterAssetClass(FPlaceholderShip);

   FPlaceholderShipInstructionManual := TResearch.Create(
      idPlaceholderShipInstructionManualResearch,
      TMillisecondsDuration.Zero,
      0,
      [],
      [],
      [
         TReward.CreateForMessage(InstructionManualText),
         TReward.CreateForAssetClass(FPlaceholderShip),
         TReward.CreateForAssetClass(FMessage),
         TReward.CreateForAssetClass(FPlanetaryBody),
         TReward.CreateForAssetClass(FRegion),
         TReward.CreateForAssetClass(FCrater),
         TReward.CreateForAssetClass(FRubblePile)
      ]
   );
   FResearches[FPlaceholderShipInstructionManual.ID] := FPlaceholderShipInstructionManual;
end;

destructor TEncyclopedia.Destroy();
var
   AssetClass: TAssetClass;
   Research: TResearch;
   Material: TMaterial;
   Topic: TTopic;
begin
   for Research in FResearches.Values do
      Research.Free();
   FResearches.Free();
   for Material in FMaterials.Values do
      Material.Free();
   FMaterials.Free();
   for AssetClass in FAssetClasses.Values do
      AssetClass.Free();
   FAssetClasses.Free();
   for Topic in FTopics.Values do
      Topic.Free();
   FTopics.Free();
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
   TechTreeResearches: TResearch.TArray;
   Research: TResearch;
   TechTreeTopics: TTopic.TArray;
   Topic: TTopic;
begin
   TechTreeMaterials := TechTree.ExtractMaterials();
   for Material in TechTreeMaterials do
      FMaterials[Material.ID] := Material;
   TechTreeAssetClasses := TechTree.ExtractAssetClasses();
   for AssetClass in TechTreeAssetClasses do
      FAssetClasses[AssetClass.ID] := AssetClass;
   TechTreeResearches := TechTree.ExtractResearches();
   for Research in TechTreeResearches do
      FResearches[Research.ID] := Research;
   TechTreeTopics := TechTree.ExtractTopics();
   for Topic in TechTreeTopics do
      FTopics[Topic.Value] := Topic;
end;

function TEncyclopedia.GetAssetClass(ID: Integer): TAssetClass;
begin
   Result := FAssetClasses[ID];
end;

function TEncyclopedia.GetMaterial(ID: TMaterialID): TMaterial;
begin
   Result := FMaterials[ID];
end;

function TEncyclopedia.GetResearch(ID: TResearchID): TResearch;
begin
   Result := FResearches[ID];
end;

function TEncyclopedia.GetTopic(Name: UTF8String): TTopic;
begin
   Result := FTopics[Name];
end;

function TEncyclopedia.GetMinMassPerOreUnit(): Double;
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
   Assert(Assigned(FStars[Category]));
   Result := FStars[Category];
end;

function TEncyclopedia.WrapAssetForOrbit(Child: TAssetNode): TAssetNode;
var
   OrbitFeature: TOrbitFeatureNode;
begin
   OrbitFeature := TOrbitFeatureNode.Create(Child.System);
   Result := FOrbits.Spawn(nil { orbits have no owner }, Child.System, [ OrbitFeature ]);
   OrbitFeature.SetPrimaryChild(Child);
end;

function TEncyclopedia.CreateLoneStar(StarID: TStarID; System: TSystem): TAssetNode;
var
   Category: TStarCategory;
begin
   Category := CategoryOf(StarID);
   Assert(Assigned(FStars[Category]));
   Result := FStars[Category].Spawn(
      nil, // no owner
      System,
      [
         TStarFeatureNode.Create(System, StarID),
         TAssetNameFeatureNode.Create(System, StarNameOf(StarID))
      ]
   );
end;

procedure TEncyclopedia.CondenseProtoplanetaryDisks(Space: TSolarSystemFeatureNode; System: TSystem);

   function CreateBodyNode(const Body: TBody): TAssetNode;
   var
      Index, Count: Cardinal;
      TotalVolume, TotalRelativeVolume: Double;
      BodyComposition: TBodyComposition;
      AssetComposition: TOreFractions;
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
            Assert(BodyComposition.Material.MassPerUnit > 0);
            Assert(BodyComposition.Material.Density > 0);
            Assert(AssetComposition[BodyComposition.Material.ID].IsZero);
            AssetComposition[BodyComposition.Material.ID] := Fraction32.FromDouble((BodyComposition.RelativeVolume / TotalRelativeVolume) * TotalVolume * BodyComposition.Material.Density / Body.ApproximateMass);
            // This might end up being zero, if the RelativeVolume is very very low (but non-zero). That's fine, the default is zero anyway.
         end;
      end;
      Fraction32.NormalizeArray(@AssetComposition[Low(AssetComposition)], Length(AssetComposition));
      Result := FPlanetaryBody.Spawn(
         nil, // no owner
         System,
         [
            TPlanetaryBodyFeatureNode.Create(
               System,
               Body.Seed,
               Body.Radius * 2.0, // diameter of body
               Body.Temperature,
               AssetComposition,
               Body.ApproximateMass,
               Body.Habitable // whether to consider this body when selecting a crash landing point
            ), // $R-
            TSurfaceFeatureNode.Create(
               System,
               FPlanetaryBody.Features[1] as TSurfaceFeatureClass,
               Body.Radius * 2.0 // diameter of surface
            )
         ]
      );
   end;

   procedure AddBody(const Body: TBody; Orbit: TOrbitFeatureNode);
   var
      Node, OrbitNode: TAssetNode;
      Satellite: TBody;
   begin
      Node := CreateBodyNode(Body);
      Assert(ApproximatelyEqual(Node.Mass, WeighBody(Body)), 'Node.Mass = ' + FloatToStr(Node.Mass) + '; WeighBody = ' + FloatToStr(WeighBody(Body)));
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
begin
   Result := FRegion.Spawn(
      nil, // no owner
      System,
      [
         TRegionFeatureNode.Create(System, FRegion.Features[0] as TRegionFeatureClass),
         TKnowledgeBusFeatureNode.Create(System),
         TFoodBusFeatureNode.Create(System),
         TBuilderBusFeatureNode.Create(System),
         TPeopleBusFeatureNode.Create(System),
         TGridFeatureNode.Create(System, bePlanetRegion, CellSize, Dimension)
      ]
   );
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
   Home: TAssetNode;
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
   A := Power(PeriodOverTwoPi * PeriodOverTwoPi * G * Home.Mass, 1/3); // $R-
   Omega := System.RandomNumberGenerator.GetDouble(0.0, 2.0 * Pi); // $R-
   (Home.Parent as TOrbitFeatureNode).AddOrbitingChild(
      WrapAssetForOrbit(PlaceholderShip.Spawn(
         Dynasty,
         System,
         [
            TSpaceSensorFeatureNode.Create(System, PlaceholderShip.Features[0] as TSpaceSensorFeatureClass),
            TGridSensorFeatureNode.Create(System, PlaceholderShip.Features[1] as TGridSensorFeatureClass),
            TStructureFeatureNode.Create(System, PlaceholderShip.Features[2] as TStructureFeatureClass, 10000 { materials quantity }, 10000 { hp }),
            TDynastyOriginalColonyShipFeatureNode.Create(System, Dynasty),
            TPopulationFeatureNode.CreatePopulated(System, PlaceholderShip.Features[4] as TPopulationFeatureClass, 2000, 1.0),
            TMessageBoardFeatureNode.Create(System, PlaceholderShip.Features[5] as TMessageBoardFeatureClass),
            TKnowledgeBusFeatureNode.Create(System),
            TFoodBusFeatureNode.Create(System),
            TFoodGenerationFeatureNode.Create(System, PlaceholderShip.Features[8] as TFoodGenerationFeatureClass),
            TPeopleBusFeatureNode.Create(System),
            TResearchFeatureNode.Create(System, PlaceholderShip.Features[10] as TResearchFeatureClass),
            TInternalSensorFeatureNode.Create(System, PlaceholderShip.Features[11] as TInternalSensorFeatureClass),
            TKnowledgeFeatureNode.Create(System, PlaceholderShipInstructionManual),
            TOnOffFeatureNode.Create(System)
         ]
      )),
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
   Composition: TMaterialQuantityArray;
   RubbleCollectionMessage: TRubbleCollectionMessage;
   Index: Cardinal;
   Material: TMaterial;
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
   for OldAsset in OldASsets do
   begin
      OldAsset.ReportPermanentlyGone();
      OldAsset.Parent.DropChild(OldAsset);
      OldAsset.System.Server.ScheduleDemolition(OldAsset);
   end;
   Result := FCrater.Spawn(nil { no owner }, NewAsset.System, [
      TProxyFeatureNode.Create(NewAsset.System, NewAsset),
      TRubblePileFeatureNode.Create(NewAsset.System, Diameter, Composition)
   ]);
end;

function TEncyclopedia.HandleBusMessage(Asset: TAssetNode; Message: TBusMessage): Boolean;
var
   DismantleMessage: TDismantleMessage;
begin
   if (Message is TPhysicalConnectionWithExclusionBusMessage) then
   begin
      if ((Message as TPhysicalConnectionWithExclusionBusMessage).Asset = Asset) then
      begin
         Result := True;
         exit;
      end;
   end;
   if (Message is TDismantleMessage) then
   begin
      DismantleMessage := Message as TDismantleMessage;
      if (Assigned(Asset.Owner) and (DismantleMessage.Owner <> Asset.Owner)) then
      begin
         DismantleMessage.AddExcessAsset(Asset);
         Result := True;
         exit;
      end;
   end;
   Result := False;
end;

procedure TEncyclopedia.Dismantle(Asset: TAssetNode; Message: TMessage);
var
   FindDestructors: TFindDestructorsMessage;
   DismantleMessage: TDismantleMessage;
   ExcessAssets: TAssetNode.TArray;
   ExcessMaterials: TMaterialQuantityHashTable;
   RubbleComposition: TMaterialQuantityArray;
   Child: TAssetNode;
   Material: TMaterial;
   Index: Cardinal;
   Handled: Boolean;
   PlayerDynasty: TDynasty;
   OldSize: Double;
begin
   if (Message.CloseInput()) then
   begin
      Message.Reply();
      PlayerDynasty := (Message.Connection as TConnection).PlayerDynasty;
      if (Assigned(Asset.Owner) and (PlayerDynasty <> Asset.Owner)) then
      begin
         Message.Error(ieInvalidMessage);
      end
      else
      begin
         Writeln('DISMANTLE LOGIC CALLED');
         Writeln('TARGET: ', Asset.DebugName);
         if (Asset.Mass <> 0.0) then
         begin
            Writeln('SEARCHING FOR DESTRUCTORS');
            FindDestructors := TFindDestructorsMessage.Create(PlayerDynasty);
            try
               if (Asset.InjectBusMessage(FindDestructors) <> mrHandled) then
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
         DismantleMessage := TDismantleMessage.Create(PlayerDynasty, Asset);
         Writeln('SENDING DISMANTLE MESSAGE');
         Handled := Asset.HandleBusMessage(DismantleMessage);
         Assert(not Handled, 'TDismantleMessage must not be marked as handled');
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
            Asset.Become(RubblePile);
            if (DismantleMessage.ExcessPopulation > 0) then
            begin
               Writeln('POPULATION PLACED ON RUBBLE ', DismantleMessage.ExcessPopulation);
               (Asset.Features[0] as TPopulationFeatureNode).AbsorbPopulation(DismantleMessage.ExcessPopulation);
            end;
            (Asset.Features[1] as TRubblePileFeatureNode).Resize(OldSize);
            if (DismantleMessage.HasExcessMaterials) then
            begin
               ExcessMaterials := DismantleMessage.ExtractExcessMaterials();
               SetLength(RubbleComposition, ExcessMaterials.Count);
               Index := 0;
               for Material in ExcessMaterials do
               begin
                  Writeln('RUBBLE CONTENTS: ', Material.Name, ' ', ExcessMaterials[Material] * Material.MassPerUnit, 'kg');
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