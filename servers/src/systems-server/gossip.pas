{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit gossip;

interface

uses
   systems, materials, time, hashtable, serverstream, internals;

type
   TGossipKind = (gkCrash);
   
const
   GossipMessage: array[TGossipKind] of UTF8String = (
     'Experienced a crash'
   );

type
   TGossipFlag = (gfUpdateJournal);
   TGossipFlags = set of TGossipFlag;
   {$IF SIZEOF(TGossipFlags) <> SIZEOF(Cardinal)} {$FATAL} {$ENDIF}

   PGossip = ^TGossip;
   TGossip = record
      Timestamp: TTimeInMilliseconds;
      Duration: TMillisecondsDuration;
      HappinessImpact: Double; // per person
      PopulationAnchorTime: TTimeInMilliseconds; // time that AffectedPeople was last updated
      SpreadRate: TGrowthRate;
      AffectedPeople: Cardinal;
      Flags: TGossipFlags;
      function ComputeActualPeople(TotalPopulation: Cardinal; Now: TTimeInMilliseconds): Cardinal;
      function ComputeHappinessContribution(TotalPopulation: Cardinal; Now: TTimeInMilliseconds): Double;
      function GetTimeUntilNextEvent(Now: TTimeInMilliseconds): TMillisecondsDuration; inline;
      function IsValid(Now: TTimeInMilliseconds): Boolean;
   end;

   TGossipIdentifier = record
   private
      class function Hash32(const Value: TGossipIdentifier): DWord; static; inline;
   public
      Source: TAssetNode; // could be nil, if the asset is out-system
      Kind: TGossipKind; // value scoped to the asset class
      // when moving gossip out of a system, gossips with the same Kind but different Sources get merged in some way that minimizes abuse potential
      function Anonymize(): TGossipIdentifier;
   end;

   TSpreadGossipBusMessage = class(TPhysicalConnectionBusMessage)
   private
      FGossip: TGossip;
      FIdentifier: TGossipIdentifier;
      function GetGossip(): PGossip; inline;
      function GetSpread(): Boolean; inline;
   public
      // If the gossip's AffectedPeople is zero, then it is implied that it affects everyone and spreads to all population centers.
      // Otherwise, it affects the specified number of people and does not spread.
      // It is an error for the AffectedPeople to be non-zero and less than the receiving population center's population.
      constructor Create(AGossip: TGossip; AIdentifier: TGossipIdentifier);
      property Gossip: PGossip read GetGossip;
      property Identifier: TGossipIdentifier read FIdentifier;
      property Spread: Boolean read GetSpread;
   end;

   TGossipIdentifierUtils = record
      class function Equals(const A, B: TGossipIdentifier): Boolean; static; inline;
      class function LessThan(const A, B: TGossipIdentifier): Boolean; static; inline;
      class function GreaterThan(const A, B: TGossipIdentifier): Boolean; static; inline;
      class function Compare(const A, B: TGossipIdentifier): Int64; static; inline;
   end;

   TGossipHashTable = record
   strict private
      type
         TInternalHashTable = specialize THashTable<TGossipIdentifier, TGossip, TGossipIdentifierUtils>;
      var
         FHashTable: TInternalHashTable;
      function GetItems(const Index: TGossipIdentifier): PGossip; inline;
      function GetAllocated(): Boolean; inline;
      class operator Initialize(var Rec: TGossipHashTable);
   public
      procedure Allocate(); // sets Allocated to true
      procedure Free(); // sets Allocated to false (this is a no-op if Allocated is false)
      procedure Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter; Now: TTimeInMilliseconds);
      procedure UpdateJournal(Journal: TJournalWriter; Now: TTimeInMilliseconds);
      procedure ApplyJournal(Journal: TJournalReader; ASystem: TSystem); // will call Allocate if necessary
      function HandleAssetGoingAway(Asset: TAssetNode; TotalPopulation: Cardinal; Now: TTimeInMilliseconds): Boolean; // returns true if anything changed
      function ComputeHappinessContribution(TotalPopulation: Cardinal; Now: TTimeInMilliseconds): Double;
      function GetTimeUntilNextEvent(Now: TTimeInMilliseconds): TMillisecondsDuration;
      property Allocated: Boolean read GetAllocated;
   public // these are only valid if Allocated
      procedure AddNewGossip(const Source: TGossipIdentifier; const Gossip: TGossip; TotalPopulation: Cardinal); // Gossip.Timestamp must be Now
      procedure AddOldGossip(const Source: TGossipIdentifier; const Gossip: TGossip; AffectedPeople: Cardinal; Now: TTimeInMilliseconds);
      function IsEmpty(Now: TTimeInMilliseconds): Boolean;
   public
      class procedure MoveGossip(Source, Target: TGossipHashTable; SourcePeopleCount, TransferPeopleCount: Cardinal; Now: TTimeInMilliseconds); static;
      function Extract(): TGossipHashTable;
   end;
   
