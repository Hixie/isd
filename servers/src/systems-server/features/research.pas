{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit research;

interface

// {$DEFINE VERBOSE}

uses
   hashtable, genericutils, basenetwork, systemnetwork, systems, serverstream, systemdynasty, materials, techtree, time;

type
   TResearchTimeHashTable = class(specialize THashTable<TResearch, TMillisecondsDuration, TObjectUtils>)
      constructor Create();
   end;

   TResearchFeatureClass = class(TFeatureClass)
   private
      FFacilities: TTopic.TArray;
   strict protected
      function GetFeatureNodeClass(): FeatureNodeReference; override;
   public
      constructor CreateFromTechnologyTree(Reader: TTechTreeReader); override;
      function InitFeatureNode(): TFeatureNode; override;
   end;

   TResearchFeatureNode = class(TFeatureNode)
   strict private
      FUpdateResearchScheduled: Boolean;
      FFeatureClass: TResearchFeatureClass;
      FSeed: Int64;
      FTopic: TTopic;
      FSpecialties: array of TResearch;
      FBankedResearch: TResearchTimeHashTable;
      FCurrentResearch: TResearch;
      FResearchStartTime: TTimeInMilliseconds;
      FResearchEvent: TSystemEvent;
      procedure BankResearch(CachedSystem: TSystem);
      procedure UpdateResearch(CachedSystem: TSystem);
      procedure TriggerResearch(var Data);
      procedure ScheduleUpdateResearch();
   protected
      constructor CreateFromJournal(Journal: TJournalReader; AFeatureClass: TFeatureClass; ASystem: TSystem); override;
      procedure Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter; CachedSystem: TSystem); override;
      procedure HandleChanges(CachedSystem: TSystem); override;
   public
      constructor Create(AFeatureClass: TResearchFeatureClass);
      destructor Destroy(); override;
      procedure UpdateJournal(Journal: TJournalWriter; CachedSystem: TSystem); override;
      procedure ApplyJournal(Journal: TJournalReader; CachedSystem: TSystem); override;
      function HandleCommand(Command: UTF8String; var Message: TMessage): Boolean; override;
   end;

implementation

uses
   exceptions, sysutils, arrayutils, isdprotocol, isderrors, knowledge, messages;

constructor TResearchTimeHashTable.Create();
begin
   inherited Create(@ResearchHash32);
end;


constructor TResearchFeatureClass.CreateFromTechnologyTree(Reader: TTechTreeReader);
begin
   inherited Create();
   repeat
      if (Reader.Tokens.IsComma()) then
         Reader.Tokens.ReadComma();
      if (Reader.Tokens.IsIdentifier('provides')) then
      begin
         Reader.Tokens.ReadIdentifier('provides');
         SetLength(FFacilities, Length(FFacilities) + 1);
         FFacilities[High(FFacilities)] := ReadTopic(Reader);
         Assert(Length(FFacilities) < 8); // TODO: if we start having a lot of FFacilities, consider using a set instead, or a set/array adaptive hybrid...
      end;
   until not Reader.Tokens.IsComma();
end;

function TResearchFeatureClass.GetFeatureNodeClass(): FeatureNodeReference;
begin
   Result := TResearchFeatureNode;
end;

function TResearchFeatureClass.InitFeatureNode(): TFeatureNode;
begin
   Result := TResearchFeatureNode.Create(Self);
end;


constructor TResearchFeatureNode.Create(AFeatureClass: TResearchFeatureClass);
begin
   inherited Create();
   FFeatureClass := AFeatureClass;
   FSeed := -1;
   FUpdateResearchScheduled := True;
   FBankedResearch := TResearchTimeHashTable.Create();
end;

constructor TResearchFeatureNode.CreateFromJournal(Journal: TJournalReader; AFeatureClass: TFeatureClass; ASystem: TSystem);
begin
   FBankedResearch := TResearchTimeHashTable.Create();
   inherited CreateFromJournal(Journal, AFeatureClass, ASystem);
   Assert(Assigned(AFeatureClass));
   FFeatureClass := AFeatureClass as TResearchFeatureClass;
