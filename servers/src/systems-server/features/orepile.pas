{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit orepile;

interface

uses
   basenetwork, systems, serverstream, materials, techtree,
   messageport, region, time, annotatedpointer, systemdynasty, masses;

type
   TOreMaterialKnowledgePackage = record
   strict private
      {$IFOPT C+} function GetLength(): Cardinal; {$ENDIF}
      function GetIsPointer(): Boolean; inline;
      function GetKnowledge(DynastyIndex: Cardinal): TOreFilter;
      property IsPointer: Boolean read GetIsPointer;
   public
      procedure Init(DynastyCount: Cardinal); // TODO: use an arena somehow
      procedure Done();
      procedure Reset();
      procedure ResetKnowledge(DynastyIndex: Cardinal);
      procedure AddKnowledge(DynastyIndex: Cardinal; Value: TOreFilter);
      property Materials[DynastyIndex: Cardinal]: TOreFilter read GetKnowledge; default;
      {$IFOPT C+} property Length: Cardinal read GetLength; {$ENDIF}
   strict private
      {$IF SIZEOF(TOreFilter) <> SIZEOF(Pointer)} {$FATAL This platform will need work.} {$ENDIF}
      case Integer of
         0: (FSingleData: TOreFilter);
         1: (FArrayData: POreFilter);
   end;

   TOrePileFeatureClass = class(TFeatureClass)
   private
      FCapacityMass: TMass; // max kg storage
   strict protected
      function GetFeatureNodeClass(): FeatureNodeReference; override;
   public
      constructor CreateFromTechnologyTree(Reader: TTechTreeReader); override;
      function InitFeatureNode(ASystem: TSystem): TFeatureNode; override;
   end;

   TOrePileFeatureNode = class(TFeatureNode, IOrePile)
   strict private
      type
         TRegionFlag = (rfSearchedForRegion);
      var
      FFeatureClass: TOrePileFeatureClass;
      FDynastyKnowledge: TOreMaterialKnowledgePackage; // per dynasty bits for each ore
      FRegion: specialize TAnnotatedPointer<TRegionFeatureNode, TRegionFlag>; // TODO: either use TAnnotatedPointer more widely, or remove the use here
   private // IOrePile
      function GetOrePileCapacity(): TMass;
      procedure SetOrePileRegion(Region: TRegionFeatureNode);
      procedure RegionAdjustedOrePiles();
      procedure DisconnectOrePile();
      function GetDynasty(): TDynasty;
   protected
      constructor CreateFromJournal(Journal: TJournalReader; AFeatureClass: TFeatureClass; ASystem: TSystem); override;
      procedure Detaching(); override;
      function GetMass(): TMass; override;
      function GetMassFlowRate(): TMassRate; override;
      function HandleBusMessage(Message: TBusMessage): THandleBusMessageResult; override;
      procedure HandleChanges(); override;
      procedure Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter); override;
      procedure ResetDynastyNotes(OldDynasties: TDynastyIndexHashTable; NewDynasties: TDynasty.TArray); override;
      procedure ResetVisibility(); override;
      procedure HandleKnowledge(const DynastyIndex: Cardinal; const Sensors: ISensorsProvider); override;
   public
      constructor Create(ASystem: TSystem; AFeatureClass: TOrePileFeatureClass);
      destructor Destroy(); override;
      procedure UpdateJournal(Journal: TJournalWriter); override;
      procedure ApplyJournal(Journal: TJournalReader); override;
      function HandleCommand(PlayerDynasty: TDynasty; Command: UTF8String; var Message: TMessage): Boolean; override;
   end;

// TODO: handle our ancestor chain changing

implementation

uses
   exceptions, sysutils, knowledge, messages, isdprotocol, rubble, commonbuses;

function TOreMaterialKnowledgePackage.GetIsPointer(): Boolean;
begin
   Result := not FSingleData.Active;
end;

procedure TOreMaterialKnowledgePackage.Init(DynastyCount: Cardinal);
var
   NewAllocSize, OldAllocSize: PtrUInt;
