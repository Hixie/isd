{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit basenetwork;

interface

uses
   corenetwork, corewebsocket, genericutils, hashset, binarystream,
   stringstream, sharedpointer, servers, baseunix;

type
   TBaseIncomingCapableConnection = class;

   TBaseConversationHandle = class
   protected
      FConnection: TBaseIncomingCapableConnection;
      constructor Create(AConnection: TBaseIncomingCapableConnection);
   public
      procedure DiscardSocket();
   end;

   TMessageConversationHandle = class(TBaseConversationHandle)
   protected
      FInput: TStringStreamReader;
      FConversationID: Cardinal;
      FOutput: TStringStreamWriter;
      constructor Create(AMessage: UTF8String; AConnection: TBaseIncomingCapableConnection);
   public
      destructor Destroy(); override;
   end;

   TConversationHashSet = specialize THashSet<TBaseConversationHandle, TObjectUtils>;
   
   TMessage = record
   public
      const
         MaxMessageNameLength = 32;
      type
         CommandString = String[MaxMessageNameLength];
   strict private
      FCommand: CommandString; // must be first, must be a short string
      FConversation: specialize TSharedPointer<TMessageConversationHandle>;
      function GetInput(): TStringStreamReader;
      function GetOutput(): TStringStreamWriter;
      function GetInputClosed(): Boolean;
      function GetOutputClosed(): Boolean;
   public
      constructor Create(AConversation: TMessageConversationHandle);
      function CloseInput(): Boolean;
      procedure CloseOutput();
      procedure Error(const Code: UTF8String);
      procedure Reply();
      property Input: TStringStreamReader read GetInput;
      property Output: TStringStreamWriter read GetOutput;
      property InputClosed: Boolean read GetInputClosed;
      property OutputClosed: Boolean read GetOutputClosed;
   end;

   TConnectionCallback = procedure (Connection: TBaseIncomingCapableConnection; Data: Pointer) is nested;
   
   TBaseIncomingCapableConnection = class(TWebSocket)
   strict private
      FConversations: TConversationHashSet;
   protected
      procedure HandleMessage(Message: UTF8String); override;
   public
      constructor Create(AListenerSocket: TListenerSocket);
      destructor Destroy(); override;
      procedure TrackConversation(Conversation: TBaseConversationHandle);
      procedure DiscardConversation(Conversation: TBaseConversationHandle);
      procedure Invoke(Callback: TConnectionCallback); virtual;
      procedure DefaultHandlerStr(var Message); override;
      {$IFOPT C+} procedure WriteFrame(const s: UTF8String); override; {$ENDIF}
      {$IFOPT C+} procedure WriteFrame(const Buf; const Length: Cardinal); override; {$ENDIF} {BOGUS Hint: Value parameter "Buf" is assigned but never used}
   end;

   TConnectionMode = (cmNew, cmWebsocket, cmControlHandshake, cmControlMessages);

   TBaseIncomingInternalCapableConnection = class(TBaseIncomingCapableConnection)
   protected
      FMode: TConnectionMode;
      FIPCBuffer: TBinaryStreamWriter;
      function InternalRead(Data: array of Byte): Boolean; override;
      procedure MaybeHandleIPCPassword();
      procedure MaybeHandleIPC();
      procedure HandleIPC(Arguments: TBinaryStreamReader); virtual; abstract;
      function GetInternalPassword(): UTF8String; virtual; abstract;
   public
      constructor Create(AListenerSocket: TListenerSocket);
      destructor Destroy(); override;
      procedure HoldsCleared(); virtual;
   end;

   TInternalConversationHandle = class(TBaseConversationHandle)
   strict private
      FHolds: Cardinal;
      function GetHasHolds(): Boolean;
   public
      constructor Create(AConnection: TBaseIncomingInternalCapableConnection);
      procedure AddHold();
      procedure RemoveHold();
      property HasHolds: Boolean read GetHasHolds;
   end;

   TBaseOutgoingInternalConnection = class(TNetworkSocket)
   private
      FSystemServer: PServerEntry;
      FPendingAcknowledgements: Cardinal;
   protected
      procedure Preconnect(); override;
      function InternalRead(Data: array of Byte): Boolean; override;
      procedure IncrementPendingCount();
      procedure Done(); virtual;
   public
      constructor Create(ASystemServer: PServerEntry);
      procedure Connect();
      procedure ReportConnectionError(ErrorCode: cint); override;
   end;

   TBaseServer = class(TNetworkServer)
   protected
      FDeadObjects: array of TObject;
      procedure ReportChanges(); virtual;
   public
      procedure ScheduleDemolition(Victim: TObject);
      procedure CompleteDemolition();
      procedure Run();
   end;

   procedure ConsoleWriteln(const Prefix, S: UTF8String);

implementation

uses
   sysutils, isderrors, utf8, unicode, exceptions, hashfunctions, sigint, errors;

procedure ConsoleWriteln(const Prefix, S: UTF8String);
var
   Index, Codepoint, Count: Cardinal;
   Control, NextIsControl: Boolean;
   Color: Boolean;
begin
   Color := GetEnvironmentVariable('TERM') <> 'dumb';
   Write(Prefix);
   if (Length(S) > 0) then
   begin
      Count := Length(S); // $R-
      if (Count > 256) then
         Count := 256;
      Control := False;
      if (Color) then
         Write(#$1B'[30;37;1m');
      for Index := 1 to Count do // $R-
      begin
         Codepoint := Ord(S[Index]);
         NextIsControl := (Codepoint < $20) or (Codepoint = $80);
         if (Color and (NextIsControl <> Control)) then
         begin
            if (NextIsControl) then
            begin
               Write(#$1B'[30;33;1m');
            end
            else
            begin
               Write(#$1B'[30;37;1m');
            end;
         end;
         Control := NextIsControl;
         if (Control) then
         begin
            if (Codepoint < $20) then
            begin
               Write(CodepointToUTF8(TUnicodeCodepointRange(Codepoint + $2400)).AsString);
            end
            else if (Codepoint = $80) then
            begin
               Write(CodepointToUTF8(TUnicodeCodepointRange($2421)).AsString);
            end
            else
            begin
               Write('$', HexStr(Codepoint, 2));
            end;
         end
         else
         begin
            Write(S[Index]);
         end;
      end;
      if (Color) then
         Write(#$1B'[0m');
      if (Count < Length(S)) then
         Write('...');
      Writeln();
   end
   else
   begin
      Writeln('<nothing>');
   end;
end;


function ConversationHash32(const Key: TBaseConversationHandle): DWord;
begin
   Result := PtrUIntHash32(PtrUInt(Key));
end;


constructor TBaseConversationHandle.Create(AConnection: TBaseIncomingCapableConnection);
begin
   inherited Create();
   FConnection := AConnection;
end;

procedure TBaseConversationHandle.DiscardSocket();
begin
   FConnection := nil;
end;


constructor TMessageConversationHandle.Create(AMessage: UTF8String; AConnection: TBaseIncomingCapableConnection);
begin
   inherited Create(AConnection);
   FInput := TStringStreamReader.Create(AMessage);
   FConversationID := FInput.ReadCardinal();
   FOutput := TStringStreamWriter.Create();
end;

destructor TMessageConversationHandle.Destroy();
begin
   FInput.Free();
   FOutput.Free();
   inherited;
end;


constructor TMessage.Create(AConversation: TMessageConversationHandle);
begin
   FConversation := AConversation;
   FCommand := Input.ReadString(TMessage.MaxMessageNameLength);
end;

function TMessage.GetInput(): TStringStreamReader;
begin
   Result := FConversation.Value.FInput;
end;

function TMessage.GetInputClosed(): Boolean;
begin
   Result := Input.Ended;
end;

function TMessage.CloseInput(): Boolean;
begin
   Input.ReadEnd();
   Result := Input.Ended;
   if (not Result) then
   begin
      Error(ieInvalidMessage);
   end;
end;

function TMessage.GetOutput(): TStringStreamWriter;
begin
   Result := FConversation.Value.FOutput;
end;

function TMessage.GetOutputClosed(): Boolean;
begin
   Result := Output.Closed;
end;

procedure TMessage.CloseOutput();
begin
   Assert(not OutputClosed);
   Output.Close();
   if (Assigned(FConversation.Value.FConnection)) then
   begin
      FConversation.Value.FConnection.WriteFrame(Output.Serialize());
      FConversation.Value.FConnection.DiscardConversation(FConversation.Value);
   end;
end;

procedure TMessage.Error(const Code: UTF8String);
begin
   if (not InputClosed) then
   begin
      Input.Bail();
   end;
   if (not OutputClosed) then
   begin
      Output.Reset();
      Output.WriteString('reply');
      Output.WriteCardinal(FConversation.Value.FConversationID);
      Output.WriteBoolean(False);
      Output.WriteString(Code);
      CloseOutput();
   end;
end;

procedure TMessage.Reply();
begin
   {$IFOPT C+} Assert(not Output.DebugStarted); {$ENDIF}
   {$IFOPT C+} Assert(not OutputClosed); {$ENDIF}
   Output.WriteString('reply');
   Output.WriteCardinal(FConversation.Value.FConversationID);
   Output.WriteBoolean(True);
end;


constructor TBaseIncomingCapableConnection.Create(AListenerSocket: TListenerSocket);
begin
   inherited Create(AListenerSocket);
   FConversations := TConversationHashSet.Create(@ConversationHash32);
end;

destructor TBaseIncomingCapableConnection.Destroy();
var
   Conversation: TBaseConversationHandle;
begin
   for Conversation in FConversations do
      Conversation.DiscardSocket();
   FConversations.Free();
   inherited;
end;

procedure TBaseIncomingCapableConnection.TrackConversation(Conversation: TBaseConversationHandle);
begin
   FConversations.Add(Conversation);
end;

procedure TBaseIncomingCapableConnection.DiscardConversation(Conversation: TBaseConversationHandle);
begin
   FConversations.Remove(Conversation);
   Conversation.DiscardSocket();
end;

procedure TBaseIncomingCapableConnection.Invoke(Callback: TConnectionCallback);
begin
   Callback(Self, nil);
end;

procedure TBaseIncomingCapableConnection.HandleMessage(Message: UTF8String);
var
   Conversation: TMessageConversationHandle;
   ParsedMessage: TMessage;
begin
   ConsoleWriteln('Received WebSocket: ', Message);
   Conversation := TMessageConversationHandle.Create(Message, Self);
   TrackConversation(Conversation);
   ParsedMessage := TMessage.Create(Conversation);
   try
      DispatchStr(ParsedMessage);
      if (not ParsedMessage.InputClosed) then
         ParsedMessage.Error(ieInvalidMessage);
   except
      ParsedMessage.Error(ieInternalError);
      ReportCurrentException();
      raise;
   end;
end;

procedure TBaseIncomingCapableConnection.DefaultHandlerStr(var Message);
begin
   TMessage(Message).Error(ieInvalidMessage);
end;

{$IFOPT C+}
procedure TBaseIncomingCapableConnection.WriteFrame(const S: UTF8String);
begin
   ConsoleWriteln('Sending WebSocket Text: ', S);
   Sleep(500); // this is to simulate bad network conditions
   inherited;
end;

procedure TBaseIncomingCapableConnection.WriteFrame(const Buf; const Length: Cardinal);
var
   S: RawByteString;
begin
   SetLength(S, Length);
   Move(Buf, S[1], Length);
   ConsoleWriteln('Sending WebSocket Binary: ', S);
   Sleep(500); // this is to simulate bad network conditions
   inherited;
end;
{$ENDIF}


constructor TBaseIncomingInternalCapableConnection.Create(AListenerSocket: TListenerSocket);
begin
   inherited Create(AListenerSocket);
   FIPCBuffer := TBinaryStreamWriter.Create();
end;

destructor TBaseIncomingInternalCapableConnection.Destroy();
begin
   FreeAndNil(FIPCBuffer);
   inherited;
end;

function TBaseIncomingInternalCapableConnection.InternalRead(Data: array of Byte): Boolean;
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

procedure TBaseIncomingInternalCapableConnection.MaybeHandleIPCPassword();
var
   FullBuffer: RawByteString;
   Reader: TBinaryStreamReader;
   BufferLength: Cardinal;
begin
   if (FIPCBuffer.BufferLength >= SizeOf(Cardinal)) then
   begin
      FullBuffer := FIPCBuffer.Serialize(False);
      Reader := TBinaryStreamReader.Create(FullBuffer);
      try
         BufferLength := Reader.ReadCardinal();
         if (SizeOf(Cardinal) + BufferLength <= Length(FullBuffer)) then
         begin
            FIPCBuffer.Consume(SizeOf(Cardinal) + BufferLength); // $R-
            Reader.Reset();
            if (Reader.ReadString() <> GetInternalPassword()) then
            begin
               Disconnect();
            end
            else
            begin
               FMode := cmControlMessages;
            end;
         end;
      finally
         FreeAndNil(Reader);
      end;
   end;
end;

procedure TBaseIncomingInternalCapableConnection.MaybeHandleIPC();
var
   FullBuffer: RawByteString;
   Reader: TBinaryStreamReader;
   BufferLength: Cardinal;
begin
   while (FIPCBuffer.BufferLength >= SizeOf(Cardinal)) do
   begin
      FullBuffer := FIPCBuffer.Serialize(False);
      Reader := TBinaryStreamReader.Create(FullBuffer);
      try
         BufferLength := Reader.ReadCardinal();
         if (SizeOf(Cardinal) + BufferLength <= Length(FullBuffer)) then
         begin
            FIPCBuffer.Consume(SizeOf(Cardinal) + BufferLength); // $R-
            Reader.Truncate(BufferLength);
            ConsoleWriteln('Received IPC: ', Reader.RawInput);
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

procedure TBaseIncomingInternalCapableConnection.HoldsCleared();
begin
   Assert(FMode = cmControlMessages);
   Write(#$01);
   Disconnect();
end;


constructor TInternalConversationHandle.Create(AConnection: TBaseIncomingInternalCapableConnection);
begin
   inherited Create(AConnection);
end;

procedure TInternalConversationHandle.AddHold();
begin
   Inc(FHolds);
end;

procedure TInternalConversationHandle.RemoveHold();
begin
   Dec(FHolds);
   if (FHolds = 0) then
   begin
      (FConnection as TBaseIncomingInternalCapableConnection).HoldsCleared();
   end;
end;

function TInternalConversationHandle.GetHasHolds(): Boolean;
begin
   Result := FHolds > 0;
end;


constructor TBaseOutgoingInternalConnection.Create(ASystemServer: PServerEntry);
begin
   inherited Create();
   FSystemServer := ASystemServer;
end;

function TBaseOutgoingInternalConnection.InternalRead(Data: array of Byte): Boolean;
var
   B: Byte;
begin
   Result := True;
   for B in Data do
   begin
      case (B) of
         $01:
            begin
               if (FPendingAcknowledgements = 0) then
               begin
                  Result := False;
                  exit;
               end;
               Dec(FPendingAcknowledgements);
            end;
         else
            Result := False;
            exit;
      end;
   end;
   if (FPendingAcknowledgements = 0) then
   begin
      Result := False;
      Done();
   end;
end;

procedure TBaseOutgoingInternalConnection.IncrementPendingCount();
begin
   Inc(FPendingAcknowledgements);
end;

procedure TBaseOutgoingInternalConnection.Done();
begin
end;

procedure TBaseOutgoingInternalConnection.Connect();
begin
   ConnectIpV4(FSystemServer^.DirectHost, FSystemServer^.DirectPort);
end;

procedure TBaseOutgoingInternalConnection.Preconnect();
var
   PasswordLengthPrefix: Cardinal;
begin
   inherited;
   Write(#0); // to tell server it's not websockets
   PasswordLengthPrefix := Length(FSystemServer^.DirectPassword); // $R-
   Write(@PasswordLengthPrefix, SizeOf(PasswordLengthPrefix));
   Write(FSystemServer^.DirectPassword);
end;

procedure TBaseOutgoingInternalConnection.ReportConnectionError(ErrorCode: cint);
begin
   Writeln('Unexpected internal error #', ErrorCode, ': ', StrError(ErrorCode));
   Writeln(GetStackTrace());
end;


procedure TBaseServer.ScheduleDemolition(Victim: TObject);
begin
   SetLength(FDeadObjects, Length(FDeadObjects) + 1);
   FDeadObjects[High(FDeadObjects)] := Victim;
end;

procedure TBaseServer.CompleteDemolition();
var
   Victim: TObject;
begin
   for Victim in FDeadObjects do
      Victim.Free();
   SetLength(FDeadObjects, 0);
end;

procedure TBaseServer.Run();
begin
   repeat
      Select(-1);
      ReportChanges();
      CompleteDemolition();
   until Aborted;
end;

procedure TBaseServer.ReportChanges();
begin
end;

initialization
   InstallSigIntHandler();
end.
