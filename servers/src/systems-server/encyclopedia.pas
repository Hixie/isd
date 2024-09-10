{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit encyclopedia;

interface

uses
   systems, configuration, astronomy;

type
   TEncyclopedia = class(TAssetClassDatabase)
   private
      var
         FAssetClasses: TAssetClassHashTable; 
         FSpace, FOrbits, FPlaceholder: TAssetClass;
         FStars: array[TStarCategory] of TAssetClass;
         FDarkMatter: TMaterial;
      function GetStarClass(Category: TStarCategory): TAssetClass;
   protected
      function GetAssetClass(ID: Integer): TAssetClass; override;
      procedure RegisterAssetClass(AssetClass: TAssetClass);
   public
      constructor Create(Settings: PSettings);
      destructor Destroy(); override;
      property SpaceClass: TAssetClass read FSpace;
      property Placeholder: TAssetClass read FPlaceholder;
      property StarClass[Category: TStarCategory]: TAssetClass read GetStarClass;
      function CreateLoneStar(StarID: TStarID): TAssetNode;
      function CreateStarSystem(StarID: TStarID): TAssetNode;
      function WrapAssetForOrbit(Child: TAssetNode): TAssetNode;
   end;

const
   // built-in asset classes
   idSpace = -1;
   idOrbits = -2;
   idPlaceholder = -3;
   idStars = -100;
   // built-in materials
   idDarkMatter = -1;

implementation

uses
   icons, space, orbit, structure, stellar, name, sensors, exceptions;

constructor TEncyclopedia.Create(Settings: PSettings);

   function CreateStarFeatures(Category: TStarCategory): TFeatureClassArray;
   begin
      Result := [ TStarFeatureClass.Create(),
                  TAssetNameFeatureClass.Create() ];
   end;

var
   AssetClass: TAssetClass;
begin
   inherited Create();
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
                                   CreateStarFeatures(2), Star2Icon);
   FStars[3] := TAssetClass.Create(idStars - 3,
                                   'Red dwarf star', 'Star',
                                   'A class M star. Class M stars are among the coldest stars in the galaxy at around 3000K.',
                                   CreateStarFeatures(3), Star3Icon);
   FStars[8] := TAssetClass.Create(idStars - 8,
                                   'K-type main-sequence star', 'Star',
                                   'A class K star. Class K stars are around 4000K.',
                                   CreateStarFeatures(8), Star8Icon);
   FStars[4] := TAssetClass.Create(idStars - 4,
                                   'G-type main-sequence star', 'Star',
                                   'A class G star. This whiteish-colored star is around 6000K.',
                                   CreateStarFeatures(4), Star4Icon);
   FStars[5] := TAssetClass.Create(idStars - 5,
                                   'F-type main-sequence star', 'Star',
                                   'A class F star. Class F stars are around 7000K.',
                                   CreateStarFeatures(5), Star5Icon);
   FStars[9] := TAssetClass.Create(idStars - 9,
                                   'A-type main-sequence star', 'Star',
                                   'A class A star. Class A stars can reach temperatures of up to 10000K.',
                                   CreateStarFeatures(9), Star9Icon);
   FStars[6] := TAssetClass.Create(idStars - 6,
                                   'B-type main-sequence star', 'Star',
                                   'A class B star. Class B stars are extremely hot, around 20000K.',
                                   CreateStarFeatures(6), Star6Icon);
   FStars[7] := TAssetClass.Create(idStars - 7,
                                   'O-type main-sequence star', 'Star',
                                   'A class O star. Class O stars are the brightest and hottest stars in the galaxy, over 30000K.',
                                   CreateStarFeatures(7), Star7Icon);
   FStars[10] := TAssetClass.Create(idStars - 10,
                                   'Red hypergiant star', 'Star',
                                   'A very large, very bright star.',
                                   CreateStarFeatures(10), Star10Icon);
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
      1.0 // kg per m^3
   );
   
   FPlaceholder := TAssetClass.Create(
      idPlaceholder,                                   
      'Placeholder', 'Indeterminate item',
      'A McGuffin owned and controlled by a player.',
      [
         TSpaceSensorFeatureClass.Create(1, 1, 1, 4e6, [dmVisibleSpectrum]),
         TStructureFeatureClass.Create([TMaterialLineItem.Create('Shell', FDarkMatter, 10000000)], 0, 200e6)
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
   for AssetClass in FStars do
      AssetClass.Free();
   FOrbits.Free();
   FSpace.Free();
   FAssetClasses.Free();
   inherited;
end;

function TEncyclopedia.GetAssetClass(ID: Integer): TAssetClass;
begin
   Result := FAssetClasses[ID];
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

function TEncyclopedia.CreateStarSystem(StarID: TStarID): TAssetNode;
begin
   Result := WrapAssetForOrbit(CreateLoneStar(StarID));
   // TODO: planets
end;

function TEncyclopedia.WrapAssetForOrbit(Child: TAssetNode): TAssetNode;
begin
   Result := FOrbits.Spawn(nil, [ TOrbitFeatureNode.Create(Child) ]);
end;

end.