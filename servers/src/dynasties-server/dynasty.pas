{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit dynasty;

interface

uses
   sysutils, passwords;

type
   TSettings = record
      DynastyID: Cardinal;
   end;

   TToken = record
      Salt: TSalt;
      Hash: THash;
   end;

   TSystem = record
      
   end;
   
   TDynasty = class
   protected
      FSettings: TSettings;
      FConfigurationDirectory: UTF8String;
      FTokens: array of TToken;
      FSystems: array of TSystem;
      procedure SaveSettings();
      procedure SaveTokens();
   public
      constructor Create(ADynastyID: Cardinal; AConfigurationDirectory: UTF8String);
      constructor CreateFromDisk(AConfigurationDirectory: UTF8String);
      procedure AddToken(Salt: TSalt; Hash: THash);
      function VerifyToken(Password: UTF8String): Boolean;
      procedure ResetTokens();
      property DynastyID: Cardinal read FSettings.DynastyID;
   end;

implementation

uses
   exceptions, configuration;

const
   SettingsFileName = 'settings.dat';
   TokensFileName = 'tokens.db';

constructor TDynasty.Create(ADynastyID: Cardinal; AConfigurationDirectory: UTF8String);
begin
   inherited Create();
   FSettings.DynastyID := ADynastyID;
   FConfigurationDirectory := AConfigurationDirectory;
   try
      Assert(not DirectoryExists(FConfigurationDirectory));
      MkDir(FConfigurationDirectory);
   except
      ReportCurrentException();
   end;
   SaveSettings();
end;

constructor TDynasty.CreateFromDisk(AConfigurationDirectory: UTF8String);
var
   SettingsFile: File of TSettings;
   TokensFile: File of TToken;
begin
   inherited Create();
   FConfigurationDirectory := AConfigurationDirectory;
   Assert(DirectoryExists(FConfigurationDirectory));
   Assign(SettingsFile, FConfigurationDirectory + SettingsFileName);
   Reset(SettingsFile);
   BlockRead(SettingsFile, FSettings, 1);
   Close(SettingsFile);
   Assign(TokensFile, FConfigurationDirectory + TokensFileName);
   Reset(TokensFile);
   SetLength(FTokens, FileSize(TokensFile));
   if (Length(FTokens) > 0) then
   begin
      BlockRead(TokensFile, FTokens[0], Length(FTokens));
   end;
   Close(TokensFile);
end;

procedure TDynasty.SaveSettings();
var
   TempFile: File of TSettings;
   TempFileName: UTF8String;
   RealFileName: UTF8String;
begin
   RealFileName := FConfigurationDirectory + SettingsFileName;
   TempFileName := RealFileName + TemporaryExtension;
   Assert(DirectoryExists(FConfigurationDirectory));
   Assign(TempFile, TempFileName);
   Rewrite(TempFile);
   BlockWrite(TempFile, FSettings, 1);
   Close(TempFile);
   DeleteFile(RealFileName);
   RenameFile(TempFileName, RealFileName);
end;

procedure TDynasty.SaveTokens();
var
   TempFile: File of TToken;
   TempFileName: UTF8String;
   RealFileName: UTF8String;
begin
   RealFileName := FConfigurationDirectory + TokensFileName;
   TempFileName := RealFileName + TemporaryExtension;
   Assert(DirectoryExists(FConfigurationDirectory));
   Assign(TempFile, TempFileName);
   Rewrite(TempFile);
   if (Length(FTokens) > 0) then
      BlockWrite(TempFile, FTokens[0], Length(FTokens)); // $R-
   Close(TempFile);
   DeleteFile(RealFileName);
   RenameFile(TempFileName, RealFileName);
end;

procedure TDynasty.AddToken(Salt: TSalt; Hash: THash);
var
   Index: Cardinal;
begin
   Index := Length(FTokens); // $R-
   SetLength(FTokens, Index + 1);
   FTokens[Index].Salt := Salt;
   FTokens[Index].Hash := Hash;
   SaveTokens();
end;

function TDynasty.VerifyToken(Password: UTF8String): Boolean;
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

procedure TDynasty.ResetTokens();
begin
   SetLength(FTokens, 0);
   SaveTokens();
end;

end.
