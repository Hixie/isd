{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit pile;

interface

uses
   basenetwork, systems, serverstream, materials, techtree,
   messageport, region, time;

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
      FCapacityMass: Double; // max kg storage
   strict protected
      function GetFeatureNodeClass(): FeatureNodeReference; override;
   public
      constructor CreateFromTechnologyTree(Reader: TTechTreeReader); override;
      function InitFeatureNode(): TFeatureNode; override;
   end;
   
   TOrePileFeatureNode = class(TFeatureNode, IOrePile)
   strict private
      FFeatureClass: TOrePileFeatureClass;
      FDynastyKnowledge: TOreMaterialKnowledgePackage; // per dynasty bits for each ore
      FRegion: TRegionFeatureNode;
   private // IPile
      function GetOrePileCapacity(): Double; // kg
      procedure StartOrePile(Region: TRegionFeatureNode);
      procedure StopOrePile();
   protected
      constructor CreateFromJournal(Journal: TJournalReader; AFeatureClass: TFeatureClass; ASystem: TSystem); override;
      function GetMass(): Double; override;
      function GetMassFlowRate(): TRate; override;
      procedure HandleChanges(CachedSystem: TSystem); override;
      procedure Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter; CachedSystem: TSystem); override;
      procedure ResetDynastyNotes(OldDynasties: TDynastyIndexHashTable; NewDynasties: TDynastyHashSet; CachedSystem: TSystem); override;
      procedure HandleVisibility(const DynastyIndex: Cardinal; var Visibility: TVisibility; const Sensors: ISensorsProvider; const VisibilityHelper: TVisibilityHelper); override;
   public
      constructor Create(AFeatureClass: TOrePileFeatureClass);
      destructor Destroy(); override;
      procedure UpdateJournal(Journal: TJournalWriter; CachedSystem: TSystem); override;
      procedure ApplyJournal(Journal: TJournalReader; CachedSystem: TSystem); override;
   end;

// TODO: handle our ancestor chain changing

implementation

uses
   exceptions, sysutils, knowledge, messages, isdprotocol;

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
      if (Reader.Tokens.IsComma()) then
         Reader.Tokens.ReadComma();
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
   until not Reader.Tokens.IsComma();
   if (not SeenMaxMass) then
      Reader.Tokens.Error('Expected "max mass" parameter', []);
end;

function TOrePileFeatureClass.GetFeatureNodeClass(): FeatureNodeReference;
begin
   Result := TOrePileFeatureNode;
end;

function TOrePileFeatureClass.InitFeatureNode(): TFeatureNode;
begin
   Result := TOrePileFeatureNode.Create(Self);
end;


constructor TOrePileFeatureNode.Create(AFeatureClass: TOrePileFeatureClass);
begin
   inherited Create();
   FFeatureClass := AFeatureClass;
end;

constructor TOrePileFeatureNode.CreateFromJournal(Journal: TJournalReader; AFeatureClass: TFeatureClass; ASystem: TSystem);
begin
   inherited CreateFromJournal(Journal, AFeatureClass, ASystem);
   Assert(Assigned(AFeatureClass));
   FFeatureClass := AFeatureClass as TOrePileFeatureClass;
end;

destructor TOrePileFeatureNode.Destroy();
begin
   FDynastyKnowledge.Done();
   inherited;
end;

function TOrePileFeatureNode.GetOrePileCapacity(): Double; // kg
begin
   Result := FFeatureClass.FCapacityMass;
end;

procedure TOrePileFeatureNode.StartOrePile(Region: TRegionFeatureNode);
begin
   Writeln('StartOrePile(', Region.Parent.DebugName, ')');
   Assert(not Assigned(FRegion));
   FRegion := Region;
   MarkAsDirty([dkUpdateClients, dkUpdateJournal]);
end;

procedure TOrePileFeatureNode.StopOrePile();
begin
   Writeln('StopOrePile(', FRegion.Parent.DebugName, ')');
   Assert(Assigned(FRegion));
   FRegion := nil;
   MarkAsDirty([dkUpdateClients, dkUpdateJournal, dkNeedsHandleChanges]);
end;

procedure TOrePileFeatureNode.HandleChanges(CachedSystem: TSystem);
var
   Message: TRegisterOrePileBusMessage;
begin
   if (not Assigned(FRegion)) then
   begin
      Message := TRegisterOrePileBusMessage.Create(Self);
      InjectBusMessage(Message); // TODO: report if we found a region
      FreeAndNil(Message);
   end;
   inherited;
end;

function TOrePileFeatureNode.GetMass(): Double;
begin
   if (Assigned(FRegion)) then
   begin
      Result := FRegion.GetOrePileMass(Self);
   end
   else
   begin
      Result := 0.0;
   end;
   Assert(Result >= 0.0);
end;

function TOrePileFeatureNode.GetMassFlowRate(): TRate;
begin
   if (Assigned(FRegion)) then
   begin
      Result := FRegion.GetOrePileMassFlowRate(Self);
   end
   else
   begin
      Result := TRate.FromPerMillisecond(0.0);
   end;
end;

procedure TOrePileFeatureNode.Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter; CachedSystem: TSystem);
var
   Ores: TOreFilter;
   Ore: TOres;
   Visibility: TVisibility;
begin
   Visibility := Parent.ReadVisibilityFor(DynastyIndex, CachedSystem);
   if ((dmDetectable * Visibility <> []) and (dmClassKnown in Visibility)) then // TODO: should probably be able to recognize special kinds of ore piles even if you didn't research them?
   begin
      Writer.WriteCardinal(fcOrePile);
      Writer.WriteDouble(Mass);
      Writer.WriteDouble(MassFlowRate.AsDouble);
      Writer.WriteDouble(FFeatureClass.FCapacityMass);
      if (Assigned(FRegion)) then
      begin
         Ores := FRegion.GetOresPresent() and FDynastyKnowledge[DynastyIndex];
         for Ore in TOres do
         begin
            if (Ores[Ore]) then
               Writer.WriteCardinal(Ore);
         end;
      end;
      Writer.WriteCardinal(0);
   end;
end;

procedure TOrePileFeatureNode.ResetDynastyNotes(OldDynasties: TDynastyIndexHashTable; NewDynasties: TDynastyHashSet; CachedSystem: TSystem);
begin
   FDynastyKnowledge.Init(NewDynasties.Count);
end;

procedure TOrePileFeatureNode.HandleVisibility(const DynastyIndex: Cardinal; var Visibility: TVisibility; const Sensors: ISensorsProvider; const VisibilityHelper: TVisibilityHelper);
begin
   {$IFOPT C+} Assert(DynastyIndex < FDynastyKnowledge.Length); {$ENDIF}
   FDynastyKnowledge.AddKnowledge(DynastyIndex, Sensors.GetOreKnowledge());
end;

procedure TOrePileFeatureNode.UpdateJournal(Journal: TJournalWriter; CachedSystem: TSystem);
begin
end;

procedure TOrePileFeatureNode.ApplyJournal(Journal: TJournalReader; CachedSystem: TSystem);
begin
end;

initialization
   RegisterFeatureClass(TOrePileFeatureClass);
end.