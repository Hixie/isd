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
         FPlaceholder: TAssetClass;
         FStars: array[TStarCategory] of TAssetClass;
         FPlanetaryBody: TAssetClass;
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
      property Placeholder: TAssetClass read FPlaceholder;
      property StarClass[Category: TStarCategory]: TAssetClass read GetStarClass;
      function WrapAssetForOrbit(Child: TAssetNode): TAssetNode;
      function CreateLoneStar(StarID: TStarID): TAssetNode;
      procedure CondenseProtoplanetaryDisks(Space: TSolarSystemFeatureNode; RandomSource: TRandomNumberGenerator);
      property ProtoplanetaryMaterials: TMaterialHashSet read FProtoplanetaryMaterials;
   end;

const
   // built-in asset classes
   idSpace = -1;
   idOrbits = -2;
   idPlaceholder = -3;
   idStars = -100; // -100..-199
   idPlanetaryBody = -200;

const
   // built-in materials
   idDarkMatter = -1;

implementation

uses
   icons, orbit, structure, stellar, name, sensors, exceptions, planetary, protoplanetary;

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
      SpaceIcon
   );
   RegisterAssetClass(FSpace);
   
   FOrbits := TAssetClass.Create(idOrbits, 'Orbit', 'Orbit', 'Objects in space are attracted to each other in a way that makes them spin around each other.', [ TOrbitFeatureClass.Create() ], OrbitIcon);
   RegisterAssetClass(FOrbits);

   FStars[2] := TAssetClass.Create(idStars - 2,
                                   'Brown dwarf star', 'Star',
                                   'A late class M star. Class M stars are among the coldest stars in the galaxy at around 3000K. ' +
                                   'This star is at the lower end of the temperature scale for M stars.',
                                   CreateStarFeatures(), Star2Icon);
   FStars[3] := TAssetClass.Create(idStars - 3,
                                   'Red dwarf star', 'Star',
                                   'A class M star. Class M stars are among the coldest stars in the galaxy at around 3000K.',
                                   CreateStarFeatures(), Star3Icon);
   FStars[8] := TAssetClass.Create(idStars - 8,
                                   'K-type main-sequence star', 'Star',
                                   'A class K star. Class K stars are around 4000K.',
                                   CreateStarFeatures(), Star8Icon);
   FStars[4] := TAssetClass.Create(idStars - 4,
                                   'G-type main-sequence star', 'Star',
                                   'A class G star. This whiteish-colored star is around 6000K.',
                                   CreateStarFeatures(), Star4Icon);
   FStars[5] := TAssetClass.Create(idStars - 5,
                                   'F-type main-sequence star', 'Star',
                                   'A class F star. Class F stars are around 7000K.',
                                   CreateStarFeatures(), Star5Icon);
   FStars[9] := TAssetClass.Create(idStars - 9,
                                   'A-type main-sequence star', 'Star',
                                   'A class A star. Class A stars can reach temperatures of up to 10000K.',
                                   CreateStarFeatures(), Star9Icon);
   FStars[6] := TAssetClass.Create(idStars - 6,
                                   'B-type main-sequence star', 'Star',
                                   'A class B star. Class B stars are extremely hot, around 20000K.',
                                   CreateStarFeatures(), Star6Icon);
   FStars[7] := TAssetClass.Create(idStars - 7,
                                   'O-type main-sequence star', 'Star',
                                   'A class O star. Class O stars are the brightest and hottest stars in the galaxy, over 30000K.',
                                   CreateStarFeatures(), Star7Icon);
   FStars[10] := TAssetClass.Create(idStars - 10,
                                   'Red hypergiant star', 'Star',
                                   'A very large, very bright star.',
                                   CreateStarFeatures(), Star10Icon);
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
      [], // tags
      ZeroAbundance // abundances
   );
   FMaterials.Add(FDarkMatter.ID, FDarkMatter);

   FPlanetaryBody := TAssetClass.Create(
      idPlanetaryBody,
      'Planetary body',
      'Really big rock',
      'A cold gravitionally-bound astronomical object. (Cold when compared to a star, at least.)',
      [ TPlanetaryBodyFeatureClass.Create() ],
      PlanetIcon
   );
   RegisterAssetClass(FPlanetaryBody);
   
   FPlaceholder := TAssetClass.Create(
      idPlaceholder,                                   
      'Placeholder', 'Indeterminate item',
      'A McGuffin owned and controlled by a player.',
      [
         TSpaceSensorFeatureClass.Create(10 { max steps to orbit }, 10 { steps up from orbit }, 10 { steps down from top}, 0.01 { min size }, [dmVisibleSpectrum, dmClassKnown, dmInternals]),
         TStructureFeatureClass.Create([TMaterialLineItem.Create('Shell', FDarkMatter, 10000 { mass in units (g): 10kg })], 1 { min functional quantity }, 1.0 { default diameter, m })
      ],
      PlaceholderIcon
   );
   RegisterAssetClass(FPlaceholder);