end;

destructor TResearchFeatureNode.Destroy();
begin
   FBankedResearch.Free();
   if (Assigned(FResearchEvent)) then
      FResearchEvent.Cancel();
   inherited;
end;

procedure TResearchFeatureNode.Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter; CachedSystem: TSystem);
var
   Visibility: TVisibility;
begin
   Visibility := Parent.ReadVisibilityFor(DynastyIndex, CachedSystem);
   if ((dmDetectable * Visibility <> []) and (dmClassKnown in Visibility)) then
   begin
      Writer.WriteCardinal(fcResearch);
      if (Assigned(FTopic) and (dmInternals in Visibility)) then
      begin
         Writer.WriteStringReference(FTopic.Value);
      end
      else
      begin
         Writer.WriteStringReference('');
      end;
   end;
end;

procedure TResearchFeatureNode.ScheduleUpdateResearch();
begin
   FUpdateResearchScheduled := True;
   MarkAsDirty([dkUpdateClients, dkUpdateJournal, dkNeedsHandleChanges]);
end;

procedure TResearchFeatureNode.HandleChanges(CachedSystem: TSystem);
begin
   if (FUpdateResearchScheduled) then
   begin
      FUpdateResearchScheduled := False;
      UpdateResearch(CachedSystem);
   end;
   inherited;
end;

procedure TResearchFeatureNode.UpdateJournal(Journal: TJournalWriter; CachedSystem: TSystem);
var
   Research: TResearch;
begin
   Journal.WriteInt64(FSeed);
   Journal.WriteCardinal(FBankedResearch.Count);
   for Research in FBankedResearch do
   begin
      Assert(Research <> FCurrentResearch);
      Journal.WriteInt32(Research.ID);
      Journal.WriteInt64(FBankedResearch[Research].AsInt64);
   end;
   if (Assigned(FCurrentResearch)) then
   begin
      Journal.WriteInt32(FCurrentResearch.ID);
      Journal.WriteInt64(FResearchStartTime.AsInt64);
   end
   else
      Journal.WriteInt32(TResearch.kNil);
   Journal.WriteCardinal(Length(FSpecialties));
   for Research in FSpecialties do
      Journal.WriteInt32(Research.ID);
   if (Assigned(FTopic)) then
      Journal.WriteString(FTopic.Value)
   else
      Journal.WriteString('');
end;

procedure TResearchFeatureNode.ApplyJournal(Journal: TJournalReader; CachedSystem: TSystem);
var
   Count, Index: Cardinal;
   ResearchID: TResearchID;
   Research: TResearch;
   DurationAsInt64: Int64;
   Duration: TMillisecondsDuration;
   TopicName: UTF8String;
begin
   // Reset state
   FCurrentResearch := nil;
   FResearchStartTime := TTimeInMilliseconds.FromMilliseconds(0);
   FBankedResearch.Empty();
   if (Assigned(FResearchEvent)) then
   begin
      FResearchEvent.Cancel();
      FResearchEvent := nil;
   end;
   FUpdateResearchScheduled := True; // in case the tech tree changed or something
   // Read journal
   FSeed := Journal.ReadInt64();
   Count := Journal.ReadCardinal();
   if (Count > 0) then
   begin
      for Index := 0 to Count - 1 do // $R-
      begin
         ResearchID := Journal.ReadInt32(); // $R-
         Research := CachedSystem.Encyclopedia.Researches[ResearchID];
         DurationAsInt64 := Journal.ReadInt64();
         Duration := TMillisecondsDuration(DurationAsInt64);
         FBankedResearch[Research] := Duration;
      end;
   end;
   ResearchID := Journal.ReadInt32();
   if (ResearchID <> TResearch.kNil) then
   begin
      FCurrentResearch := CachedSystem.Encyclopedia.Researches[ResearchID]; // $R-
      FResearchStartTime := TTimeInMilliseconds.FromMilliseconds(Journal.ReadInt64());
   end;
   Count := Journal.ReadCardinal();
   SetLength(FSpecialties, Count);
   if (Count > 0) then
   begin
      for Index := 0 to Count - 1 do // $R-
      begin
         ResearchID := Journal.ReadInt32(); // $R-
         FSpecialties[Index] := CachedSystem.Encyclopedia.Researches[ResearchID];
      end;
   end;
   TopicName := Journal.ReadString();
   if (TopicName <> '') then
   begin
      FTopic := CachedSystem.Encyclopedia.Topics[TopicName];
   end
   else
      FTopic := nil;
