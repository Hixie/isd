{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit users;

interface

uses
   logindynasty, hashtable, stringutils, genericutils, plasticarrays, hashfunctions;

type
   TDynastyHashTable = class(specialize THashTable<UTF8String, TDynasty, UTF8StringUtils>)
      constructor Create(PredictedCount: THashTableSizeInt = 8);
   end;

   TDynastyServerHashTable = class(specialize THashTable<UTF8String, Cardinal, UTF8StringUtils>)
      constructor Create();
   end;

   TUserDatabase = class
   protected
      const
         MinPasswordLength = 6;
         TemporaryUsernameMarker = #$10; // ASCII DLE
      var
         FAccountsByUsername: TDynastyHashTable;
         FAccounts: specialize PlasticArray<TDynasty, TObjectUtils>;
         NextID: Cardinal;
         FDatabase: File of TDynastyRecord;
      procedure Save(Dynasty: TDynasty);
      function GetDynasties(): TDynastyHashTable.TValueEnumerator; inline;
      function GetDynastyCount(): Cardinal; inline;
   public
      constructor Create(var ADatabase: File);
      destructor Destroy(); override;
      function CreateNewAccount(Password: UTF8String; DynastyServer: Cardinal): TDynasty;
      function GetAccount(Username: UTF8String; Password: UTF8String): TDynasty;
      function GetAccount(DynastyID: Cardinal): TDynasty;
      procedure ChangeUsername(Dynasty: TDynasty; Username: UTF8String);
      procedure ChangePassword(Dynasty: TDynasty; Password: UTF8String);
      function UsernameAdequate(Username: UTF8String): Boolean;
      class function PasswordAdequate(Password: UTF8String): Boolean;
      procedure RegisterScoreUpdate(const DynastyID: Cardinal; const Score: Double);
      property Dynasties: TDynastyHashTable.TValueEnumerator read GetDynasties;
      property DynastyCount: Cardinal read GetDynastyCount;
   end;

type
   TDynastyFile = File of TDynastyRecord;

procedure OpenUserDatabase(out F: TDynastyFile; Filename: UTF8String);

implementation

uses fphashutils, sysutils;

constructor TDynastyHashTable.Create(PredictedCount: THashTableSizeInt = 8);
begin
   if (PredictedCount = 0) then
      PredictedCount := 8;
   inherited Create(@UTF8StringHash32, PredictedCount);
end;

constructor TDynastyServerHashTable.Create();
begin
   inherited Create(@UTF8StringHash32);
end;


constructor TUserDatabase.Create(var ADatabase: File);
var
   Dynasty: TDynasty;
   DynastyRecord: TDynastyRecord;
   Count: Cardinal;
begin
   inherited Create();
   FDatabase := ADatabase;
   Count := FileSize(FDatabase); // $R-
   if (Count > 0) then
      FAccounts.Prepare(Count);
   FAccountsByUsername := TDynastyHashTable.Create(Count);
   Seek(FDatabase, 0);
   NextID := 1;
   while (not EOF(FDatabase)) do
   begin
      BlockRead(FDatabase, DynastyRecord, 1); // {BOGUS Hint: Local variable "DynastyRecord" does not seem to be initialized}
      Dynasty := TDynasty.CreateFromRecord(NextID, DynastyRecord);
      Assert(not FAccountsByUsername.Has(Dynasty.Username), 'duplicate dynasties with username "' + Dynasty.Username + '"');
      FAccountsByUsername[Dynasty.Username] := Dynasty;
      FAccounts.Push(Dynasty);
      Inc(NextID);
   end;
   Assert(Count + 1 = NextID);
   Assert(Count = FAccounts.Length);
end;

destructor TUserDatabase.Destroy();
var
   Account: TDynasty;
begin
   if (Assigned(FAccountsByUsername)) then
      for Account in FAccountsByUsername.Values do
         Account.Free();
   FreeAndNil(FAccountsByUsername);
   inherited;
end;

function TUserDatabase.CreateNewAccount(Password: UTF8String; DynastyServer: Cardinal): TDynasty;
var
   ID: Cardinal;
begin
   ID := NextID;
   Inc(NextID);
   Result := TDynasty.Create(ID, TemporaryUsernameMarker + IntToStr(ID), Password, DynastyServer);
   Assert(not FAccountsByUsername.Has(Result.Username));
   FAccountsByUsername.Add(Result.Username, Result);
   FAccounts.Push(Result);
   Assert(Result.ID = FAccounts.Length);
   Assert(FAccountsByUsername.Count = FAccounts.Length);
   Save(Result);
end;

procedure TUserDatabase.Save(Dynasty: TDynasty);
begin
   Seek(FDatabase, Dynasty.ID - 1);
   BlockWrite(FDatabase, Dynasty.ToRecord(), 1); // {BOGUS Hint: Local variable "WriteCount" does not seem to be initialized}
end;

function TUserDatabase.GetDynasties(): TDynastyHashTable.TValueEnumerator;
begin
   Result := FAccountsByUsername.Values();
end;

function TUserDatabase.GetDynastyCount(): Cardinal;
begin
   Result := FAccountsByUsername.Count;
end;

function TUserDatabase.GetAccount(Username: UTF8String; Password: UTF8String): TDynasty;
var
   Dynasty: TDynasty;
begin
   Dynasty := FAccountsByUsername[Username];
   if (Assigned(Dynasty)) then
   begin
      if (Dynasty.VerifyPassword(Password)) then
      begin
         Result := Dynasty;
         exit;
      end;
   end;
   Result := nil;
end;

function TUserDatabase.GetAccount(DynastyID: Cardinal): TDynasty;
begin
   Assert(DynastyID > 0);
   Assert(DynastyID <= FAccounts.Length);
   Result := FAccounts[DynastyID - 1]; // $R-
end;

procedure TUserDatabase.ChangeUsername(Dynasty: TDynasty; Username: UTF8String);
begin
   Assert(Username <> Dynasty.Username);
   Assert(FAccountsByUsername[Dynasty.Username] = Dynasty);
   Assert(not FAccountsByUsername.Has(Username));
   FAccountsByUsername.Remove(Dynasty.Username);
   FAccountsByUsername[Username] := Dynasty;
   Dynasty.UpdateUsername(Username);
   Save(Dynasty);
end;

procedure TUserDatabase.ChangePassword(Dynasty: TDynasty; Password: UTF8String);
begin
   Dynasty.UpdatePassword(Password);
   Save(Dynasty);
end;

function TUserDatabase.UsernameAdequate(Username: UTF8String): Boolean;
begin
   Result := (Username <> '') and
             (Length(Username) <= TDynastyRecord.MaxUsernameLength) and
             (not FAccountsByUsername.Has(Username)) and
             (Pos(TemporaryUsernameMarker, Username) = 0);
end;

class function TUserDatabase.PasswordAdequate(Password: UTF8String): Boolean;
begin
   Result := Length(Password) >= MinPasswordLength;
end;

procedure TUserDatabase.RegisterScoreUpdate(const DynastyID: Cardinal; const Score: Double);
var
   Dynasty: TDynasty;
begin
   Dynasty := GetAccount(DynastyID);
   Dynasty.UpdateScore(Score);
   Save(Dynasty);
end;

procedure OpenUserDatabase(out F: TDynastyFile; Filename: UTF8String);
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