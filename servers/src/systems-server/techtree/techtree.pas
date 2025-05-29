{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit techtree;

//{$DEFINE VERBOSE}

interface

uses
   sysutils, time, systems, plasticarrays, genericutils, tttokenizer, materials;

type   
   TTechnologyTree = class
   strict private
      FResearches: specialize PlasticArray<TResearch, TObjectUtils>;
      FTopics: specialize PlasticArray<TTopic, TObjectUtils>;
      FAssetClasses: specialize PlasticArray<TAssetClass, TObjectUtils>;
      FMaterials: specialize PlasticArray<TMaterial, TObjectUtils>;
   private
      procedure AddResearch(Research: TResearch);
      procedure AddTopic(Topic: TTopic);
      procedure AddAssetClass(AssetClass: TAssetClass);
      procedure AddMaterial(Material: TMaterial);
   public
      constructor Create();
      destructor Destroy(); override;
      function GetRootResearch(): TResearch;
      function ExtractResearches(): TResearch.TArray;
      function ExtractTopics(): TTopic.TArray;
      function ExtractAssetClasses(): TAssetClass.TArray;
      function ExtractMaterials(): TMaterial.TArray;
   end;

function LoadTechnologyTree(Filename: RawByteString; Materials: TMaterialHashSet): TTechnologyTree;
procedure RegisterFeatureClass(FeatureClass: FeatureClassReference);   

function ReadBuildEnvironment(Tokens: TTokenizer): TBuildEnvironment;
function ReadAssetClass(Reader: TTechTreeReader): TAssetClass;
function ReadMaterial(Reader: TTechTreeReader): TMaterial;
function ReadTopic(Reader: TTechTreeReader): TTopic;
function ReadNumber(Tokens: TTokenizer; Min, Max: Int64): Int64;
function ReadLength(Tokens: TTokenizer): Double;
function ReadMass(Tokens: TTokenizer): Double;
function ReadMassPerTime(Tokens: TTokenizer): TRate;

implementation

uses
   {$IFDEF VERBOSE} unicode, {$ENDIF}
   typedump, exceptions, fileutils, rtlutils, stringutils, hashtable, hashfunctions, icons;

constructor TTechnologyTree.Create();
begin
   inherited;
end;

destructor TTechnologyTree.Destroy();
var
   Research: TResearch;
   Topic: TTopic;
   AssetClass: TAssetClass;
   Material: TMaterial;
begin
   for Research in FResearches do
      Research.Free();
   for Topic in FTopics do
      Topic.Free();
   for AssetClass in FAssetClasses do
      AssetClass.Free();
   for Material in FMaterials do
      Material.Free();
   inherited;
end;

procedure TTechnologyTree.AddResearch(Research: TResearch);
begin
   FResearches.Push(Research);
end;

procedure TTechnologyTree.AddTopic(Topic: TTopic);
begin
   FTopics.Push(Topic);
end;

procedure TTechnologyTree.AddAssetClass(AssetClass: TAssetClass);
begin
   FAssetClasses.Push(AssetClass);
end;

procedure TTechnologyTree.AddMaterial(Material: TMaterial);
begin
   FMaterials.Push(Material);
end;

function TTechnologyTree.GetRootResearch(): TResearch;
begin
   Assert(FResearches.Length > 0);
   Result := FResearches[0];
end;

function TTechnologyTree.ExtractResearches(): TResearch.TArray;
begin
   Result := FResearches.Distill();
end;

function TTechnologyTree.ExtractTopics(): TTopic.TArray;
begin
   Result := FTopics.Distill();
end;

function TTechnologyTree.ExtractAssetClasses(): TAssetClass.TArray;
begin
   Result := FAssetClasses.Distill();
end;

function TTechnologyTree.ExtractMaterials(): TMaterial.TArray;
begin
   Result := FMaterials.Distill();
end;


type
   TSegment = record
      Start: Pointer;
      Size: QWord;
      class function From(AString: UTF8String): TSegment; inline; overload; static;
      class function From(AStart, AEnd: Pointer): TSegment; inline; overload; static;
   end;   


class function TSegment.From(AString: UTF8String): TSegment;
begin
   {$IFOPT C+} AssertStringIsConstant(AString); {$ENDIF}
   Assert(AString <> '');
   Result.Start := @AString[1];
   Result.Size := Length(AString); // $R-
end;
   
class function TSegment.From(AStart, AEnd: Pointer): TSegment;
begin
   Assert(AEnd > AStart);
   Result.Start := AStart;
   Result.Size := AEnd - AStart; // $R-
end;


type
   TFeatureClassHashTable = class(specialize THashTable<UTF8String, FeatureClassReference, UTF8StringUtils>)
      constructor Create();
   end;

   constructor TFeatureClassHashTable.Create();
   begin
      inherited Create(@UTF8StringHash32);
   end;

type
   TResearchHashTable = class(specialize THashTable<UTF8String, TResearch, UTF8StringUtils>)
      constructor Create();
   end;

   constructor TResearchHashTable.Create();
   begin
      inherited Create(@UTF8StringHash32);
   end;

var
   FeatureClasses: TFeatureClassHashTable; 
  
function Parse(Tokens: TTokenizer; Materials: TMaterialHashSet): TTechnologyTree;
var
   Researches: TResearchHashTable;
   Topics: TTopicHashTable;
   AssetClasses: TAssetClassIdentifierHashTable;
   MaterialNames: TMaterialNameHashTable;
   MaterialIDs: TMaterialIDHashTable;
   NewMaterials: specialize PlasticArray<TMaterial, specialize IncomparableUtils<TMaterial>>;

   function GetTechTreeReader(): TTechTreeReader; inline;
   begin
      Result := TTechTreeReader.Create(Tokens, AssetClasses, MaterialNames, Topics);
   end;
   
   function ParseTime(): TMillisecondsDuration;
   var
      Number: Int64;
      Units: UTF8String;
   begin
      Number := Tokens.ReadNumber();
      Units := Tokens.ReadIdentifier();
      case Units of
         'second', 'seconds': Result := TMillisecondsDuration(Number * 1000);
         'minute', 'minutes': Result := TMillisecondsDuration(Number * 60 * 1000);
         'hour', 'hours': Result := TMillisecondsDuration(Number * 60 * 60 * 1000);
         'day', 'days': Result := TMillisecondsDuration(Number * 24 * 60 * 60 * 1000);
         'week', 'weeks': Result := TMillisecondsDuration(Number * 7 * 24 * 60 * 60 * 1000);
         'month', 'months': Result := TMillisecondsDuration(Number * 30 * 24 * 60 * 60 * 1000);
         'year', 'years': Result := TMillisecondsDuration(Number * 365 * 24 * 60 * 60 * 1000);
         'decade', 'decades': Result := TMillisecondsDuration(Number * 10 * 365 * 24 * 60 * 60 * 1000);
         'century', 'centuries': Result := TMillisecondsDuration(Number * 100 * 365 * 24 * 60 * 60 * 1000);
         else
            Tokens.Error('Unknown time unit "%s"', [Units]);
      end;
   end;

   function ParseWeight(): TWeight;
   var
      Value: Int64;
   begin
      Value := Tokens.ReadNumber();
      if (Value < 0) then
         Tokens.Error('Unexpected negative weight', []);
      Result := Value; // $R-
   end;

   function ParseResearchReference(): TResearch;
   var
      Value: UTF8String;
   begin
      Value := Tokens.ReadIdentifier();
      Result := Researches[Value];
      if (not Assigned(Result)) then
      begin
         Tokens.Error('Unknown research "%s" for node reference', [Value]);
      end;
   end;
   
   function ParseNodeReference(): TNode;
   begin
      if (Tokens.IsIdentifier()) then
      begin
         Result := ParseResearchReference();
      end
      else
      if (Tokens.IsString()) then
      begin
         Result := ReadTopic(GetTechTreeReader());
      end
      else
         Tokens.Error('Expected identifier or string for node reference', []);
   end;
   
   procedure ParseResearch();
   type
      TComponent = (rcID, rcTakes, rcWeight, rcRequires, rcWith, rcRewards);
      TComponents = set of TComponent;


      procedure ParseBonus(out Bonus: TBonus; const Components: TComponents; const BaseTime: TMillisecondsDuration; const BaseWeight: TWeight; const Negate: Boolean);
      var
         Node: TNode;
         TimeDelta: TMillisecondsDuration;
         WeightDelta: TWeightDelta;
         Keyword: UTF8String;
         Value: Int64;
         Temp: Double;
         SeenTime, SeenWeight: Boolean;
      begin
         SeenTime := False;
         SeenWeight := False;
         Node := ParseNodeReference();
         TimeDelta := TMillisecondsDuration.FromMilliseconds(0);
         WeightDelta := 0;
         Tokens.ReadColon();
         repeat
            if (SeenTime or SeenWeight) then
               Tokens.ReadComma();
            Keyword := Tokens.ReadIdentifier();
            case Keyword of
               'time':
                  begin
                     if (not (rcTakes in Components)) then
                        Tokens.Error('Cannot provide time bonus when no default time is provided; unexpected "time" bonus', []);
                     if (SeenTime) then
                        Tokens.Error('Duplicate "time" bonus', []);
                     SeenTime := True;
                     Value := Tokens.ReadNumber();
                     Tokens.ReadPercentage();
                     TimeDelta := BaseTime.Scale(Value / 100.0);
                  end;
               'weight':
                  begin
                     if (SeenWeight) then
                        Tokens.Error('Duplicate "weight" bonus', []);
                     SeenWeight := True;
                     Value := Tokens.ReadNumber();
                     Tokens.ReadPercentage();
                     Temp := BaseWeight * (Value / 100.0);
                     if (Temp <= Low(WeightDelta)) then
                     begin
                        WeightDelta := 0;
                     end
                     else
                     if (Temp >= High(WeightDelta)) then
                     begin
                        WeightDelta := High(WeightDelta);
                     end
                     else
                     begin
                        WeightDelta := Round(Temp); // $R-
                     end;
                  end;
               else
                  Tokens.Error('Unknown bonus kind "%s"', [Keyword]);
            end;
         until Tokens.IsSemicolon();
         Bonus := TBonus.Create(Node, TimeDelta, WeightDelta, Negate);
      end;

      // returns whether the reward was string or not
      function ParseReward(out Reward: TReward): Boolean;
      var
         Keyword, Value: UTF8String;
         AssetClass: TAssetClass;
         Material: TMaterial;
      begin
         if (Tokens.IsIdentifier()) then
         begin
            Keyword := Tokens.ReadIdentifier();
            case Keyword of
               'asset':
                  begin
                     AssetClass := ReadAssetClass(GetTechTreeReader());
                     Reward := TReward.CreateForAssetClass(AssetClass);
                  end;
               'material':
                  begin
                     Material := ReadMaterial(GetTechTreeReader());
                     Reward := TReward.CreateForMaterial(Material);
                  end;
            else
               Tokens.Error('Expected "asset", "material", or string for reward, but got "%s"', [Keyword]);
            end;
            Result := False;
         end
         else
         if (Tokens.IsString()) then
         begin
            Value := Tokens.ReadString();
            Reward := TReward.CreateForMessage(Value);
            Result := True;
         end
         else
            Tokens.Error('Expected "asset", "material", or string for reward', []);
      end;

   var
      ID: TResearchID;
      Name: UTF8String;
      Keyword: UTF8String;
      Research: TResearch;
      DefaultTime: TMillisecondsDuration;
      DefaultWeight: TWeight;
      Node: TNode;
      Requirements: TNode.TNodeArray; // these get back-propagated as "unlocks" when the TResearch or TTopic constructor is called
      Bonuses: TBonus.TArray;
      Rewards: TReward.TArray;
      Components: TComponents;
      SeenStringReward: Boolean;

      procedure MarkSeen(Component: TComponent);
      begin
         Assert(not (Component in [rcRequires, rcWith, rcRewards]));
         if (Component in Components) then
            Tokens.Error('Duplicate directive "%s" in research', [Keyword]);
         Include(Components, Component);
      end;

      function PluralS(Count: Double; S: UTF8String = 's'): UTF8String;
      begin
         if (Count = 1.0) then
         begin
            Result := '';
         end
         else
         begin
            Result := S;
         end;
      end;

   var
      WasString: Boolean;
   begin
      Name := Tokens.ReadIdentifier();
      if (Researches.Has(Name)) then
         Tokens.Error('Duplicate research name "%s"', [Name]);
      Tokens.ReadOpenBrace();
      Components := [];
      SeenStringReward := False;
      DefaultTime := TMillisecondsDuration.FromMilliseconds(0);
      DefaultWeight := 1;
      SetLength(Requirements, 0);
      SetLength(Bonuses, 0);
      SetLength(Rewards, 0);
      while (not Tokens.IsCloseBrace()) do
      begin
         Keyword := Tokens.ReadIdentifier();
         case Keyword of
            'id':
               begin
                  MarkSeen(rcID);
                  Tokens.ReadColon();
                  ID := ReadNumber(Tokens, Low(TResearchID), High(TResearchID)); // $R-
                  if (ID = 0) then
                  begin
                     if (not Tokens.IsOpenParenthesis()) then
                        Tokens.Error('Expected research with ID 0 to have the parenthetical "(root)" for clarity', []);
                     Tokens.ReadOpenParenthesis();
                     Tokens.ReadIdentifier('root');
                     Tokens.ReadCloseParenthesis();
                  end;
                  Tokens.ReadSemicolon();
               end;
            'takes':
               begin
                  MarkSeen(rcTakes);
                  if (rcWith in Components) then
                     Tokens.Error('The "takes" and "weight" directives must come before any "with" directives', []);
                  DefaultTime := ParseTime();
                  Tokens.ReadSemicolon();
               end;
            'weight':
               begin
                  MarkSeen(rcWeight);
                  if (rcWith in Components) then
                     Tokens.Error('The "takes" and "weight" directives must come before any "with" directives', []);
                  DefaultWeight := ParseWeight();
                  Tokens.ReadSemicolon();
               end;
            'requires':
               begin
                  Include(Components, rcRequires);
                  Node := ParseNodeReference();
                  SetLength(Requirements, Length(Requirements) + 1); // XXX potentially expensive allocation and copy
                  Requirements[High(Requirements)] := Node;
                  Tokens.ReadSemicolon();
               end;
            'with':
               begin
                  Include(Components, rcWith);
                  SetLength(Bonuses, Length(Bonuses) + 1); // XXX potentially expensive allocation and copy
                  ParseBonus(Bonuses[High(Bonuses)], Components, DefaultTime, DefaultWeight, False);
                  Tokens.ReadSemicolon();
               end;
            'without':
               begin
                  Include(Components, rcWith);
                  SetLength(Bonuses, Length(Bonuses) + 1); // XXX potentially expensive allocation and copy
                  ParseBonus(Bonuses[High(Bonuses)], Components, DefaultTime, DefaultWeight, True);
                  Tokens.ReadSemicolon();
               end;
            'rewards':
               begin
                  Include(Components, rcRewards);
                  SetLength(Rewards, Length(Rewards) + 1);
                  WasString := ParseReward(Rewards[High(Rewards)]);
                  if (WasString) then
                  begin
                     if (SeenStringReward) then
                     begin
                        Tokens.Error('Extraneous message reward', []);
                     end;
                     SeenStringReward := True;
                  end;
                  Tokens.ReadSemicolon();
               end;
         else
            Tokens.Error('Unknown keyword "%s" in research', [Keyword]);
         end;
      end;
      Tokens.ReadCloseBrace();
      if (not (rcID in Components)) then
         Tokens.Error('Missing "id" directive in research block', []);
      if (ID = 0) then
      begin
         if (not DefaultTime.IsZero) then
            Tokens.Error('Expected root research to take no time, but time specified was %1.1d second%s', [DefaultTime.ToSIUnits(), PluralS(DefaultTime.ToSIUnits())]);
         if (Length(Requirements) > 0) then
            Tokens.Error('Expected root research to have no requirements (by definition), but found %d requirement%s specified in research block', [Length(Requirements), PluralS(Length(Requirements))]);
         if (Length(Bonuses) > 0) then
            Tokens.Error('Expected root research to have no bonuses ("with" and "without" directives), but found %d bonus%s specified in research block', [Length(Requirements), PluralS(Length(Requirements), 'es')]);
         if (Length(Rewards) > 0) then
            Tokens.Error('Expected root research to have no rewards, but found %d reward%s specified in research block', [Length(Rewards), PluralS(Length(Rewards))]);
      end
      else
      begin
         if (Length(Requirements) = 0) then
            Tokens.Error('Missing requirement in non-root research block', [Length(Requirements), PluralS(Length(Requirements))]);
         if (not SeenStringReward) then
            Tokens.Error('Missing message reward in non-root research block', []);
      end;
      Research := TResearch.Create(ID, DefaultTime, DefaultWeight, Requirements, Bonuses, Rewards);
      Researches[Name] := Research;
      Result.AddResearch(Research);
   end;

   procedure ParseTopic(Selectable: Boolean);
   var
      Name: UTF8String;
      Researches: TResearch.TArray;
      Obsoletes: TTopic.TArray;
      Topic: TTopic;
      Keyword: UTF8String;
   begin
      if (Selectable or Tokens.IsString()) then
      begin
         Name := Tokens.ReadString();
      end
      else
      begin
         Name := '';
      end;
      SetLength(Researches, 0);
      SetLength(Obsoletes, 0);
      while (not Tokens.IsSemicolon()) do
      begin
         Keyword := Tokens.ReadIdentifier();
         case Keyword of
            'requires':
               begin
                  SetLength(Researches, Length(Researches) + 1);
                  Researches[High(Researches)] := ParseResearchReference();
               end;
            'obsoletes':
               begin
                  SetLength(Obsoletes, Length(Obsoletes) + 1);
                  Obsoletes[High(Obsoletes)] := ReadTopic(GetTechTreeReader());
               end;
         else
         end;
         if (not Tokens.IsSemicolon()) then
            Tokens.ReadComma();
      end;
      Tokens.ReadSemicolon();
      if (Selectable and (Length(Researches) = 0)) then
         Tokens.Error('Topic does not specify any requirements and is not marked implicit', []);
      Topic := TTopic.Create(Name, Selectable, Researches, Obsoletes);
      if (Name <> '') then
         Topics[Name] := Topic;
      Result.AddTopic(Topic);
   end;

   procedure ParseClass();
   type
      TClassComponent = (ccID, ccName, ccDescription, ccIcon, ccBuild, ccFeature);
      TClassComponents = set of TClassComponent;
   var
      Keyword: UTF8String;
      Components: TClassComponents;

      procedure MarkSeen(Component: TClassComponent);
      begin
         Assert(not (Component in [ccFeature]));
         if (Component in Components) then
            Tokens.Error('Duplicate directive "%s" in asset class block', [Keyword]);
         Include(Components, Component);
      end;

      procedure ParseFeature(var Feature: TFeatureClass);
      var
         FeatureClassName: UTF8String;
      begin
         FeatureClassName := Tokens.ReadIdentifier();
         if (not FeatureClasses.Has(FeatureClassName)) then
            Tokens.Error('Unknown feature class "%s" in asset class block', [FeatureClassName]);
         Feature := FeatureClasses[FeatureClassName].CreateFromTechnologyTree(GetTechTreeReader());
      end;
      
   var
      ID: TAssetClassID;
      Identifier, Name, VagueName, Description, Icon: UTF8String;
      ReadEnvironment: TBuildEnvironment;
      BuildEnvironments: TBuildEnvironments;
      Features: TFeatureClass.TArray;
      Feature: TFeatureClass;
      AssetClass: TAssetClass;
      First: Boolean;
   begin
      Components := [];
      BuildEnvironments := [];
      Assert(Length(Features) = 0); {BOGUS Warning: Local variable "Features" of a managed type does not seem to be initialized}
      try
         Identifier := Tokens.ReadIdentifier();
         Tokens.ReadOpenBrace();
         repeat
            Keyword := Tokens.ReadIdentifier();
            Tokens.ReadColon();
            case Keyword of
               'id':
                  begin
                     MarkSeen(ccID);
                     ID := ReadNumber(Tokens, 1, High(TAssetClassID)); // $R-
                  end;
               'name':
                  begin
                     MarkSeen(ccName);
                     Name := Tokens.ReadString;
                     Tokens.ReadOpenParenthesis;
                     VagueName := Tokens.ReadString;
                     Tokens.ReadCloseParenthesis;
                  end;
               'description':
                  begin
                     MarkSeen(ccDescription);
                     Description := Tokens.ReadString;
                  end;
               'icon':
                  begin
                     MarkSeen(ccIcon);
                     Icon := Tokens.ReadString;
                  end;
               'build':
                  begin
                     MarkSeen(ccBuild);
                     First := True;
                     repeat
                        if (not First) then
                           Tokens.ReadComma();
                        ReadEnvironment := ReadBuildEnvironment(Tokens);
                        if (ReadEnvironment in BuildEnvironments) then
                           Tokens.Error('Duplicate build environment in asset class block', []);
                        Include(BuildEnvironments, ReadEnvironment);
                        First := False;
                     until Tokens.IsSemicolon();
                  end;
               'feature':
                  begin
                     SetLength(Features, Length(Features) + 1);
                     ParseFeature(Features[High(Features)]);
                  end;
            else
               Tokens.Error('Unknown keyword "%s" in asset class block', [Keyword]);
            end;
            Tokens.ReadSemicolon();
         until Tokens.IsCloseBrace();
         if (not (ccID in Components)) then
            Tokens.Error('Missing "id" directive in asset class block', []);
         if (not (ccName in Components)) then
            Tokens.Error('Missing "name" directive in asset class block', []);
         if (not (ccDescription in Components)) then
            Tokens.Error('Missing "description" directive in asset class block', []);
         if (not (ccIcon in Components)) then
            Tokens.Error('Missing "icon" directive in asset class block', []);
         Tokens.ReadCloseBrace();
      except
         for Feature in Features do
            Feature.Free();
         raise;
      end;
      AssetClass := TAssetClass.Create(ID, Name, VagueName, Description, Features, Icon, BuildEnvironments);
      AssetClasses[Identifier] := AssetClass;
      Result.AddAssetClass(AssetClass);
   end;

   procedure ParseMaterial();
   type
      TComponent = (mcID, mcName, mcDescription, mcIcon, mcMetrics);
   var
      Components: set of TComponent;
      Keyword: UTF8String;

      procedure MarkSeen(Component: TComponent);
      begin
         if (Component in Components) then
            Tokens.Error('Duplicate directive "%s" in material block', [Keyword]);
         Include(Components, Component);
      end;
      
   var
      Material: TMaterial;
      ID: TMaterialID;
      Name, AmbiguousName, Description: UTF8String;
      Icon: TIcon;
      UnitKind: TUnitKind;
      Length, Volume, MassPerUnit, Density: Double;
      Tag: UTF8String;
      Tags: TMaterialTags;
   begin
      Components := [];
      Tokens.ReadOpenBrace();
      repeat
         Keyword := Tokens.ReadIdentifier();
         Tokens.ReadColon();
         case Keyword of
            'id':
               begin
                  MarkSeen(mcID);
                  ID := ReadNumber(Tokens, 65, High(TMaterialID)); // $R-
                  if (MaterialIDs.Has(ID)) then
                     Tokens.Error('Material ID %d is already used by "%s"', [ID, MaterialIDs[ID].Name]);
               end;
            'name':
               begin
                  MarkSeen(mcName);
                  Name := Tokens.ReadString();
                  if (MaterialNames.Has(Name)) then
                     Tokens.Error('Material name "%s" is already used', [Name]);
                  Tokens.ReadOpenParenthesis();
                  AmbiguousName := Tokens.ReadString();
                  Tokens.ReadCloseParenthesis();
               end;
            'description':
               begin
                  MarkSeen(mcDescription);
                  Description := Tokens.ReadString();
               end;
            'icon':
               begin
                  MarkSeen(mcIcon);
                  Icon := Tokens.ReadString();
               end;
            'metrics':
               begin
                  MarkSeen(mcMetrics);
                  // metrics: [pressurized] [bulk|component|fluid] <length> weighs <mass>;
                  Tags := [];
                  if (Tokens.IsIdentifier('pressurized')) then
                  begin
                     Tokens.ReadIdentifier();
                     Include(Tags, mtPressurized);
                  end;
                  Tag := Tokens.ReadIdentifier();
                  case Tag of
                     'bulk':
                        begin
                           Include(Tags, mtSolid);
                           UnitKind := ukBulkResource;
                        end;
                     'fluid':
                        begin
                           Include(Tags, mtFluid);
                           UnitKind := ukBulkResource;
                        end;
                     'component':
                        begin
                           Include(Tags, mtSolid);
                           UnitKind := ukComponent;
                        end;
                  else
                     Tokens.Error('Unknown material category "%s", expected "bulk", "fluid", or "component"', [Tag]);
                  end;
                  Length := ReadLength(Tokens);
                  Tokens.ReadIdentifier('weighs');
                  MassPerUnit := ReadMass(Tokens);
                  Volume := Length * Length * Length;
                  Density := MassPerUnit / Volume;
               end;
         else
            Tokens.Error('Unknown directive "%s" in material block', [Keyword]);
         end;
         Tokens.ReadSemicolon();
      until Tokens.IsCloseBrace();
      Tokens.ReadCloseBrace();
      if (Components <> [Low(Components) .. High(Components)]) then
         Tokens.Error('Missing directive in material block, material blocks must have id, name, description, icon, and metrics directives', []);
      Material := TMaterial.Create(ID, Name, AmbiguousName, Description, Icon, UnitKind, MassPerUnit, Density, 0.5, Tags, []);
      Result.AddMaterial(Material);
      MaterialNames[Material.Name] := Material;
      MaterialIDs[Material.ID] := Material;
   end;
   
var
   Keyword: UTF8String;
   Material: TMaterial;
begin
   try
      Result := TTechnologyTree.Create();
      Researches := TResearchHashTable.Create();
      Topics := TTopicHashTable.Create();
      AssetClasses := TAssetClassIdentifierHashTable.Create();
      MaterialNames := TMaterialNameHashTable.Create(Materials.Count);
      MaterialIDs := TMaterialIDHashTable.Create(Materials.Count);
      for Material in Materials do
      begin
         MaterialNames[Material.Name] := Material;
         MaterialIDs[Material.ID] := Material;
      end;
      NewMaterials.Init(16);
      try
         while (not Tokens.IsEOF()) do
         begin
            Keyword := Tokens.ReadIdentifier();
            case Keyword of
               'research': ParseResearch();
               'implicit':
                  begin
                     Tokens.ReadIdentifier('topic');
                     ParseTopic(False);
                  end;
               'topic': ParseTopic(True);
               'class': ParseClass();
               'material': ParseMaterial();
            else
               Tokens.Error('Unknown keyword "%s" at top level', [Keyword]);
            end;
         end;
      except
         FreeAndNil(Result);
         for Material in NewMaterials do
            Material.Free();
         raise;
      end;
   finally
      FreeAndNil(Researches);
      FreeAndNil(Topics);
      FreeAndNil(AssetClasses);
      FreeAndNil(MaterialNames);
      FreeAndNil(MaterialIDs);
   end;
end;

function LoadTechnologyTree(Filename: RawByteString; Materials: TMaterialHashSet): TTechnologyTree;
var
   Data: TFileData;
   Tokens: TTokenizer;
begin
   Data := ReadFile(Filename);
   try
      Tokens := TTokenizer.Create(Data.Start, Data.Length);
      try
         try
            Result := Parse(Tokens, Materials);
         except
            on E: EParseError do
            begin
               Write(Filename + ':' + IntToStr(E.Line) + ':' + IntToStr(E.Column) + ': ');
               ReportCurrentException();
               Abort();
            end;
         end;
      finally
         FreeAndNil(Tokens);
      end;
   finally
      Data.Destroy();
   end;
end;


procedure RegisterFeatureClass(FeatureClass: FeatureClassReference);
begin
   Assert(not FeatureClasses.Has(FeatureClass.ClassName));
   FeatureClasses[FeatureClass.ClassName] := FeatureClass;
end;

function ReadBuildEnvironment(Tokens: TTokenizer): TBuildEnvironment;
var
   Keyword: UTF8String;
begin
   Keyword := Tokens.ReadIdentifier();
   case Keyword of
      'land': Result := bePlanetRegion;
      'spacedock': Result := beSpaceDock;
   else
      Tokens.Error('Unknown build environment "%s"', [Keyword]);
   end;
end;

function ReadAssetClass(Reader: TTechTreeReader): TAssetClass;
var
   Value: UTF8String;
begin
   Value := Reader.Tokens.ReadIdentifier();
   Result := Reader.AssetClasses[Value];
   if (not Assigned(Result)) then
      Reader.Tokens.Error('Unknown asset class "%s"', [Value]);
end;

function ReadMaterial(Reader: TTechTreeReader): TMaterial;
var
   Value: UTF8String;
begin
   Value := Reader.Tokens.ReadString();
   Result := Reader.Materials[Value];
   if (not Assigned(Result)) then
      Reader.Tokens.Error('Unknown material "%s"', [Value]);
end;

function ReadTopic(Reader: TTechTreeReader): TTopic;
var
   Value: UTF8String;
begin
   Value := Reader.Tokens.ReadString();
   Result := Reader.Topics[Value];
   if (not Assigned(Result)) then
      Reader.Tokens.Error('Unknown topic "%s"', [Value]);
end;

function ReadNumber(Tokens: TTokenizer; Min, Max: Int64): Int64;
begin
   Result := Tokens.ReadNumber();
   if (Result < Min) then
      Tokens.Error('Invalid value %d; must be greater than or equal to %d', [Result, Min]);
   if (Result > Max) then
      Tokens.Error('Invalid value %d; must be less than or equal to %d', [Result, Max]);
end;

function ReadLength(Tokens: TTokenizer): Double;
var
   Value: Int64;
   Keyword: UTF8String;
begin
   Value := Tokens.ReadNumber();
   if (Value <= 0) then
      Tokens.Error('Invalid length "%d"; must be greater than zero', [Value]);
   Keyword := Tokens.ReadIdentifier();
   case Keyword of
      'km': Result := Value * 1000.0;
      'm': Result := Value;
      'cm': Result := Value / 100.0;
      'mm': Result := Value / 1000.0;
   else
      Tokens.Error('Unknown unit for length "%s"', [Keyword]);
   end;
end;

function ReadMass(Tokens: TTokenizer): Double;
var
   Value: Int64;
   Keyword: UTF8String;
begin
   Value := Tokens.ReadNumber();
   if (Value <= 0) then
      Tokens.Error('Invalid mass "%d"; must be greater than zero', [Value]);
   Keyword := Tokens.ReadIdentifier();
   case Keyword of
      'kg': Result := Value;
      'g': Result := Value / 1000.0;
      'mg': Result := Value / 1000000.0;
   else
      Tokens.Error('Unknown unit for length "%s"', [Keyword]);
   end;
end;

function ReadMassPerTime(Tokens: TTokenizer): TRate;
var
   Keyword: UTF8String;
   Value: Double;
begin
   Value := ReadMass(Tokens);
   if (Value < 0.0) then
      Tokens.Error('Invalid throughput "%f"; must be positive', [Value]);
   Tokens.ReadSlash();
   Keyword := Tokens.ReadIdentifier();
   case Keyword of
      'h': Value := Value / (60.0 * 60.0 * 1000.0);
      'min': Value := Value / (60.0 * 1000.0);
      's': Value := Value / 1000.0;
      'ms': ;
   else
      Tokens.Error('Unknown unit for time "%s"', [Keyword]);
   end;
   Result := TRate.FromPerMillisecond(Value);
end;

initialization
   FeatureClasses := TFeatureClassHashTable.Create();
finalization
   FeatureClasses.Free();
end.