end;

function TResearchFeatureNode.HandleCommand(Command: UTF8String; var Message: TMessage): Boolean;
 
   procedure DetermineTopics(Topics, ObsoleteTopics: TTopicHashSet);
   var
      KnowledgeBase: TGetKnownResearchesMessage;
      Injected: TBusMessageResult;
      RequirementsMet: Boolean;
      Research, Requirement: TResearch;
      Node: TNode;
      Candidate, Topic: TTopic;
   begin
      KnowledgeBase := TGetKnownResearchesMessage.Create(Parent.Owner);
      try
         Injected := InjectBusMessage(KnowledgeBase);
         Assert(Injected = mrHandled);
         for Research in KnowledgeBase do
         begin
            for Node in Research.Unlocks do
            begin
               if (Node is TTopic) then
               begin
                  Candidate := Node as TTopic;
                  if (Candidate.Selectable and not Topics.Has(Candidate)) then
                  begin
                     RequirementsMet := True;
                     for Requirement in Candidate.Requirements do
                     begin
                        if (not KnowledgeBase.Knows(Requirement)) then
                        begin
                           RequirementsMet := False;
                           break;
                        end;
                     end;
                     if (RequirementsMet) then
                     begin
                        Topics.Add(Candidate);
                        if (Assigned(ObsoleteTopics)) then
                           for Topic in Candidate.Obsoletes do
                           begin
                              if (not ObsoleteTopics.Has(Topic)) then
                                 ObsoleteTopics.Add(Topic);
                           end;
                     end;
                  end;
               end;
            end;
         end;
      finally
         FreeAndNil(KnowledgeBase);
      end;
   end;

var
   PlayerDynasty: TDynasty;
   Topics, ObsoleteTopics: TTopicHashSet;
   Topic: TTopic;
   TopicName: UTF8String;
begin
   if (Command = 'get-topics') then
   begin
      Result := True;
      PlayerDynasty := (Message.Connection as TConnection).PlayerDynasty;
      if (PlayerDynasty <> Parent.Owner) then
      begin
         Message.Error(ieInvalidCommand);
         exit;
      end;
      if (Message.CloseInput()) then
      begin
         Message.Reply();
         Topics := TTopicHashSet.Create();
         ObsoleteTopics := TTopicHashSet.Create();
         try
            DetermineTopics(Topics, ObsoleteTopics);
            for Topic in Topics do
            begin
               Message.Output.WriteString(Topic.Value);
               Message.Output.WriteBoolean(not ObsoleteTopics.Has(Topic));
            end;
            Message.Output.WriteString('');
            Message.Output.WriteBoolean(False);
         finally
            FreeAndNil(Topics);
            FreeAndNil(ObsoleteTopics);
         end;
         Message.CloseOutput();
      end;
   end
   else
   if (Command = 'set-topic') then
   begin
      PlayerDynasty := (Message.Connection as TConnection).PlayerDynasty;
      if (PlayerDynasty <> Parent.Owner) then
      begin
         Message.Error(ieInvalidCommand);
         exit;
      end;
      TopicName := Message.Input.ReadString();
      if (TopicName = '') then
      begin
         Topic := nil;
      end
      else
      begin
         Topic := System.Encyclopedia.Topics[TopicName];
         if (not Assigned(Topic)) then
         begin
            Message.Error(ieInvalidCommand);
            exit;
         end;
         Topics := TTopicHashSet.Create();
         try
            DetermineTopics(Topics, nil);
            if (not Topics.Has(Topic)) then
            begin
               Message.Error(ieInvalidCommand);
               exit;
            end;
         finally
            FreeAndNil(Topics);
         end;
      end;
      if (Message.CloseInput()) then
      begin
         Message.Reply();
         if (FTopic <> Topic) then
         begin
            FTopic := Topic;
            ScheduleUpdateResearch();
         end;
         Message.CloseOutput();
      end;
      Result := True;
   end
   else
      Result := inherited;
