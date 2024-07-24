{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit network;

interface

uses
   corenetwork, binarystream, basenetwork, dynasty, astronomy,
   systems, hashtable, genericutils, basedynasty, encyclopedia,
   configuration, servers, baseunix, authnetwork;

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
      procedure HandleIPC(Arguments: TBinaryStreamReader); override;
      function GetDynasty(DynastyID: Cardinal): TBaseDynasty; override; // used for VerifyLogin
      procedure DoLogin(var Message: TMessage); message 'login';
      function GetInternalPassword(): UTF8String; override;
   public
      constructor Create(AListener: TListenerSocket; AServer: TServer);
      destructor Destroy(); override;
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

   TServer = class(TBaseServer)
   protected
      FPassword: UTF8String;
      FSystemServerID: Cardinal;
      FDynastyServers: TServerDatabase;
      FConfigurationDirectory: UTF8String;
      FSystems: TSystemHashTable;
      FEncyclopedia: TEncyclopedia;
      FDynastyManager: TDynastyManager;
      function CreateNetworkSocket(AListenerSocket: TListenerSocket): TNetworkSocket; override;
      function GetSystem(Index: Cardinal): TSystem;
      function CreateSystem(SystemID: Cardinal): TSystem;
      procedure ReportChanges(); override;
   public
      constructor Create(APort: Word; APassword: UTF8String; ASystemServerID: Cardinal; ASettings: PSettings; ADynastyServers: TServerDatabase; AConfigurationDirectory: UTF8String);
      destructor Destroy(); override;
      function SerializeAllSystemsFor(Dynasty: TDynasty): RawByteString;
      property Password: UTF8String read FPassword;
      property SystemServerID: Cardinal read FSystemServerID;
      property Systems[Index: Cardinal]: TSystem read GetSystem;
      property DynastyManager: TDynastyManager read FDynastyManager;
      property DynastyServerDatabase: TServerDatabase read FDynastyServers;
      property Encyclopedia: TEncyclopedia read FEncyclopedia;
   end;

implementation

uses
   sysutils, hashfunctions, isdprotocol, passwords, exceptions, space, orbit, errors;

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
end;

destructor TConnection.Destroy();
begin
   if (Assigned(FDynasty)) then
      FDynasty.RemoveConnection(Self);
   inherited;
end;

procedure TConnection.HandleIPC(Arguments: TBinaryStreamReader);
type
   TStarEntry = record
      StarID: TStarID;
      DX, DY: Double; // meters
   end;
var
   Command: UTF8String;
   SystemID, DynastyID, DynastyServerID, StarCount, Index, StarID: Cardinal;
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
      System := FServer.CreateSystem(SystemID);
      Assert(System.RootNode.AssetClass.FeatureCount > 0);
      Assert(System.RootNode.AssetClass.Features[0] is TSolarSystemFeatureClass);
      SolarSystem := System.RootNode.Features[0] as TSolarSystemFeatureNode;
      for Star in Stars do
      begin
         SolarSystem.AddCartesianChild(FServer.Encyclopedia.CreateStarSystem(StarID), Star.DX, Star.DY); // $R-
      end;
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
      ((System.RootNode.Features[0] as TSolarSystemFeatureNode).Children[0].Features[0] as TOrbitFeatureNode).AddOrbitingChild(
         FServer.Encyclopedia.WrapAssetForOrbit(FServer.Encyclopedia.Placeholder.Spawn(Dynasty)),
         1 * AU, // SemiMajorAxis
         1.0, // Eccentricity
         0.0, // ThetaZero
         0.0 // Omega
      );
      // TODO: actual plot
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
   FDynasty := FServer.DynastyManager.GetDynasty(DynastyID); // $R-
   FDynasty.AddConnection(Self);
   Message.Reply();
   Message.Output.WriteCardinal(fcHighestKnownFeatureCode);
   Message.Output.WriteCardinal(DynastyID); // $R-
   Message.CloseOutput();
   SystemStatus := FServer.SerializeAllSystemsFor(FDynasty);
   Assert(Length(SystemStatus) > 0);
   WriteFrame(SystemStatus[1], Length(SystemStatus)); // $R-
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
begin
   Writer := TBinaryStreamWriter.Create();
   Writer.WriteString(icAddSystemServer);
   Writer.WriteCardinal(Dynasty.DynastyID);
   Writer.WriteCardinal(FServer.SystemServerID);
   Write(Writer.Serialize(True));
   FreeAndNil(Writer);
end;

procedure TInternalDynastyConnection.RemoveServerFor(Dynasty: TDynasty);
var
   Writer: TBinaryStreamWriter;
begin
   Writer := TBinaryStreamWriter.Create();
   Writer.WriteString(icRemoveSystemServer);
   Writer.WriteCardinal(Dynasty.DynastyID);
   Writer.WriteCardinal(FServer.SystemServerID);
   Write(Writer.Serialize(True));
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


constructor TServer.Create(APort: Word; APassword: UTF8String; ASystemServerID: Cardinal; ASettings: PSettings; ADynastyServers: TServerDatabase; AConfigurationDirectory: UTF8String);
var
   SystemsFile: File of Cardinal;
   SystemID: Cardinal;
   System: TSystem;
begin
   inherited Create(APort);
   FPassword := APassword;
   FDynastyServers := ADynastyServers;
   FConfigurationDirectory := AConfigurationDirectory;
   FEncyclopedia := TEncyclopedia.Create(ASettings);
   FDynastyManager := TDynastyManager.Create(FConfigurationDirectory + DynastyDataSubDirectory, Self);
   FSystems := TSystemHashTable.Create();
   if (DirectoryExists(FConfigurationDirectory)) then
   begin
      Assign(SystemsFile, FConfigurationDirectory + SystemsDatabaseFileName);
      Reset(SystemsFile);
      while (not Eof(SystemsFile)) do
      begin
         BlockRead(SystemsFile, SystemID, 1); // $DFA- for SystemID
         System := TSystem.CreateFromDisk(FConfigurationDirectory + SystemDataSubDirectory + IntToStr(SystemID) + '/', SystemID, FEncyclopedia.SpaceClass, FDynastyManager, FEncyclopedia);
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
   FEncyclopedia.Free();
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

function TServer.CreateSystem(SystemID: Cardinal): TSystem;
var
   SystemsFile: File of Cardinal;
begin
   Assert(not FSystems.Has(SystemID));
   Result := TSystem.Create(FConfigurationDirectory + SystemDataSubDirectory + IntToStr(SystemID) + '/', SystemID, FEncyclopedia.SpaceClass, FDynastyManager, FEncyclopedia);
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

function TServer.SerializeAllSystemsFor(Dynasty: TDynasty): RawByteString;
var
   Writer: TBinaryStreamWriter;
   System: TSystem;
begin
   Writer := TBinaryStreamWriter.Create();
   for System in FSystems.Values do
   begin
      if (System.HasDynasty(Dynasty)) then
      begin
         System.SerializeSystemFor(Dynasty, Writer, False);
      end;
   end;
   Result := Writer.Serialize(False);
   Writer.Free();
end;


end.