implementation

uses
   sysutils, hashfunctions, math, plasticarrays, genericutils, typedump, exceptions;

function Decay(T: Double): Double;
begin // inverse smoothstep with edges 0 and 1
   Result := 1 - T * T * (3.0 - 2.0 * T);
end;

function TGossip.ComputeActualPeople(TotalPopulation: Cardinal; Now: TTimeInMilliseconds): Cardinal;
var
   SpreadTime: TMillisecondsDuration;
begin
   SpreadTime := Now - PopulationAnchorTime;
   Result := Min(AffectedPeople * SpreadRate ** SpreadTime, TotalPopulation); // $R-
end;

function TGossip.ComputeHappinessContribution(TotalPopulation: Cardinal; Now: TTimeInMilliseconds): Double;
var
   Age: TMillisecondsDuration;
   ActualImpact: Double;
   ActualPeople: Cardinal;
begin
   Age := Now - Timestamp;
   if (Age > Duration) then
   begin
      Result := 0.0;
      exit;
   end;
   ActualImpact := HappinessImpact * Decay(Age / Duration);
   ActualPeople := ComputeActualPeople(TotalPopulation, Now);
   Result := ActualImpact * ActualPeople;
end;

function TGossip.GetTimeUntilNextEvent(Now: TTimeInMilliseconds): TMillisecondsDuration;
begin
   Result := Now - Timestamp + Duration;
end;

function TGossip.IsValid(Now: TTimeInMilliseconds): Boolean;
begin
   Result := (HappinessImpact <> 0.0) and (AffectedPeople > 0) and (Now - Timestamp < Duration);
end;


class function TGossipIdentifier.Hash32(const Value: TGossipIdentifier): DWord;
begin
   Result := PointerHash32(Value.Source) xor Integer32Hash32(Cardinal(Value.Kind));
end;

function TGossipIdentifier.Anonymize(): TGossipIdentifier;
begin
   Result.Source := nil;
   Result.Kind := Kind;
end;

      
constructor TSpreadGossipBusMessage.Create(AGossip: TGossip; AIdentifier: TGossipIdentifier);
begin
   inherited Create();
   FGossip := AGossip;
   FIdentifier := AIdentifier;
end;

function TSpreadGossipBusMessage.GetGossip(): PGossip;
begin
   Result := @FGossip;
end;

function TSpreadGossipBusMessage.GetSpread(): Boolean;
begin
   Result := FGossip.AffectedPeople = 0;
end;


class function TGossipIdentifierUtils.Equals(const A, B: TGossipIdentifier): Boolean;
begin
   Result := (A.Source = B.Source) and (A.Kind = B.Kind);
end;

class function TGossipIdentifierUtils.LessThan(const A, B: TGossipIdentifier): Boolean;
begin
   raise Exception.Create('Gossip identifiers cannot be compared relatively.');
   Result := False;
end;

class function TGossipIdentifierUtils.GreaterThan(const A, B: TGossipIdentifier): Boolean;
begin
   raise Exception.Create('Gossip identifiers cannot be compared relatively.');
   Result := False;
end;

class function TGossipIdentifierUtils.Compare(const A, B: TGossipIdentifier): Int64;
begin
   raise Exception.Create('Gossip identifiers cannot be compared relatively.');
   Result := 0;
end;


class operator TGossipHashTable.Initialize(var Rec: TGossipHashTable);
begin
   Rec.FHashTable := nil;
end;

procedure TGossipHashTable.Allocate();
begin
   FHashTable := specialize THashTable<TGossipIdentifier, TGossip, TGossipIdentifierUtils>.Create(@TGossipIdentifier.Hash32);
end;

procedure TGossipHashTable.Free();
begin
   FreeAndNil(FHashTable);
end;

function TGossipHashTable.GetAllocated(): Boolean;
begin
   Result := Assigned(FHashTable);
