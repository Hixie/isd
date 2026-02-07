{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit research;

interface

{$DEFINE VERBOSE}
//{$DEFINE DEBUG_VERBOSE}

uses
   hashtable, genericutils, basenetwork, systems, internals,
   serverstream, systemdynasty, materials, time,
   commonbuses, knowledge, annotatedpointer;

type
   // Sent by a research feature to find other facilities.
   // Sent to the research feature's asset specifically.
   TFindResearchFacilitiesBusMessage = class(TPhysicalConnectionBusMessage)
   strict private
      FDynasty: TDynasty;
      FSituations: TSituationHashSet;
   public
      constructor Create(ADynasty: TDynasty);
      procedure AddFacility(Situation: TSituation);
      property Dynasty: TDynasty read FDynasty;
      procedure MoveTo(var Target: TSituationHashSet);
   end;

   // Injected by a facility to notify possible research features.
   // Sent up the tree to the nearest research feature.
   TResearchFacilityChangedBusMessage = class(TPhysicalConnectionBusMessage)
   strict private
      FDynasty: TDynasty;
   public
      constructor Create(ADynasty: TDynasty);
      property Dynasty: TDynasty read FDynasty;
   end;

type
   TResearchTimeHashTable = class(specialize THashTable<TResearch, TMillisecondsDuration, specialize DefaultUnorderedUtils<TResearch>>)
      constructor Create();
   end;

   TWeightedResearchHashTable = class(specialize THashTable<TResearch, TWeight, specialize DefaultUnorderedUtils<TResearch>>)
      constructor Create();
   end;

   TResearchFeatureClass = class(TFeatureClass)
   private
      FFacilities: TSituationHashSet; // situations provided by research feature
   strict protected
      function GetFeatureNodeClass(): FeatureNodeReference; override;
   public
      constructor Create(AFacilities: TSituationHashSet);
      constructor CreateFromTechnologyTree(const Reader: TTechTreeReader); override;
      function InitFeatureNode(ASystem: TSystem): TFeatureNode; override;
      function Provides(Facility: TSituation): Boolean;
   end;

   TResearchFeatureNode = class(TFeatureNode)
   strict private
      FFeatureClass: TResearchFeatureClass;
      FSeed: Int64; // negative values indicate that the seed has not been established yet; once established, it is fixed
      FBankedResearch: TResearchTimeHashTable;
      FSubscription: TKnowledgeSubscription;
      FResearchEvent: TSystemEvent;
      FResearchStartTime: TTimeInMilliseconds;
      FRateLimit, FResearchTimeFactor: Double; // always bank research before changing these
      FTopic: TTopic;
      FCurrentResearch: TResearch;
      FDisabledReasons: TDisabledReasons;
      FUpdateResearchScheduled, FResearchSlow: Boolean; // TODO: move these into FCurrentResearch using TAnnotatedPointer
      procedure BankResearch();
      procedure UpdateResearch();
      procedure TriggerResearch(var Data);
      procedure HandleKnowledgeChanged();
      procedure ScheduleUpdateResearch();
      procedure FillEvaluationContext(out EvaluationContext: TResearchConditionEvaluationContext; const IncludeTopic: Boolean);
      procedure DetermineTopics(var Target: TTopicHashSet);
   protected
      constructor CreateFromJournal(Journal: TJournalReader; AFeatureClass: TFeatureClass; ASystem: TSystem); override;
      function ManageBusMessage(Message: TBusMessage): TInjectBusMessageResult; override;
      procedure Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter); override;
      procedure HandleChanges(); override;
   public
      constructor Create(ASystem: TSystem; AFeatureClass: TResearchFeatureClass);
      destructor Destroy(); override;
      procedure UpdateJournal(Journal: TJournalWriter); override;
      procedure ApplyJournal(Journal: TJournalReader); override;
      function HandleCommand(PlayerDynasty: TDynasty; Command: UTF8String; var Message: TMessage): Boolean; override;
   end;

   // TODO: unsubscribe from bus when detaching
   // TODO: schedule update when attaching

implementation

uses
   exceptions, sysutils, arrayutils, isdprotocol, messages, typedump, ttparser, hashfunctions, conditions;


