{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit dynasty;

interface

uses
   sysutils, passwords, basedynasty, servers, stringstream;

type
   TSettings = record
      DynastyID: Cardinal;
   end;

   TSystemServer = record
      // if we make this longer, we should make the logic below return
      // a pointer instead of a copy
      ServerID: Cardinal;
   end;

   TDynasty = class(TBaseDynasty)
   strict private
      FSettings: TSettings;
      FSystemServers: array of TSystemServer;
      function GetServerCount(): Cardinal;
      function GetServer(Index: Cardinal): TSystemServer;
      procedure SaveSettings();
      procedure SaveSystems();
   protected
      procedure Reload(); override;
   public
      constructor Create(ADynastyID: Cardinal; AConfigurationDirectory: UTF8String);
      procedure AddSystemServer(SystemServerID: Cardinal);
      procedure RemoveSystemServer(SystemServerID: Cardinal);
      procedure EncodeServers(ServerDatabase: TServerDatabase; Writer: TStringStreamWriter);
      procedure UpdateClients(ServerDatabase: TServerDatabase);
      procedure ForgetDynasty(); override;
      property DynastyID: Cardinal read FSettings.DynastyID;
      property ServerCount: Cardinal read GetServerCount;
      property Servers[Index: Cardinal]: TSystemServer read GetServer;
   end;

implementation

uses
   exceptions, configuration, isdprotocol;

constructor TDynasty.Create(ADynastyID: Cardinal; AConfigurationDirectory: UTF8String);
begin
   inherited Create(AConfigurationDirectory);
   FSettings.DynastyID := ADynastyID;
   SaveSystems();
   SaveSettings();
end;

function TDynasty.GetServerCount(): Cardinal;
begin
   Result := Length(FSystemServers); // $R-
end;

function TDynasty.GetServer(Index: Cardinal): TSystemServer;
begin
   Result := FSystemServers[Index];
end;

procedure TDynasty.Reload();
var
   SettingsFile: File of TSettings;
   SystemsFile: File of TSystemServer;
begin
   // dynasty server ID
   Assign(SettingsFile, FConfigurationDirectory + SettingsDatabaseFileName);
   FileMode := 0;
   Reset(SettingsFile);
   BlockRead(SettingsFile, FSettings, 1);
   Close(SettingsFile);
   // list of systems
   Assign(SystemsFile, FConfigurationDirectory + SystemsDatabaseFileName);
   FileMode := 0;
   Reset(SystemsFile);
   SetLength(FSystemServers, FileSize(SystemsFile));
   if (Length(FSystemServers) > 0) then
      BlockRead(SystemsFile, FSystemServers[0], Length(FSystemServers));
   Close(SystemsFile);
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

procedure TDynasty.SaveSystems();
var
   TempFile: File of TSystemServer;
   TempFileName: UTF8String;
   RealFileName: UTF8String;
begin
   Assert(DirectoryExists(FConfigurationDirectory));
   RealFileName := FConfigurationDirectory + SystemsDatabaseFileName;
   TempFileName := RealFileName + TemporaryExtension;
   Assign(TempFile, TempFileName);
   FileMode := 1;
   Rewrite(TempFile);
   if (Length(FSystemServers) > 0) then
      BlockWrite(TempFile, FSystemServers[0], Length(FSystemServers)); // $R-
   Close(TempFile);
   DeleteFile(RealFileName);
   RenameFile(TempFileName, RealFileName);
end;

procedure TDynasty.AddSystemServer(SystemServerID: Cardinal);

   function ServerAlreadyKnown(): Boolean;
   var
      Server: TSystemServer;
   begin
      // this is not super efficient but is debug-mode only
      for Server in FSystemServers do
      begin
         if (Server.ServerID = SystemServerID) then
         begin
            Result := True;
            exit;
         end;
      end;
      Result := False;
   end;

begin
   Assert(not ServerAlreadyKnown());
   // this is not super efficient (likely results in full array copy) but is expected to be rare with usually small numbers
   SetLength(FSystemServers, Length(FSystemServers) + 1);
   FSystemServers[High(FSystemServers)].ServerID := SystemServerID;
   SaveSystems();
end;

procedure TDynasty.RemoveSystemServer(SystemServerID: Cardinal);
var
   Index: Cardinal;
begin
   // this is not super efficient but is expected to be rare
   Index := 0;
   while (Index < Length(FSystemServers)) do
   begin
      if (FSystemServers[Index].ServerID = SystemServerID) then
      begin
         Delete(FSystemServers, Index, 1);
      end
      else
      begin
         Inc(Index);
      end;
   end;
   SaveSystems();
end;

procedure TDynasty.EncodeServers(ServerDatabase: TServerDatabase; Writer: TStringStreamWriter);
var
   System: TSystemServer;
begin
   Writer.WriteCardinal(Length(FSystemServers));
   for System in FSystemServers do
      Writer.WriteString(ServerDatabase.Servers[System.ServerID]^.URL);
end;

procedure TDynasty.UpdateClients(ServerDatabase: TServerDatabase);
var
   Writer: TStringStreamWriter;
begin
   if (HasConnections) then
   begin
      Writer := TStringStreamWriter.Create();
      try
         Writer.WriteString(iuSystemServers);
         EncodeServers(ServerDatabase, Writer);
         Writer.Close();
         SendToAllConnections(Writer.Serialize());
      finally
         Writer.Free();
      end;
   end;
end;

procedure TDynasty.ForgetDynasty();
begin
   Assert(False);
   DeleteFile(FConfigurationDirectory + SettingsDatabaseFileName);
   DeleteFile(FConfigurationDirectory + SystemsDatabaseFileName);
   inherited;
end;

end.