end;

function TGossipHashTable.GetItems(const Index: TGossipIdentifier): PGossip;
begin
   Result := FHashTable.ItemsPtr[Index];
end;

procedure TGossipHashTable.AddNewGossip(const Source: TGossipIdentifier; const Gossip: TGossip; TotalPopulation: Cardinal);
var
   NewGossip: PGossip;
begin
   Assert(Allocated);
   NewGossip := FHashTable.AddDefault(Source);
   NewGossip^.Timestamp := Gossip.Timestamp;
   NewGossip^.Duration := Gossip.Duration;
   NewGossip^.HappinessImpact := Gossip.HappinessImpact;
   NewGossip^.PopulationAnchorTime := Gossip.PopulationAnchorTime;
   Assert(Gossip.PopulationAnchorTime = Gossip.Timestamp); // = Now
   NewGossip^.SpreadRate := Gossip.SpreadRate;
   if (Gossip.AffectedPeople = 0) then
   begin
      NewGossip^.AffectedPeople := TotalPopulation;
   end
   else
   begin
      Assert(Gossip.AffectedPeople <= TotalPopulation);
      NewGossip^.AffectedPeople := Gossip.AffectedPeople;
   end;
   NewGossip^.Flags := Gossip.Flags + [gfUpdateJournal];
   Assert(NewGossip^.IsValid(NewGossip^.Timestamp));
end;

procedure TGossipHashTable.AddOldGossip(const Source: TGossipIdentifier; const Gossip: TGossip; AffectedPeople: Cardinal; Now: TTimeInMilliseconds);
var
   NewGossip: PGossip;
begin
   Assert(Allocated);
   NewGossip := FHashTable.AddDefault(Source);
   NewGossip^.Timestamp := Gossip.Timestamp;
   NewGossip^.Duration := Gossip.Duration;
   NewGossip^.HappinessImpact := Gossip.HappinessImpact;
   NewGossip^.PopulationAnchorTime := Now;
   NewGossip^.SpreadRate := Gossip.SpreadRate;
   NewGossip^.AffectedPeople := AffectedPeople;
   NewGossip^.Flags := Gossip.Flags + [gfUpdateJournal];
   Assert(NewGossip^.IsValid(Now));
end;

function TGossipHashTable.HandleAssetGoingAway(Asset: TAssetNode; TotalPopulation: Cardinal; Now: TTimeInMilliseconds): Boolean; // returns true if anything changed
var
   NewTimestamp: TTimeInMilliseconds;
   VictimGossip, AnonymousGossip: PGossip;
   Identifier, Alternate: TGossipIdentifier;
   Victims: specialize PlasticArray<TGossipIdentifier, specialize IncomparableUtils<TGossipIdentifier>>;
   People1, People2: Cardinal;
begin
   Result := False;
   if (Allocated) then
   begin
      for Identifier in FHashTable do
         if (Identifier.Source = Asset) then
            Victims.Push(Identifier);
      for Identifier in Victims do
      begin
         VictimGossip := FHashTable.ItemsPtr[Identifier];
         if (VictimGossip^.IsValid(Now)) then
         begin
            Alternate := Identifier.Anonymize();
            if (FHashTable.Has(Alternate)) then
            begin
               AnonymousGossip := FHashTable.ItemsPtr[Alternate];
               NewTimestamp := Min(AnonymousGossip^.Timestamp, VictimGossip^.Timestamp);
               AnonymousGossip^.Duration := Max(AnonymousGossip^.Timestamp + AnonymousGossip^.Duration, VictimGossip^.Timestamp + VictimGossip^.Duration) - NewTimestamp;
               AnonymousGossip^.Timestamp := NewTimestamp;
               People1 := AnonymousGossip^.ComputeActualPeople(TotalPopulation, Now);
               People2 := VictimGossip^.ComputeActualPeople(TotalPopulation, Now);
               AnonymousGossip^.HappinessImpact := (AnonymousGossip^.HappinessImpact * People1 + VictimGossip^.HappinessImpact * People2) / (People1 + People2);
               AnonymousGossip^.SpreadRate := Max(AnonymousGossip^.SpreadRate, VictimGossip^.SpreadRate);
               AnonymousGossip^.AffectedPeople := Min(People1 + People2, TotalPopulation); // $R-
               AnonymousGossip^.PopulationAnchorTime := Now;
               AnonymousGossip^.Flags := VictimGossip^.Flags + AnonymousGossip^.Flags + [gfUpdateJournal];
               Assert(AnonymousGossip^.IsValid(Now));
            end
            else
            begin
               FHashTable.Add(Alternate, VictimGossip^);
            end;
            VictimGossip^.AffectedPeople := 0;
            Include(VictimGossip^.Flags, gfUpdateJournal);
            Assert(not VictimGossip^.IsValid(Now));
            Result := True;
         end;
      end;
   end;