end;

procedure TResearchFeatureNode.BankResearch(CachedSystem: TSystem);
var
   Elapsed: TMillisecondsDuration;
begin
   if (Assigned(FCurrentResearch)) then
   begin
      Assert(not FBankedResearch.Has(FCurrentResearch));
      Elapsed := CachedSystem.Now - FResearchStartTime;
      FBankedResearch[FCurrentResearch] := Elapsed;
      FCurrentResearch := nil;
   end;
end;

procedure TResearchFeatureNode.UpdateResearch(CachedSystem: TSystem);

   function TopicMatches(Topic: TTopic): Boolean;
   var
      Facility: TTopic;
   begin
      if (Topic = FTopic) then
      begin
         Result := True;
         exit;
      end
      else
      for Facility in FFeatureClass.FFacilities do
      begin
         if (Topic = Facility) then
         begin
            Result := True;
            exit;
         end;
      end;
      Result := False;
   end;

var
   Candidates: TResearch.TArray;
   
   function CompareCandidates(const A, B: Integer): Integer;
   begin
      Result := Candidates[A].ID - Candidates[B].ID; // $R-
   end;

   procedure SwapCandidates(const A, B: Integer);
   var
      Temp: TResearch;
   begin
      Temp := Candidates[A];
      Candidates[A] := Candidates[B];
      Candidates[B] := Temp;
   end;

var
   KnowledgeBase: TGetKnownResearchesMessage;
   WeightedCandidates: TWeightedResearchHashTable;
   Injected: TBusMessageResult;
   RequirementsMet: Boolean;
   Research, Candidate: TResearch;
   Node, Requirement: TNode;
   Weight: TWeight;
   TotalWeight, SelectedResearch: Int64;
   Bonus: TBonus;
   Index: Cardinal;
   Duration, BankedTime: TMillisecondsDuration;