constructor TFindResearchFacilitiesBusMessage.Create(ADynasty: TDynasty);
begin
   inherited Create();
   FDynasty := ADynasty;
end;

procedure TFindResearchFacilitiesBusMessage.AddFacility(Situation: TSituation);
begin
   FSituations.Add(Situation);
end;

procedure TFindResearchFacilitiesBusMessage.MoveTo(var Target: TSituationHashSet);
begin
   FSituations.MoveTo(Target); {BOGUS Warning: Function result variable of a managed type does not seem to be initialized}
end;


constructor TResearchFacilityChangedBusMessage.Create(ADynasty: TDynasty);
begin
   inherited Create();
   FDynasty := ADynasty;
end;


function ResearchHash32(const Key: TResearch): DWord;
begin
   Result := ObjectHash32(Key);
end;


constructor TResearchTimeHashTable.Create();
begin
   inherited Create(@ResearchHash32);
end;


constructor TWeightedResearchHashTable.Create();
begin
   inherited Create(@ResearchHash32);
end;


constructor TResearchFeatureClass.Create(AFacilities: TSituationHashSet);
begin
   inherited Create();
   AFacilities.MoveTo(FFacilities);
end;

constructor TResearchFeatureClass.CreateFromTechnologyTree(const Reader: TTechTreeReader);
begin
   inherited Create();
   repeat
      if (Reader.Tokens.IsIdentifier('provides')) then
      begin
         Reader.Tokens.ReadIdentifier('provides');
         FFacilities.Add(ReadSituation(Reader));
      end;
   until not ReadComma(Reader.Tokens);
end;

function TResearchFeatureClass.GetFeatureNodeClass(): FeatureNodeReference;
begin
   Result := TResearchFeatureNode;
end;

function TResearchFeatureClass.InitFeatureNode(ASystem: TSystem): TFeatureNode;
begin
   Result := TResearchFeatureNode.Create(ASystem, Self);
end;

function TResearchFeatureClass.Provides(Facility: TSituation): Boolean;
begin
   Result := FFacilities.Has(Facility);
end;


constructor TResearchFeatureNode.Create(ASystem: TSystem; AFeatureClass: TResearchFeatureClass);
begin
   inherited Create(ASystem);
   FFeatureClass := AFeatureClass;
   FSeed := -1;
   FUpdateResearchScheduled := True;
   FBankedResearch := TResearchTimeHashTable.Create();
end;

constructor TResearchFeatureNode.CreateFromJournal(Journal: TJournalReader; AFeatureClass: TFeatureClass; ASystem: TSystem);
begin
   Assert(Assigned(AFeatureClass));
   FFeatureClass := AFeatureClass as TResearchFeatureClass;
   FBankedResearch := TResearchTimeHashTable.Create();
   inherited;
end;

destructor TResearchFeatureNode.Destroy();
begin
   if (FSubscription.Subscribed) then
      FSubscription.Unsubscribe();
   FBankedResearch.Free();
   if (Assigned(FResearchEvent)) then
      CancelEvent(FResearchEvent);
   inherited;
end;

function TResearchFeatureNode.ManageBusMessage(Message: TBusMessage): TInjectBusMessageResult;
begin
   if (Message is TResearchFacilityChangedBusMessage) then
   begin
      if ((Message as TResearchFacilityChangedBusMessage).Dynasty = Parent.Owner) then
         ScheduleUpdateResearch();
      Result := irHandled;
   end
   else
      Result := inherited;
end;

procedure TResearchFeatureNode.Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter);
var
   Visibility: TVisibility;
   Topics: TTopicHashSet;
   Topic: TTopic.TIndex;
begin
   Visibility := Parent.ReadVisibilityFor(DynastyIndex);
   if ((dmDetectable * Visibility <> []) and (dmClassKnown in Visibility)) then
   begin
      Writer.WriteCardinal(fcResearch);
      Writer.WriteCardinal(Cardinal(FDisabledReasons));
      // Topics
      if (System.DynastyByIndex[DynastyIndex] = Parent.Owner) then
      begin
         DetermineTopics(Topics);
         for Topic in Topics do
            Writer.WriteStringReference(System.Encyclopedia.TopicsByIndex[Topic].Name);
      end;
      Writer.WriteStringReference('');
      // Topic
      if (Assigned(FTopic) and (dmInternals in Visibility)) then
      begin
         Writer.WriteStringReference(FTopic.Name);
      end
      else
      begin
         Writer.WriteStringReference('');
      end;
      // Difficulty
      if (not Assigned(FCurrentResearch)) then
      begin
         Writer.WriteByte(0);
      end
      else
      if (FResearchSlow) then
      begin
         Writer.WriteByte(1);
      end
      else
      begin
         Writer.WriteByte(2);
      end;
   end;
