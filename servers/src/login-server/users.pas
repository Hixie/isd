{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit users;

interface

uses logindynasty, hashtable, stringutils;

type
   TDynastyHashTable = class(specialize THashTable<UTF8String, TDynasty, UTF8StringUtils>)
      constructor Create();
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
         FAccounts: TDynastyHashTable;
         NextID: Cardinal;
         FDatabase: File of TDynastyRecord;
      procedure Save(Dynasty: TDynasty);
      function GetDynasties(): TDynastyHashTable.TValueEnumerator;
   public
      constructor Create(var ADatabase: File);
      destructor Destroy(); override;
      function CreateNewAccount(Password: UTF8String; DynastyServer: Cardinal): TDynasty;
      function GetAccount(Username: UTF8String; Password: UTF8String): TDynasty;
      procedure ChangeUsername(Dynasty: TDynasty; Username: UTF8String);
      procedure ChangePassword(Dynasty: TDynasty; Password: UTF8String);
      function UsernameAdequate(Username: UTF8String): Boolean;
      class function PasswordAdequate(Password: UTF8String): Boolean;
      property Dynasties: TDynastyHashTable.TValueEnumerator read GetDynasties;
   end;

type
   TDynastyFile = File of TDynastyRecord;

procedure OpenUserDatabase(out F: TDynastyFile; Filename: UTF8String);

implementation

uses hashfunctions, fphashutils, sysutils;

constructor TDynastyHashTable.Create();
begin
   inherited Create(@UTF8StringHash32);
end;

constructor TDynastyServerHashTable.Create();
begin
   inherited Create(@UTF8StringHash32);
end;


constructor TUserDatabase.Create(var ADatabase: File);
var
   Dynasty: TDynasty;
   DynastyRecord: TDynastyRecord;
begin
   inherited Create();
   FDatabase := ADatabase;
   FAccounts := TDynastyHashTable.Create();
   Seek(FDatabase, 0);
   NextID := 1;
   while (not EOF(FDatabase)) do
   begin
      BlockRead(FDatabase, DynastyRecord, 1); // {BOGUS Hint: Local variable "DynastyRecord" does not seem to be initialized}
      Dynasty := TDynasty.CreateFromRecord(NextID, DynastyRecord);
      Assert(not FAccounts.Has(Dynasty.Username), 'duplicate dynasties with username "' + Dynasty.Username + '"');
      FAccounts[Dynasty.Username] := Dynasty;
      Inc(NextID);
   end;
end;

destructor TUserDatabase.Destroy();
var
   Account: TDynasty;
begin
   for Account in FAccounts.Values do
      Account.Free();
   FAccounts.Free();
   inherited;
end;

function TUserDatabase.CreateNewAccount(Password: UTF8String; DynastyServer: Cardinal): TDynasty;
var
   ID: Cardinal;
begin
   ID := NextID;
   Inc(NextID);
   Result := TDynasty.Create(ID, TemporaryUsernameMarker + IntToStr(ID), Password, DynastyServer);
   Assert(not FAccounts.Has(Result.Username));
   FAccounts.Add(Result.Username, Result);
   Save(Result);
end;

procedure TUserDatabase.Save(Dynasty: TDynasty);
begin
   Seek(FDatabase, Dynasty.ID - 1);
   BlockWrite(FDatabase, Dynasty.ToRecord(), 1); // {BOGUS Hint: Local variable "WriteCount" does not seem to be initialized}
end;

function TUserDatabase.GetDynasties(): TDynastyHashTable.TValueEnumerator;
begin
   Result := FAccounts.Values();
end;

function TUserDatabase.GetAccount(Username: UTF8String; Password: UTF8String): TDynasty;
var
   Dynasty: TDynasty;
begin
   Dynasty := FAccounts[Username];
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

procedure TUserDatabase.ChangeUsername(Dynasty: TDynasty; Username: UTF8String);
begin
   Assert(Username <> Dynasty.Username);
   Assert(FAccounts[Dynasty.Username] = Dynasty);
   Assert(not FAccounts.Has(Username));
   FAccounts.Remove(Dynasty.Username);
   FAccounts[Username] := Dynasty;
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
             (not FAccounts.Has(Username)) and
             (Pos(TemporaryUsernameMarker, Username) = 0);
end;

class function TUserDatabase.PasswordAdequate(Password: UTF8String): Boolean;
begin
   Result := Length(Password) >= MinPasswordLength;
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