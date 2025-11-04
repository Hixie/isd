{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit endtoend;

interface

uses
   sysutils, harness, unixtype, unixutils, configuration, stringstream, hashtable, genericutils, binarystream;

type
   TServerStreamReader = class;

   TServerWebSocket = class
   strict private
      const
         KB = 1024;
      type
         TWebSocketClientParseMode = (wsHandshake0, wsHandshake1, wsHandshake2, wsHandshake3, wsFrameByte1, wsFrameByte2, wsFrameExtendedLength16, wsFrameExtendedLength64, wsFramePayload);
         TWebSocketFrameType = (ftContinuation := $00, ftText := $01, ftBinary := $02, ftClose := $08, ftPing := $09, ftPong := $0A);
      var
         FWebSocket: cint; // socket file descriptor
         // raw data from the websocket connection
         FPendingDataBuffer: array[0..16 * KB] of Byte; // TODO: make this a ring buffer
         FPendingDataStart: Cardinal;
         FPendingDataEnd: Cardinal;
         // parsed data from the websocket connection
         FParseMode: TWebSocketClientParseMode;
         FPendingFrameType: TWebSocketFrameType;
         FPendingFinalFrame: Boolean;
         FPendingFrameLength: QWord;
         FPendingFrameIndex: Cardinal;
         FPendingFramePayload: RawByteString;
      type
         TStringHashTable = specialize THashTable <UInt32, UTF8String, CardinalUtils>;
      procedure ReceiveWebSocketBytes();
      procedure ParseHandshake();
      procedure ParseFrame();
   private
      var
         FStrings: TStringHashTable;
      procedure OpenWebSocket(Port: Word);
   public
      constructor Create();
      destructor Destroy(); override;
      procedure SendWebSocketStringMessage(const Data: UTF8String);
      procedure SendWebSocketBinaryMessage(var Data; const DataLength: Cardinal);
      procedure SendWebSocketBinaryMessage(const Data: TBytes);
      function ReadWebSocketStringMessage(): UTF8String;
      function ReadWebSocketBinaryMessage(): RawByteString;
      procedure CloseWebSocket();
      function GetStreamReader(const Input: RawByteString): TServerStreamReader;
   end;

   TServerStreamReader = class(TBinaryStreamReader)
   strict private
      FWebSocket: TServerWebSocket;
   public
      constructor Create(const Input: RawByteString; WebSocket: TServerWebSocket);
      function ReadStringReference(): UTF8String;
   end;

type
   TServerIPCSocket = class
   strict private
      var
         FSocket: cint; // socket file descriptor
   private
      procedure OpenSocket(Port: Word; Password: RawByteString);
   public
      destructor Destroy(); override;
      function SendControlMessage(const Data: RawByteString): Boolean;
      procedure AdvanceClock(Milliseconds: Int64);
      procedure AwaitScores(Count: Cardinal);
      procedure CloseSocket();
   end;

type
   TServerProcess = class
   strict private
      type
         PProcessOutput = ^TProcessOutput;
         TProcessOutput = record
            Segment: UTF8String;
            Previous, Next: PProcessOutput;
         end;
      var
         FProcess: TProcess;
         FProcessOutput, FLastProcessOutput: PProcessOutput;
         FPort: Word;
         FPassword: UTF8String; // for system messages
         FHadError: Boolean;
      procedure GrabProcessOutput();
      procedure WaitUntilProcessOutputContains(ControlCharacter: Char);
      procedure PushProcessOutput(const Buffer: UTF8String);
      procedure DumpProcessOutput();
   public
      constructor Create(AProcess: TProcess; APort: Word; APassword: UTF8String);
      class function StartServer(const Executable, HostDirectory: UTF8String; Port: Word; Password: UTF8String; Index: Cardinal = 0): TServerProcess;
      destructor Destroy(); override;
      function ConnectWebSocket(): TServerWebSocket;
      function ConnectIPCSocket(): TServerIPCSocket;
      procedure Shutdown(HadOtherErrors: Boolean = False);
   end;

   TServerProcessList = array of TServerProcess;

   TIsdServerTest = class abstract (TIsdTest)
   strict private
      FNextPort: Word;
      function AssignPort(): Word;
   protected
      FSettings: PSettings;
      FLoginServer: TServerProcess;
      FDynastiesServers: TServerProcessList;
      FSystemsServers: TServerProcessList;
      procedure CopyFile(const FromFile, ToFile: UTF8String);
      procedure CopyTemplate(const BaseDirectory, TestDirectory, FileName: UTF8String);
      procedure PrepareConfiguration(const BaseDirectory, TestDirectory: UTF8String); virtual;
      procedure RegisterServers(const HostDirectory, ServerListName: UTF8String; Count: Cardinal);
      procedure StartServers(const HostDirectory: UTF8String); virtual;
      procedure CloseServers(const Success: Boolean); virtual;
   protected
      procedure RunTestBody(); virtual; abstract;
   public
      procedure RunTest(const BaseDirectory, TestDirectory: UTF8String); override;
      destructor Destroy(); override;
   end;

procedure VerifyPositiveResponse(Response: TStringStreamReader; ConversationID: Cardinal = 0);
procedure VerifyEndOfResponse(var Response: TStringStreamReader);

implementation

uses
   exceptions, fileutils, passwords, sockets, baseunix, base64,
   csvdocument, servers, isdprotocol, strutils, hashfunctions;

const
   TestPasswordLength = 64;
   LocalHostAddr = (127 shl 24) + 1;
   LocalHostName = '127.0.0.1';

procedure VerifyPositiveResponse(Response: TStringStreamReader; ConversationID: Cardinal = 0);
begin
   Verify(Response.ReadString() = 'reply');
   Verify(Response.ReadCardinal() = ConversationID);
   Verify(Response.ReadBoolean());
end;

procedure VerifyEndOfResponse(var Response: TStringStreamReader);
begin
   Response.ReadEnd();
   Verify(Response.Ended);
   FreeAndNil(Response);
end;

procedure WaitUntilSocketReadyToSend(const Socket: cint);
var
   PollResult: cint;
   FileDescriptors: PPollFd;
begin
   New(FileDescriptors);
   FileDescriptors^.FD := Socket;
   FileDescriptors^.Events := POLLOUT;
   FileDescriptors^.REvents := 0;
   try
      PollResult := fpPoll(FileDescriptors, 1, TestTimeout);
      if (PollResult < 0) then
         raise EKernelError.Create(fpGetErrNo);
      if (PollResult = 0) then
         raise Exception.Create('timed out waiting to be able to send message to server');
      Assert(PollResult = 1);
      if (FileDescriptors^.REvents <> POLLOUT) then
         raise Exception.Create('unexpected activity on socket');
   finally
      Dispose(FileDescriptors);
   end;
end;

procedure WaitUntilSocketReadyToReceive(const Socket: cint);
var
   PollResult: cint;
   FileDescriptors: PPollFd;
begin
   New(FileDescriptors);
   FileDescriptors^.FD := Socket;
   FileDescriptors^.Events := POLLIN;
   FileDescriptors^.REvents := 0;
   try
      PollResult := fpPoll(FileDescriptors, 1, TestTimeout);
      if (PollResult < 0) then
         raise EKernelError.Create(fpGetErrNo);
      if (PollResult = 0) then
         raise Exception.Create('timed out waiting for message from server');
      Assert(PollResult = 1);
      if (FileDescriptors^.REvents <> POLLIN) then
         raise Exception.Create('unexpected activity on socket');
   finally
      Dispose(FileDescriptors);
   end;
end;

procedure TransmitSocketBytes(const Socket: cint; const Data: RawByteString);
var
   Sent: ssize_t;
   Error: cint;
begin
   FpSetErrNo(Low(SocketError));
   Sent := fpSend(Socket, PChar(Data), Length(Data), {$IFDEF Linux} MSG_NOSIGNAL {$ELSE} 0 {$ENDIF}); // $R-
   if (Sent < Length(Data)) then
   begin
      Error := SocketError;
      if (Error <> Low(SocketError)) then
         raise ESocketError.Create(Error);
      raise Exception.Create('unexpected error sending data on socket connection');
   end;
end;


constructor TServerWebSocket.Create();
begin
   inherited;
   FStrings := TStringHashTable.Create(@Integer32Hash32, 8);
end;

procedure TServerWebSocket.OpenWebSocket(Port: Word);
const
   CRLF = #13#10;
var
   ConnectResult: cint;
   Address: PSockAddr;
   Handshake: UTF8String;
begin
   Assert(FWebSocket = 0);
   New(Address);
   Address^.sin_family := AF_INET;
   Address^.sin_addr.s_addr := HToNL(LocalHostAddr);
   Address^.sin_port := HToNS(Port);
   try
      FWebSocket := fpSocket(Address^.sin_family, SOCK_STREAM, 0);
      if (FWebSocket < 0) then
         raise ESocketError.Create(SocketError);
      ConnectResult := fpConnect(FWebSocket, Address, SizeOf(SockAddr));
      if ((ConnectResult < 0) and (SocketError <> EINPROGRESS)) then
         raise ESocketError.Create(SocketError);
      WaitUntilSocketReadyToSend(FWebSocket);
      Handshake := 'GET / HTTP/1.1' + CRLF +
         'Host: ' + LocalHostName + CRLF +
         'Upgrade: websocket' + CRLF +
         'Connection: Upgrade' + CRLF +
         'Sec-WebSocket-Key: ' + EncodeStringBase64(#00#00#00#00#00#00#00#00#00#00#00#00#00#00#00#00) + CRLF + // NOT SECURE - FOR TEST PURPOSES ONLY
         'Sec-WobSocket-Version: 13' + CRLF +
         CRLF;
      TransmitSocketBytes(FWebSocket, Handshake);
      repeat
         ParseHandshake();
      until FParseMode = wsFrameByte1;
   finally
      Dispose(Address);
   end;
end;

destructor TServerWebSocket.Destroy();
begin
   Assert(FWebSocket = 0, 'Call CloseWebSocket before freeing websocket object');
   FreeAndNil(FStrings);
   inherited;
end;

procedure TServerWebSocket.ReceiveWebSocketBytes();
var
   Received: ssize_t;
begin
   WaitUntilSocketReadyToReceive(FWebSocket);
   if (FPendingDataEnd >= SizeOf(FPendingDataBuffer)) then
      raise Exception.CreateFmt('buffer overflow during websocket handshake: buffer length %d, position %d', [SizeOf(FPendingDataBuffer), FPendingDataEnd]);
   Received := fpRecv(FWebSocket, @FPendingDataBuffer[FPendingDataEnd], SizeOf(FPendingDataBuffer) - FPendingDataEnd, 0); // $R-
   if (Received < 0) then
      raise ESocketError.Create(SocketError);
   Inc(FPendingDataEnd, Received);
end;

procedure TServerWebSocket.ParseHandshake();
begin
   repeat
      if (FPendingDataStart = FPendingDataEnd) then
      begin
         FPendingDataStart := 0;
         FPendingDataEnd := 0;
         ReceiveWebSocketBytes();
      end;
      case (FParseMode) of
         wsHandshake0: begin
            if (FPendingDataBuffer[FPendingDataStart] = 13) then
            begin
               Inc(FParseMode);
            end
            else
            begin
               FParseMode := wsHandshake0;
            end;
         end;
         wsHandshake1: begin
            if (FPendingDataBuffer[FPendingDataStart] = 10) then
            begin
               Inc(FParseMode);
            end
            else
            begin
               FParseMode := wsHandshake0;
            end;
         end;
         wsHandshake2: begin
            if (FPendingDataBuffer[FPendingDataStart] = 13) then
            begin
               Inc(FParseMode);
            end
            else
            begin
               FParseMode := wsHandshake0;
            end;
         end;
         wsHandshake3: begin
            if (FPendingDataBuffer[FPendingDataStart] = 10) then
            begin
               Inc(FParseMode);
               Assert(FParseMode = wsFrameByte1);
            end
            else
            begin
               FParseMode := wsHandshake0;
            end;
         end;
         else
            raise Exception.Create('inconsistent parse state during websocket handshake');
      end;
      Inc(FPendingDataStart);
   until FParseMode = wsFrameByte1;
end;

procedure TServerWebSocket.ParseFrame();
var
   CurrentByte: Byte;
begin
   repeat
      if (FPendingDataStart = FPendingDataEnd) then
      begin
         FPendingDataStart := 0;
         FPendingDataEnd := 0;
         ReceiveWebSocketBytes();
      end;
      CurrentByte := FPendingDataBuffer[FPendingDataStart];
      case (FParseMode) of
         wsFrameByte1: begin
            FPendingFrameType := TWebSocketFrameType(CurrentByte and $0F);
            // assume bits 5, 6, and 7 are zero (extension bits, we don't negotiate any extensions)
            FPendingFinalFrame := (CurrentByte and $80) = $80;
            FParseMode := wsFrameByte2;
         end;
         wsFrameByte2: begin
            FPendingFrameLength := Byte(CurrentByte and $7F);
            // assume bit 8 is clear (masking bit, client must not mask)
            case (FPendingFrameLength) of
             0: begin FPendingFramePayload := ''; FParseMode := wsFrameByte1; end;
             1..125: begin FPendingFrameIndex := 0; SetLength(FPendingFramePayload, FPendingFrameLength); FParseMode := wsFramePayload; end;
             126: begin FPendingFrameLength := 0; FPendingFrameIndex := 2; FParseMode := wsFrameExtendedLength16; end;
             127: begin FPendingFrameLength := 0; FPendingFrameIndex := 8; FParseMode := wsFrameExtendedLength64; end;
             else Assert(False);
            end;
         end;
         wsFrameExtendedLength16, wsFrameExtendedLength64: begin
            // we use FPendingFrameIndex to track how many bytes of data remain to compute the length
            Dec(FPendingFrameIndex);
            FPendingFrameLength := FPendingFrameLength or (CurrentByte shl (FPendingFrameIndex * 8));
            if (FPendingFrameIndex = 0) then
            begin
               // if you don't trust the server, then this is where you'd want to sanity check the length so it doesn't DOS you
               Assert(FPendingFrameIndex = 0);
               if (FPendingFrameLength = 0) then
                  raise Exception.Create('invalid length from server');
               FParseMode := wsFramePayload;
               SetLength(FPendingFramePayload, FPendingFrameLength);
            end;
         end;
         wsFramePayload: begin
            Inc(FPendingFrameIndex);
            Assert(FPendingFrameLength = Length(FPendingFramePayload));
            Assert(FPendingFrameIndex <= Length(FPendingFramePayload));
            FPendingFramePayload[FPendingFrameIndex] := Chr(CurrentByte);
            if (FPendingFrameIndex >= FPendingFrameLength) then
            begin
               FParseMode := wsFrameByte1;
            end;
         end;
         else
            raise Exception.Create('inconsistent parse state during websocket handshake');
      end;
      Inc(FPendingDataStart);
   until FParseMode = wsFrameByte1;
end;

function EncodeLength(const Length: Int64): RawByteString;
begin
   if (Length > 65535) then
   begin
      Result :=
         Chr(127 or $80) +
         Chr((Length shr (8*7)) and $FF) +
         Chr((Length shr (8*6)) and $FF) +
         Chr((Length shr (8*5)) and $FF) +
         Chr((Length shr (8*4)) and $FF) +
         Chr((Length shr (8*3)) and $FF) +
         Chr((Length shr (8*2)) and $FF) +
         Chr((Length shr (8*1)) and $FF) +
         Chr((Length          ) and $FF);
   end
   else // 126..65535
   if (Length >= 126) then
   begin
      Result :=
         Chr(126 or $80) +
         Chr((Length shr (8*1)) and $FF) +
         Chr((Length          ) and $FF);
   end
   else // 0..126
      Result := Chr(Length or $80);
end;

procedure TServerWebSocket.SendWebSocketStringMessage(const Data: UTF8String);
var
   Message: RawByteString;
begin
   Message := Chr($81) + EncodeLength(Length(Data)) + #$00#$00#$00#$00 + Data;
   TransmitSocketBytes(FWebSocket, Message);
end;

procedure TServerWebSocket.SendWebSocketBinaryMessage(var Data; const DataLength: Cardinal);
var
   Message: RawByteString;
   Index: Cardinal;
begin
   Message := Chr($82) + EncodeLength(DataLength) + #$00#$00#$00#$00;
   Index := Length(Message); // $R-
   SetLength(Message, Length(Message) + DataLength);
   Move(Data, Message[Index + 1], DataLength);
   TransmitSocketBytes(FWebSocket, Message);
end;

procedure TServerWebSocket.SendWebSocketBinaryMessage(const Data: TBytes);
begin
   SendWebSocketBinaryMessage(Data[0], Length(Data)); // $R-
end;

function TServerWebSocket.ReadWebSocketStringMessage(): UTF8String;
begin
   repeat
      ParseFrame();
   until FParseMode = wsFrameByte1;
   if (FPendingFrameType <> ftText) then
      raise Exception.CreateFmt('Expected text websocket frame, got type=%d instead.', [FPendingFrameType]);
   if (not FPendingFinalFrame) then
      raise Exception.Create('Expected complete text websocket frame, got incomplete frame instead.');
   Result := FPendingFramePayload;
end;

function TServerWebSocket.ReadWebSocketBinaryMessage(): RawByteString;
begin
   repeat
      ParseFrame();
   until FParseMode = wsFrameByte1;
   if (FPendingFrameType <> ftBinary) then
      raise Exception.CreateFmt('Expected text websocket frame, got type=%d instead.', [FPendingFrameType]);
   if (not FPendingFinalFrame) then
      raise Exception.Create('Expected complete text websocket frame, got incomplete frame instead.');
   Result := FPendingFramePayload;
end;

procedure TServerWebSocket.CloseWebSocket();
var
   Error: Integer;
begin
   Assert(FWebSocket > 0);
   Error := fpShutdown(FWebSocket, 2);
   if ((Error <> 0) and (SocketError <> 107)) then // 107 = already disconnected
      raise ESocketError.Create(SocketError);
   if (fpClose(FWebSocket) <> 0) then
      raise EKernelError.Create(fpGetErrNo);
   FWebSocket := 0;
end;

function TServerWebSocket.GetStreamReader(const Input: RawByteString): TServerStreamReader;
begin
   Result := TServerStreamReader.Create(Input, Self);
end;


constructor TServerStreamReader.Create(const Input: RawByteString; WebSocket: TServerWebSocket);
begin
   inherited Create(Input);
   FWebSocket := WebSocket;
end;

function TServerStreamReader.ReadStringReference(): UTF8String;
var
   Code: Cardinal;
   Value: UTF8String;
begin
   Code := ReadCardinal();
   if (not FWebSocket.FStrings.Has(Code)) then
   begin
      Value := ReadString();
      FWebSocket.FStrings[Code] := Value;
   end;
   Result := FWebSocket.FStrings[Code];
end;


procedure TServerIPCSocket.OpenSocket(Port: Word; Password: RawByteString);
var
   ConnectResult: cint;
   Address: PSockAddr;
   Stream: TBinaryStreamWriter;
begin
   Assert(FSocket = 0);
   New(Address);
   Address^.sin_family := AF_INET;
   Address^.sin_addr.s_addr := HToNL(LocalHostAddr);
   Address^.sin_port := HToNS(Port);
   Stream := nil;
   try
      FSocket := fpSocket(Address^.sin_family, SOCK_STREAM, 0);
      if (FSocket < 0) then
         raise ESocketError.Create(SocketError);
      ConnectResult := fpConnect(FSocket, Address, SizeOf(SockAddr));
      if ((ConnectResult < 0) and (SocketError <> EINPROGRESS)) then
         raise ESocketError.Create(SocketError);
      WaitUntilSocketReadyToSend(FSocket);
      Stream := TBinaryStreamWriter.Create();
      Stream.WriteByte($00);
      Stream.WriteStringByPointer(Password);
      TransmitSocketBytes(FSocket, Stream.Serialize(False));
   finally
      FreeAndNil(Stream);
      Dispose(Address);
   end;
end;

destructor TServerIPCSocket.Destroy();
begin
   Assert(FSocket = 0, 'Call CloseSocket before freeing IPC socket object');
   inherited;
end;

function TServerIPCSocket.SendControlMessage(const Data: RawByteString): Boolean;
var
   Response: Byte;
   Received: ssize_t;
begin
   TransmitSocketBytes(FSocket, Data);
   WaitUntilSocketReadyToReceive(FSocket);
   Received := fpRecv(FSocket, @Response, SizeOf(Response), 0);
   if (Received < 0) then
      raise ESocketError.Create(SocketError);
   if (Received = 0) then
      raise Exception.Create('Server disconnected after receiving "' + Data + '"');
   Assert(Received = 1, 'Unexpected number of bytes read: ' + IntToStr(Received));
   Result := Response = $01;
end;

procedure TServerIPCSocket.AdvanceClock(Milliseconds: Int64);
var
   BinaryWriter: TBinaryStreamWriter;
begin
   BinaryWriter := TBinaryStreamWriter.Create();
   BinaryWriter.WriteStringByPointer(icAdvanceClock);
   BinaryWriter.WriteInt64(Milliseconds);
   Verify(SendControlMessage(BinaryWriter.Serialize(True)));
   FreeAndNil(BinaryWriter);
end;

procedure TServerIPCSocket.AwaitScores(Count: Cardinal);
var
   BinaryWriter: TBinaryStreamWriter;
begin
   BinaryWriter := TBinaryStreamWriter.Create();
   BinaryWriter.WriteStringByPointer(icAwaitScores);
   BinaryWriter.WriteCardinal(Count);
   Verify(SendControlMessage(BinaryWriter.Serialize(True)));
   FreeAndNil(BinaryWriter);
end;

procedure TServerIPCSocket.CloseSocket();
var
   Error: Integer;
begin
   Assert(FSocket > 0);
   Error := fpShutdown(FSocket, 2);
   if ((Error <> 0) and (SocketError <> 107)) then // 107 = already disconnected
      raise ESocketError.Create(SocketError);
   if (fpClose(FSocket) <> 0) then
      raise EKernelError.Create(fpGetErrNo);
   FSocket := 0;
end;


constructor TServerProcess.Create(AProcess: TProcess; APort: Word; APassword: UTF8String);
begin
   inherited Create();
   FProcess := AProcess;
   FPort := APort;
   FPassword := APassword;
   WaitUntilProcessOutputContains(ControlReady);
end;

class function TServerProcess.StartServer(const Executable, HostDirectory: UTF8String; Port: Word; Password: UTF8String; Index: Cardinal = 0): TServerProcess;
var
   Arguments: array of UTF8String;
begin
   Arguments := [HostDirectory];
   if (Index > 0) then
   begin
      SetLength(Arguments, Length(Arguments) + 1);
      Arguments[High(Arguments)] := IntToStr(Index);
   end;
   Result := TServerProcess.Create(TProcess.Start(Executable, Arguments), Port, Password);
end;

function TServerProcess.ConnectWebSocket(): TServerWebSocket;
begin
   Result := TServerWebSocket.Create();
   Result.OpenWebSocket(FPort);
end;

function TServerProcess.ConnectIPCSocket(): TServerIPCSocket;
begin
   Result := TServerIPCSocket.Create();
   Result.OpenSocket(FPort, FPassword);
end;

procedure TServerProcess.Shutdown(HadOtherErrors: Boolean = False);
const
   ExpectedTail = ControlEnd + #10;
var
   Tail: UTF8String;
   Part: PProcessOutput;
begin
   FProcess.Close(TestTimeout);
   PushProcessOutput(FProcess.ReadAllRemainingOutput());
   Tail := '';
   Part := FLastProcessOutput;
   while ((Length(Tail) < Length(ExpectedTail)) and Assigned(Part)) do
   begin
      Tail := Part^.Segment + Tail;
      Part := Part^.Previous;
   end;
   if (not EndsStr(ExpectedTail, Tail)) then
   begin
      Writeln('======== Subprocess did not terminate cleanly ======================');
      DumpProcessOutput();
      Writeln('====================================================================');
      Writeln('Tail length was ', Length(Tail), '; expected ', Length(ExpectedTail));
      raise Exception.Create('subprocess did not terminate cleanly');
   end
   else
   if (FHadError) then
   begin
      Writeln('======== Subprocess flagged an error ===============================');
      DumpProcessOutput();
      Writeln('====================================================================');
      raise Exception.Create('subprocess flagged an error');
   end
   else
   if (HadOtherErrors) then
   begin
      Writeln('======== Subprocess output =========================================');
      DumpProcessOutput();
      Writeln('====================================================================');
   end;
end;

destructor TServerProcess.Destroy();
var
   Current, Next: PProcessOutput;
begin
   Next := FProcessOutput;
   while (Assigned(Next)) do
   begin
      Current := Next;
      Next := Current^.Next;
      Dispose(Current);
   end;
   FLastProcessOutput := nil;
   FreeAndNil(FProcess);
   inherited;
end;

procedure TServerProcess.GrabProcessOutput();
var
   Buffer: UTF8String;
begin
   repeat
      Buffer := FProcess.ReadSomeOutput(0);
      PushProcessOutput(Buffer);
   until Buffer = '';
end;

procedure TServerProcess.WaitUntilProcessOutputContains(ControlCharacter: Char);
var
   Buffer: UTF8String;
begin
   repeat
      Buffer := FProcess.ReadSomeOutput(TestTimeout);
      PushProcessOutput(Buffer);
      if (Pos(ControlCharacter, Buffer) > 0) then
         exit;
   until Buffer = '';
   Writeln('======== Failed to find control character in process output ========');
   DumpProcessOutput();
   Writeln('====================================================================');
   raise Exception.Create('subprocess never printed expected control character (' + IntToStr(Ord(ControlCharacter)) + ')');
end;

procedure TServerProcess.PushProcessOutput(const Buffer: UTF8String);
begin
   if (Buffer <> '') then
   begin
      if (Assigned(FProcessOutput)) then
      begin
         New(FLastProcessOutput^.Next);
         FLastProcessOutput^.Next^.Previous := FLastProcessOutput;
         FLastProcessOutput := FLastProcessOutput^.Next;
      end
      else
      begin
         New(FProcessOutput);
         FProcessOutput^.Previous := nil;
         FLastProcessOutput := FProcessOutput;
      end;
      FLastProcessOutput^.Segment := Buffer;
      FLastProcessOutput^.Next := nil;
      if (Pos(ControlError, Buffer) > 0) then
         FHadError := True;
   end;
end;

procedure TServerProcess.DumpProcessOutput();
var
   Part: PProcessOutput;
begin
   Part := FProcessOutput;
   while (Assigned(Part)) do
   begin
      Write(Part^.Segment);
      Part := Part^.Next;
   end;
   Writeln();
end;


procedure TIsdServerTest.RunTest(const BaseDirectory, TestDirectory: UTF8String);
var
   Success: Boolean;
begin
   Writeln('## ', UnitName, ' ##');
   Writeln('Starting...');
   PrepareConfiguration(BaseDirectory, TestDirectory);
   StartServers(TestDirectory);
   Success := False;
   try
      Writeln('Running...');
      RunTestBody();
      Success := True;
   finally
      Writeln('Shutting down...');
      CloseServers(Success);
   end;
end;

function TIsdServerTest.AssignPort(): Word;
begin
   Result := FNextPort;
   Inc(FNextPort);
end;

procedure TIsdServerTest.CopyFile(const FromFile, ToFile: UTF8String);
var
   Data: TFileData;
begin
   Data := ReadFile(FromFile);
   try
      WriteFile(ToFile, Data);
   finally
      Data.Destroy();
   end;
end;

procedure TIsdServerTest.CopyTemplate(const BaseDirectory, TestDirectory, FileName: UTF8String);
begin
   CopyFile(BaseDirectory + 'templates/' + FileName, TestDirectory + FileName);
end;

procedure TIsdServerTest.PrepareConfiguration(const BaseDirectory, TestDirectory: UTF8String);
begin
   CopyTemplate(BaseDirectory, TestDirectory, GalaxyBlobFilename);
   CopyTemplate(BaseDirectory, TestDirectory, SystemsBlobFilename);
   CopyTemplate(BaseDirectory, TestDirectory, OreRecordsFilename);
   CopyTemplate(BaseDirectory, TestDirectory, TechnologyTreeFilename);
   CopyTemplate(BaseDirectory, TestDirectory, ServerSettingsFilename);
   WriteTextFile(TestDirectory + DynastiesServersListFilename, '');
   WriteTextFile(TestDirectory + SystemsServersListFilename, '');
   FSettings := LoadSettingsConfiguration(TestDirectory);
   FNextPort := 40000; // TODO: avoid hard-coding this
   RegisterServers(TestDirectory, LoginServersListFilename, 1);
   RegisterServers(TestDirectory, DynastiesServersListFilename, 1);
   RegisterServers(TestDirectory, SystemsServersListFilename, 1);
end;

procedure TIsdServerTest.RegisterServers(const HostDirectory, ServerListName: UTF8String; Count: Cardinal);
var
   F: Text;
   Index: Cardinal;
   Port: Word;
begin
   Assert(Count > 0);
   Assign(F, HostDirectory + ServerListName);
   Rewrite(F);
   for Index := 0 to Count - 1 do // $R-
   begin
      Port := AssignPort();
      Writeln(F, LocalHostName, ',', Port, ',', LocalHostName, ',', Port, ',', CreatePassword(TestPasswordLength));
   end;
   Close(F);
end;

procedure TIsdServerTest.StartServers(const HostDirectory: UTF8String);

   procedure LaunchServers(const ServersListFilename, Executable: UTF8String; var ServersList: TServerProcessList; IndexOffset: Integer = 1);
   var
      ServerFile: TCSVDocument;
      ServerDatabase: TServerDatabase;
      ServerConfig: PServerEntry;
      Index: Cardinal;
   begin
      ServerFile := LoadServersConfiguration(HostDirectory, ServersListFilename);
      ServerDatabase := TServerDatabase.Create(ServerFile);
      FreeAndNil(ServerFile);
      SetLength(ServersList, ServerDatabase.Count);
      for Index := 0 to ServerDatabase.Count - 1 do // $R-
      begin
         ServerConfig := ServerDatabase[Index];
         ServersList[Index] := TServerProcess.StartServer(Executable, HostDirectory, ServerConfig^.DirectPort, ServerConfig^.DirectPassword, Index + IndexOffset); // $R-
      end;
      FreeAndNil(ServerDatabase);
   end;

var
   LoginServers: TServerProcessList;
begin
   LoginServers := [];
   LaunchServers(LoginServersListFilename, 'bin/login-server', LoginServers, 0);
   Assert(Length(LoginServers) = 1);
   FLoginServer := LoginServers[0];
   LaunchServers(DynastiesServersListFilename, 'bin/dynasties-server', FDynastiesServers);
   LaunchServers(SystemsServersListFilename, 'bin/systems-server', FSystemsServers);
end;

procedure TIsdServerTest.CloseServers(const Success: Boolean);
var
   Server: TServerProcess;
begin
   FLoginServer.Shutdown(not Success);
   FreeAndNil(FLoginServer);
   for Server in FDynastiesServers do
   begin
      Server.Shutdown(not Success);
      FreeAndNil(Server);
   end;
   SetLength(FDynastiesServers, 0);
   for Server in FSystemsServers do
   begin
      Server.Shutdown(not Success);
      FreeAndNil(Server);
   end;
   SetLength(FSystemsServers, 0);
end;

destructor TIsdServerTest.Destroy();
begin
   Dispose(FSettings);
   inherited;
end;

end.