end;

destructor TEncyclopedia.Destroy();
var
   AssetClass: TAssetClass;
begin
   FPlaceholder.Free();
   FDarkMatter.Free();
   FMaterials.Free();
   for AssetClass in FStars do
      AssetClass.Free();
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

procedure TEncyclopedia.CondenseProtoplanetaryDisks(Space: TSolarSystemFeatureNode; RandomSource: TRandomNumberGenerator);

   function CreateBodyNode(const Body: TBody): TAssetNode;
   var
      Index, Count: Cardinal;
      TotalVolume: Double;
      BodyComposition: TBodyComposition;
      AssetComposition: TPlanetaryComposition;
   begin
      Count := 0;
      for BodyComposition in Body.Composition do
      begin
         if (BodyComposition.RelativeVolume > 0) then
            Inc(Count);
      end;
      Assert(Count > 0);
      SetLength(AssetComposition, Count);
      TotalVolume := (4.0 / 3.0) * Pi * Body.Radius * Body.Radius * Body.Radius; // $R-
      Index := 0;
      for BodyComposition in Body.Composition do
      begin
         if (BodyComposition.RelativeVolume > 0) then
         begin
            AssetComposition[Index].Material := BodyComposition.Material;
            Assert(BodyComposition.Material.MassPerUnit > 0);
            AssetComposition[Index].Mass := BodyComposition.RelativeVolume * TotalVolume * BodyComposition.Material.Density;
            Assert(AssetComposition[Index].Mass > 0);
            Inc(Index);
         end;
      end;
      Result := FPlanetaryBody.Spawn(
         nil,
         [
            TPlanetaryBodyFeatureNode.Create(
               Body.Radius * 2.0, // diameter
               AssetComposition,
               RoundAboveZero(Body.Radius) // hp
            ) // $R-
         ]
      );
   end;

   procedure AddBody(const Body: TBody; Orbit: TOrbitFeatureNode);
   var
      Node, OrbitNode: TAssetNode;
      Satellite: TBody;
   begin
      Node := CreateBodyNode(Body);
      OrbitNode := WrapAssetForOrbit(Node);
      Orbit.AddOrbitingChild(
         OrbitNode,
         Body.Distance,
         Body.Eccentricity,
         RandomSource.GetDouble(0.0, 2.0 * Pi), // Omega // $R-
         0, // TimeOrigin
         Body.Clockwise
      );
      if (Assigned(Body.Moons)) then
      begin
         for Satellite in Body.Moons^ do
            AddBody(Satellite, OrbitNode.GetFeatureByClass(TOrbitFeatureClass) as TOrbitFeatureNode);
      end;
   end;
   
var
   Index: Cardinal;
   StarOrbit, Star: TAssetNode;
   StarHillDiameter: Double;
   Planets: TBodyArray;
   Body: TBody;
   StarOrbitFeature: TOrbitFeatureNode;
begin
   Assert(Space.ChildCount > 0);
   for Index := 0 to Space.ChildCount - 1 do // $R-
   begin
      StarOrbit := Space.Children[Index];
      StarOrbitFeature := StarOrbit.GetFeatureByClass(TOrbitFeatureClass) as TOrbitFeatureNode;
      Star := StarOrbitFeature.PrimaryChild;
      StarHillDiameter := Space.GetHillDiameter(StarOrbit, Star.Mass);
      if (StarHillDiameter > Star.Size) then
      begin
         Planets := CondenseProtoplanetaryDisk(Star.Mass, Star.Size / 2.0, StarHillDiameter / 2.0, FProtoplanetaryMaterials, RandomSource);
         for Body in Planets do
            AddBody(Body, StarOrbitFeature);
      end;
   end;
end;

end.