begin
   Assert(SizeOf(TOreFilter) = 8);
   NewAllocSize := DynastyCount * SizeOf(TOreFilter); // $R-
   if (not Assigned(FArrayData)) then
   begin
      OldAllocSize := 0;
   end
   else
   if (IsPointer) then
   begin
      OldAllocSize := MemSize(FArrayData);
   end
   else
   begin
      OldAllocSize := SizeOf(FSingleData);
      Assert(OldAllocSize = 8);
   end;
   if (OldAllocSize <> NewAllocSize) then
   begin
      if (OldAllocSize > SizeOf(FSingleData)) then
         FreeMem(FArrayData);
      if (NewAllocSize > SizeOf(FSingleData)) then
      begin
         GetMem(FArrayData, NewAllocSize);
         TOreFilter.ClearArray(FArrayData, DynastyCount);
      end
      else
      if (NewAllocSize = SizeOf(FSingleData)) then
      begin
         FSingleData.Clear();
      end
      else
      begin
         FArrayData := nil;
      end;
   end;
end;

procedure TOreMaterialKnowledgePackage.Done();
begin
   if (IsPointer and Assigned(FArrayData)) then
      FreeMem(FArrayData);
end;

procedure TOreMaterialKnowledgePackage.Reset();
begin
   if (IsPointer) then
   begin
      TOreFilter.ClearArray(FArrayData, MemSize(FArrayData) div SizeOf(TOreFilter)); // $R-
   end
   else
   begin
      FSingleData.Clear();
   end;
end;

{$IFOPT C+}
function TOreMaterialKnowledgePackage.GetLength(): Cardinal;
var
   AllocSize: PtrUInt;
begin
   if (not Assigned(FArrayData)) then
   begin
      AllocSize := 0;
   end
   else
   if (IsPointer) then
   begin
      AllocSize := MemSize(FArrayData);
   end
   else
   begin
      AllocSize := SizeOf(FSingleData);
      Assert(SizeOf(FSingleData) = SizeOf(TOreFilter));
   end;
   Result := AllocSize div SizeOf(TOreFilter); // $R-
end;
{$ENDIF}

function TOreMaterialKnowledgePackage.GetKnowledge(DynastyIndex: Cardinal): TOreFilter;
begin
   if (IsPointer) then
   begin
      Assert(Assigned(FArrayData));
      {$PUSH}
      {$POINTERMATH ON}
      Result := (POreFilter(FArrayData) + DynastyIndex)^;
      {$POP}
   end
   else
   begin
      Assert(DynastyIndex = 0);
      Result := FSingleData;
   end;
end;

procedure TOreMaterialKnowledgePackage.ResetKnowledge(DynastyIndex: Cardinal);
begin
   if (IsPointer) then
   begin
      Assert(Assigned(FArrayData));
      {$PUSH}
      {$POINTERMATH ON}
      (POreFilter(FArrayData) + DynastyIndex)^.Clear();
      {$POP}
   end
   else
   begin
      Assert(DynastyIndex = 0);
      FSingleData.Clear();
   end;
end;

procedure TOreMaterialKnowledgePackage.AddKnowledge(DynastyIndex: Cardinal; Value: TOreFilter);
begin
   if (IsPointer) then
   begin
      Assert(Assigned(FArrayData));
      {$PUSH}
      {$POINTERMATH ON}
      (POreFilter(FArrayData) + DynastyIndex)^.Add(Value);
      {$POP}
   end
   else
   begin
      Assert(DynastyIndex = 0);
      FSingleData.Add(Value);
   end;
end;


constructor TOrePileFeatureClass.CreateFromTechnologyTree(Reader: TTechTreeReader);
var
   Keyword: UTF8String;
   SeenMaxMass: Boolean;
begin
   inherited Create();
   SeenMaxMass := False;
   repeat
      Keyword := Reader.Tokens.ReadIdentifier();
      case Keyword of
         'max':
            begin
               Keyword := Reader.Tokens.ReadIdentifier();
               case Keyword of
                  'mass':
                     begin
                        if (SeenMaxMass) then
                           Reader.Tokens.Error('Duplicate parameter "max mass"', []);
                        FCapacityMass := ReadMass(Reader.Tokens);
                        SeenMaxMass := True;
                     end;
               else
                  Reader.Tokens.Error('Unexpected keyword "max %s"', [Keyword]);
               end;
            end;
      else
         Reader.Tokens.Error('Unexpected keyword "%s"', [Keyword]);
      end;
   until not ReadComma(Reader.Tokens);
   if (not SeenMaxMass) then
      Reader.Tokens.Error('Expected "max mass" parameter', []);
