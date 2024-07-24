{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit network;

interface

uses
   corenetwork, binarystream, basenetwork, dynasty, hashtable, genericutils,
   basedynasty, authnetwork, servers, sharedpointer, passwords;

type
   TDynastyHashTable = class(specialize THashTable<Cardinal, TDynasty, CardinalUtils>)
      constructor Create();
   end;

   TServer = class;
   
   TConnection = class(TAuthenticatableBaseIncomingInternalCapableConnection)
   protected
      FServer: TServer;
      FDynasty: TDynasty;
      procedure HandleIPC(Arguments: TBinaryStreamReader); override;
      function GetDynasty(DynastyID: Cardinal): TBaseDynasty; override;
      procedure DoLogin(var Message: TMessage); message 'login';
      procedure GetStarName(var Message: TMessage) message 'get-star-name'; // argument: star ID
      function GetInternalPassword(): UTF8String; override;
   public
      constructor Create(AListener: TListenerSocket; AServer: TServer);
      destructor Destroy(); override;
   end;

   TInternalSystemConnection = class(TBaseOutgoingInternalConnection)
   protected
      FServer: TServer;
      FConversation: specialize TSharedPointer<TInternalConversationHandle>;
      procedure Done(); override;
   public
      constructor Create(AServer: TServer; ASystemServer: PServerEntry; AConversation: TInternalConversationHandle);
      procedure RegisterToken(Dynasty: TDynasty; Salt: TSalt; Hash: THash);
      procedure Logout(Dynasty: TDynasty);
   end;
   
   TServer = class(TBaseServer)
   protected
      FPassword: UTF8String;
      FSystemServers: TServerDatabase;
      FDynasties: TDynastyHashTable;
      FConfigurationDirectory: UTF8String;
      function CreateNetworkSocket(AListenerSocket: TListenerSocket): TNetworkSocket; override;
      function GetDynasty(Index: Cardinal): TDynasty;
   public
      constructor Create(APort: Word; APassword: UTF8String; ASystemServers: TServerDatabase; AConfigurationDirectory: UTF8String);
      destructor Destroy(); override;
      procedure AddDynasty(DynastyID: Cardinal);
      property Password: UTF8String read FPassword;
      property Dynasties[Index: Cardinal]: TDynasty read GetDynasty;
      property SystemServerDatabase: TServerDatabase read FSystemServers;
   end;

implementation

uses
   sysutils, hashfunctions, isdprotocol, configuration, astronomy, isderrors;

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
var
   Command: UTF8String;
   DynastyID, SystemServerID: Cardinal;
   Dynasty: TDynasty;
   Salt: TSalt;
   Hash: THash;
   Tokens: TTokenArray;
   Token: TToken;
   Index: Cardinal;
   Conversation: TInternalConversationHandle;
   Socket: TInternalSystemConnection;
begin
   Assert(FMode = cmControlMessages);
   Command := Arguments.ReadString();
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
            Socket := TInternalSystemConnection.Create(FServer, FServer.SystemServerDatabase.Servers[Dynasty.Servers[Index].ServerID], Conversation);
            try
               Socket.Connect();
            except
               FreeAndNil(Socket);
               raise;
            end;
            FServer.Add(Socket);
            Socket.RegisterToken(Dynasty, Salt, Hash);
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
            Socket := TInternalSystemConnection.Create(FServer, FServer.SystemServerDatabase.Servers[Dynasty.Servers[Index].ServerID], Conversation);
            try
               Socket.Connect();
            except
               FreeAndNil(Socket);
               raise;
            end;
            FServer.Add(Socket);
            Socket.Logout(Dynasty);
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
         Socket := TInternalSystemConnection.Create(FServer, FServer.SystemServerDatabase.Servers[SystemServerID], Conversation);
         try
            Socket.Connect();
         except
            FreeAndNil(Socket);
            raise;
         end;
         FServer.Add(Socket);
         for Token in Tokens do
         begin
            Socket.RegisterToken(Dynasty, Token.Salt, Token.Hash);
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
   begin
      Writeln('Received unknown command: ', Command);
      Disconnect();
      exit;
   end;
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
   FDynasty := FServer.Dynasties[DynastyID]; // $R-
   FDynasty.AddConnection(Self);
   Message.Reply();
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


constructor TInternalSystemConnection.Create(AServer: TServer; ASystemServer: PServerEntry; AConversation: TInternalConversationHandle);
begin
   inherited Create(ASystemServer);
   FServer := AServer;
   FConversation := AConversation;
   FConversation.Value.AddHold();
end;

procedure TInternalSystemConnection.Done();
begin
   FConversation.Value.RemoveHold();
end;

procedure TInternalSystemConnection.RegisterToken(Dynasty: TDynasty; Salt: TSalt; Hash: THash);
var
   Writer: TBinaryStreamWriter;
begin
   Writer := TBinaryStreamWriter.Create();
   Writer.WriteString(icRegisterToken);
   Writer.WriteCardinal(Dynasty.DynastyID);
   Writer.WriteRawBytes(@Salt[0], SizeOf(Salt));
   Writer.WriteRawBytes(@Hash[0], SizeOf(Hash));
   Write(Writer.Serialize(True));
   FreeAndNil(Writer);
   IncrementPendingCount();
end;

procedure TInternalSystemConnection.Logout(Dynasty: TDynasty);
var
   Writer: TBinaryStreamWriter;
begin
   Writer := TBinaryStreamWriter.Create();
   Writer.WriteString(icLogout);
   Writer.WriteCardinal(Dynasty.DynastyID);
   Write(Writer.Serialize(True));
   FreeAndNil(Writer);
   IncrementPendingCount();
end;


constructor TServer.Create(APort: Word; APassword: UTF8String; ASystemServers: TServerDatabase; AConfigurationDirectory: UTF8String);
var
   DynastiesFile: File of Cardinal;
   DynastyID: Cardinal;
   Dynasty: TDynasty;
begin
   inherited Create(APort);
   FPassword := APassword;
   FSystemServers := ASystemServers;
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

end.