end;

procedure TResearchFeatureNode.HandleKnowledgeChanged();
begin
   FSubscription.Reset();
   ScheduleUpdateResearch();
end;

procedure TResearchFeatureNode.ScheduleUpdateResearch();
begin
   FUpdateResearchScheduled := True;
   MarkAsDirty([dkNeedsHandleChanges]);
   // HandleChanges is called soon thereafter, and calls UpdateResearch
end;

procedure TResearchFeatureNode.HandleChanges();
var
   NewDisabledReasons: TDisabledReasons;
   NewRateLimit: Double;
begin
   NewDisabledReasons := CheckDisabled(Parent, NewRateLimit);
   if (NewDisabledReasons <> FDisabledReasons) then
   begin
      FDisabledReasons := NewDisabledReasons;
      MarkAsDirty([dkUpdateClients]);
   end;
   if (NewRateLimit <> FRateLimit) then
   begin
      BankResearch();
      FRateLimit := NewRateLimit;
      FUpdateResearchScheduled := True;
   end;
   if (FUpdateResearchScheduled) then
   begin
      FUpdateResearchScheduled := False;
      UpdateResearch();
   end;
   inherited;
end;

procedure TResearchFeatureNode.UpdateJournal(Journal: TJournalWriter);
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
      Assert(FRateLimit > 0.0);
      Journal.WriteInt32(FCurrentResearch.ID);
      Journal.WriteInt64(FResearchStartTime.AsInt64);
      Journal.WriteDouble(FResearchTimeFactor);
   end
   else
      Journal.WriteInt32(TResearch.kNilID);
   Journal.WriteDouble(FRateLimit);
   Journal.WriteCardinal(0);
   if (Assigned(FTopic)) then
      Journal.WriteString(FTopic.Name)
   else
      Journal.WriteString('');
end;

procedure TResearchFeatureNode.ApplyJournal(Journal: TJournalReader);
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
      CancelEvent(FResearchEvent);
   FUpdateResearchScheduled := True;
   // Read journal
   FSeed := Journal.ReadInt64();
   Count := Journal.ReadCardinal();
   if (Count > 0) then
   begin
      for Index := 0 to Count - 1 do // $R-
      begin
         ResearchID := Journal.ReadInt32(); // $R-
         Research := System.Encyclopedia.ResearchesByID[ResearchID];
         DurationAsInt64 := Journal.ReadInt64();
         Duration := TMillisecondsDuration(DurationAsInt64);
         FBankedResearch[Research] := Duration;
      end;
   end;
   ResearchID := Journal.ReadInt32();
   if (ResearchID <> TResearch.kNilID) then
   begin
      FCurrentResearch := System.Encyclopedia.ResearchesByID[ResearchID]; // $R-
      FResearchStartTime := TTimeInMilliseconds.FromMilliseconds(Journal.ReadInt64());
      FResearchTimeFactor := Journal.ReadDouble();
   end;
   FRateLimit := Journal.ReadDouble();
   Count := Journal.ReadCardinal();
   TopicName := Journal.ReadString();
   if (TopicName <> '') then
   begin
      FTopic := System.Encyclopedia.TopicsByName[TopicName];
   end
   else
      FTopic := nil;
end;

procedure TResearchFeatureNode.FillEvaluationContext(out EvaluationContext: TResearchConditionEvaluationContext; const IncludeTopic: Boolean);
var
   FetchFacilities: TFindResearchFacilitiesBusMessage;
   KnowledgeBase: TGetKnownResearchesMessage;
