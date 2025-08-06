{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit passwords;

interface

uses
   sysutils, fpsha256;

const
   SaltLength = 8;
   HashLength = 256 div 8; // SHA256 length in bytes
   MaxTokenLength = 1024;

type
   TSalt = array[0..SaltLength-1] of Byte;
   THash = TSha256Digest;

function CreateSalt(): TSalt;
function CreatePassword(PasswordLength: Cardinal): UTF8String;
procedure ComputeHash(Salt: TSalt; Password: UTF8String; out Hash: THash);
function CompareHashes(const Hash1: THash; const Hash2: THash): Boolean;

implementation

uses
   fphashutils;

function CreateSalt(): TSalt;
begin
   CryptoGetRandomBytes(@Result[0], SizeOf(TSalt)); // $R- (we know SaltLength will fit)
end;

function CreatePassword(PasswordLength: Cardinal): UTF8String;
var
   Index: Cardinal;
   Bytes: TBytes;
begin
   SetLength(Bytes, PasswordLength);
   CryptoGetRandomBytes(PByte(Bytes), Length(Bytes)); // $R- (bytes is a reasonable size)
   for Index := Low(Bytes) to High(Bytes) do // $R- (bytes is a reasonable size)
   begin
      Bytes[Index] := (Bytes[Index] and $3F) + $3F; // $R-
   end;
   Result := '';
   SetLength(Result, Length(Bytes));
   Move(Bytes[0], Result[1], Length(Result));
end;

procedure ComputeHash(Salt: TSalt; Password: UTF8String; out Hash: THash);
var
   Sha256: TSha256;
begin
   Sha256.Init();
   Sha256.Update(Pointer(@Salt[0]), SizeOf(Salt));
   Sha256.Update(Pointer(@Password[1]), Length(Password)); // $R-
   Sha256.Final();
   Hash := Sha256.Digest;
end;

function GetTrueRandomBytes(aBytes: PByte; aCount: Integer): Boolean;
var
   Source: File of Byte;
   ActualCount: Cardinal;
begin
   Assign(Source, '/dev/random');
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

function CompareHashes(const Hash1: THash; const Hash2: THash): Boolean;
begin
   Result := CompareMem(@Hash1, @Hash2, SizeOf(THash));
end;


initialization
   GetRandomBytes := @GetTrueRandomBytes;
end.