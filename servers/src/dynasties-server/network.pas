{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit network;

interface

uses
   corenetwork, corewebsocket, binarystream, isderrors, messages, basenetwork, dynasty, hashtable, genericutils;

type
   TDynastyHashTable = class(specialize THashTable<Cardinal, TDynasty, CardinalUtils>)
      constructor Create();
   end;

   TConnectionMode = (cmNew, cmWebsocket, cmControlHandshake, cmControlMessages);

   TServer = class;
   
   TConnection = class(TBaseConnection)
   protected
      FServer: TServer;
      FMode: TConnectionMode;
      FIPCBuffer: TBinaryStreamWriter;
      FDynasty: TDynasty;
      function InternalRead(Data: array of Byte): Boolean; override;
      procedure MaybeHandleIPC();
      procedure MaybeHandleIPCPassword();
      procedure HandleIPC(Arguments: TBinaryStreamReader);
      procedure DoLogin(var Message: TMessage); message 'login';
   public
      constructor Create(AListener: TListenerSocket; AServer: TServer);
      destructor Destroy(); override;
   end;
   
   TServer = class(TBaseServer)
   protected
      FPassword: UTF8String;
      FDynasties: TDynastyHashTable;
      FConfigurationDirectory: UTF8String;
      function CreateNetworkSocket(AListenerSocket: TListenerSocket): TNetworkSocket; override;
      function GetDynasty(Index: Cardinal): TDynasty;
   public
      constructor Create(APort: Word; APassword: UTF8String; AConfigurationDirectory: UTF8String);
      destructor Destroy(); override;
      procedure AddDynasty(DynastyID: Cardinal);
      property Password: UTF8String read FPassword;
      property Dynasties[Index: Cardinal]: TDynasty read GetDynasty;
   end;

implementation

uses
   sysutils, hashfunctions, isdprotocol, passwords, configuration;

constructor TDynastyHashTable.Create();
begin
   inherited Create(@Integer32Hash32);
end;

constructor TConnection.Create(AListener: TListenerSocket; AServer: TServer);
begin
   inherited Create(AListener, @AServer.ScheduleDemolition);
   FServer := AServer;
   FIPCBuffer := TBinaryStreamWriter.Create();
end;

destructor TConnection.Destroy();
begin
   FreeAndNil(FIPCBuffer);
   inherited;
end;

function TConnection.InternalRead(Data: array of Byte): Boolean;
var
   ReceivedControlHandshake: Boolean;
begin
   ReceivedControlHandshake := False;
   Assert(Length(Data) > 0);
   if (FMode = cmNew) then
   begin
      if (Data[0] = $00) then
      begin
         FMode := cmControlHandshake;
         ReceivedControlHandshake := True;
         Writeln('   Switching to cmControlHandshake...');
      end
      else
      begin
         FMode := cmWebSocket;
      end;
   end;
   if (FMode = cmWebSocket) then
   begin
      Result := inherited;
   end
   else
   begin
      FIPCBuffer.WriteRawBytes(@Data[0], Length(Data)); // $R-
      if (ReceivedControlHandshake) then
      begin
         FIPCBuffer.Consume(1);
      end;
      if (FMode = cmControlHandshake) then
      begin
         MaybeHandleIPCPassword();
         // can change the mode to cmControlMessages
      end;
      if (FMode = cmControlMessages) then
      begin
         MaybeHandleIPC();
      end;
      Result := True;
   end;
end;

procedure TConnection.MaybeHandleIPCPassword();
var
   FullBuffer: RawByteString;
   Reader: TBinaryStreamReader;
   BufferLength: Cardinal;
begin
   Writeln('   Considering password message...');
   if (FIPCBuffer.BufferLength >= SizeOf(Cardinal)) then
   begin
      FullBuffer := FIPCBuffer.Serialize(False);
      Reader := TBinaryStreamReader.Create(FullBuffer);
      BufferLength := Reader.ReadCardinal();
      if (SizeOf(Cardinal) + BufferLength <= Length(FullBuffer)) then
      begin
         Writeln('   Received length-prefixed message of size ', BufferLength);
         FIPCBuffer.Consume(SizeOf(Cardinal) + BufferLength); // $R-
         Reader.Reset();
         if (Reader.ReadString() <> FServer.Password) then
         begin
            Disconnect();
         end
         else
         begin
            FMode := cmControlMessages;
         end;
      end;
      FreeAndNil(Reader);
   end;
end;

procedure TConnection.MaybeHandleIPC();
var
   FullBuffer: RawByteString;
   Reader: TBinaryStreamReader;
   BufferLength: Cardinal;
begin
   Writeln('   Considering IPC message...');
   while (FIPCBuffer.BufferLength >= SizeOf(Cardinal)) do
   begin
      FullBuffer := FIPCBuffer.Serialize(False);
      Reader := TBinaryStreamReader.Create(FullBuffer);
      try
         BufferLength := Reader.ReadCardinal();
         if (SizeOf(Cardinal) + BufferLength <= Length(FullBuffer)) then
         begin
            Writeln('   Received length-prefixed message of size ', BufferLength);
            FIPCBuffer.Consume(SizeOf(Cardinal) + BufferLength); // $R-
            Reader.Truncate(BufferLength);
            HandleIPC(Reader);
         end
         else
         begin
            exit;
         end;
      finally
         FreeAndNil(Reader);
      end;
   end;
end;

procedure TConnection.HandleIPC(Arguments: TBinaryStreamReader);
var
   Command: UTF8String;
   DynastyID: Cardinal;
   Dynasty: TDynasty;
   Salt: TSalt;
   Hash: THash;
begin
   Assert(FMode = cmControlMessages);
   Command := Arguments.ReadString();
   if (Command = icCreateAccount) then
   begin
      DynastyID := Arguments.ReadCardinal();
      Writeln('Received IPC: Create dynasty ', DynastyID);
      Dynasty := FServer.Dynasties[DynastyID];
      if (Assigned(Dynasty)) then
      begin
         Writeln('  Failed: Dynasty ', DynastyID, ' already exists.');
         Disconnect();
         exit;
      end;
      FServer.AddDynasty(DynastyID); // XXX this will eventually be async
      Writeln('  Sending acknowledgement...');
      Write(#$01);
   end
   else
   if (Command = icRegisterToken) then
   begin
      DynastyID := Arguments.ReadCardinal();
      Arguments.ReadRawBytes(SizeOf(Salt), Salt);
      Arguments.ReadRawBytes(SizeOf(Hash), Hash);
      Writeln('Received IPC: Register token for dynasty ', DynastyID);
      Dynasty := FServer.Dynasties[DynastyID];
      if (not Assigned(Dynasty)) then
      begin
         Writeln('  Failed: Dynasty ', DynastyID, ' does not exist.');
         Disconnect();
         exit;
      end;
      Dynasty.AddToken(Salt, Hash); // XXX this will eventually be async
      Writeln('  Sending acknowledgement...');
      Write(#$01);
   end
   else
   if (Command = icLogout) then
   begin
      DynastyID := Arguments.ReadCardinal();
      Writeln('Received IPC: Logout for dynasty ', DynastyID);
      Dynasty := FServer.Dynasties[DynastyID];
      if (not Assigned(Dynasty)) then
      begin
         Writeln('  Failed: Dynasty ', DynastyID, ' does not exist.');
         Disconnect();
         exit;
      end;
      Dynasty.ResetTokens(); // XXX this will eventually be async
      Writeln('  Sending acknowledgement...');
      Write(#$01);
   end
   else
   begin
      Writeln('received unknown command: ', Command);
      Disconnect();
      exit;
   end;
end;

procedure TConnection.DoLogin(var Message: TMessage);
var
   Token: UTF8String;
   SeparatorIndex: Cardinal;
   DynastyID: Integer;
   Dynasty: TDynasty;
begin
   Dynasty := nil;
   Token := Message.Conversation.Input.ReadString(MaxTokenLength); // arbitrary length limit
   SeparatorIndex := Pos(TokenSeparator, Token); // $R-
   if ((SeparatorIndex < 2) or (Length(Token) - SeparatorIndex <= 0)) then
   begin
      Message.Conversation.Error(ieUnrecognizedCredentials);
      exit;
   end;     
   DynastyID := StrToIntDef(Copy(Token, 1, SeparatorIndex - 1), -1);
   if (DynastyID < 0) then
   begin
      Message.Conversation.Error(ieUnrecognizedCredentials);
      exit;
   end;
   Dynasty := FServer.Dynasties[DynastyID]; // $R-
   if ((not Assigned(Dynasty)) or (not Dynasty.VerifyToken(Copy(Token, SeparatorIndex + 1, Length(Token) - SeparatorIndex)))) then
   begin
      Message.Conversation.Error(ieUnrecognizedCredentials);
      exit;
   end;
   if (not Message.Conversation.CloseInput()) then
      exit;
   Message.Conversation.Reply();
   Message.Conversation.Output.WriteCardinal(0);
   Message.Conversation.CloseOutput();
   FDynasty := Dynasty;
end;


constructor TServer.Create(APort: Word; APassword: UTF8String; AConfigurationDirectory: UTF8String);
var
   DynastiesFile: File of Cardinal;
   DynastyID: Cardinal;
   Dynasty: TDynasty;
begin
   inherited Create(APort);
   FPassword := APassword;
   FDynasties := TDynastyHashTable.Create();
   FConfigurationDirectory := AConfigurationDirectory;
   if (DirectoryExists(FConfigurationDirectory)) then
   begin
      Assign(DynastiesFile, FConfigurationDirectory + DynastiesListFileName);
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
      Assign(DynastiesFile, FConfigurationDirectory + DynastiesListFileName);
      Rewrite(DynastiesFile);
      Close(DynastiesFile);
   end;
end;

destructor TServer.Destroy();
var
   Dynasty: TDynasty;
begin
   for Dynasty in FDynasties.Values do
      Dynasty.Free();
   FDynasties.Free();
   inherited Destroy();
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
   Assign(DynastiesFile, FConfigurationDirectory + DynastiesListFileName);
   FileMode := 2;
   Reset(DynastiesFile);
   Seek(DynastiesFile, FDynasties.Count - 1);
   BlockWrite(DynastiesFile, DynastyID, 1);
   Close(DynastiesFile);
end;

end.