begin
   KnowledgeBase := TGetKnownResearchesMessage.Create(Parent.Owner);
   InjectBusMessage(KnowledgeBase);
   if (not FSubscription.Subscribed) then
      FSubscription := KnowledgeBase.Subscribe(@HandleKnowledgeChanged);
   KnowledgeBase.CopyTo(EvaluationContext.KnownResearches); {BOGUS Hint: Variable "EvaluationContext" of a managed type does not seem to be initialized}
   FreeAndNil(KnowledgeBase);

   FetchFacilities := TFindResearchFacilitiesBusMessage.Create(Parent.Owner);
   Parent.HandleBusMessage(FetchFacilities);
   FetchFacilities.MoveTo(EvaluationContext.Situations);
   FreeAndNil(FetchFacilities);

   // TODO: situations from knowledge bus
   // (will need to add to EvaluationContext.Situations, not just move into it, unless we pass a pointer in?)

   if (IncludeTopic and Assigned(FTopic)) then
      EvaluationContext.SelectedTopic := FTopic.Index
   else
      EvaluationContext.SelectedTopic := TTopic.kNilIndex;
end;

procedure TResearchFeatureNode.DetermineTopics(var Target: TTopicHashSet);
var
   Research: TResearchIndex;
   Topic: TTopic.TIndex;
   EvaluationContext: TResearchConditionEvaluationContext;
begin
   FillEvaluationContext(EvaluationContext, False); // False because current topic must not affect available topics
   Target.Reset();
   for Research in EvaluationContext.KnownResearches do
      for Topic in System.Encyclopedia.ResearchesByIndex[Research].UnlockedTopics do
      begin
         if ((not Target.Has(Topic)) and EvaluateCondition(System.Encyclopedia.TopicsByIndex[Topic].Condition.ConditionProgram, @EvaluationContext)) then
            Target.Add(Topic);
      end;
end;

function TResearchFeatureNode.HandleCommand(PlayerDynasty: TDynasty; Command: UTF8String; var Message: TMessage): Boolean;
var
   Topics: TTopicHashSet;
   Topic: TTopic;
   TopicName: UTF8String;
begin
   if (Command = ccSetTopic) then
   begin
      Result := True;
      if (PlayerDynasty <> Parent.Owner) then
      begin
         Message.Error(ieNotOwner);
         exit;
      end;
      TopicName := Message.Input.ReadString();
      if (TopicName = '') then
      begin
         Topic := nil;
      end
      else
      begin
         Topic := System.Encyclopedia.TopicsByName[TopicName];
         if (not Assigned(Topic)) then
         begin
            Message.Error(ieInvalidMessage);
            exit;
         end;
         Assert(Topics.IsEmpty);
         DetermineTopics(Topics);
         if (not Topics.Has(Topic.Index)) then
         begin
            Message.Error(ieInvalidMessage);
            exit;
         end;
      end;
      if (Message.CloseInput()) then
      begin
         Message.Reply();
         if (FTopic <> Topic) then
         begin
            FTopic := Topic;
            ScheduleUpdateResearch();
            MarkAsDirty([dkUpdateClients, dkUpdateJournal]);
         end;
         Message.CloseOutput();
      end;
   end
   else
      Result := False;
end;

procedure TResearchFeatureNode.BankResearch();
var
   Elapsed: TMillisecondsDuration;
begin
   if (Assigned(FCurrentResearch)) then
   begin
      Assert(FRateLimit > 0.0, DebugName + ' has rate limit ' + FloatToStr(FRateLimit) + ' while having an active research');
      Assert(not FBankedResearch.Has(FCurrentResearch));
      if (Assigned(FResearchEvent)) then // it's nil, e.g., just after we load from the journal
         CancelEvent(FResearchEvent);
      Elapsed := System.Now - FResearchStartTime;
      FBankedResearch[FCurrentResearch] := Elapsed / (FRateLimit * FResearchTimeFactor);
      FCurrentResearch := nil;
   end;
end;

procedure TResearchFeatureNode.UpdateResearch();

   function CompareCandidates(const A, B: TResearch): Integer;
   begin
      Result := A.ID - B.ID; // $R-
   end;

var
   Candidates: TResearch.TArray;
   WeightedCandidates: TWeightedResearchHashTable;
   Research, Candidate: TResearch;
   ResearchIndex, CandidateIndex: TResearchIndex;
   Weight: TWeight;
   TotalWeight, SelectedResearch: Int64;
   Bonus: TBonus; // TODO: see if there's a way we can avoid copying these around
   Index: Cardinal;
   Duration, BankedTime: TMillisecondsDuration;
   EvaluationContext: TResearchConditionEvaluationContext;
   {$IFDEF VERBOSE}
   Message: UTF8String;
   Found: Boolean;
   {$ENDIF}