end;

function TOrePileFeatureClass.GetFeatureNodeClass(): FeatureNodeReference;
begin
   Result := TOrePileFeatureNode;
end;

function TOrePileFeatureClass.InitFeatureNode(ASystem: TSystem): TFeatureNode;
begin
   Result := TOrePileFeatureNode.Create(ASystem, Self);
end;


constructor TOrePileFeatureNode.Create(ASystem: TSystem; AFeatureClass: TOrePileFeatureClass);
begin
   inherited Create(ASystem);
   FFeatureClass := AFeatureClass;
end;

constructor TOrePileFeatureNode.CreateFromJournal(Journal: TJournalReader; AFeatureClass: TFeatureClass; ASystem: TSystem);
begin
   Assert(Assigned(AFeatureClass));
   FFeatureClass := AFeatureClass as TOrePileFeatureClass;
   inherited;
end;

destructor TOrePileFeatureNode.Destroy();
begin
   if (FRegion.Assigned) then
      FRegion.Unwrap().RemoveOrePile(Self);
   FDynastyKnowledge.Done();
   inherited;
end;

function TOrePileFeatureNode.GetOrePileCapacity(): TMass;
begin
   Result := FFeatureClass.FCapacityMass;
end;

procedure TOrePileFeatureNode.SetOrePileRegion(Region: TRegionFeatureNode);
begin
   Assert(not FRegion.Assigned);
   FRegion := Region;
end;

procedure TOrePileFeatureNode.RegionAdjustedOrePiles();
begin
   Assert(FRegion.Assigned);
   MarkAsDirty([dkUpdateClients]); // the mass flow rate and contents may have changed
end;

procedure TOrePileFeatureNode.DisconnectOrePile();
begin
   Assert(FRegion.Assigned);
   FRegion.Clear();
   MarkAsDirty([dkUpdateClients, dkNeedsHandleChanges]); // the mass flow rate and contents may have changed
end;

function TOrePileFeatureNode.GetDynasty(): TDynasty;
begin
   Result := Parent.Owner;
end;

function TOrePileFeatureNode.HandleBusMessage(Message: TBusMessage): THandleBusMessageResult;
begin
   if (Message is TRubbleCollectionMessage) then
   begin
      if (FRegion.Assigned) then
      begin
         FRegion.Unwrap().FlattenOrePileIntoGround(Self);
         FRegion.Clear();
         MarkAsDirty([dkUpdateClients, dkNeedsHandleChanges]);
      end;
   end
   else
   if (Message is TDismantleMessage) then
   begin
      if (not Assigned(Parent.Owner)) then
      begin
         // TODO: when we add the ability to have an ore pile hold ore separate from the region, we should
         // handle this case by moving the ore to region on behalf of the Message.Owner dynasty.
         Assert(not FRegion.Assigned);
      end
      else
      begin
         Assert((Message as TDismantleMessage).Owner = Parent.Owner);
         if (FRegion.Assigned) then
         begin
            FRegion.Unwrap().RehomeOreForPile(Self);
            FRegion.Clear();
         end
         else
         begin
            // TODO: when we add the ability to have an ore pile hold ore separate from the region, we should
            // handle this case by moving the ore to region on behalf of the Message.Owner dynasty.
         end;
      end;
      Assert(not FRegion.Assigned);
   end;
   Result := inherited;
end;

procedure TOrePileFeatureNode.HandleChanges();
var
   Message: TRegisterOrePileBusMessage;
begin
   if (Assigned(Parent.Owner) and FRegion.IsFlagClear(rfSearchedForRegion)) then
   begin
      Message := TRegisterOrePileBusMessage.Create(Self);
      InjectBusMessage(Message);
      FreeAndNil(Message);
      FRegion.SetFlag(rfSearchedForRegion);
   end;
   inherited;
end;

procedure TOrePileFeatureNode.Detaching();
begin
   if (FRegion.Assigned) then
   begin
      FRegion.Unwrap().RemoveOrePile(Self);
      FRegion.Clear();
   end;
end;

function TOrePileFeatureNode.GetMass(): TMass;
begin
   if (FRegion.Assigned) then
   begin
      Result := FRegion.Unwrap().GetOrePileMass(Self);
   end
   else
   begin
      Result := TMass.Zero;
   end;
   Assert(not Result.IsNegative);
