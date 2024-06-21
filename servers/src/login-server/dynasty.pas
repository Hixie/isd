{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit dynasty;

interface

uses
   sysutils, passwords;

type
   TDynastyRecord = record
   public
      const
         MaxUsernameLength = 127; // plus one byte for the length
      var
         Username: String[MaxUsernameLength];
         Salt: TSalt;
         PasswordHash: THash;
         DynastyServer: Cardinal;
   end;

   TDynasty = class
   protected
      FID: Cardinal;
      FUsername: UTF8String;
      FSalt: TSalt;
      FPasswordHash: THash;
      FDynastyServer: Cardinal;
   public
      constructor Create(AID: Cardinal; AUsername: UTF8String; APassword: UTF8String; ADynastyServer: Cardinal);
      constructor CreateFromRecord(AID: Cardinal; DynastyRecord: TDynastyRecord);
      function ToRecord(): TDynastyRecord;
      procedure UpdateUsername(NewUsername: UTF8String);
      procedure UpdatePassword(NewPassword: UTF8String);
      function VerifyPassword(Candidate: UTF8String): Boolean;
      property ID: Cardinal read FID;
      property Username: UTF8String read FUsername;
      property ServerID: Cardinal read FDynastyServer;
   end;

implementation

function RawToString(var Source; Length: Cardinal): UTF8String;
begin
   Result := '';
   SetLength(Result, Length);
   Move(Source, Result[1], Length);
end;

function RawToBytes(var Source; Length: Cardinal): TBytes;
begin
   Result := nil;
   SetLength(Result, Length);
   Move(Source, Result[0], Length);
end;

constructor TDynasty.Create(AID: Cardinal; AUsername: UTF8String; APassword: UTF8String; ADynastyServer: Cardinal);
begin
   inherited Create();
   FID := AID;
   FUsername := AUsername;
   FDynastyServer := ADynastyServer;
   UpdatePassword(APassword);
end;

constructor TDynasty.CreateFromRecord(AID: Cardinal; DynastyRecord: TDynastyRecord);
begin
   inherited Create();
   FID := AID;
   FUsername := DynastyRecord.Username;
   FSalt := DynastyRecord.Salt;
   FPasswordHash := DynastyRecord.PasswordHash;
   FDynastyServer := DynastyRecord.DynastyServer;
end;

function TDynasty.ToRecord(): TDynastyRecord;
begin
   FillChar(Result.Username, High(Result.Username), 0);
   Result.Username := FUsername;
   Move(FSalt[0], Result.Salt[0], Length(Result.Salt));
   Move(FPasswordHash[0], Result.PasswordHash[0], Length(Result.PasswordHash));
   Result.DynastyServer := FDynastyServer;
end;

procedure TDynasty.UpdateUsername(NewUsername: UTF8String);
begin
   FUsername := NewUsername;
end;

procedure TDynasty.UpdatePassword(NewPassword: UTF8String);
var
   NewSalt: TSalt;
   HashedPassword: THash;
begin
   NewSalt := CreateSalt();
   ComputeHash(NewSalt, NewPassword, HashedPassword);
   FSalt := NewSalt;
   FPasswordHash := HashedPassword;
end;

function TDynasty.VerifyPassword(Candidate: UTF8String): Boolean;
var
   HashedPassword: THash;
begin
   ComputeHash(FSalt, Candidate, HashedPassword);
   Assert(Length(HashedPassword) = Length(FPasswordHash));
   Assert(Length(HashedPassword) > 0);
   Result := CompareHashes(HashedPassword, FPasswordHash);
end;

end.