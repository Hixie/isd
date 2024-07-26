{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit galaxy;

interface

uses
   binaries, configuration, plasticarrays, hashtable, genericutils, binarystream, astronomy;

type
   THomeSystemsFile = File of Byte;

   TSystemServerRecord = record
      StarID: TStarID;
      ServerID: Cardinal;
   end;
   
   TSystemServerFile = File of TSystemServerRecord;
   
   TGalaxyManager = class
   protected
      type
         TPosition = record
            X, Y: Cardinal;
         end;
         THomeStar = record
         strict private
            const
               OccupiedMask: Cardinal = $80000000;
            var
               FData: Cardinal;
            function GetID(): TStarID;
            procedure SetID(ID: TStarID);
            function GetOccupied(): Boolean;
            procedure SetOccupied(Value: Boolean);
         public
            DistanceSquared: Single;
            procedure Init(AID: TStarID; ADistanceSquared: Single);
            property ID: TStarID read GetID write SetID;
            property Occupied: Boolean read GetOccupied write SetOccupied;
         end;
         TStarIDUtils = record
            class function Equals(const A, B: TStarID): Boolean; static; inline;
            class function LessThan(const A, B: TStarID): Boolean; static; inline;
            class function GreaterThan(const A, B: TStarID): Boolean; static; inline;
         end;
         PExtraStars = ^TExtraStars;
         TExtraStars = array of TStarID;
         TSystemsHashTable = class(specialize THashTable<TStarID, PExtraStars, TStarIDUtils>)
           constructor Create();
         end;
         TServersHashTable = class(specialize THashTable<TStarID, Cardinal, TStarIDUtils>)
           constructor Create();
         end;
         TStarUtils = record
            class function Equals(const A, B: THomeStar): Boolean; static; inline;
            class function LessThan(const A, B: THomeStar): Boolean; static; inline;
            class function GreaterThan(const A, B: THomeStar): Boolean; static; inline;
         end;
      var
         FGalaxyData, FSystemsData: TBinaryFile;
         FSettings: PSettings;
         FHomeDatabase: THomeSystemsFile;
         FServersDatabase: TSystemServerFile;
         FCategoryStartIndices: array of Cardinal;
         FExtraStars: TSystemsHashTable;
         FServers: TServersHashTable;
         FHomeCandidates: specialize PlasticArray<THomeStar, TStarUtils>;
         FNextHomeCandidate: Cardinal;
         FMetersPerDWordUnit: Double;
      function IsStar(ID: TStarID): Boolean;
      function PositionOf(Category: TStarCategory; Index: TStarIndex): TPosition; inline;
      function PositionOf(ID: TStarID): TPosition; inline;
      function CanonicalStarOf(ID: TStarID): TStarID;
      function ExtraStarsOf(ID: TStarID): PExtraStars;
      function CountExtraStarsOf(ID: TStarID): Cardinal;
      procedure PreparseGalaxy();
      procedure PreparseSystems();
      procedure PrepareHomeCandidates();
      procedure ReloadHomeDatabase();
      procedure ReloadServersDatabase();
      procedure SaveHomeStatusFor(CandidateIndex: Cardinal);
      procedure AddServerRecord(Star: TStarID; SystemServer: Cardinal);
      function GetGalaxyDiameter(): Double;
   public
      constructor Create(AGalaxyData, ASystemsData: TBinaryFile; ASettings: PSettings; var AHomeDatabase: THomeSystemsFile; var AServersDatabase: TSystemServerFile);
      destructor Destroy(); override;
      function SelectNextHomeSystem(): TStarID; 
      procedure SerializeSystemDescription(System: TStarID; Writer: TBinaryStreamWriter);
      property GalaxyData: TBinaryFile read FGalaxyData;
      property SystemsData: TBinaryFile read FSystemsData;
      property MetersPerDWordUnit: Double read FMetersPerDWordUnit;
      property GalaxyDiameter: Double read GetGalaxyDiameter;
   end;
   
procedure OpenHomeSystemsDatabase(out F: THomeSystemsFile; Filename: UTF8String);
procedure OpenSystemServerDatabase(out F: TSystemServerFile; Filename: UTF8String);

implementation

uses
   math, arrayutils, sysutils, hashfunctions, exceptions;

const
   GalaxyDataHeaderLength = 2;

function TStarIDHash(const Value: TStarID): DWord;
begin
   Result := Integer32Hash32(DWord(Value));
end;

class function TGalaxyManager.TStarIDUtils.Equals(const A, B: TStarID): Boolean;
begin
   Result := A = B;
end;

class function TGalaxyManager.TStarIDUtils.LessThan(const A, B: TStarID): Boolean;
begin
   Result := A < B;
end;

class function TGalaxyManager.TStarIDUtils.GreaterThan(const A, B: TStarID): Boolean;
begin
   Result := A > B;
end;


constructor TGalaxyManager.TSystemsHashTable.Create();
begin
   inherited Create(@TStarIDHash);
end;

constructor TGalaxyManager.TServersHashTable.Create();
begin
   inherited Create(@TStarIDHash);
end;


procedure TGalaxyManager.THomeStar.Init(AID: TStarID; ADistanceSquared: Single);
begin
   Assert(AID >= 0);
   FData := AID; // $R-
   DistanceSquared := ADistanceSquared;
end;

function TGalaxyManager.THomeStar.GetID(): TStarID;
begin
   Result := FData and not OccupiedMask; // $R-
end;

procedure TGalaxyManager.THomeStar.SetID(ID: TStarID);
begin
   Assert(ID >= 0);
   FData := (FData and OccupiedMask) or ID; // $R-
end;

function TGalaxyManager.THomeStar.GetOccupied(): Boolean;
begin
   Result := (FData and OccupiedMask) > 0;
end;

procedure TGalaxyManager.THomeStar.SetOccupied(Value: Boolean);
begin
   if (Value) then
      FData := FData or OccupiedMask
   else
      FData := FData and not OccupiedMask;
end;


class function TGalaxyManager.TStarUtils.Equals(const A, B: THomeStar): Boolean;
begin
   Result := A.ID = B.ID;
end;

class function TGalaxyManager.TStarUtils.LessThan(const A, B: THomeStar): Boolean;
begin
   Result := A.DistanceSquared < B.DistanceSquared;
end;

class function TGalaxyManager.TStarUtils.GreaterThan(const A, B: THomeStar): Boolean;
begin
   Result := A.DistanceSquared > B.DistanceSquared;
end;


constructor TGalaxyManager.Create(AGalaxyData, ASystemsData: TBinaryFile; ASettings: PSettings; var AHomeDatabase: THomeSystemsFile; var AServersDatabase: TSystemServerFile);
begin
   inherited Create();
   FGalaxyData := AGalaxyData;
   FSystemsData := ASystemsData;
   FSettings := ASettings;
   FHomeDatabase := AHomeDatabase;
   FServersDatabase := AServersDatabase;
   FExtraStars := TSystemsHashTable.Create();
   FServers := TServersHashTable.Create();
   PreparseGalaxy();
   PreparseSystems();
   PrepareHomeCandidates();
   ReloadHomeDatabase();
   ReloadServersDatabase();
end;

destructor TGalaxyManager.Destroy;
var
   ExtraStars: PExtraStars;
begin
   for ExtraStars in FExtraStars.Values do
      Dispose(ExtraStars);
   FExtraStars.Free();
   FServers.Free();
   inherited;
end;

procedure TGalaxyManager.PreparseGalaxy();
var
   CategoryCount, Category, Index, Value: Cardinal;
begin
   CategoryCount := FGalaxyData.Cardinals[1];
   if (CategoryCount <= 0) then
      raise Exception.Create('Galaxy data has no categories.');
   SetLength(FCategoryStartIndices, CategoryCount);
   Index := GalaxyDataHeaderLength + CategoryCount; // $R-
   for Category := 0 to CategoryCount - 1 do // $R-
   begin
      FCategoryStartIndices[Category] := Index;
      Value := FGalaxyData.Cardinals[GalaxyDataHeaderLength + Category]; // $R-
      if (Value <= 0) then
         raise Exception.Create('Galaxy data has an empty category at category ' + IntToStr(Category) + '.');
      if (Value > High(TStarIndex)) then
         raise Exception.Create('Galaxy data has a category with more than ' + IntToStr(High(TStarIndex)) + ' stars (' + IntToStr(Value) + ') at category ' + IntToStr(Category) + '.');
      Inc(Index, Value * 2); // $R-
   end;
   Assert(Index * 4 = FGalaxyData.Length);
   FMetersPerDWordUnit := FSettings^.GalaxyDiameter / High(Cardinal);
end;

procedure TGalaxyManager.PreparseSystems();
var
   StarID, CanonicalStarID: TStarID;
   Index, SystemCount: Cardinal;
   ExtraStars: PExtraStars;
begin
   if (FSystemsData.Length <= 4) then
      exit;
   SystemCount := FSystemsData.Length div (SizeOf(Cardinal) * 2); // $R-
   Assert(SystemCount > 0);
   for Index := 0 to SystemCount - 1 do // $R-
   begin
      StarID := FSystemsData.Cardinals[1 + Index * 2]; // $R-
      CanonicalStarID := FSystemsData.Cardinals[1 + Index * 2 + 1]; // $R-
      ExtraStars := FExtraStars[CanonicalStarID];
      if (not Assigned(ExtraStars)) then
         New(ExtraStars);
      SetLength(ExtraStars^, Length(ExtraStars^) + 1);
      ExtraStars^[High(ExtraStars^)] := StarID;
      FExtraStars[CanonicalStarID] := ExtraStars;
   end;
end;

procedure TGalaxyManager.PrepareHomeCandidates();
var
   Category: TStarCategory;
   StarIndex: TStarIndex;
   HomeStarID, CandidateStarID: TStarID;
   CategoryCount, Count: Cardinal;
   DX, DY, DistanceSquared, MinDistanceSquared: Double;
   Star: THomeStar;
   Index: Cardinal;
   HomePosition, StarPosition: TPosition;

   function CompareDistances (const A, B: THomeStar): Integer;
   begin        
      Result := Sign(A.DistanceSquared - B.DistanceSquared);
   end;
   
begin
   CategoryCount := FGalaxyData.Cardinals[1];
   if (CategoryCount < FSettings^.HomeStarCategory) then
      raise Exception.Create('Expected at least ' + IntToStr(FSettings^.HomeStarCategory) + ' categories (based on "' + HomeStarCategorySetting + '") but galaxy only has ' + IntToStr(CategoryCount) + ' categories.');
   HomeStarID := EncodeStarID(FSettings^.HomeStarCategory, FSettings^.HomeStarIndex);
   HomePosition := PositionOf(FSettings^.HomeStarCategory, FSettings^.HomeStarIndex);
   MinDistanceSquared := FSettings^.MinimumDistanceFromHome * FSettings^.MinimumDistanceFromHome;
   FHomeCandidates.Length := (FGalaxyData.Length - (GalaxyDataHeaderLength + CategoryCount)) div 2; // $R-
   Index := 0;
   for Category in FSettings^.HomeCandidateCategories do
   begin
      if (CategoryCount < Category) then
         raise Exception.Create('Expected at least ' + IntToStr(Category) + ' categories (based on "' + HomeCandidateCategoriesSetting + '" setting) but galaxy only has ' + IntToStr(CategoryCount) + ' categories.');
      Count := FGalaxyData.Cardinals[GalaxyDataHeaderLength + Category]; // $R-
      Assert(Count > 0);
      for StarIndex := 0 to Count - 1 do // $R-
      begin
         CandidateStarID := EncodeStarID(Category, StarIndex);
         if ((CandidateStarID <> HomeStarID) and
             (CanonicalStarOf(CandidateStarID) = CandidateStarID) and
             (CountExtraStarsOf(CandidateStarID) <= FSettings^.MaxStarsPerHomeSystem)) then
         begin
            StarPosition := PositionOf(Category, StarIndex);
            DX := StarPosition.X - HomePosition.X;
            DY := StarPosition.Y - HomePosition.Y;
            DistanceSquared := DX * DX + DY * DY;
            if (DistanceSquared >= MinDistanceSquared) then
            begin
               Star.Init(EncodeStarID(Category, StarIndex), DistanceSquared); // $R-
               FHomeCandidates[Index] := Star;
               Inc(Index);
            end;
         end;
      end;
   end;
   FHomeCandidates.Length := Index;
   FHomeCandidates.Sort(@CompareDistances);
end;

procedure TGalaxyManager.ReloadHomeDatabase();
var
   Index: Cardinal;
   Data: Byte;
   Star: THomeStar;
begin
   Assert(FHomeCandidates.Length > 0);
   Seek(FHomeDatabase, 0);
   Index := 0;
   while (not EOF(FHomeDatabase)) do
   begin
      Assert(Index < FHomeCandidates.Length, 'Index reached ' + IntToStr(Index) + ' which is more than our ' + IntToStr(FHomeCandidates.Length) + ' candidates');
      BlockRead(FHomeDatabase, Data, 1); // {BOGUS Hint: Local variable "Data" does not seem to be initialized}
      if ((Data and $1) > 0) then
      begin
         Star := FHomeCandidates[Index]; // $R-
         Star.Occupied := True;
         FHomeCandidates[Index] := Star; // $R-
      end
      else
      if ((Data and $2) > 0) then
      begin
         FNextHomeCandidate := Index;
      end;
      Inc(Index);
   end;
   Assert(Index = FileSize(FHomeDatabase));
end;

procedure TGalaxyManager.ReloadServersDatabase();
var
   ServerRecord: TSystemServerRecord;
begin
   Seek(FServersDatabase, 0);
   while (not EOF(FServersDatabase)) do
   begin
      BlockRead(FServersDatabase, ServerRecord, 1); {BOGUS Hint: Local variable "ServerRecord" does not seem to be initialized}
      FServers[ServerRecord.StarID] := ServerRecord.ServerID;
   end;
end;

procedure TGalaxyManager.SaveHomeStatusFor(CandidateIndex: Cardinal);
var
   Data: Byte;
begin
   Assert(CandidateIndex < FHomeCandidates.Length);
   Seek(FHomeDatabase, CandidateIndex);
   Data := 0;
   if (FHomeCandidates[CandidateIndex].Occupied) then
      Data := Data or $1; // $R-
   if (FNextHomeCandidate = CandidateIndex) then
      Data := Data or $2; // $R-
   BlockWrite(FHomeDatabase, Data, 1);
end;

function TGalaxyManager.IsStar(ID: TStarID): Boolean;
var
   Category, StarIndex, CategoryCount, StarCount: Cardinal;
begin
   if (ID < 0) then
   begin
      Result := False;
      exit;
   end;
   Category := ID shr CategoryShift; // $R-
   StarIndex := ID and StarIndexMask; // $R-
   CategoryCount := FGalaxyData.Cardinals[1];
   if (Category >= CategoryCount) then
   begin
      Result := False;
      exit;
   end;
   StarCount := FGalaxyData.Cardinals[GalaxyDataHeaderLength + Category]; // $R-
   Result := StarIndex < StarCount;
end;

function TGalaxyManager.PositionOf(Category: TStarCategory; Index: TStarIndex): TPosition;
var
   DataIndex: Cardinal;
begin
   DataIndex := FCategoryStartIndices[Category] + Index * 2; // $R-
   Result.X := FGalaxyData.Cardinals[DataIndex];
   Result.Y := FGalaxyData.Cardinals[DataIndex + 1]; // $R-
end;

function TGalaxyManager.PositionOf(ID: TStarID): TPosition;
var
   DataIndex: Cardinal;
begin
   DataIndex := FCategoryStartIndices[ID shr CategoryShift] + (ID and StarIndexMask) * 2; // $R-
   Result.X := FGalaxyData.Cardinals[DataIndex];
   Result.Y := FGalaxyData.Cardinals[DataIndex + 1]; // $R-
end;

function TGalaxyManager.CanonicalStarOf(ID: TStarID): TStarID;

   function Search(const Index: Integer): Integer;
   begin
      Result := Sign(ID - FSystemsData.Cardinals[Index * 2]); // $R-
   end;

var
   Index: Integer;
begin
   Index := BinarySearch(0, FSystemsData.Length div (2 * SizeOf(Cardinal)), @Search); // $R-
   if ((Index < FSystemsData.Length div 2) and (FSystemsData.Cardinals[Index * 2] = ID)) then // $R-
      Result := FSystemsData.Cardinals[Index * 2 + 1] // $R-
   else
      Result := ID;
end;

function TGalaxyManager.ExtraStarsOf(ID: TStarID): PExtraStars;
begin
   Result := FExtraStars[ID];
end;

function TGalaxyManager.CountExtraStarsOf(ID: TStarID): Cardinal;
var
   ExtraStars: PExtraStars;
begin
   ExtraStars := FExtraStars[ID];
   if (not Assigned(ExtraStars)) then
   begin
      Result := 0;
   end
   else
   begin
      Result := Length(ExtraStars^); // $R-
   end;
end;

function TGalaxyManager.SelectNextHomeSystem(): TStarID;
var
   HomePosition: TPosition;
   MinDistance, MaxDistance: Double;

   function SearchMin(const Index: Integer): Integer;
   var
      Position: TPosition;
      DX, DY: Double;
   begin
      Position := PositionOf(FHomeCandidates[Index].ID); // $R-
      DX := Position.X - HomePosition.X;
      DY := Position.Y - HomePosition.Y;
      Result := Sign(Sqrt(DX * DX + DY * DY) - MinDistance);
   end;

   function SearchMax(const Index: Integer): Integer;
   var
      Position: TPosition;
      DX, DY: Double;
   begin
      Position := PositionOf(FHomeCandidates[Index].ID); // $R-
      DX := Position.X - HomePosition.X;
      DY := Position.Y - HomePosition.Y;
      Result := Sign(Sqrt(DX * DX + DY * DY) - MaxDistance);
   end;

type
   TNearbyStar = record
      CandidateIndex: Cardinal;
      DistanceSquared: Single;
   end;
   TNearbyStarUtils = specialize IncomparableUtils<TNearbyStar>;
   
   function NearbyStarsSorter(const A, B: TNearbyStar): Integer;
   begin
      Result := Sign(A.DistanceSquared - B.DistanceSquared);
   end;

var
   Min, Max, Index: Cardinal;
   CandidatePosition, NearbyPosition: TPosition;
   DX, DY: Double;
   NearbyStars: specialize PlasticArray<TNearbyStar, TNearbyStarUtils>;
   Star: THomeStar;
   NearbyStar: TNearbyStar;
begin
   Result := -1;
   HomePosition := PositionOf(FSettings^.HomeStarCategory, FSettings^.HomeStarIndex);
   while ((Result < 0) and (FNextHomeCandidate < FHomeCandidates.Length)) do
   begin
      if (not FHomeCandidates[FNextHomeCandidate].Occupied) then
      begin
         CandidatePosition := PositionOf(FHomeCandidates[FNextHomeCandidate].ID);
         DX := HomePosition.X - CandidatePosition.X;
         DY := HomePosition.Y - CandidatePosition.Y;
         MinDistance := Sqrt(DX * DX + DY * DY) - FSettings^.LocalSpaceRadius;
         MaxDistance := Sqrt(DX * DX + DY * DY) + FSettings^.LocalSpaceRadius;
         Assert(MinDistance < MaxDistance);
         Min := BinarySearch(0, FHomeCandidates.Length, @SearchMin); // $R-
         Max := BinarySearch(Min, FHomeCandidates.Length, @SearchMax); // $R-
         Assert(Min <= Max);
         if (Min <= Max - FSettings^.MaxStarsPerHomeSystem) then
         begin
            NearbyStars.Init();
            for Index := Min to Max - 1 do // $R-
            begin
               if ((Index <> FNextHomeCandidate) and (not FHomeCandidates[Index].Occupied)) then
               begin
                  NearbyPosition := PositionOf(FHomeCandidates[Index].ID);
                  if ((NearbyPosition.X > CandidatePosition.X - FSettings^.LocalSpaceRadius) and
                      (NearbyPosition.X < CandidatePosition.X + FSettings^.LocalSpaceRadius) and
                      (NearbyPosition.X > CandidatePosition.Y - FSettings^.LocalSpaceRadius) and
                      (NearbyPosition.Y < CandidatePosition.Y + FSettings^.LocalSpaceRadius)) then
                  begin
                     NearbyStar.CandidateIndex := Index;
                     DX := NearbyPosition.X - CandidatePosition.X;
                     DY := NearbyPosition.Y - CandidatePosition.Y;
                     NearbyStar.DistanceSquared := DX * DX + DY * DY; // $R-
                     NearbyStars.Push(NearbyStar);
                  end;
               end;
            end;
            if (NearbyStars.Length >= FSettings^.MaxStarsPerHomeSystem) then
            begin
               NearbyStars.Sort(@NearbyStarsSorter);
               Star := FHomeCandidates[FNextHomeCandidate];
               Star.Occupied := True;
               FHomeCandidates[FNextHomeCandidate] := Star;
               SaveHomeStatusFor(FNextHomeCandidate);
               for Index := 0 to FSettings^.MaxStarsPerHomeSystem - 1 do // $R-
               begin
                  Star := FHomeCandidates[NearbyStars[Index].CandidateIndex];
                  Star.Occupied := True;
                  FHomeCandidates[NearbyStars[Index].CandidateIndex] := Star;
                  SaveHomeStatusFor(NearbyStars[Index].CandidateIndex);
               end;
               Result := FHomeCandidates[FNextHomeCandidate].ID;
            end;
         end;
      end;
      Inc(FNextHomeCandidate);
      SaveHomeStatusFor(FNextHomeCandidate);
   end;
end;

procedure TGalaxyManager.AddServerRecord(Star: TStarID; SystemServer: Cardinal);
var
   Data: TSystemServerRecord; {BOGUS Note: Local variable "Data" is assigned but never used}
begin
   Seek(FServersDatabase, FileSize(FServersDatabase));
   Data.StarID := Star;
   Data.ServerID := SystemServer;
   BlockWrite(FServersDatabase, Data, 1);
   FServers[Star] := SystemServer;
end;

procedure TGalaxyManager.SerializeSystemDescription(System: TStarID; Writer: TBinaryStreamWriter);
var
   CenterPosition: TPosition;

   procedure SerializeStar(Star: TStarID);
   var
      StarPosition: TPosition;
   begin
      Assert(Star >= 0);
      Writer.WriteCardinal(Star); // $R-
      StarPosition := PositionOf(Star);
      Writer.WriteDouble((StarPosition.X - CenterPosition.X) * MetersPerDWordUnit);
      Writer.WriteDouble((StarPosition.Y - CenterPosition.Y) * MetersPerDWordUnit);
   end;

var
   Index, ExtraStarCount: Cardinal;
   ExtraStars: PExtraStars;
begin
   Assert(System >= 0);
   Writer.WriteCardinal(System); // $R-
   if (IsStar(System) and (System = CanonicalStarOf(System))) then
   begin
      CenterPosition := PositionOf(System);
      Writer.WriteDouble(CenterPosition.X * MetersPerDWordUnit);
      Writer.WriteDouble(CenterPosition.Y * MetersPerDWordUnit);
      ExtraStarCount := CountExtraStarsOf(System);
      Writer.WriteCardinal(1 + ExtraStarCount); // $R-
      SerializeStar(System);
      if (ExtraStarCount > 0) then
      begin
         ExtraStars := ExtraStarsOf(System);
         Assert(Assigned(ExtraStars));
         for Index := 0 to ExtraStarCount-1 do // $R-
         begin
            SerializeStar(ExtraStars^[Index]);
         end;
      end;
   end
   else
   begin
      XXX;
   end;
end;

function TGalaxyManager.GetGalaxyDiameter(): Double;
begin
   Result := FSettings^.GalaxyDiameter;
end;

procedure OpenHomeSystemsDatabase(out F: THomeSystemsFile; Filename: UTF8String);
begin
   Assign(F, Filename);
   FileMode := 2;
   if (not FileExists(Filename)) then
   begin
      Rewrite(F);
   end
   else
   begin
      Reset(F);
   end;
end;

procedure OpenSystemServerDatabase(out F: TSystemServerFile; Filename: UTF8String);
begin
   Assign(F, Filename);
   FileMode := 2;
   if (not FileExists(Filename)) then
   begin
      Rewrite(F);
   end
   else
   begin
      Reset(F);
   end;
end;

end.