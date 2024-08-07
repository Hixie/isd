{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit basedynasty;

interface

uses
   sysutils, passwords, genericutils, basenetwork, hashset;

type
   // TODO: expire tokens after a few days (and have the client automatically ask for new ones)
   TToken = record
      Salt: TSalt;
      Hash: THash;
   end;
   TTokenArray = array of TToken;

   TConnectionUtils = specialize DefaultUnorderedUtils <TBaseIncomingCapableConnection>;
   TConnectionHashSet = specialize THashSet<TBaseIncomingCapableConnection, TConnectionUtils>;

   TBaseDynasty = class
   protected
      FConfigurationDirectory: UTF8String;
      FTokens: TTokenArray;
      FConnections: TConnectionHashSet;
      procedure SaveTokens();
      procedure Reload(); virtual;
      function GetHasConnections(): Boolean;
   public
      constructor Create(AConfigurationDirectory: UTF8String);
      constructor CreateFromDisk(AConfigurationDirectory: UTF8String);
      class function CanCreateFromDisk(AConfigurationDirectory: UTF8String): Boolean; static;
      destructor Destroy(); override;
      procedure AddToken(Salt: TSalt; Hash: THash);
      function VerifyToken(Password: UTF8String): Boolean;
      procedure ResetTokens();
      procedure ForgetDynasty(); virtual;
      procedure AddConnection(AConnection: TBaseIncomingCapableConnection);
      procedure RemoveConnection(AConnection: TBaseIncomingCapableConnection);
      procedure SendToAllConnections(Message: RawByteString);
      procedure ForEachConnection(Callback: TConnectionCallback);
      property HasConnections: Boolean read GetHasConnections;
      property Tokens: TTokenArray read FTokens;
   end;

implementation

uses
   exceptions, configuration, hashfunctions;

function ConnectionHash32(const Key: TBaseIncomingCapableConnection): DWord;
begin
   Result := PtrUIntHash32(PtrUInt(Key));
end;


constructor TBaseDynasty.Create(AConfigurationDirectory: UTF8String);
begin
   inherited Create();
   FConfigurationDirectory := AConfigurationDirectory;
   try
      Assert(not DirectoryExists(FConfigurationDirectory));
      MkDir(FConfigurationDirectory);
   except
      ReportCurrentException();
      raise;
   end;
   FConnections := TConnectionHashSet.Create(@ConnectionHash32);
end;

constructor TBaseDynasty.CreateFromDisk(AConfigurationDirectory: UTF8String);
begin
   inherited Create();
   FConfigurationDirectory := AConfigurationDirectory;
   Assert(DirectoryExists(FConfigurationDirectory));
   Reload();
   FConnections := TConnectionHashSet.Create(@ConnectionHash32);
end;

class function TBaseDynasty.CanCreateFromDisk(AConfigurationDirectory: UTF8String): Boolean;
begin
   Result := DirectoryExists(AConfigurationDirectory);
end;

destructor TBaseDynasty.Destroy();
begin
   FConnections.Free();
   inherited;
end;

procedure TBaseDynasty.Reload();
var
   TokensFile: File of TToken;
begin
   Assign(TokensFile, FConfigurationDirectory + TokensDatabaseFileName);
   FileMode := 0;
   Reset(TokensFile);
   SetLength(FTokens, FileSize(TokensFile));
   if (Length(FTokens) > 0) then
      BlockRead(TokensFile, FTokens[0], Length(FTokens));
   Close(TokensFile);
end;

procedure TBaseDynasty.SaveTokens();
var
   TempFile: File of TToken;
   TempFileName: UTF8String;
   RealFileName: UTF8String;
begin
   // TODO: just add the new token
   RealFileName := FConfigurationDirectory + TokensDatabaseFileName;
   TempFileName := RealFileName + TemporaryExtension;
   Assert(DirectoryExists(FConfigurationDirectory));
   Assign(TempFile, TempFileName);
   FileMode := 1;
   Rewrite(TempFile);
   if (Length(FTokens) > 0) then
      BlockWrite(TempFile, FTokens[0], Length(FTokens)); // $R-
   Close(TempFile);
   DeleteFile(RealFileName);
   RenameFile(TempFileName, RealFileName);
end;

procedure TBaseDynasty.AddToken(Salt: TSalt; Hash: THash);
var
   Index: Cardinal;
begin
   Index := Length(FTokens); // $R-
   SetLength(FTokens, Index + 1);
   FTokens[Index].Salt := Salt;
   FTokens[Index].Hash := Hash;
   SaveTokens(); // TODO: append instead of rewriting
end;

function TBaseDynasty.VerifyToken(Password: UTF8String): Boolean;
var
   Index: Cardinal;
   Hash: THash;
begin
   if (Length(FTokens) > 0) then
   begin
      for Index := Low(FTokens) to High(FTokens) do // $R-
      begin
         ComputeHash(FTokens[Index].Salt, Password, Hash);
         if (CompareHashes(Hash, FTokens[Index].Hash)) then
         begin
            Result := True;
            exit;
         end;
      end;
   end;
   Result := False;
end;

procedure TBaseDynasty.ResetTokens();
begin
   SetLength(FTokens, 0);
   SaveTokens(); // TODO: just empty the file
end;

procedure TBaseDynasty.ForgetDynasty();
begin
   DeleteFile(FConfigurationDirectory + TokensDatabaseFileName);
   RmDir(FConfigurationDirectory);
   Assert(not DirectoryExists(FConfigurationDirectory));
end;

procedure TBaseDynasty.AddConnection(AConnection: TBaseIncomingCapableConnection);
begin
   Assert(not FConnections.Has(AConnection));
   FConnections.Add(AConnection);
end;

procedure TBaseDynasty.RemoveConnection(AConnection: TBaseIncomingCapableConnection);
begin
   FConnections.Remove(AConnection);
end;

procedure TBaseDynasty.SendToAllConnections(Message: RawByteString);
var
   Connection: TBaseIncomingCapableConnection;
begin
   for Connection in FConnections do
   begin
      try
         Connection.WriteFrame(Message, Length(Message)); // $R-
      except
         ReportCurrentException();
      end;
   end;
end;

procedure TBaseDynasty.ForEachConnection(Callback: TConnectionCallback);
var
   Connection: TBaseIncomingCapableConnection;
begin
   for Connection in FConnections do
   begin
      try
         Connection.Invoke(Callback); // $R-
      except
         ReportCurrentException();
      end;
   end;
end;

function TBaseDynasty.GetHasConnections(): Boolean;
begin
   Result := FConnections.Count > 0;
end;

end.