end;

function TGossipHashTable.ComputeHappinessContribution(TotalPopulation: Cardinal; Now: TTimeInMilliseconds): Double;
var
   Gossip: PGossip;
begin
   Result := 0.0;
   if (Allocated) then
      for Gossip in FHashTable.ValuePtrs do
         Result := Result + Gossip^.ComputeHappinessContribution(TotalPopulation, Now);
end;

function TGossipHashTable.GetTimeUntilNextEvent(Now: TTimeInMilliseconds): TMillisecondsDuration;
var
   Gossip: PGossip;
   Candidate: TMillisecondsDuration;
begin
   Result := TMillisecondsDuration.Infinity;
   if (Allocated) then
      for Gossip in FHashTable.ValuePtrs do
      begin
         Candidate := Gossip^.GetTimeUntilNextEvent(Now);
         if (Candidate < Result) then
            Result := Candidate;
      end;
end;

procedure TGossipHashTable.Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter; Now: TTimeInMilliseconds);
var
   Gossip: PGossip;
   Identifier: TGossipIdentifier;
begin
   if (Allocated) then
      for Identifier in FHashTable do
      begin
         Gossip := FHashTable.ItemsPtr[Identifier];
         Assert(Gossip^.Timestamp <= Now);
         if (Gossip^.IsValid(Now)) then
         begin
            Writer.WriteStringReference(GossipMessage[Identifier.Kind]);
            if (Assigned(Identifier.Source) and Identifier.Source.IsVisibleFor(DynastyIndex)) then
            begin
               Writer.WriteCardinal(Identifier.Source.ID(DynastyIndex));
            end
            else
            begin
               Writer.WriteCardinal(0);
            end;
            Writer.WriteInt64(Gossip^.Timestamp.AsInt64);
            Writer.WriteDouble(Gossip^.HappinessImpact);
            Assert(not Gossip^.Duration.IsNegative);
            Writer.WriteInt64(Gossip^.Duration.AsInt64);
            Writer.WriteInt64(Gossip^.PopulationAnchorTime.AsInt64);
            Writer.WriteCardinal(Gossip^.AffectedPeople);
            Writer.WriteDouble(Gossip^.SpreadRate.AsDouble);
         end;
      end;
   Writer.WriteCardinal(0);
end;

const
   EndGossip = $00;
   ActiveGossip = $01;
   ObsoleteGossip = $02;

procedure TGossipHashTable.UpdateJournal(Journal: TJournalWriter; Now: TTimeInMilliseconds);
var
   Gossip: PGossip;
   Identifier: TGossipIdentifier;
   Enumerator: TInternalHashTable.TValuePtrEnumerator;
begin
   if (Allocated) then
      try
         Enumerator := FHashTable.ValuePtrs;
         while (Enumerator.MoveNext()) do
         begin
            Identifier := Enumerator.CurrentKey;
            Gossip := Enumerator.Current;
            if (not Gossip^.IsValid(Now)) then
            begin
               // mark that we're dropping it
               Journal.WriteByte(ObsoleteGossip);
               Journal.WriteAssetNodeReference(Identifier.Source);
               Journal.WriteCardinal(Cardinal(Identifier.Kind));
               Enumerator.RemoveCurrent();
            end
            else
            if (gfUpdateJournal in Gossip^.Flags) then
            begin
               Exclude(Gossip^.Flags, gfUpdateJournal);
               Journal.WriteByte(ActiveGossip);
               Journal.WriteAssetNodeReference(Identifier.Source);
               Journal.WriteCardinal(Cardinal(Identifier.Kind));
               Journal.WriteInt64(Gossip^.Timestamp.AsInt64);
               Journal.WriteInt64(Gossip^.Duration.AsInt64);
               Journal.WriteDouble(Gossip^.HappinessImpact);
               Journal.WriteInt64(Gossip^.PopulationAnchorTime.AsInt64);
               Journal.WriteDouble(Gossip^.SpreadRate.AsDouble);
               Journal.WriteCardinal(Gossip^.AffectedPeople);
               Assert(SizeOf(Gossip^.Flags) = SizeOf(Cardinal));
               Journal.WriteCardinal(Cardinal(Gossip^.Flags));
            end;
         end;
      finally
         FreeAndNil(Enumerator);
      end;
   Journal.WriteByte(EndGossip);