end;

function TOrePileFeatureNode.GetMassFlowRate(): TMassRate;
begin
   if (FRegion.Assigned) then
   begin
      Result := FRegion.Unwrap().GetOrePileMassFlowRate(Self);
   end
   else
   begin
      Result := TMassRate.Zero;
   end;
end;

procedure TOrePileFeatureNode.Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter);
var
   Ores: TOreFilter;
   Ore: TOres;
   Visibility: TVisibility;
begin
   Visibility := Parent.ReadVisibilityFor(DynastyIndex);
   if ((dmDetectable * Visibility <> []) and (dmClassKnown in Visibility)) then // TODO: should probably be able to recognize special kinds of ore piles even if you didn't research them?
   begin
      Writer.WriteCardinal(fcOrePile);
      Writer.WriteDouble(Mass.AsDouble);
      Writer.WriteDouble(MassFlowRate.AsDouble);
      Writer.WriteDouble(FFeatureClass.FCapacityMass.AsDouble);
      if (FRegion.Assigned) then
      begin
         Ores := FRegion.Unwrap().GetOresPresentForPile(Self) and FDynastyKnowledge[DynastyIndex];
         for Ore in TOres do
         begin
            if (Ores[Ore]) then
            begin
               Writer.WriteCardinal(Ore);
            end;
         end;
      end;
      Writer.WriteCardinal(0);
   end;
end;

procedure TOrePileFeatureNode.ResetDynastyNotes(OldDynasties: TDynastyIndexHashTable; NewDynasties: TDynasty.TArray);
begin
   FDynastyKnowledge.Init(Length(NewDynasties)); // $R-
end;

procedure TOrePileFeatureNode.ResetVisibility();
begin
   FDynastyKnowledge.Reset();
end;

procedure TOrePileFeatureNode.HandleKnowledge(const DynastyIndex: Cardinal; const Sensors: ISensorsProvider);
begin
   {$IFOPT C+} Assert(DynastyIndex < FDynastyKnowledge.Length); {$ENDIF}
   FDynastyKnowledge.AddKnowledge(DynastyIndex, Sensors.GetOreKnowledge());
end;

procedure TOrePileFeatureNode.UpdateJournal(Journal: TJournalWriter);
begin
end;

procedure TOrePileFeatureNode.ApplyJournal(Journal: TJournalReader);
begin
end;

function TOrePileFeatureNode.HandleCommand(PlayerDynasty: TDynasty; Command: UTF8String; var Message: TMessage): Boolean;
var
   DynastyIndex: Cardinal;
   OreKnowledge: TOreFilter;
   OreQuantities: TOreQuantities;
   Ore: TOres;
   Total: TQuantity64;
begin
   if (Command = ccAnalyze) then
   begin
      Result := True;
      DynastyIndex := System.DynastyIndex[PlayerDynasty];
      // TODO: check if we have the right visibility on the ore pile to do an analysis
      if (Message.CloseInput()) then
      begin
         Message.Reply();
         if (FRegion.Assigned) then
         begin
            OreKnowledge := FRegion.Unwrap().GetOresPresentForPile(Self) and FDynastyKnowledge[DynastyIndex];
            OreQuantities := FRegion.Unwrap().GetOresForPile(Self);
            Total := TQuantity64.Zero;
            for Ore in TOres do
            begin
               Total := Total + OreQuantities[Ore];
            end;
            Message.Output.WriteInt64(System.Now.AsInt64);
            Message.Output.WriteInt64(Total.AsInt64);
            if (Total.IsZero) then
            begin
               if (FRegion.Unwrap().GetOrePileMass(Self).IsPositive) then
                  Message.Output.WriteString('not enough materials')
               else
                  Message.Output.WriteString('pile empty');
            end
            else
               Message.Output.WriteString('');
            for Ore in TOres do
            begin
               if (OreKnowledge[Ore] and (OreQuantities[Ore].IsPositive)) then
               begin
                  Message.Output.WriteLongint(Ore);
                  Message.Output.WriteInt64(OreQuantities[Ore].AsInt64);
               end;
            end;
         end;
         Message.CloseOutput();
      end;
   end
   else
      Result := False;
end;

initialization
   RegisterFeatureClass(TOrePileFeatureClass);
end.