begin
   while (FSeed < 0) do
      FSeed := System.RandomNumberGenerator.GetUInt32();
   if (Assigned(FResearchEvent)) then
   begin
      FResearchEvent.Cancel();
      FResearchEvent := nil;
   end;
   BankResearch(CachedSystem);
   KnowledgeBase := TGetKnownResearchesMessage.Create(Parent.Owner);
   WeightedCandidates := TWeightedResearchHashTable.Create();
   TotalWeight := 0;
   {$IFDEF VERBOSE} Writeln('  ', Parent.DebugName, ': Enumerating researches for dynasty ', Parent.Owner.DynastyID, '.'); {$ENDIF}
   try
      Injected := InjectBusMessage(KnowledgeBase);
      Assert(Injected = mrHandled);
      KnowledgeBase.Subscribe(@ScheduleUpdateResearch); // TODO: how do we know this isn't leaking memory by adding infinite callbacks
      for Research in KnowledgeBase do
      begin
         {$IFDEF VERBOSE} Writeln('   - ', Research.ID, ' is known'); {$ENDIF}
         for Node in Research.Unlocks do
         begin
            if (Node is TResearch) then // we don't care about which topics we unlock here, as we're just making a list of researches that have been unlocked
            begin
               Candidate := Node as TResearch;
               {$IFDEF VERBOSE} Writeln('     - ', Candidate.ID, ' is unlocked by ', Research.ID); {$ENDIF}
               {$IFDEF VERBOSE} Writeln('       already known = ', KnowledgeBase.Knows(Candidate)); {$ENDIF}
               {$IFDEF VERBOSE} Writeln('       weighted = ', WeightedCandidates.Has(Candidate)); {$ENDIF}
               if ((not KnowledgeBase.Knows(Candidate)) and
                   (not WeightedCandidates.Has(Candidate))) then
               begin
                  RequirementsMet := True;
                  for Requirement in Candidate.Requirements do
                  begin
                     if (Requirement is TResearch) then
                     begin
                        if (not KnowledgeBase.Knows(Requirement as TResearch)) then
                        begin
                           RequirementsMet := False;
                           break;
                        end;
                     end
                     else
                     if (Requirement is TTopic) then
                     begin
                        if (not TopicMatches(Requirement as TTopic)) then
                        begin
                           RequirementsMet := False;
                           break;
                        end;
                     end
                     else
                     begin
                        Assert(False);
                     end;
                  end;
                  {$IFDEF VERBOSE} Writeln('       requirements met = ', RequirementsMet); {$ENDIF}
                  if (RequirementsMet) then
                  begin
                     Weight := Candidate.DefaultWeight;
                     for Bonus in Candidate.Bonuses do
                     begin
                        RequirementsMet := Bonus.Negate;
                        if (Bonus.Node is TResearch) then
                        begin
                           if (KnowledgeBase.Knows(Bonus.Node as TResearch)) then
                           begin
                              RequirementsMet := not RequirementsMet;
                           end;
                        end
                        else
                        if (Bonus.Node is TTopic) then
                        begin
                           if (TopicMatches(Bonus.Node as TTopic)) then
                           begin
                              RequirementsMet := not RequirementsMet;
                           end;
                        end
                        else
                        begin
                           Assert(False, 'Unexpected node type: ' + Bonus.Node.ClassName);
                        end;
                        if (RequirementsMet) then
                           Inc(Weight, Bonus.WeightDelta);
                     end;
                     {$IFDEF VERBOSE} Writeln('       weight = ', Weight); {$ENDIF}
                     if (Weight > 0) then
                     begin
                        WeightedCandidates[Candidate] := Weight;
                        Inc(TotalWeight, Weight);
                     end;
                  end;
               end;
            end;
         end;
      end;

      if (TotalWeight = 0) then
      begin
         Assert(not Assigned(FCurrentResearch));
         Assert(not Assigned(FResearchEvent));
         {$IFDEF VERBOSE} Writeln('  ', Parent.DebugName, ': No viable research detected for dynasty ', Parent.Owner.DynastyID, '.'); {$ENDIF}
         exit;
      end;   
      
      // We get the researches in a defined order so that changes to
      // the hash table algorithm don't affect the results.
      SetLength(Candidates, WeightedCandidates.Count);
      Index := 0;
      for Candidate in WeightedCandidates do
      begin
         Candidates[Index] := Candidate;
         Inc(Index);
      end;
      Sort(Length(Candidates), @CompareCandidates, @SwapCandidates); // $R-
      Assert(Length(Candidates) = WeightedCandidates.Count);

      // Pick a random number using our seed.
      SelectedResearch := FSeed mod TotalWeight;
      Assert(SelectedResearch >= 0);
      Assert(SelectedResearch < TotalWeight);

      // Find the corresponding research
      Index := Low(Candidates);
      repeat
         Weight := WeightedCandidates[Candidates[Index]];
         Assert(Weight > 0);
         Assert(Weight <= TotalWeight);
         if (SelectedResearch < Weight) then
            break;
         Dec(SelectedResearch, Weight);
         Inc(Index);
         {$IFOPT C+}
         if (Index >= Length(Candidates)) then
         begin
            Writeln('  ', Parent.DebugName, ': Failed with index = ', Index, ', selected research = ', SelectedResearch);
            Writeln('  Total weight = ', TotalWeight);
            Writeln('  Selected research = ', FSeed mod TotalWeight);
            Writeln(Length(Candidates), ' candidates:');
            for Index := Low(Candidates) to High(Candidates) do // $R-
               Writeln('    #', Index, ': research ', Candidates[Index].ID, ' has weight ', WeightedCandidates[Candidates[Index]]);
            Assert(False);
         end;
         {$ENDIF}
         Assert(Index < Length(Candidates));
      until False;

      Assert(Index < Length(Candidates));
      FCurrentResearch := Candidates[Index];

      Duration := FCurrentResearch.DefaultTime;
      for Bonus in FCurrentResearch.Bonuses do
      begin
         RequirementsMet := Bonus.Negate;
         if (Bonus.Node is TResearch) then
         begin
            if (KnowledgeBase.Knows(Bonus.Node as TResearch)) then
            begin
               RequirementsMet := not RequirementsMet;
            end;
         end
         else
         if (Bonus.Node is TTopic) then
         begin
            if (TopicMatches(Bonus.Node as TTopic)) then
            begin
               RequirementsMet := not RequirementsMet;
            end;
         end
         else
         begin
            Assert(False);
         end;
         if (RequirementsMet) then
            Duration := Duration + Bonus.TimeDelta;
      end;

      // TODO: apply FSpecialties
      // TODO: apply modifier based on how structurally sound this asset is
      // TODO: apply modifiers based on how powered this asset is
      // TODO: apply modifiers based on how staffed this asset is
      
      if (FBankedResearch.Has(FCurrentResearch)) then
      begin
         BankedTime := FBankedResearch[FCurrentResearch];
         Duration := Duration - FBankedResearch[FCurrentResearch];
         FBankedResearch.Remove(FCurrentResearch);
      end
      else
         BankedTime := TMillisecondsDuration.FromMilliseconds(0);

      FResearchStartTime := CachedSystem.Now - BankedTime;
      
      if (Duration.IsNegative) then
         Duration := TMillisecondsDuration.FromMilliseconds(0);
      Writeln('  ', Parent.DebugName, ': Scheduled research ', FCurrentResearch.ID, '; T-', Duration.ToString());
      
      FResearchEvent := CachedSystem.ScheduleEvent(Duration, @TriggerResearch, Self);
   finally
      WeightedCandidates.Free();
      KnowledgeBase.Free();
   end;
   MarkAsDirty([dkUpdateClients, dkUpdateJournal]); // save new situation (but don't update research)
