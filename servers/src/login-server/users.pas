{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit users;

interface

uses dynasty, hashtable, stringutils;

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
   ReadCount: Cardinal;
   Dynasty: TDynasty;
   DynastyRecord: TDynastyRecord;
begin
   inherited Create();
   FDatabase := ADatabase;
   FAccounts := TDynastyHashTable.Create();
   Seek(FDatabase, 0);
   Assert(NextID = 0);
   while (not EOF(FDatabase)) do
   begin
      BlockRead(ADatabase, DynastyRecord, 1, ReadCount);
      if (ReadCount <> 1) then
      begin
         Writeln('Expected to read one record from user database but read ', ReadCount, ' records at index ', NextID, '.');
         Writeln('Aborting.');
         raise Exception.Create('Failed to read user database.');
      end;
      Dynasty := TDynasty.CreateFromRecord(NextID, DynastyRecord);
      FAccounts[Dynasty.Username] := Dynasty;
      Writeln('Loaded dynasty ', Dynasty.ID, ' "', Dynasty.Username, '"');
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
var
   WriteCount: Cardinal;
begin
   Seek(FDatabase, Dynasty.ID);
   BlockWrite(FDatabase, Dynasty.ToRecord(), 1, WriteCount);
   if (WriteCount <> 1) then
   begin
      Writeln('Expected to write one record to user database but wrote ', WriteCount, ' records at index ', NextID, '!!');
      // XXX report this somewhere promptly
   end;
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
   Assert(FAccounts[Dynasty.Username] = Dynasty);
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

end.