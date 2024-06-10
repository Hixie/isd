{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit dynasty;

interface

uses
   sysutils;

type
   TDynastyRecord = record
   public
      const
         MaxUsernameLength = 127; // plus one byte for the length
         SaltLength = 8;
         SHA256Length = 32;
      var
         Username: String[MaxUsernameLength];
         Salt: array[0..SaltLength-1] of Byte;
         PasswordHash: array[0..SHA256Length-1] of Byte; // SHA256
   end;

   TDynasty = class
   protected
      FID: Cardinal;
      FUsername: UTF8String;
      FSalt: UTF8String;
      FPasswordHash: TBytes;
      class procedure ComputeHash(Salt: UTF8String; Password: UTF8String; out Hash: TBytes);
   public
      constructor Create(AID: Cardinal; AUsername: UTF8String; APassword: UTF8String);
      constructor CreateFromRecord(AID: Cardinal; DynastyRecord: TDynastyRecord);
      function ToRecord(): TDynastyRecord;
      procedure UpdateUsername(NewUsername: UTF8String);
      procedure UpdatePassword(NewPassword: UTF8String);
      function VerifyPassword(Candidate: UTF8String): Boolean;
      property ID: Cardinal read FID;
      property Username: UTF8String read FUsername;
   end;

implementation

uses fpsha256, fphashutils;

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

constructor TDynasty.Create(AID: Cardinal; AUsername: UTF8String; APassword: UTF8String);
begin
   inherited Create();
   FID := AID;
   FUsername := AUsername;
   UpdatePassword(APassword);
end;

constructor TDynasty.CreateFromRecord(AID: Cardinal; DynastyRecord: TDynastyRecord);
begin
   inherited Create();
   FID := AID;
   FUsername := DynastyRecord.Username;
   FSalt := RawToString(DynastyRecord.Salt[0], Length(DynastyRecord.Salt));
   FPasswordHash := RawToBytes(DynastyRecord.PasswordHash[0], Length(DynastyRecord.PasswordHash));
end;

function TDynasty.ToRecord(): TDynastyRecord;
begin
   FillChar(Result.Username, High(Result.Username), 0);
   Result.Username := FUsername;
   Assert(Length(FSalt) = Length(Result.Salt));
   Move(FSalt[1], Result.Salt[0], Length(Result.Salt));
   Assert(Length(FPasswordHash) = Length(Result.PasswordHash));
   Move(FPasswordHash[0], Result.PasswordHash[0], Length(Result.PasswordHash));
   TDynasty.CreateFromRecord(FID, Result).Free();
end;

class procedure TDynasty.ComputeHash(Salt: UTF8String; Password: UTF8String; out Hash: TBytes);
var
   SaltedPassword: TBytes;
   HashedPassword: TBytes;
begin
   SaltedPassword := BytesOf(Salt + Password);
   TSHA256.DigestBytes(SaltedPassword, HashedPassword);
   Hash := HashedPassword;
end;

procedure TDynasty.UpdateUsername(NewUsername: UTF8String);
begin
   FUsername := NewUsername;
end;

procedure TDynasty.UpdatePassword(NewPassword: UTF8String);
var
   NewSalt: UTF8String;
   HashedPassword: TBytes;
begin
   SetLength(NewSalt, TDynastyRecord.SaltLength);
   CryptoGetRandomBytes(PByte(NewSalt), Length(NewSalt)); // $R- (we know SaltLength will fit)
   ComputeHash(NewSalt, NewPassword, HashedPassword);
   FSalt := NewSalt;
   FPasswordHash := HashedPassword;
end;

function TDynasty.VerifyPassword(Candidate: UTF8String): Boolean;
var
   Index: Cardinal;
   HashedPassword: TBytes;
begin
   ComputeHash(FSalt, Candidate, HashedPassword);
   Assert(Length(HashedPassword) = Length(FPasswordHash));
   Assert(Length(HashedPassword) > 0);
   for Index := Low(HashedPassword) to High(HashedPassword) do // $R- (we know the hash is a reasonable size)
   begin
      if (HashedPassword[Index] <> FPasswordHash[Index]) then
      begin
         Result := False;
         exit;
      end;
   end;
   Result := True;
end;


function GetTrueRandomBytes(aBytes: PByte; aCount: Integer): Boolean;
var
   Source: File of Byte;
   ActualCount: Cardinal;
begin
   Assign(Source, '/dev/urandom');
   FileMode := 0;
   Reset(Source);
   if (IOResult <> 0) then
   begin
      Result := False;
      exit;
   end;
   BlockRead(Source, aBytes^, aCount, ActualCount); // $DFA- for ActualCount // $R-
   Result := (IOResult = 0) and (ActualCount >= aCount);
   Close(Source);
end;

initialization
   GetRandomBytes := @GetTrueRandomBytes;
end.