end;

procedure TResearchFeatureNode.TriggerResearch(var Data);
var
   Reward: TReward;
   RewardMessage: TNotificationMessage;
   Injected: TBusMessageResult;
   Body: UTF8String;
begin
   Writeln('  ', Parent.DebugName, ': Triggering research ', FCurrentResearch.ID);
   FResearchEvent := nil;
   Assert(not FBankedResearch.Has(FCurrentResearch));
   Assert(Length(FCurrentResearch.Rewards) > 0);
   for Reward in FCurrentResearch.Rewards do
   begin
      if (Reward.Kind = rkMessage) then
      begin
         Body := Reward.Message;
         break;
      end;
   end;
   Assert(Body <> '');
   RewardMessage := TNotificationMessage.Create(Parent, Body, FCurrentResearch);
   Injected := InjectBusMessage(RewardMessage);
   if (Injected <> mrHandled) then
      Writeln('  ', Parent.DebugName, ': Discarding message from research feature ("', RewardMessage.Body, '")');
   FreeAndNil(RewardMessage);
   SetLength(FSpecialties, Length(FSpecialties) + 1);
   FSpecialties[High(FSpecialties)] := FCurrentResearch;
   FCurrentResearch := nil;
   FResearchStartTime := TTimeInMilliseconds.FromMilliseconds(0);
   FSeed := -1;
   ScheduleUpdateResearch();
end;

initialization
   RegisterFeatureClass(TResearchFeatureClass);
end.