begin
   Writeln(DebugName, ' updating research agenda for dynasty ', Parent.Owner.DynastyID);
   BankResearch(); // see also comment in HandleChanges

   if (FRateLimit = 0.0) then
   begin
      FCurrentResearch := nil;
      exit;
   end;
   
   while (FSeed < 0) do
      FSeed := System.RandomNumberGenerator.GetUInt32();

   FillEvaluationContext(EvaluationContext, True);
   WeightedCandidates := TWeightedResearchHashTable.Create();
   TotalWeight := 0;
   {$IFDEF DEBUG_VERBOSE} Writeln(Parent.DebugName, ': Enumerating researches for dynasty ', Parent.Owner.DynastyID, ' (found ', EvaluationContext.KnownResearches.Count, ' known researches).'); {$ENDIF}
   try
      for ResearchIndex in EvaluationContext.KnownResearches do
      begin
         Research := System.Encyclopedia.ResearchesByIndex[ResearchIndex];
         {$IFDEF DEBUG_VERBOSE} Writeln('  known research: index ', ResearchIndex, ', ID ', Research.ID, ': ', Research.DebugDescription); {$ENDIF}
         for CandidateIndex in Research.UnlockedResearches do
         begin
            Candidate := System.Encyclopedia.ResearchesByIndex[CandidateIndex];
            {$IFDEF DEBUG_VERBOSE} Writeln('    might unlock research index ', CandidateIndex, ', ID ', Candidate.ID, ': ', Candidate.DebugDescription); {$ENDIF}
            if (not EvaluationContext.KnownResearches.Has(CandidateIndex)) then
            begin
               {$IFDEF DEBUG_VERBOSE} Writeln('     + not yet known'); {$ENDIF}
               if (not WeightedCandidates.Has(Candidate)) then
               begin
                  {$IFDEF DEBUG_VERBOSE} Writeln('     + not yet considered'); {$ENDIF}
                  if (EvaluateCondition(Candidate.Condition.ConditionProgram, @EvaluationContext)) then
                  begin
                     {$IFDEF DEBUG_VERBOSE} Writeln('     + passes its condition'); {$ENDIF}
                     Weight := Candidate.DefaultWeight;
                     {$IFDEF DEBUG_VERBOSE} Writeln('     default weight: ', Weight); {$ENDIF}
                     for Bonus in Candidate.Bonuses do
                     begin
                        if (EvaluateCondition(Bonus.Condition.ConditionProgram, @EvaluationContext)) then
                        begin
                           {$IFDEF DEBUG_VERBOSE} Writeln('     + additional weight ', Bonus.WeightDelta); {$ENDIF}
                           Inc(Weight, Bonus.WeightDelta);
                        end;
                     end;
                     if (Weight > 0) then
                     begin
                        {$IFDEF DEBUG_VERBOSE} Writeln('     => final weight ', Weight); {$ENDIF}
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

      // We reorder the researches so that changes to the hash table
      // algorithm don't affect the results.
      SetLength(Candidates, WeightedCandidates.Count);
      Index := 0;
      for Candidate in WeightedCandidates do
      begin
         Candidates[Index] := Candidate;
         Inc(Index);
      end;
      specialize Sort<TResearch>(Candidates, @CompareCandidates);
      Assert(Length(Candidates) = WeightedCandidates.Count);

      // Pick a random number using our seed.
      SelectedResearch := FSeed mod TotalWeight;
      Assert(SelectedResearch >= 0);
      Assert(SelectedResearch < TotalWeight);

      {$IFDEF VERBOSE}
      Writeln('  Candidate researches (selected research weight: ', SelectedResearch, '):');
      Weight := 0;
      Found := False;
      for Research in Candidates do
      begin
         Message := Research.DebugDescription();
         Write('    ', WeightedCandidates[Research]:9, ' ', Research.ID, ' (', Message, ')');
         Inc(Weight, WeightedCandidates[Research]);
         if (not Found and (SelectedResearch < Weight)) then
         begin
            Write('  <---- selected');
            Found := True;
         end;
         Writeln();
      end;
      {$ENDIF}

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
         Assert(Index < Length(Candidates));
      until False;
      Assert(Index < Length(Candidates));
      FCurrentResearch := Candidates[Index];

      FResearchTimeFactor := 1.0;
      for Bonus in FCurrentResearch.Bonuses do
         if (EvaluateCondition(Bonus.Condition.ConditionProgram, @EvaluationContext)) then
            FResearchTimeFactor := FResearchTimeFactor * Bonus.TimeFactor;
      Assert(FResearchTimeFactor > 0.0);
      Duration := FCurrentResearch.DefaultTime;

      {$IFDEF VERBOSE}
      Writeln('  Research default time: ', Duration.ToString());
      Writeln('  Bonus time factor: ', FResearchTimeFactor.ToString());
      Writeln('  Rate limit: ', FRateLimit.ToString());
      {$ENDIF}

      FResearchSlow := (Duration / FResearchTimeFactor) > (TWallMillisecondsDuration.FromDays(1) * System.TimeFactor);
      
      if (FBankedResearch.Has(FCurrentResearch)) then
      begin
         BankedTime := FBankedResearch[FCurrentResearch];
         Duration := Duration - BankedTime;
         FBankedResearch.Remove(FCurrentResearch);
      end
      else
         BankedTime := TMillisecondsDuration.FromMilliseconds(0);

      {$IFDEF VERBOSE}
      Writeln('  Slow? ', FResearchSlow);
      Writeln('  Banked time: ', BankedTime.ToString());
      Writeln('  Remaining duration: ', Duration.ToString());
      {$ENDIF}

      FResearchStartTime := System.Now - (BankedTime * FRateLimit * FResearchTimeFactor);
      Duration := Duration / (FRateLimit * FResearchTimeFactor);

      {$IFDEF VERBOSE}
      Writeln('  Computed duration with modifiers: ', Duration.ToString());
      {$ENDIF}

      if (Duration.IsNegative) then
         Duration := TMillisecondsDuration.FromMilliseconds(0);
      Writeln(Parent.DebugName, ': Scheduled research; T-', Duration.ToString());

      FResearchEvent := System.ScheduleEvent(Duration, @TriggerResearch, Self);
   finally
      WeightedCandidates.Free();
   end;
   MarkAsDirty([dkUpdateJournal, dkUpdateClients]);
