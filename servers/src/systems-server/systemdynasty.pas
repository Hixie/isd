{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit systemdynasty;

interface

uses
   sysutils, passwords, basedynasty, basenetwork;

type
   TDynasty = class(TBaseDynasty)
   public
      type
         TDynastyCallback = procedure(Dynasty: TDynasty) of object;
   strict private
      type
         TSettings = record
            ServerID: Cardinal;
         end;
      var
         FID: Cardinal;
         FSettings: TSettings;
         FRefCount: Cardinal;
         FOnUnreferenced: TDynastyCallback;
      procedure SaveSettings();
      procedure LoadSettings();
   public
      // (the configuration directory is used for the tokens)
      constructor Create(ADynastyID: Cardinal; ADynastyServerID: Cardinal; AConfigurationDirectory: UTF8String; AOnUnreferenced: TDynastyCallback);
      constructor CreateFromDisk(ADynastyID: Cardinal; AConfigurationDirectory: UTF8String; AOnUnreferenced: TDynastyCallback);
      procedure ForgetDynasty(); override;
      procedure IncRef();
      procedure DecRef();
      property DynastyID: Cardinal read FID;
      property DynastyServerID: Cardinal read FSettings.ServerID;
      property RefCount: Cardinal read FRefCount;
   end;
   
   TDynastyDatabase = class abstract
   public
      function GetDynastyFromDisk(DynastyID: Cardinal): TDynasty; virtual; abstract;
   end;

implementation

uses
   exceptions, configuration;

constructor TDynasty.Create(ADynastyID: Cardinal; ADynastyServerID: Cardinal; AConfigurationDirectory: UTF8String; AOnUnreferenced: TDynastyCallback);
begin
   inherited Create(AConfigurationDirectory);
   FID := ADynastyID;
   FSettings.ServerID := ADynastyServerID;
   FOnUnreferenced := AOnUnreferenced;
   SaveSettings();
end;

constructor TDynasty.CreateFromDisk(ADynastyID: Cardinal; AConfigurationDirectory: UTF8String; AOnUnreferenced: TDynastyCallback);
begin
   inherited CreateFromDisk(AConfigurationDirectory);
   FID := ADynastyID;
   FOnUnreferenced := AOnUnreferenced;
   LoadSettings();
end;

procedure TDynasty.LoadSettings();
var
   SettingsFile: File of TSettings;
begin
   Assign(SettingsFile, FConfigurationDirectory + SettingsDatabaseFileName);
   Reset(SettingsFile);
   BlockRead(SettingsFile, FSettings, 1);
   Close(SettingsFile);
   inherited;
end;

procedure TDynasty.SaveSettings();
var
   TempFile: File of TSettings;
   TempFileName: UTF8String;
   RealFileName: UTF8String;
begin
   Assert(DirectoryExists(FConfigurationDirectory));
   RealFileName := FConfigurationDirectory + SettingsDatabaseFileName;
   TempFileName := RealFileName + TemporaryExtension;
   Assign(TempFile, TempFileName);
   FileMode := 1;
   Rewrite(TempFile);
   BlockWrite(TempFile, FSettings, 1);
   Close(TempFile);
   DeleteFile(RealFileName);
   RenameFile(TempFileName, RealFileName);
end;

procedure TDynasty.ForgetDynasty();
begin
   Assert(False); // we should only hit this once dynasties can actually leave systems
   DeleteFile(FConfigurationDirectory + SettingsDatabaseFileName);
   inherited;
end;

procedure TDynasty.IncRef();
begin
   Inc(FRefCount);
end;

procedure TDynasty.DecRef();
begin
   Dec(FRefCount);
   if (FRefCount = 0) then
   begin
      FOnUnreferenced(Self);
   end;
end;

end.
