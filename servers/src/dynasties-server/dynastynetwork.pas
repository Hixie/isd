{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit dynastynetwork;

interface

uses
   corenetwork, binarystream, basenetwork, dynasty, hashtable, genericutils,
   basedynasty, authnetwork, servers, sharedpointer, passwords, unixtype;

type
   TDynastyHashTable = class(specialize THashTable<Cardinal, TDynasty, CardinalUtils>)
      constructor Create();
   end;

   TServer = class;

   TConnection = class(TAuthenticatableBaseIncomingInternalCapableConnection)
   protected
      FServer: TServer;
      FDynasty: TDynasty;
      procedure HandleIPC(const Command: UTF8String; const Arguments: TBinaryStreamReader); override;
      function GetDynasty(DynastyID: Cardinal): TBaseDynasty; override;
      procedure DoLogin(var Message: TMessage); message 'login';
      procedure GetStarName(var Message: TMessage) message 'get-star-name'; // argument: star ID
      function GetInternalPassword(): UTF8String; override;
   public
      constructor Create(AListener: TListenerSocket; AServer: TServer);
      destructor Destroy(); override;
   end;

   TInternalConnection = class abstract(TBaseOutgoingInternalConnection)
   protected
      FServer: TServer;
      FConversation: specialize TSharedPointer<TInternalConversationHandle>;
      procedure Done(); override;
   public
      constructor Create(AServer: TServer; AServerEntry: PServerEntry; AConversation: TInternalConversationHandle);
      procedure ReportConnectionError(ErrorCode: cint); override;
   end;

   TInternalSystemConnection = class(TInternalConnection)
   public
      procedure RegisterToken(Dynasty: TDynasty; Salt: TSalt; Hash: THash);
      procedure Logout(Dynasty: TDynasty);
   end;

   TInternalLoginConnection = class(TInternalConnection)
   public
      procedure UpdateScore(Dynasty: TDynasty);
   end;

   TServer = class(TBaseServer)
   protected
      FSystemServers: TServerDatabase;
      FLoginServers: TServerDatabase;
      FDynasties: TDynastyHashTable;
      FConfigurationDirectory: UTF8String;
      function CreateNetworkSocket(AListenerSocket: TListenerSocket): TNetworkSocket; override;
      function GetDynasty(Index: Cardinal): TDynasty;
      function GetLoginServer(): PServerEntry;
   public
      constructor Create(APort: Word; APassword: UTF8String; ALoginServers, ASystemServers: TServerDatabase; AConfigurationDirectory: UTF8String);
      destructor Destroy(); override;
      procedure AddDynasty(DynastyID: Cardinal);
      property Dynasties[Index: Cardinal]: TDynasty read GetDynasty;
      property SystemServerDatabase: TServerDatabase read FSystemServers;
      property LoginServer: PServerEntry read GetLoginServer;
   end;

implementation

uses
   sysutils, hashfunctions, isdprotocol, configuration, astronomy, isderrors, errors;

constructor TDynastyHashTable.Create();
begin
   inherited Create(@Integer32Hash32);
end;


constructor TConnection.Create(AListener: TListenerSocket; AServer: TServer);
begin
   inherited Create(AListener, AServer);
   FServer := AServer;
end;

destructor TConnection.Destroy();
begin
   if (Assigned(FDynasty)) then
      FDynasty.RemoveConnection(Self);
   inherited;
end;

procedure TConnection.HandleIPC(const Command: UTF8String; const Arguments: TBinaryStreamReader);
var
   DynastyID, SystemServerID: Cardinal;
   Dynasty: TDynasty;
   Salt: TSalt;
   Hash: THash;
   Tokens: TTokenArray;
   Token: TToken;
   Index: Cardinal;
   Conversation: TInternalConversationHandle;
   SystemSocket: TInternalSystemConnection;
   LoginSocket: TInternalLoginConnection;
   Score: Double;
begin
   if (Command = icCreateAccount) then
   begin
      DynastyID := Arguments.ReadCardinal();
      Dynasty := FServer.Dynasties[DynastyID];
      if (Assigned(Dynasty)) then
      begin
         Writeln('Received an invalid dynasty ID for ', icCreateAccount, ' command: Dynasty ', DynastyID, ' is already a known dynasty on this server.');
         Disconnect();
         exit;
      end;
      FServer.AddDynasty(DynastyID);
      Write(#$01);
   end
   else
   if (Command = icRegisterToken) then
   begin
      DynastyID := Arguments.ReadCardinal();
      Arguments.ReadRawBytes(SizeOf(Salt), Salt);
      Arguments.ReadRawBytes(SizeOf(Hash), Hash);
      Dynasty := FServer.Dynasties[DynastyID];
      if (not Assigned(Dynasty)) then
      begin
         Writeln('Received an invalid dynasty ID for ', icRegisterToken, ' command: Dynasty ', DynastyID, ' is not assigned to this server.');
         Disconnect();
         exit;
      end;
      Dynasty.AddToken(Salt, Hash);
      // Connect to each system server dynasty has and forward the token
      if (Dynasty.ServerCount > 0) then
      begin
         Conversation := TInternalConversationHandle.Create(Self);
         for Index := 0 to Dynasty.ServerCount - 1 do // $R-
         begin
            SystemSocket := TInternalSystemConnection.Create(FServer, FServer.SystemServerDatabase.Servers[Dynasty.Servers[Index]^.ServerID], Conversation);
            try
               SystemSocket.Connect();
            except
               FreeAndNil(SystemSocket);
               raise;
            end;
            FServer.Add(SystemSocket);
            SystemSocket.RegisterToken(Dynasty, Salt, Hash);
         end;
         Assert(Conversation.HasHolds);
      end
      else
      begin
         Write(#$01); // nothing else to do
      end;
   end
   else
   if (Command = icLogout) then
   begin
      DynastyID := Arguments.ReadCardinal();
      Dynasty := FServer.Dynasties[DynastyID];
      if (not Assigned(Dynasty)) then
      begin
         Writeln('Received an invalid dynasty ID for ', icLogout, ' command: Dynasty ', DynastyID, ' is not assigned to this server.');
         Disconnect();
         exit;
      end;
      Dynasty.ResetTokens();
      // Connect to each system server dynasty has and forward the logout request
      if (Dynasty.ServerCount > 0) then
      begin
         Conversation := TInternalConversationHandle.Create(Self);
         for Index := 0 to Dynasty.ServerCount - 1 do // $R-
         begin
            SystemSocket := TInternalSystemConnection.Create(FServer, FServer.SystemServerDatabase.Servers[Dynasty.Servers[Index]^.ServerID], Conversation);
            try
               SystemSocket.Connect();
            except
               FreeAndNil(SystemSocket);
               raise;
            end;
            FServer.Add(SystemSocket);
            SystemSocket.Logout(Dynasty);
         end;
         Assert(Conversation.HasHolds);
      end
      else
      begin
         Write(#$01); // nothing else to do
      end;
   end
   else
   if (Command = icAddSystemServer) then
   begin
      DynastyID := Arguments.ReadCardinal();
      Dynasty := FServer.Dynasties[DynastyID];
      if (not Assigned(Dynasty)) then
      begin
         Writeln('Received an invalid dynasty ID for ', icAddSystemServer, ' command: Dynasty ', DynastyID, ' is not assigned to this server.');
         Disconnect();
         exit;
      end;
      SystemServerID := Arguments.ReadCardinal();
      Dynasty.AddSystemServer(SystemServerID);
      Dynasty.UpdateClients(FServer.SystemServerDatabase);
      // Connect to that system server and tell it all the dynasty's tokens
      Tokens := Dynasty.Tokens;
      if (Length(Tokens) > 0) then
      begin
         Conversation := TInternalConversationHandle.Create(Self);
         SystemSocket := TInternalSystemConnection.Create(FServer, FServer.SystemServerDatabase.Servers[SystemServerID], Conversation);
         try
            SystemSocket.Connect();
         except
            FreeAndNil(SystemSocket);
            raise;
         end;
         FServer.Add(SystemSocket);
         for Token in Tokens do
         begin
            SystemSocket.RegisterToken(Dynasty, Token.Salt, Token.Hash);
         end;
         Assert(Conversation.HasHolds);
      end
      else
      begin
         Write(#$01); // nothing else to do
      end;
   end
   else
   if (Command = icRemoveSystemServer) then
   begin
      DynastyID := Arguments.ReadCardinal();
      Dynasty := FServer.Dynasties[DynastyID];
      if (not Assigned(Dynasty)) then
      begin
         Writeln('Received an invalid dynasty ID for ', icRemoveSystemServer, ' command: Dynasty ', DynastyID, ' is not assigned to this server.');
         Disconnect();
         exit;
      end;
      SystemServerID := Arguments.ReadCardinal();
      Dynasty.RemoveSystemServer(SystemServerID);
      Dynasty.UpdateClients(FServer.SystemServerDatabase);
      Write(#$01);
   end
   else
   if (Command = icUpdateScoreDatum) then
   begin
      DynastyID := Arguments.ReadCardinal();
      Dynasty := FServer.Dynasties[DynastyID];
      if (not Assigned(Dynasty)) then
      begin
         Writeln('Received an invalid dynasty ID for ', icUpdateScoreDatum, ' command: Dynasty ', DynastyID, ' is not assigned to this server.');
         Disconnect();
         exit;
      end;
      SystemServerID := Arguments.ReadCardinal();
      Score := Arguments.ReadDouble();
      Dynasty.UpdateScore(SystemServerID, Score);
      // Now update login server.
      Conversation := TInternalConversationHandle.Create(Self);
      LoginSocket := TInternalLoginConnection.Create(FServer, FServer.LoginServer, Conversation);
      try
         LoginSocket.Connect();
      except
         FreeAndNil(LoginSocket);
         raise;
      end;
      FServer.Add(LoginSocket);
      LoginSocket.UpdateScore(Dynasty);
      Assert(Conversation.HasHolds);
   end
   else
      inherited;
end;

function TConnection.GetDynasty(DynastyID: Cardinal): TBaseDynasty;
begin
   Result := FServer.Dynasties[DynastyID];
end;

procedure TConnection.DoLogin(var Message: TMessage);
var
   DynastyID: Integer;
begin
   DynastyID := VerifyLogin(Message);
   if (DynastyID < 0) then
      exit;
   if (Assigned(FDynasty)) then
   begin
      FDynasty.RemoveConnection(Self);
   end;
   FDynasty := FServer.Dynasties[DynastyID]; // $R-
   FDynasty.AddConnection(Self);
   Message.Reply();
   Message.Output.WriteCardinal(DynastyID); // $R-
   FDynasty.EncodeServers(FServer.SystemServerDatabase, Message.Output);
   Message.CloseOutput();
end;

procedure TConnection.GetStarName(var Message: TMessage);
var
   StarID: Cardinal;
begin
   StarID := Message.Input.ReadCardinal();
   if (not Message.CloseInput()) then
      exit;
   if (StarID > High(TStarID)) then
   begin
      Message.Error(ieInvalidMessage);
      exit;
   end;
   Message.Reply();
   Message.Output.WriteString(StarNameOf(StarID)); // $R-
   Message.CloseOutput();
end;

function TConnection.GetInternalPassword(): UTF8String;
begin
   Result := FServer.Password;
end;


constructor TInternalConnection.Create(AServer: TServer; AServerEntry: PServerEntry; AConversation: TInternalConversationHandle);
begin
   inherited Create(AServerEntry);
   FServer := AServer;
   FConversation := AConversation;
   FConversation.Value.AddHold();
end;

procedure TInternalConnection.Done();
begin
   FConversation.Value.RemoveHold();
end;

procedure TInternalConnection.ReportConnectionError(ErrorCode: cint);
begin
   FConversation.Value.FailHold();
   Writeln('IPC connection to system server failed with error #', ErrorCode, ': ', StrError(ErrorCode));
end;


procedure TInternalSystemConnection.RegisterToken(Dynasty: TDynasty; Salt: TSalt; Hash: THash);
var
   Writer: TBinaryStreamWriter;
   Message: RawByteString;
begin
   Writer := TBinaryStreamWriter.Create();
   Writer.WriteStringByPointer(icRegisterToken);
   Writer.WriteCardinal(Dynasty.DynastyID);
   Writer.WriteRawBytesByPointer(@Salt[0], SizeOf(Salt));
   Writer.WriteRawBytesByPointer(@Hash[0], SizeOf(Hash));
   Message := Writer.Serialize(True);
   if (FConversation.Value.HasFailed) then
   begin
      ConsoleWriteln('Would send IPC to system server (but connection has failed): ', Message);
   end
   else
   begin
      ConsoleWriteln('Sending IPC to system server: ', Message);
   end;
   Write(Message);
   FreeAndNil(Writer);
   IncrementPendingCount();
end;

procedure TInternalSystemConnection.Logout(Dynasty: TDynasty);
var
   Writer: TBinaryStreamWriter;
   Message: RawByteString;
begin
   Writer := TBinaryStreamWriter.Create();
   Writer.WriteStringByPointer(icLogout);
   Writer.WriteCardinal(Dynasty.DynastyID);
   Message := Writer.Serialize(True);
   if (FConversation.Value.HasFailed) then
   begin
      ConsoleWriteln('Would send IPC to system server (but connection has failed): ', Message);
   end
   else
   begin
      ConsoleWriteln('Sending IPC to system server: ', Message);
   end;
   Write(Message);
   FreeAndNil(Writer);
   IncrementPendingCount();
end;


procedure TInternalLoginConnection.UpdateScore(Dynasty: TDynasty);
var
   Writer: TBinaryStreamWriter;
   Message: RawByteString;
begin
   Writer := TBinaryStreamWriter.Create();
   Writer.WriteStringByPointer(icAddScoreDatum);
   Writer.WriteCardinal(Dynasty.DynastyID);
   Writer.WriteDouble(Dynasty.ComputeScore());
   Message := Writer.Serialize(True);
   if (FConversation.Value.HasFailed) then
   begin
      ConsoleWriteln('Would send IPC to login server (but connection has failed): ', Message);
   end
   else
   begin
      ConsoleWriteln('Sending IPC to login server: ', Message);
   end;
   Write(Message);
   FreeAndNil(Writer);
   IncrementPendingCount();
end;


constructor TServer.Create(APort: Word; APassword: UTF8String; ALoginServers,ASystemServers: TServerDatabase; AConfigurationDirectory: UTF8String);
var
   DynastiesFile: File of Cardinal;
   DynastyID: Cardinal;
   Dynasty: TDynasty;
begin
   inherited Create(APort, APassword, nil);
   FSystemServers := ASystemServers;
   FLoginServers := ALoginServers;
   Assert(FLoginServers.Count = 1);
   FDynasties := TDynastyHashTable.Create();
   FConfigurationDirectory := AConfigurationDirectory;
   if (DirectoryExists(FConfigurationDirectory)) then
   begin
      Assign(DynastiesFile, FConfigurationDirectory + DynastiesDatabaseFileName);
      Reset(DynastiesFile);
      while (not Eof(DynastiesFile)) do
      begin
         BlockRead(DynastiesFile, DynastyID, 1); // $DFA- for DynastyID
         Dynasty := TDynasty.CreateFromDisk(FConfigurationDirectory + IntToStr(DynastyID) + '/');
         Assert(Dynasty.DynastyID = DynastyID);
         FDynasties[DynastyID] := Dynasty;
      end;
      Close(DynastiesFile);
   end
   else
   begin
      MkDir(FConfigurationDirectory);
      Assign(DynastiesFile, FConfigurationDirectory + DynastiesDatabaseFileName);
      FileMode := 1;
      Rewrite(DynastiesFile);
      Close(DynastiesFile);
   end;
end;

destructor TServer.Destroy();
var
   Dynasty: TDynasty;
begin
   inherited Destroy();
   if (Assigned(FDynasties)) then
   begin
      for Dynasty in FDynasties.Values do
         Dynasty.Free();
      FDynasties.Free();
   end;
end;

function TServer.CreateNetworkSocket(AListenerSocket: TListenerSocket): TNetworkSocket;
begin
   Result := TConnection.Create(AListenerSocket, Self);
end;

function TServer.GetDynasty(Index: Cardinal): TDynasty;
begin
   Result := FDynasties[Index];
end;

procedure TServer.AddDynasty(DynastyID: Cardinal);
var
   Dynasty: TDynasty;
   DynastiesFile: File of Cardinal;
begin
   Assert(not FDynasties.Has(DynastyID));
   Dynasty := TDynasty.Create(DynastyID, FConfigurationDirectory + IntToStr(DynastyID) + '/');
   FDynasties[Dynasty.DynastyID] := Dynasty;
   Assign(DynastiesFile, FConfigurationDirectory + DynastiesDatabaseFileName);
   FileMode := 2;
   Reset(DynastiesFile);
   Seek(DynastiesFile, FDynasties.Count - 1);
   BlockWrite(DynastiesFile, DynastyID, 1);
   Close(DynastiesFile);
end;

function TServer.GetLoginServer(): PServerEntry;
begin
   Result := FLoginServers.Servers[0];
end;

end.
