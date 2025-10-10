{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit systemnetwork;

interface

// TODO: handle the case of all assets of a dynasty going away
// (right now we assert when they relogin because we can't find anything to send them)

uses
   configuration, servers, baseunix, authnetwork, serverstream,
   materials, corenetwork, binarystream, basenetwork, systemdynasty,
   astronomy, systems, hashtable, genericutils, basedynasty,
   encyclopedia, clock;

type
   TSystemHashTable = class(specialize THashTable<Cardinal, TSystem, CardinalUtils>)
      constructor Create();
   end;

   TDynastyHashTable = class(specialize THashTable<Cardinal, TDynasty, CardinalUtils>)
      constructor Create();
   end;

   TServer = class;

   TConnection = class(TAuthenticatableBaseIncomingInternalCapableConnection)
   protected
      FServer: TServer;
      FDynasty: TDynasty;
      FWriter: TServerStreamWriter;
      procedure HandleIPC(Arguments: TBinaryStreamReader); override;
      function GetDynasty(DynastyID: Cardinal): TBaseDynasty; override; // used for VerifyLogin
      procedure DoLogin(var Message: TMessage); message 'login';
      procedure DoPlay(var Message: TMessage); message 'play';
      function GetInternalPassword(): UTF8String; override;
   public
      constructor Create(AListener: TListenerSocket; AServer: TServer);
      destructor Destroy(); override;
      procedure Invoke(Callback: TConnectionCallback); override;
      property PlayerDynasty: TDynasty read FDynasty;
   end;

   TInternalDynastyConnection = class(TNetworkSocket)
   protected
      FServer: TServer;
      FDynastyServer: PServerEntry;
      function InternalRead(Data: array of byte): Boolean; override; // return false if connection is bad
      procedure Preconnect(); override;
   public
      constructor Create(ADynastyServer: PServerEntry; AServer: TServer);
      procedure Connect();
      procedure ReportConnectionError(ErrorCode: cint); override;
      procedure AddServerFor(Dynasty: TDynasty);
      procedure RemoveServerFor(Dynasty: TDynasty);
   end;
 
   TDynastyManager = class(TDynastyDatabase)
   protected
      FDynasties: TDynastyHashTable;
      FConfigurationDirectory: UTF8String;
      FServer: TServer;
   public
      constructor Create(AConfigurationDirectory: UTF8String; AServer: TServer);
      destructor Destroy(); override;
      function GetDynasty(DynastyID: Cardinal): TDynasty; // returns nil if we don't have it (in which case it shouldn't be on disk either)
      function GetDynastyFromDisk(DynastyID: Cardinal): TDynasty; override; // assumes we have it or that it's irrelevant -- used on startup only when replaying journals
      function HandleDynastyArrival(DynastyID, DynastyServerID: Cardinal): TDynasty;
      procedure HandleDynastyDeparture(Dynasty: TDynasty);
   end;

   {$IFOPT C+}
   TDebugHandler = procedure (Arguments: TBinaryStreamReader);
   {$ENDIF}
   
   TServer = class(TBaseServer)
   protected
      FPassword: UTF8String;
      FSystemServerID: Cardinal;
      FSettings: PSettings;
      FDynastyServers: TServerDatabase;
      FConfigurationDirectory: UTF8String;
      FSystems: TSystemHashTable;
      FEncyclopedia: TEncyclopedia;
      FDynastyManager: TDynastyManager;
      {$IFOPT C+} FDebugHandler: TDebugHandler; {$ENDIF}
      function CreateNetworkSocket(AListenerSocket: TListenerSocket): TNetworkSocket; override;
      function GetSystem(Index: Cardinal): TSystem;
      function CreateSystem(SystemID: Cardinal; X, Y: Double): TSystem;
      procedure ReportChanges(); override;
   public
      constructor Create(APort: Word; AClock: TClock; APassword: UTF8String; ASystemServerID: Cardinal; ASettings: PSettings; AEncyclopedia: TEncyclopedia; ADynastyServers: TServerDatabase; AConfigurationDirectory: UTF8String {$IFOPT C+}; ADebugHandler: TDebugHandler {$ENDIF});
      destructor Destroy(); override;
      function SerializeAllSystemsFor(Dynasty: TDynasty; Writer: TServerStreamWriter): RawByteString;
      property Password: UTF8String read FPassword;
      property SystemServerID: Cardinal read FSystemServerID;
      property Systems[Index: Cardinal]: TSystem read GetSystem;
      property DynastyManager: TDynastyManager read FDynastyManager;
      property DynastyServerDatabase: TServerDatabase read FDynastyServers;
      property Encyclopedia: TEncyclopedia read FEncyclopedia;
      {$IFOPT C+} property DebugHandler: TDebugHandler read FDebugHandler; {$ENDIF}
   end;

implementation

uses
   sysutils, hashfunctions, isdprotocol, passwords, exceptions, space,
   orbit, spacesensor, structure, errors, plot, planetary, time,
   population, messages, knowledge, isderrors, food, research;

constructor TSystemHashTable.Create();
begin
   inherited Create(@Integer32Hash32);
end;

constructor TDynastyHashTable.Create();
begin
   inherited Create(@Integer32Hash32);
end;


constructor TConnection.Create(AListener: TListenerSocket; AServer: TServer);
begin
   inherited Create(AListener);
   FServer := AServer;
   FWriter := TServerStreamWriter.Create();
end;

destructor TConnection.Destroy();
begin
   if (Assigned(FDynasty)) then
      FDynasty.RemoveConnection(Self);
   FWriter.Free();
   inherited;
end;

procedure TConnection.Invoke(Callback: TConnectionCallback);
begin
   Callback(Self, FWriter);
end;

procedure TConnection.HandleIPC(Arguments: TBinaryStreamReader);


var
   NodeCount: Cardinal;
   
      function CountNodes(Asset: TAssetNode): Boolean;
      begin
         Inc(NodeCount);
         Result := True;
      end;


type
   TStarEntry = record
      StarID: TStarID;
      DX, DY: Double; // meters
   end;
var
   Command: UTF8String;
   SystemID, DynastyID, DynastyServerID, StarCount, Index, StarID: Cardinal;
   X, Y: Double;
   Dynasty: TDynasty;
   System: TSystem;
   Stars: array of TStarEntry;
   Star: TStarEntry;
   Salt: TSalt;
   Hash: THash;
   SolarSystem: TSolarSystemFeatureNode;
begin
   Assert(FMode = cmControlMessages);
   Command := Arguments.ReadString();
   if (Command = icCreateSystem) then // from login server
   begin
      SystemID := Arguments.ReadCardinal();
      X := Arguments.ReadDouble();
      Y := Arguments.ReadDouble();
      StarCount := Arguments.ReadCardinal();
      SetLength(Stars, StarCount);
      if (StarCount > 0) then
      begin
         for Index := 0 to StarCount - 1 do // $R-
         begin
            StarID := Arguments.ReadCardinal();
            if (StarID > High(TStarID)) then
            begin
               Writeln('Received an invalid star ID in ', icCreateSystem, ' command: ', StarID);
               Disconnect();
               exit;
            end;
            Stars[Index].StarID := StarID; // $R-
            Stars[Index].DX := Arguments.ReadDouble();
            Stars[Index].DY := Arguments.ReadDouble();
         end;
      end;
      System := FServer.CreateSystem(SystemID, X, Y);
      Assert(System.RootNode.AssetClass.FeatureCount > 0);
      Assert(System.RootNode.AssetClass.Features[0] is TSolarSystemFeatureClass);
      SolarSystem := System.RootNode.Features[0] as TSolarSystemFeatureNode;
      for Star in Stars do
      begin
         SolarSystem.AddCartesianChild(FServer.Encyclopedia.WrapAssetForOrbit(FServer.Encyclopedia.CreateLoneStar(Star.StarID)), Star.DX, Star.DY); // $R-
      end;
      SolarSystem.ComputeHillSpheres();
      FServer.Encyclopedia.CondenseProtoplanetaryDisks(SolarSystem, System);
      FServer.Encyclopedia.FindTemperatureEquilibria(System); // TODO: figure out when we should recompute these
      Write(#$01);
   end
   else
   if (Command = icTriggerNewDynastyScenario) then // from login server
   begin
      DynastyID := Arguments.ReadCardinal();
      DynastyServerID := Arguments.ReadCardinal();
      SystemID := Arguments.ReadCardinal();
      System := FServer.Systems[SystemID];
      if (not Assigned(System)) then
      begin
         Writeln('Received an invalid system ID for ', icTriggerNewDynastyScenario, ' command: System ', SystemID, ' does not exist.');
         Disconnect();
         exit;
      end;
      Dynasty := FServer.DynastyManager.GetDynasty(DynastyID);
      if (not Assigned(Dynasty)) then
      begin
         Dynasty := FServer.DynastyManager.HandleDynastyArrival(DynastyID, DynastyServerID); // may contact dynasty server
      end;
      Assert(Dynasty.DynastyServerID = DynastyServerID);
      FServer.Encyclopedia.SpawnColonyShip(Dynasty, System);
      Write(#$01);
   end
   else
   if (Command = icRegisterToken) then
   begin
      DynastyID := Arguments.ReadCardinal();
      Arguments.ReadRawBytes(SizeOf(Salt), Salt);
      Arguments.ReadRawBytes(SizeOf(Hash), Hash);
      Dynasty := FServer.DynastyManager.GetDynasty(DynastyID);
      if (not Assigned(Dynasty)) then
      begin
         Writeln('Received an invalid dynasty ID for ', icRegisterToken, ' command: Dynasty ', DynastyID, ' has no units on this server.');
         Disconnect();
         exit;
      end;
      Dynasty.AddToken(Salt, Hash);
      Write(#$01);
   end
   else
   if (Command = icLogout) then
   begin
      DynastyID := Arguments.ReadCardinal();
      Dynasty := FServer.DynastyManager.GetDynasty(DynastyID);
      if (not Assigned(Dynasty)) then
      begin
         Writeln('Received an invalid dynasty ID for ', icLogout, ' command: Dynasty ', DynastyID, ' has no units on this server.');
         Disconnect();
         exit;
      end;
      Dynasty.ResetTokens();
      Write(#$01);
   end
   {$IFOPT C+}
   else
   if (Command = icDebug) then
   begin
      FServer.DebugHandler(Arguments);
      Write(#$01);
   end
   {$ENDIF}
   else
   begin
      Writeln('Received unknown command: ', Command);
      Disconnect();
      exit;
   end;
end;

function TConnection.GetDynasty(DynastyID: Cardinal): TBaseDynasty;
begin
   Result := FServer.DynastyManager.GetDynasty(DynastyID);
end;

procedure TConnection.DoLogin(var Message: TMessage);
var
   DynastyID: Integer;
   SystemStatus: RawByteString;
begin
   DynastyID := VerifyLogin(Message);
   if (DynastyID < 0) then
      exit;
   if (Assigned(FDynasty)) then
   begin
      FDynasty.RemoveConnection(Self);
   end;
   FDynasty := FServer.DynastyManager.GetDynasty(DynastyID); // $R-
   FDynasty.AddConnection(Self);
   Message.Reply();
   Message.Output.WriteCardinal(fcHighestKnownFeatureCode);
   Message.CloseOutput();
   Assert(FWriter.BufferLength = 0);
   SystemStatus := FServer.SerializeAllSystemsFor(FDynasty, FWriter);
   Assert(FWriter.BufferLength = 0);
   Assert(Length(SystemStatus) > 0); // otherwise we wouldn't have their login credentials
   WriteFrame(SystemStatus[1], Length(SystemStatus)); // $R-
end;

procedure TConnection.DoPlay(var Message: TMessage);
var
   SystemID, AssetID: Cardinal;
   Command: UTF8String;
   System: TSystem;
   Asset: TAssetNode;
begin
   if (not Assigned(FDynasty)) then
   begin
      Message.Error(ieNotLoggedIn);
      exit;
   end;
   SystemID := Message.Input.ReadCardinal();
   AssetID := TAssetID(Message.Input.ReadCardinal());
   Command := Message.Input.ReadString();
   // attempt to dispatch message
   System := FServer.FSystems[SystemID];
   if (Assigned(System)) then
   begin
      Asset := System.FindCommandTarget(FDynasty, TAssetID(AssetID));
      if (Assigned(Asset)) then
      begin
         Asset.HandleCommand(Command, Message);
      end;
   end;
   // check for success
   if (not Message.InputClosed) then
   begin
      Message.Error(ieInvalidCommand);
      exit;
   end;
   if (not Message.OutputClosed) then
   begin
      Message.Error(ieInternalError);
      exit;
   end;
end;

function TConnection.GetInternalPassword(): UTF8String;
begin
   Result := FServer.Password;
end;


constructor TInternalDynastyConnection.Create(ADynastyServer: PServerEntry; AServer: TServer);
begin
   inherited Create();
   FDynastyServer := ADynastyServer;
   FServer := AServer;
end;

procedure TInternalDynastyConnection.Connect();
begin
   ConnectIpV4(FDynastyServer^.DirectHost, FDynastyServer^.DirectPort);
end;

procedure TInternalDynastyConnection.Preconnect();
var
   PasswordLengthPrefix: Cardinal;
begin
   inherited;
   Write(#0); // to tell server it's not websockets
   PasswordLengthPrefix := Length(FDynastyServer^.DirectPassword); // $R-
   Write(@PasswordLengthPrefix, SizeOf(PasswordLengthPrefix));
   Write(FDynastyServer^.DirectPassword);
end;

procedure TInternalDynastyConnection.ReportConnectionError(ErrorCode: cint);
begin
   Writeln('Unexpected internal error #', ErrorCode, ': ', StrError(ErrorCode));
   Writeln(GetStackTrace());
end;

function TInternalDynastyConnection.InternalRead(Data: array of byte): Boolean;
begin
   Result := False;
end;

procedure TInternalDynastyConnection.AddServerFor(Dynasty: TDynasty);
var
   Writer: TBinaryStreamWriter;
   Message: RawByteString;
begin
   Writer := TBinaryStreamWriter.Create();
   Writer.WriteString(icAddSystemServer);
   Writer.WriteCardinal(Dynasty.DynastyID);
   Writer.WriteCardinal(FServer.SystemServerID);
   Message := Writer.Serialize(True);
   ConsoleWriteln('Sending IPC to dynasty server: ', Message);
   Write(Message);
   FreeAndNil(Writer);
end;

procedure TInternalDynastyConnection.RemoveServerFor(Dynasty: TDynasty);
var
   Writer: TBinaryStreamWriter;
   Message: RawByteString;
begin
   Writer := TBinaryStreamWriter.Create();
   Writer.WriteString(icRemoveSystemServer);
   Writer.WriteCardinal(Dynasty.DynastyID);
   Writer.WriteCardinal(FServer.SystemServerID);
   Message := Writer.Serialize(True);
   ConsoleWriteln('Sending IPC to dynasty server: ', Message);
   Write(Message);
   FreeAndNil(Writer);
end;


constructor TDynastyManager.Create(AConfigurationDirectory: UTF8String; AServer: TServer);
begin
   inherited Create();
   FConfigurationDirectory := AConfigurationDirectory;
   FServer := AServer;
   FDynasties := TDynastyHashTable.Create();
end;

destructor TDynastyManager.Destroy();
var
   Dynasty: TDynasty;
begin
   if (Assigned(FDynasties)) then
   begin
      for Dynasty in FDynasties.Values do
         Dynasty.Free();
      FDynasties.Free();
   end;
   inherited;
end;

function TDynastyManager.GetDynasty(DynastyID: Cardinal): TDynasty;
begin
   Result := FDynasties[DynastyID];
end;

function TDynastyManager.GetDynastyFromDisk(DynastyID: Cardinal): TDynasty;
var
   ConfigurationDirectory: UTF8String;
begin
   Result := GetDynasty(DynastyID);
   ConfigurationDirectory := FConfigurationDirectory + IntToStr(DynastyID) + '/';
   if ((not Assigned(Result)) and (TDynasty.CanCreateFromDisk(ConfigurationDirectory))) then
   begin
      Result := TDynasty.CreateFromDisk(DynastyID, ConfigurationDirectory, @HandleDynastyDeparture);
      FDynasties[Result.DynastyID] := Result;
   end;
   // it's ok for this to return nil; it means the dynasty was referenced in a journal one time but will eventually go away
end;

function TDynastyManager.HandleDynastyArrival(DynastyID, DynastyServerID: Cardinal): TDynasty;
var
   Dynasty: TDynasty;
   InternalDynastyConnectionSocket: TInternalDynastyConnection;
begin
   Assert(not FDynasties.Has(DynastyID));
   Dynasty := TDynasty.Create(DynastyID, DynastyServerID, FConfigurationDirectory + IntToStr(DynastyID) + '/', @HandleDynastyDeparture);
   FDynasties[Dynasty.DynastyID] := Dynasty;
   Result := Dynasty;
   // Inform Dynasty server
   InternalDynastyConnectionSocket := TInternalDynastyConnection.Create(FServer.DynastyServerDatabase.Servers[DynastyServerID], FServer);
   try
      InternalDynastyConnectionSocket.Connect();
   except
      FreeAndNil(InternalDynastyConnectionSocket);
      raise;
   end;
   FServer.Add(InternalDynastyConnectionSocket);
   InternalDynastyConnectionSocket.AddServerFor(Dynasty);
end;

procedure TDynastyManager.HandleDynastyDeparture(Dynasty: TDynasty);
var
   InternalDynastyConnectionSocket: TInternalDynastyConnection;
begin
   Assert(FDynasties.Has(Dynasty.DynastyID));
   Assert(Dynasty.RefCount = 0);
   // Inform Dynasty server
   InternalDynastyConnectionSocket := TInternalDynastyConnection.Create(FServer.DynastyServerDatabase.Servers[Dynasty.DynastyServerID], FServer);
   try
      InternalDynastyConnectionSocket.Connect();
   except
      FreeAndNil(InternalDynastyConnectionSocket);
      raise;
   end;
   FServer.Add(InternalDynastyConnectionSocket);
   InternalDynastyConnectionSocket.RemoveServerFor(Dynasty);
   Dynasty.ForgetDynasty();
end;


constructor TServer.Create(APort: Word; AClock: TClock; APassword: UTF8String; ASystemServerID: Cardinal; ASettings: PSettings; AEncyclopedia: TEncyclopedia; ADynastyServers: TServerDatabase; AConfigurationDirectory: UTF8String {$IFOPT C+}; ADebugHandler: TDebugHandler {$ENDIF});
var
   SystemsFile: File of Cardinal;
   SystemID: Cardinal;
   System: TSystem;
begin
   inherited Create(APort, AClock);
   FPassword := APassword;
   FSettings := ASettings;
   FDynastyServers := ADynastyServers;
   FConfigurationDirectory := AConfigurationDirectory;
   FEncyclopedia := AEncyclopedia;
   FDynastyManager := TDynastyManager.Create(FConfigurationDirectory + DynastyDataSubDirectory, Self);
   FSystems := TSystemHashTable.Create();
   if (DirectoryExists(FConfigurationDirectory)) then
   begin
      Assign(SystemsFile, FConfigurationDirectory + SystemsDatabaseFileName);
      Reset(SystemsFile);
      while (not Eof(SystemsFile)) do
      begin
         BlockRead(SystemsFile, SystemID, 1); // $DFA- for SystemID
         System := TSystem.CreateFromDisk(FConfigurationDirectory + SystemDataSubDirectory + IntToStr(SystemID) + '/', SystemID, FEncyclopedia.SpaceClass, Self, FDynastyManager, FEncyclopedia);
         Assert(System.SystemID = SystemID);
         FSystems[SystemID] := System;
      end;
      Close(SystemsFile);
   end
   else
   begin
      MkDir(FConfigurationDirectory);
      MkDir(FConfigurationDirectory + DynastyDataSubDirectory);
      MkDir(FConfigurationDirectory + SystemDataSubDirectory);
      Assign(SystemsFile, FConfigurationDirectory + SystemsDatabaseFileName);
      FileMode := 1;
      Rewrite(SystemsFile);
      Close(SystemsFile);
   end;
   {$IFOPT C+}
   FDebugHandler := ADebugHandler;
   {$ENDIF}
end;

destructor TServer.Destroy();
var
   System: TSystem;
begin
   if (Assigned(FSystems)) then
   begin
      for System in FSystems.Values do
         System.Free();
      FSystems.Free();
   end;
   inherited; // frees connections, which know about the dynasties
   FDynastyManager.Free(); // frees dynasties
end;

function TServer.CreateNetworkSocket(AListenerSocket: TListenerSocket): TNetworkSocket;
begin
   Result := TConnection.Create(AListenerSocket, Self);
end;

function TServer.GetSystem(Index: Cardinal): TSystem;
begin
   Result := FSystems[Index];
end;

function TServer.CreateSystem(SystemID: Cardinal; X, Y: Double): TSystem;
var
   SystemsFile: File of Cardinal;
begin
   Assert(not FSystems.Has(SystemID));
   Result := TSystem.Create(FConfigurationDirectory + SystemDataSubDirectory + IntToStr(SystemID) + '/', SystemID, X, Y, FEncyclopedia.SpaceClass, Self, FDynastyManager, FEncyclopedia, FSettings);
   FSystems[SystemID] := Result;
   Assign(SystemsFile, FConfigurationDirectory + SystemsDatabaseFileName);
   FileMode := 2;
   Reset(SystemsFile);
   Seek(SystemsFile, FSystems.Count - 1);
   BlockWrite(SystemsFile, SystemID, 1); // $DFA- for SystemID
   Close(SystemsFile);
end;

procedure TServer.ReportChanges();
var
   System: TSystem;
begin
   for System in FSystems.Values do
      System.ReportChanges();
end;

function TServer.SerializeAllSystemsFor(Dynasty: TDynasty; Writer: TServerStreamWriter): RawByteString;
var
   System: TSystem;
begin
   for System in FSystems.Values do
   begin
      if (System.HasDynasty(Dynasty)) then
      begin
         System.SerializeSystem(Dynasty, Writer, False);
      end;
   end;
   Result := Writer.Serialize(False);
   Writer.Clear();
end;

end.
