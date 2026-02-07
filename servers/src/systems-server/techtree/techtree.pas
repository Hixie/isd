{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit techtree;

//{$DEFINE VERBOSE}

interface

uses
   sysutils, internals, time, systems, plasticarrays, genericutils,
   tttokenizer, materials, masses, conditions;

type
   TTechnologyTree = class
   strict private
      FResearches: specialize PlasticArray<TResearch, specialize IncomparableUtils<TResearch>>;
      FTopics: specialize PlasticArray<TTopic, specialize IncomparableUtils<TTopic>>;
      FAssetClasses: TAssetClass.TPlasticArray;
      FMaterials: specialize PlasticArray<TMaterial, TObjectUtils>;
   private
      function AddResearch(AID: TResearchID; ADefaultTime: TMillisecondsDuration; ADefaultWeight: TWeight; ACondition: TConditionAST; ABonuses: TBonus.TArray; AUnlockedKnowledge: TUnlockedKnowledge.TArray): TResearch;
      function AddTopic(Name: UTF8String; Condition: TRootConditionAST): TTopic;
      procedure AddAssetClass(AssetClass: TAssetClass);
      procedure AddMaterial(Material: TMaterial);
      procedure Compile();
   public
      constructor Create();
      destructor Destroy(); override;
      function ExtractResearches(): TResearch.TArray;
      function ExtractTopics(): TTopic.TArray;
      function ExtractAssetClasses(): TAssetClass.TArray;
      function ExtractMaterials(): TMaterial.TArray;
   end;

function LoadTechnologyTree(Filename: RawByteString; Materials: TMaterial.TArray): TTechnologyTree;

implementation

uses
   typedump, exceptions, fileutils, rtlutils, stringutils,
   isdprotocol, ttparser;

// OUTPUT  

constructor TTechnologyTree.Create();
begin
   inherited Create();
end;

destructor TTechnologyTree.Destroy();
var
   Research: TResearch;
   AssetClass: TAssetClass;
   Material: TMaterial;
begin
   for Research in FResearches do
      Research.Free();
   for AssetClass in FAssetClasses do
      AssetClass.Free();
   for Material in FMaterials do
      Material.Free();
   inherited;
end;

function TTechnologyTree.AddResearch(AID: TResearchID; ADefaultTime: TMillisecondsDuration; ADefaultWeight: TWeight; ACondition: TConditionAST; ABonuses: TBonus.TArray; AUnlockedKnowledge: TUnlockedKnowledge.TArray): TResearch;
var
   Index: TResearchIndex;
begin
   Assert(FResearches.Length <= High(TResearchIndex));
   Index := FResearches.Length; // $R-
   Result := TResearch.Create(AID, Index, ADefaultTime, ADefaultWeight, ACondition, ABonuses, AUnlockedKnowledge);
   FResearches.Push(Result);
end;

function TTechnologyTree.AddTopic(Name: UTF8String; Condition: TRootConditionAST): TTopic;
var
   Index: TTopic.TIndex;
begin
   Assert(FTopics.Length < High(TTopic.TIndex));
   Index := FTopics.Length + 1; // $R-
   Result := TTopic.Create(Name, Index, Condition);
   FTopics.Push(Result);
end;

procedure TTechnologyTree.AddAssetClass(AssetClass: TAssetClass);
begin
   FAssetClasses.Push(AssetClass);
end;

procedure TTechnologyTree.AddMaterial(Material: TMaterial);
begin
   FMaterials.Push(Material);
end;

procedure TTechnologyTree.Compile();
var
   Research: TResearch;
   Topic: TTopic;
   UnlockedResearches: array of TResearch.TIndexPlasticArray;
   UnlockedTopics: array of TTopic.TIndexPlasticArray;
   Collection: TResearchHashSet;
   Index, SubIndex: TResearchIndex;
begin
   Writeln('Compiling tech tree... ', FResearches.Length, ' researches, ', FTopics.Length, ' topics');
   SetLength(UnlockedResearches, FResearches.Length);
   SetLength(UnlockedTopics, FResearches.Length);
   if (FResearches.IsNotEmpty) then
      for Index := 0 to FResearches.Length - 1 do // $R-
      begin
         Research := FResearches[Index];
         Research.Condition.Compile(@Collection);
         if (Collection.IsEmpty) then
            Collection.Add(0); // we need something to hook the search to, otherwise we never consider it unlocked
         Assert(Research.Index = Index);
         for SubIndex in Collection do
            UnlockedResearches[SubIndex].Push(Index);
         Collection.Reset();
         if (Length(Research.Bonuses) > 0) then
            for SubIndex := Low(Research.Bonuses) to High(Research.Bonuses) do
               Research.Bonuses[SubIndex].Compile();
      end;
   if (FTopics.IsNotEmpty) then
      for Index := 0 to FTopics.Length - 1 do // $R-
      begin
         Topic := FTopics[Index];
         Assert(Topic.Index = Index + 1);
         Topic.Condition.Compile(@Collection);
         if (Collection.IsEmpty) then
            Collection.Add(0); // as above
         for SubIndex in Collection do
            UnlockedTopics[SubIndex].Push(Topic.Index);
         Collection.Reset();
      end;
   if (FResearches.IsNotEmpty) then
      for Index := 0 to FResearches.Length - 1 do // $R-
      begin
         Research := FResearches[Index];
         Research.UpdateUnlocks(UnlockedResearches[Index].Distill(), UnlockedTopics[Index].Distill());
      end;
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


// PARSER
   
function Parse(Tokens: TTokenizer; Ores: TMaterial.TArray): TTechnologyTree;
var
   ResearchesByID: TResearchHashTable;
   StorybeatResearches, MaterialResearches, AssetClassResearches: TResearchListHashTable;
   SituationsByIdentifier: TSituationHashTable;
   TopicsByName: TTopicHashTable;
   AssetClassesByName: TAssetClassIdentifierHashTable;
   MaterialsByName: TMaterialNameHashTable;
   AssetClassesByID: TAssetClassIDHashTable; // only used to catch duplicate IDs
   MaterialsByID: TMaterialIDHashTable; // only used to catch duplicate IDs

   function GetTechTreeReader(): TTechTreeReader; inline;
   begin
      Result := TTechTreeReader.Create(Tokens, SituationsByIdentifier, AssetClassesByName, MaterialsByName);
   end;

   function ParseCondition(): TRootConditionAST;

      function ParseConditionExpression(): TConditionAST; forward;

      function ParseLeafConditionExpression(const LastWasNegation = False): TConditionAST;
      var
         Identifier: UTF8String;
      begin
         if (Tokens.IsOpenParenthesis()) then
         begin
            Tokens.ReadOpenParenthesis();
            Result := TGroupConditionAST(ParseConditionExpression());
            Tokens.ReadCloseParenthesis();
         end
         else
         begin
            Identifier := Tokens.ReadIdentifier();
            if (Identifier = 'storybeat') then
            begin
               Identifier := Tokens.ReadIdentifier();
               if (not StorybeatResearches.Has(Identifier)) then
                  Tokens.Error('Unknown storybeat "%s" in condition', [Identifier]);
               Result := TResearchListConditionAST.Create(StorybeatResearches.ItemsPtr[Identifier]);
            end
            else
            if (Identifier = 'material') then
            begin
               Identifier := Tokens.ReadString();
               if (not MaterialResearches.Has(Identifier)) then
                  Tokens.Error('Unknown material "%s" in condition', [Identifier]);
               Result := TResearchListConditionAST.Create(MaterialResearches.ItemsPtr[Identifier]);
            end
            else
            if (Identifier = 'asset') then
            begin
               Identifier := Tokens.ReadString();
               if (not AssetClassResearches.Has(Identifier)) then
                  Tokens.Error('Unknown asset class "%s" in condition', [Identifier]);
               Result := TResearchListConditionAST.Create(AssetClassResearches.ItemsPtr[Identifier]);
            end
            else
            if (Identifier = 'situation') then
            begin
               Identifier := ReadSituationName(GetTechTreeReader());
               if (not SituationsByIdentifier.Has(Identifier)) then
                  Tokens.Error('Unknown situation "%s" in condition', [Identifier]);
               Result := TSituationConditionAST.Create(SituationsByIdentifier[Identifier]);
            end
            else
            if (Identifier = 'topic') then
            begin
               Identifier := Tokens.ReadString();
               if (not TopicsByName.Has(Identifier)) then
                  Tokens.Error('Unknown topic "%s" in condition', [Identifier]);
               Result := TTopicConditionAST.Create(TopicsByName[Identifier].Index);
            end
            else
            if (Identifier = 'no') then
            begin
               if (LastWasNegation) then
                  Tokens.Error('The "no" keyword was used twice in a row.', []);
               Result := TNotConditionAST.Create(ParseLeafConditionExpression(True));
            end
            else
               Tokens.Error('Unknown condition directive "%s", expected one of "nothing", "storybeat", "material", "asset", "situation", "topic", "no", or an open parenthesis', [Identifier]);
         end;
      end;

      function ParseConditionExpression(): TConditionAST;
      begin
         Result := ParseLeafConditionExpression();
         if (Tokens.IsIdentifier('or')) then
         begin
            repeat
               Tokens.ReadIdentifier('or');
               Result := TOrConditionAST.Create(Result, ParseLeafConditionExpression());
            until not Tokens.IsIdentifier('or');
         end
         else
         if (Tokens.IsComma()) then
         begin
            Tokens.ReadComma();
            repeat
               Result := TAndConditionAST.Create(Result, ParseLeafConditionExpression());
            until not ReadComma(Tokens);
         end;
      end;

   begin
      if (Tokens.IsIdentifier('nothing')) then
      begin
         Tokens.ReadIdentifier('nothing');
         Result := TRootConditionAST.Create(TNothingConditionAST.Create());
      end
      else
      begin
         Result := TRootConditionAST.Create(ParseConditionExpression());
      end;
   end;
   
   function RegisterSituation(Name: UTF8String): TSituation;
   begin
      Assert(Assigned(SituationsByIdentifier));
      Assert(not SituationsByIdentifier.Has(Name));
      Assert(SituationsByIdentifier.Count < High(TSituation));
      SituationsByIdentifier[Name] := SituationsByIdentifier.Count + 1; // $R-
      Result := SituationsByIdentifier.Count; // $R-
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
      if (Value <= 0) then
         Tokens.Error('Weight must be greater than zero', []);
      Result := Value; // $R-
   end;

   procedure ParseResearch();
   type
      TComponent = (rcID, rcTakes, rcWeight, rcRequires, rcWith, rcStory, rcUnlocks);
      TComponents = set of TComponent;
      
      function ParseBonus(const Components: TComponents; const BaseTime: TMillisecondsDuration; const BaseWeight: TWeight): TBonus;
      var
         Condition: TRootConditionAST;
         TimeFactor: Double;
         WeightDelta: TWeightDelta;
         Keyword: UTF8String;
         Value: Int64;
         Temp: Double;
         SeenSpeed, SeenWeight: Boolean;
      begin
         SeenSpeed := False;
         SeenWeight := False;
         Condition := ParseCondition();
         TimeFactor := 1.0;
         WeightDelta := 0;
         Tokens.ReadColon();
         repeat
            if (SeenSpeed or SeenWeight) then
               Tokens.ReadComma();
            Keyword := Tokens.ReadIdentifier();
            case Keyword of
               'speed':
                  begin
                     if (not (rcTakes in Components)) then
                        Tokens.Error('Cannot provide speed bonus when no default time is provided; unexpected "speed" bonus', []);
                     if (SeenSpeed) then
                        Tokens.Error('Duplicate "speed" bonus', []);
                     SeenSpeed := True;
                     TimeFactor := Tokens.ReadMultiplier();
                     if (TimeFactor <= 0.0) then
                        Tokens.Error('Invalid time factor, must be greater than zero', []);
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
                        WeightDelta := Low(WeightDelta);
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
         Assert(TimeFactor > 0.0);
         Result := TBonus.Create(Condition, Single(TimeFactor), WeightDelta);
      end;

      function ParseUnlock(): TUnlockedKnowledge;
      var
         Keyword: UTF8String;
         AssetClass: TAssetClass;
         Material: TMaterial;
      begin
         Keyword := Tokens.ReadIdentifier();
         case Keyword of
            'asset':
               begin
                  AssetClass := ReadAssetClass(GetTechTreeReader());
                  Result := TUnlockedKnowledge.CreateForAssetClass(AssetClass);
               end;
            'material':
               begin
                  Material := ReadMaterial(GetTechTreeReader());
                  Result := TUnlockedKnowledge.CreateForMaterial(Material);
               end;
         else
            Tokens.Error('Expected "asset" or "material" after "unlock", but got "%s"', [Keyword]);
         end;
      end;

   var
      Components: TComponents;
      
      procedure MarkSeen(Component: TComponent; Keyword: UTF8String);
      begin
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
      Package, Root: Boolean;
      ID: TResearchID;
      Keyword, Identifier, Message: UTF8String;
      Research: TResearch;
      DefaultTime: TMillisecondsDuration;
      DefaultWeight: TWeight;
      Bonuses: TBonusPlasticArray;
      Unlock: TUnlockedKnowledge;
      Unlocks: TUnlockedKnowledge.TPlasticArray;
      ResearchStorybeats: specialize PlasticArray<UTF8String, UTF8StringUtils>;
      Condition: TRootConditionAST;
      Collection: TResearchHashSet;
   begin
      if (Tokens.IsIdentifier()) then
      begin
         Keyword := Tokens.ReadIdentifier();
         Package := Keyword = 'package';
         Root := Keyword = 'root';
         if (Root) then
         begin
            ID := 0;
         end
         else      
         if (not Package) then
            Tokens.Error('Unrecognized research type "%s"', [Keyword]);
      end
      else
      begin
         Package := False;
         Root := False;
      end;
      Tokens.ReadOpenBrace();
      Components := [];
      DefaultTime := TMillisecondsDuration.FromMilliseconds(0);
      DefaultWeight := 1;
      Condition := nil;
      while (not Tokens.IsCloseBrace()) do
      begin
         Keyword := Tokens.ReadIdentifier();
         case Keyword of
            'id':
               begin
                  if (Root) then
                     Tokens.Error('Root package ID is always zero and must not be given explicitly', []);
                  MarkSeen(rcID, Keyword);
                  Tokens.ReadColon();
                  Assert(Low(TResearchID) <= 0);
                  ID := ReadNumber(Tokens, Low(TResearchID), High(TResearchID)); // $R-
                  if (ID = 0) then
                     Tokens.Error('Package ID zero is reserved for the root research', []);
                  Tokens.ReadSemicolon();
               end;
            'takes':
               begin
                  if (Root or Package) then
                     Tokens.Error('Research block cannot be directly researched and therefore should not have "takes" directives', []);
                  MarkSeen(rcTakes, Keyword);
                  if (rcWith in Components) then
                     Tokens.Error('The "takes" and "weight" directives must come before any "with" directives', []);
                  DefaultTime := ParseTime();
                  Tokens.ReadSemicolon();
               end;
            'weight':
               begin
                  if (Root or Package) then
                     Tokens.Error('Research block cannot be directly researched and therefore should not have "weight" directives', []);
                  MarkSeen(rcWeight, Keyword);
                  if (rcWith in Components) then
                     Tokens.Error('The "takes" and "weight" directives must come before any "with" directives', []);
                  DefaultWeight := ParseWeight();
                  if (DefaultWeight = 1.0) then
                     Tokens.Error('Weight with value 1.0 is redundant and should be omitted', []);
                  Tokens.ReadSemicolon();
               end;
            'requires':
               begin
                  if (Root or Package) then
                     Tokens.Error('Research block cannot be directly researched and therefore should not have "requires" directives', []);
                  MarkSeen(rcRequires, Keyword);
                  Condition := ParseCondition();
                  Tokens.ReadSemicolon();
               end;
            'with':
               begin
                  if (Root or Package) then
                     Tokens.Error('Research block cannot be directly researched and therefore should not have "with" directives', []);
                  Include(Components, rcWith);
                  Bonuses.Push(ParseBonus(Components, DefaultTime, DefaultWeight));
                  Tokens.ReadSemicolon();
               end;
            'story': 
               begin
                  MarkSeen(rcStory, Keyword);
                  Tokens.ReadColon();
                  while (Tokens.IsIdentifier()) do
                  begin
                     Identifier := Tokens.ReadIdentifier();
                     if (not StorybeatResearches.Has(Identifier)) then
                        Tokens.Error('Unknown storybeat "%s" in research', [Identifier]);
                     if (ResearchStorybeats.Contains(Identifier)) then // O(N) but N should be very short
                        Tokens.Error('Duplicate storybeat "%s" in research', [Identifier]);
                     ResearchStorybeats.Push(Identifier);
                     if (not Tokens.IsString()) then
                        Tokens.ReadComma();
                  end;
                  Message := Tokens.ReadString();
                  Unlocks.Push(TUnlockedKnowledge.CreateForMessage(Message));
                  Tokens.ReadSemicolon();
               end;
            'unlocks':
               begin
                  Include(Components, rcUnlocks);
                  Unlocks.Push(ParseUnlock());
                  Tokens.ReadSemicolon();
               end;
         else
            Tokens.Error('Unknown keyword "%s" in research', [Keyword]);
         end;
      end;
      Tokens.ReadCloseBrace();
      if (Root) then
      begin
         Assert(not Assigned(Condition));
         Condition := TRootConditionAST.Create(TNothingConditionAST.Create());
      end
      else
      begin
         if (not (rcID in Components)) then
            Tokens.Error('Missing "id" directive in research block', []);
         if (Package) then
         begin
            Assert(not Assigned(Condition));
            Condition := TRootConditionAST.Create(TPackageConditionAST.Create());
         end
         else
         begin
            if (not Assigned(Condition)) then
               Tokens.Error('Missing "requires" directive in research block', []);
            Condition.CollectResearches(Collection); {BOGUS Warning: Local variable "Collection" of a managed type does not seem to be initialized}
            if (Unlocks.IsEmpty) then
               Tokens.Error('Expected either a "story" directive or an "unlocks" directive (or both) in research block', []);
         end;
      end;
      Research := Result.AddResearch(ID, DefaultTime, DefaultWeight, Condition, Bonuses.Distill(), Unlocks.Distill());
      {$IFDEF VERBOSE}
      Writeln('Parsed research ', ID, ' (', Research.DebugDescription(), ') has default duration ', DefaultTime.ToString());
      {$ENDIF}
      ResearchesByID[Research.ID] := Research;
      for Identifier in ResearchStorybeats do
         StorybeatResearches.ItemsPtr[Identifier]^.Push(Research.Index);
      for Unlock in Research.UnlockedKnowledge do
      begin
         case Unlock.Kind of
            ukAssetClass:
               begin
                  AssetClassResearches.ItemsPtr[Unlock.AssetClass.Name]^.Push(Research.Index);
               end;
            ukMaterial:
               begin
                  MaterialResearches.ItemsPtr[Unlock.Material.Name]^.Push(Research.Index);
               end;
            ukMessage: ;
         end;
      end;
   end;

   procedure ParseStorybeat();
   var
      Identifier: UTF8String;
   begin
      Identifier := Tokens.ReadIdentifier();
      if (StorybeatResearches.Has(Identifier)) then
         Tokens.Error('Duplicate storybeat "%s"', [Identifier]);
      Tokens.ReadSemicolon();
      StorybeatResearches.AddDefault(Identifier);
   end;

   procedure ParseFacility();
   var
      Name: UTF8String;
   begin
      // We don't support _declaring_ our magic @sample etc facilities
      Name := Tokens.ReadIdentifier();
      if (SituationsByIdentifier.Has(Name)) then
         Tokens.Error('Duplicate facility (situation) "%s"', [Name]);
      Tokens.ReadSemicolon();
      RegisterSituation(Name);
   end;

   procedure ParseTopic();
   var
      Name: UTF8String;
      Condition: TRootConditionAST;
   begin
      Name := Tokens.ReadString();
      if (TopicsByName.Has(Name)) then
         Tokens.Error('Duplicate topic "%s"', [Name]);
      if (not Tokens.IsSemicolon()) then
      begin
         Tokens.ReadIdentifier('requires');
         Condition := ParseCondition();
      end;
      Tokens.ReadSemicolon();
      TopicsByName[Name] := Result.AddTopic(Name, Condition);
   end;

   procedure ParseAssetClass();
   type
      TClassComponent = (ccID, ccVaguely, ccDescription, ccIcon, ccBuild, ccFeature);
      TClassComponents = set of TClassComponent;
   var
      Keyword: UTF8String;
      Components: TClassComponents;

      procedure MarkSeen(Component: TClassComponent);
      begin
         if (Component in Components) then
            Tokens.Error('Duplicate directive "%s" in asset class block', [Keyword]);
         Include(Components, Component);
      end;

   var
      ID: TAssetClassID;
      Name, AmbiguousName, Description, Icon: UTF8String;
      ReadEnvironment: TBuildEnvironment;
      BuildEnvironments: TBuildEnvironments;
      Features: TFeatureClass.TArray;
      Feature: TFeatureClass;
      AssetClass: TAssetClass;
      Situation: TSituation;
      First: Boolean;
   begin
      Components := [];
      BuildEnvironments := [];
      Assert(Length(Features) = 0); {BOGUS Warning: Local variable "Features" of a managed type does not seem to be initialized}
      try
         Name := Tokens.ReadString();
         if (AssetClassesByName.Has(Name)) then
            Tokens.Error('Asset class name "%s" already used by another asset class (with ID %d)', [Name, AssetClassesByName[Name].ID]);
         if (MaterialsByName.Has(Name)) then
            Tokens.Error('Asset class name "%s" already used by a material (with ID %d)', [Name, MaterialsByName[Name].ID]);
         Tokens.ReadOpenBrace();
         repeat
            Keyword := Tokens.ReadIdentifier();
            Tokens.ReadColon();
            case Keyword of
               'id':
                  begin
                     MarkSeen(ccID);
                     ID := ReadNumber(Tokens, Low(TAssetClassID), High(TAssetClassID)); // $R-
                     if (AssetClassesByID.Has(ID)) then
                        Tokens.Error('Asset class ID %d is already used by "%s"', [ID, AssetClassesByID[ID].Name]);
                  end;
               'vaguely':
                  begin
                     MarkSeen(ccVaguely);
                     AmbiguousName := Tokens.ReadString;
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
                     Features[High(Features)] := ReadFeatureClass(GetTechTreeReader());
                  end;
            else
               Tokens.Error('Unknown keyword "%s" in asset class block', [Keyword]);
            end;
            Tokens.ReadSemicolon();
         until Tokens.IsCloseBrace();
         if (not (ccID in Components)) then
            Tokens.Error('Missing "id" directive in asset class block', []);
         if (not (ccVaguely in Components)) then
            Tokens.Error('Missing "vague" directive in asset class block', []);
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
      Situation := RegisterSituation('@sample ' + Name);
      AssetClass := TAssetClass.Create(ID, Name, AmbiguousName, Description, Features, Icon, BuildEnvironments, Situation);
      Result.AddAssetClass(AssetClass);
      AssetClassesByName[AssetClass.Name] := AssetClass;
      AssetClassesByID[AssetClass.ID] := AssetClass;
      AssetClassResearches.AddDefault(AssetClass.Name);
   end;

   procedure ParseMaterial();
   type
      TComponent = (mcID, mcVaguely, mcDescription, mcIcon, mcMetrics);
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
      Mass: TMass;
      Length, Volume, Density: Double;
      MassPerUnit: TMassPerUnit;
      Tag: UTF8String;
      Tags: TMaterialTags;
      Situation: TSituation;
   begin
      Components := [];
      Name := Tokens.ReadString();
      if (MaterialsByName.Has(Name)) then
         Tokens.Error('Material name "%s" already used by another material (with ID %d)', [Name, MaterialsByName[Name].ID]);
      if (AssetClassesByName.Has(Name)) then
         Tokens.Error('Material name "%s" already used by an asset class (with ID %d)', [Name, AssetClassesByName[Name].ID]);
      Tokens.ReadOpenBrace();
      repeat
         Keyword := Tokens.ReadIdentifier();
         Tokens.ReadColon();
         case Keyword of
            'id':
               begin
                  MarkSeen(mcID);
                  ID := ReadNumber(Tokens, Low(TMaterialID), High(TMaterialID)); // $R-
                  if (ID = 0) then
                     Tokens.Error('Material ID zero is reserved to represent the lack of material or material knowledge', []);
                  if (MaterialsByID.Has(ID)) then
                     Tokens.Error('Material ID %d is already used by "%s"', [ID, MaterialsByID[ID].Name]);
                  if ((ID >= Low(TOres)) and (ID <= High(TOres))) then
                     Tokens.Error('Material ID %d is a reserved ore ID', []);
               end;
            'vaguely':
               begin
                  MarkSeen(mcVaguely);
                  AmbiguousName := Tokens.ReadString();
               end;
            'description':
               begin
                  MarkSeen(mcDescription);
                  Description := Tokens.ReadString();
               end;
            'icon':
               begin
                  MarkSeen(mcIcon);
                  Icon := Tokens.ReadString(High(TIcon));
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
                  Mass := ReadMass(Tokens);
                  MassPerUnit := Mass / TQuantity64.One;
                  Volume := Length * Length * Length;
                  Density := Mass.ToSIUnits() / Volume;
               end;
         else
            Tokens.Error('Unknown directive "%s" in material block', [Keyword]);
         end;
         Tokens.ReadSemicolon();
      until Tokens.IsCloseBrace();
      Tokens.ReadCloseBrace();
      if (Components <> [Low(Components) .. High(Components)]) then
         Tokens.Error('Missing directive in material block, material blocks must have id, name, description, icon, and metrics directives', []);
      Situation := RegisterSituation('@sample ' + Name);
      Material := TMaterial.Create(ID, Name, AmbiguousName, Description, Icon, UnitKind, MassPerUnit, Density, 0.5 { Bond Albedo }, Tags, [], Situation);
      Result.AddMaterial(Material);
      MaterialsByName[Material.Name] := Material;
      MaterialsByID[Material.ID] := Material;
      MaterialResearches.AddDefault(Material.Name);
   end;

// function Parse(Tokens: TTokenizer; Ores: TMaterial.TArray): TTechnologyTree;
var
   Keyword: UTF8String;
   Material: TMaterial;
begin
   try
      Result := TTechnologyTree.Create();
      ResearchesByID := TResearchHashTable.Create();
      StorybeatResearches := TResearchListHashTable.Create();
      MaterialResearches := TResearchListHashTable.Create();
      AssetClassResearches := TResearchListHashTable.Create();
      SituationsByIdentifier := ExtractSituationRegistry();
      TopicsByName := TTopicHashTable.Create();
      AssetClassesByName := TAssetClassIdentifierHashTable.Create();
      AssetClassesByID := TAssetClassIDHashTable.Create();
      MaterialsByName := TMaterialNameHashTable.Create(Length(Ores)); // $R-
      MaterialsByID := TMaterialIDHashTable.Create(Length(Ores)); // $R-
      for Material in Ores do
      begin
         MaterialsByName[Material.Name] := Material;
         MaterialsByID[Material.ID] := Material;
         MaterialResearches.AddDefault(Material.Name);
      end;
      try
         while (not Tokens.IsEOF()) do
         begin
            Keyword := Tokens.ReadIdentifier();
            case Keyword of
               'research': ParseResearch();
               'storybeat': ParseStorybeat();
               'facility': ParseFacility();
               'topic': ParseTopic();
               'asset': ParseAssetClass();
               'material': ParseMaterial();
            else
               Tokens.Error('Unknown keyword "%s" at top level', [Keyword]);
            end;
         end;
      except
         FreeAndNil(Result);
         raise;
      end;
      Result.Compile();
   finally
      FreeAndNil(ResearchesByID);
      FreeAndNil(StorybeatResearches);
      FreeAndNil(MaterialResearches);
      FreeAndNil(AssetClassResearches);
      FreeAndNil(SituationsByIdentifier);
      FreeAndNil(TopicsByName);
      FreeAndNil(AssetClassesByName);
      FreeAndNil(AssetClassesByID);
      FreeAndNil(MaterialsByName);
      FreeAndNil(MaterialsByID);
   end;
end;


function LoadTechnologyTree(Filename: RawByteString; Materials: TMaterial.TArray): TTechnologyTree;
var
   Data: TFileData;
   Tokens: TTokenizer;
begin
   Writeln('Loading technology tree from ', Filename);
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

end.