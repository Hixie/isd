{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit encyclopedia;

interface

uses
   systems, configuration, astronomy, space, materials, random;

type
   TEncyclopedia = class(TEncyclopediaView)
   private
      var
         FAssetClasses: TAssetClassHashTable; 
         FSpace, FOrbits: TAssetClass;
         FPlaceholderShip: TAssetClass;
         FCrater: TAssetClass;
         FMessage: TAssetClass;
         FStars: array[TStarCategory] of TAssetClass;
         FPlanetaryBody, FRegion: TAssetClass;
         FProtoplanetaryMaterials: TMaterialHashSet;
         FMaterials: TMaterialHashMap; // TODO: once we have a tech tree, reconsider this
         FDarkMatter: TMaterial;
      function GetStarClass(Category: TStarCategory): TAssetClass;
   protected
      function GetAssetClass(ID: Integer): TAssetClass; override;
      function GetMaterial(ID: TMaterialID): TMaterial; override;
      procedure RegisterAssetClass(AssetClass: TAssetClass);
   public
      constructor Create(Settings: PSettings; AMaterials: TMaterialHashSet);
      destructor Destroy(); override;
      property SpaceClass: TAssetClass read FSpace;
      property PlaceholderShip: TAssetClass read FPlaceholderShip;
      property StarClass[Category: TStarCategory]: TAssetClass read GetStarClass;
      function WrapAssetForOrbit(Child: TAssetNode): TAssetNode;
      function CreateLoneStar(StarID: TStarID): TAssetNode;
      procedure CondenseProtoplanetaryDisks(Space: TSolarSystemFeatureNode; System: TSystem);
      procedure FindTemperatureEquilibria(System: TSystem);
      function Craterize(Diameter: Double; OldAsset, NewAsset: TAssetNode): TAssetNode; override;
      property RegionClass: TAssetClass read FRegion;
      property MessageClass: TAssetClass read FMessage;
      property ProtoplanetaryMaterials: TMaterialHashSet read FProtoplanetaryMaterials;
   end;

const
   // built-in asset classes
   idSpace = -1;
   idOrbits = -2;
   idPlaceholderShip = -3;
   idMessage = -4;
   idCrater = -5;
   idStars = -100; // -100..-199
   idPlanetaryBody = -200;
   idRegion = -201;

const
   // built-in materials
   idDarkMatter = -1;

implementation

uses
   icons, orbit, structure, stellar, name, sensors, exceptions,
   sysutils, planetary, protoplanetary, plot, surface, grid, time,
   population, messages, knowledge, math, food, proxy, rubble,
   floatutils;

function RoundAboveZero(Value: Double): Cardinal;
begin
   Assert(Value < High(Result));
   Assert(Value >= 0.0);
   Result := Round(Value); // $R-
   if (Result = 0) then
      Result := 1;
end;
   
constructor TEncyclopedia.Create(Settings: PSettings; AMaterials: TMaterialHashSet);

   function CreateStarFeatures(): TFeatureClassArray;
   begin
      Result := [ TStarFeatureClass.Create(), TAssetNameFeatureClass.Create() ];
   end;
   
var
   AssetClass: TAssetClass;
   Material: TMaterial;
begin
   inherited Create();
   FMaterials := TMaterialHashMap.Create();
   FProtoplanetaryMaterials := AMaterials;
   for Material in FProtoplanetaryMaterials do
      FMaterials[Material.ID] := Material;
   FAssetClasses := TAssetClassHashTable.Create();
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
      $000000,
      ukBulkResource,
      1e-3, // smallest unit is 1 gram
      1.0, // kg per m^3
      0.0,
      [], // tags
      ZeroAbundance // abundances
   );
   FMaterials.Add(FDarkMatter.ID, FDarkMatter);
   
   FMessage := TAssetClass.Create(
      idMessage,
      'Message', 'Some sort of text',
      'A notification.',
      [
         TMessageFeatureClass.Create()
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
         TSpaceSensorFeatureClass.Create(10 { max steps to orbit }, 10 { steps up from orbit }, 10 { steps down from top}, 0.01 { min size }, [dmVisibleSpectrum, dmClassKnown, dmInternals]),
         TStructureFeatureClass.Create([TMaterialLineItem.Create('Shell', FDarkMatter, 10000 { mass in units (g): 10kg })], 1 { min functional quantity }, 100.0 { default diameter, m }),
         TDynastyOriginalColonyShipFeatureClass.Create(),
         TPopulationFeatureClass.Create(),
         TMessageBoardFeatureClass.Create(FMessage),
         TKnowledgeBusFeatureClass.Create(),
         TFoodBusFeatureClass.Create(),
         TFoodGenerationFeatureClass.Create(100)
      ],
      ColonyShipIcon,
      [beSpaceDock]
   );
   RegisterAssetClass(FPlaceholderShip);

   FPlanetaryBody := TAssetClass.Create(
      idPlanetaryBody,
      'Planetary body',
      'Really big rock',
      'A cold gravitionally-bound astronomical object. (Cold when compared to a star, at least.)',
      [
         TPlanetaryBodyFeatureClass.Create(),
         TSurfaceFeatureClass.Create()
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

   FRegion := TAssetClass.Create(
      idRegion,
      'Geological region',
      'Region',
      'An area of a planetary body.',
      [
         TGenericGridFeatureClass.Create(),
         TKnowledgeBusFeatureClass.Create(),
         TFoodBusFeatureClass.Create()
      ],
      PlanetRegionIcon,
      []
   );
   RegisterAssetClass(FRegion);
end;

destructor TEncyclopedia.Destroy();
var
   AssetClass: TAssetClass;
begin
   FRegion.Free();
   FPlaceholderShip.Free();
   FMessage.Free();
   FDarkMatter.Free();
   FMaterials.Free();
   for AssetClass in FStars do
      AssetClass.Free();
   FCrater.Free();
   FPlanetaryBody.Free();
   FOrbits.Free();
   FSpace.Free();
   FAssetClasses.Free();
   inherited;
end;

function TEncyclopedia.GetAssetClass(ID: Integer): TAssetClass;
begin
   Result := FAssetClasses[ID];
end;

function TEncyclopedia.GetMaterial(ID: TMaterialID): TMaterial;
begin
   Result := FMaterials[ID];
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
begin
   Result := FOrbits.Spawn(nil, [ TOrbitFeatureNode.Create(Child) ]);
end;

function TEncyclopedia.CreateLoneStar(StarID: TStarID): TAssetNode;
var
   Category: TStarCategory;
begin
   Category := CategoryOf(StarID);
   Assert(Assigned(FStars[Category]));
   Result := FStars[Category].Spawn(
      nil,
      [
         TStarFeatureNode.Create(StarID),
         TAssetNameFeatureNode.Create(StarNameOf(StarID))
      ]
   );
end;

procedure TEncyclopedia.CondenseProtoplanetaryDisks(Space: TSolarSystemFeatureNode; System: TSystem);

   function CreateRegions(BodyRadius: Double; BodyComposition: TPlanetaryComposition): TAssetNodeArray;
   begin
      // TODO: this should do things based on the body composition, create geology, etc
      // TODO: only do this on demand
      SetLength(Result, 1); // {BOGUS Warning: Function result variable of a managed type does not seem to be initialized}
      Result[0] := FRegion.Spawn(nil, [
         TGridFeatureNode.Create(bePlanetRegion, 100.0, 5),
         TKnowledgeBusFeatureNode.Create(),
         TFoodBusFeatureNode.Create()
      ]);
   end;


   function CreateBodyNode(const Body: TBody): TAssetNode;
   var
      Index, Count: Cardinal;
      TotalVolume, TotalRelativeVolume: Double;
      BodyComposition: TBodyComposition;
      AssetComposition: TPlanetaryComposition;
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
      SetLength(AssetComposition, Count);
      TotalVolume := Body.Radius * Body.Radius * Body.Radius * Pi * 4.0 / 3.0; // $R-
      Index := 0;
      for BodyComposition in Body.Composition do
      begin
         if (BodyComposition.RelativeVolume > 0) then
         begin
            AssetComposition[Index].Material := BodyComposition.Material;
            Assert(BodyComposition.Material.MassPerUnit > 0);
            AssetComposition[Index].Quantity := (BodyComposition.RelativeVolume / TotalRelativeVolume) * TotalVolume * BodyComposition.Material.Density / BodyComposition.Material.MassPerUnit;
            Assert(AssetComposition[Index].Quantity > 0);
            Inc(Index);
         end;
      end;
      Result := FPlanetaryBody.Spawn(
         nil,
         [
            TPlanetaryBodyFeatureNode.Create(
               Body.Radius * 2.0, // diameter
               Body.Temperature,
               AssetComposition,
               RoundAboveZero(Body.Radius), // hp
               Body.Habitable // whether to consider this body when selecting a crash landing point
            ), // $R-
            TSurfaceFeatureNode.Create(
               Body.Radius * 2.0, // size of surface
               CreateRegions(Body.Radius, AssetComposition)
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
         System,
         OrbitNode,
         Body.Distance,
         Body.Eccentricity,
         System.RandomNumberGenerator.GetDouble(0.0, 2.0 * Pi), // Omega // $R-
         TTimeInMilliseconds(0), // TimeOrigin // TODO: make this a random point in the body's period
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
         Planets := CondenseProtoplanetaryDisk(Star.Mass, Star.Size / 2.0, StarHillDiameter / 2.0, StarFeature.Temperature, FProtoplanetaryMaterials, System);
         for Body in Planets do
            AddBody(Body, StarOrbitFeature);
      end;
   end;
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

function TEncyclopedia.Craterize(Diameter: Double; OldAsset, NewAsset: TAssetNode): TAssetNode;
var
   Composition: TRubbleComposition;
   RubbleCollectionMessage: TRubbleCollectionMessage;
begin
   Assert(Assigned(NewAsset));
   Assert(Diameter >= NewAsset.Size);
   if (Assigned(OldAsset)) then
   begin
      Assert(Diameter >= OldAsset.Size);
      RubbleCollectionMessage := TRubbleCollectionMessage.Create();
      try
         OldAsset.HandleBusMessage(RubbleCollectionMessage);
         Composition := RubbleCollectionMessage.Composition;
      finally
         FreeAndNil(RubbleCollectionMessage);
      end;
   end
   else
      SetLength(Composition, 0);
   Result := FCrater.Spawn(nil, [
      TProxyFeatureNode.Create(NewAsset),
      TRubblePileFeatureNode.Create(Diameter, Composition)
   ]);
end;

end.