end;

procedure TResearchFeatureNode.TriggerResearch(var Data);
var
   Unlock: TUnlockedKnowledge;
   UnlockMessage: TNotificationMessage;
   Injected: TInjectBusMessageResult;
   Body: UTF8String;
begin
   Writeln(Parent.DebugName, ': Triggering research ', FCurrentResearch.ID);
   Assert(FRateLimit > 0.0);
   FResearchEvent := nil;
   Assert(not FBankedResearch.Has(FCurrentResearch));
   Assert(Length(FCurrentResearch.UnlockedKnowledge) > 0);
   for Unlock in FCurrentResearch.UnlockedKnowledge do
   begin
      if (Unlock.Kind = ukMessage) then
      begin
         Body := Unlock.Message;
         break;
      end;
   end;
   Assert(Body <> '');
   UnlockMessage := TNotificationMessage.Create(Parent, Body, FCurrentResearch);
   Injected := InjectBusMessage(UnlockMessage);
   if (Injected <> irHandled) then
   begin
      Writeln(Parent.DebugName, ': Discarding message from research feature ("', UnlockMessage.Body, '")');
      // TODO: now what? can we be notified when we would be able to send a message? can notification centers notify when they come online?
      FResearchEvent := System.ScheduleEvent(TMillisecondsDuration.FromMilliseconds(1000 * 60 * 60 * 24), @TriggerResearch, Self); // wait a day and try again
   end
   else
   begin
      FCurrentResearch := nil;
      FResearchStartTime := TTimeInMilliseconds.FromMilliseconds(0);
      FSeed := -1;
      MarkAsDirty([dkUpdateJournal]);
      ScheduleUpdateResearch();
   end;
   FreeAndNil(UnlockMessage);
end;

initialization
   RegisterFeatureClass(TResearchFeatureClass);
end.