end;

procedure TGossipHashTable.ApplyJournal(Journal: TJournalReader; ASystem: TSystem);
var
   Kind: Byte;
   Gossip: PGossip;
   Identifier: TGossipIdentifier;
begin
   repeat
      Kind := Journal.ReadByte();
      if ((not Allocated) and (Kind <> EndGossip)) then
         Allocate();
      case (Kind) of
         ActiveGossip: begin
            Identifier.Source := Journal.ReadAssetNodeReference(ASystem);
            Identifier.Kind := TGossipKind(Journal.ReadCardinal());
            Gossip := FHashTable.GetOrAddPtr(Identifier);
            Gossip^.Timestamp := TTimeInMilliseconds.FromMilliseconds(Journal.ReadInt64());
            Gossip^.Duration := TMillisecondsDuration.FromMilliseconds(Journal.ReadInt64());
            Gossip^.HappinessImpact := Journal.ReadDouble();
            Gossip^.PopulationAnchorTime := TTimeInMilliseconds.FromMilliseconds(Journal.ReadInt64());
            Gossip^.SpreadRate := TGrowthRate.FromEachMillisecond(Journal.ReadDouble());
            Gossip^.AffectedPeople := Journal.ReadCardinal();
            Assert(SizeOf(Gossip^.Flags) = SizeOf(Cardinal));
            Gossip^.Flags := TGossipFlags(Journal.ReadCardinal());
         end;
         ObsoleteGossip: begin
            Identifier.Source := Journal.ReadAssetNodeReference(ASystem);
            Identifier.Kind := TGossipKind(Journal.ReadCardinal());
            FHashTable.Remove(Identifier);
         end;
      end;
   until Kind = EndGossip;
end;

function TGossipHashTable.IsEmpty(Now: TTimeInMilliseconds): Boolean;
var
   Gossip: PGossip;
begin
   Assert(Allocated);
   Result := True;
   for Gossip in FHashTable.ValuePtrs do
   begin
      if (Gossip^.IsValid(Now)) then
      begin
         Result := False;
         exit;
      end;
   end;
end;

class procedure TGossipHashTable.MoveGossip(Source, Target: TGossipHashTable; SourcePeopleCount, TransferPeopleCount: Cardinal; Now: TTimeInMilliseconds);
var
   SourceGossip: PGossip;
   Identifier: TGossipIdentifier;
   Enumerator: TInternalHashTable.TValuePtrEnumerator;
   ActualPeople: Cardinal;
   ActualMovedPeople: Cardinal;
begin
   Assert(Source.Allocated);
   Assert(Target.Allocated);
   Assert(Assigned(Source.FHashTable));
   Assert(Assigned(Target.FHashTable));
   try
      Enumerator := Source.FHashTable.ValuePtrs;
      while (Enumerator.MoveNext()) do
      begin
         Identifier := Enumerator.CurrentKey;
         SourceGossip := Enumerator.Current;
         if (SourceGossip^.IsValid(Now)) then
         begin
            ActualPeople := SourceGossip^.ComputeActualPeople(SourcePeopleCount, Now);
            Assert(ActualPeople > 0);
            if (ActualPeople > TransferPeopleCount) then
            begin
               ActualMovedPeople := TransferPeopleCount;
            end
            else
            begin
               ActualMovedPeople := ActualPeople;
            end;
            Assert(ActualPeople >= ActualMovedPeople);
            SourceGossip^.AffectedPeople := ActualPeople - ActualMovedPeople; // $R-
            SourceGossip^.PopulationAnchorTime := Now;
            Include(SourceGossip^.Flags, gfUpdateJournal);
            Target.AddOldGossip(Identifier, SourceGossip^, ActualMovedPeople, Now);
         end;
      end;
   finally
      FreeAndNil(Enumerator);
   end;
end;

function TGossipHashTable.Extract(): TGossipHashTable;
begin
   Result.FHashTable := FHashTable;
   FHashTable := nil;
end;
   
end.