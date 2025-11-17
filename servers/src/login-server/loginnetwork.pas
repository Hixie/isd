{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit loginnetwork;

// TODO: a program that verifies everything is consistent and removes
// user accounts for cases where the dynasty server doesn't think the
// user account has a matching dynasty, and dynasties that haven't
// progressed much and aren't still connected and don't have a
// user-specified username, etc.

interface

uses
   corenetwork, stringstream, users, logindynasty, isderrors, clock,
   servers, basenetwork, binaries, galaxy, astronomy, binarystream, sharedpointer;

const
   DefaultPasswordLength = 64;
   DefaultTokenLength = 64;
   DefaultSaltLength = 8;

type
   TServer = class;

   TPendingMessageInternals = class
   private
      FMessage: TMessage;
   public
      constructor Create(AMessage: TMessage);
      destructor Destroy(); override;
      procedure Fail(Error: UTF8String);
      property Message: TMessage read FMessage;
   end;
   TPendingMessage = specialize TSharedPointer<TPendingMessageInternals>;
   
   TDynastyServerOutgoingInternalConnection = class(TBaseOutgoingInternalConnection)
   protected
      FClientMessage: TPendingMessage;
      FServer: TServer;
      procedure Done(); override; // Called by superclass when all holds are cleared.
   public
      constructor Create(AClientMessage: TPendingMessage; AServer: TServer; ADynastyServer: PServerEntry);
      procedure Disconnect(); override;
   end;

   TInternalDynastyConnection = class(TDynastyServerOutgoingInternalConnection)
   public
      procedure RegisterNewAccount(Dynasty: TDynasty);
      procedure RegisterToken(Dynasty: TDynasty);
      procedure Logout(Dynasty: TDynasty);
   end;

   TInternalSystemConnection = class(TDynastyServerOutgoingInternalConnection)
   public
      procedure RegisterNewHome(System: TStarID; Dynasty: TDynasty; DynastyServerID: Cardinal);
   end;

   TConnection = class(TBaseIncomingInternalCapableConnection)
   protected
      FServer: TServer;
      function ParseDynastyArguments(Message: TMessage): TDynasty;
      procedure SendBinary(var Message: TMessage; BinaryFile: TBinaryFile);
      function GetInternalPassword(): UTF8String; override;
      procedure HandleIPC(const Command: UTF8String; const Arguments: TBinaryStreamReader); override;
   protected
      procedure DoCreateDynasty(var Message: TMessage) message 'new'; // no arguments
      procedure DoLogin(var Message: TMessage) message 'login'; // arguments: username, password
      procedure DoLogout(var Message: TMessage) message 'logout'; // arguments: username, password
      procedure DoChangeUsername(var Message: TMessage) message 'change-username'; // arguments: username, password, new username
      procedure DoChangePassword(var Message: TMessage) message 'change-password'; // arguments: username, password, new password
      procedure GetConstants(var Message: TMessage) message 'get-constants'; // no arguments
      procedure GetFile(var Message: TMessage) message 'get-file'; // arguments: file id
      procedure GetHighScores(var Message: TMessage) message 'get-high-scores'; // arguments: optional list of dynasty IDs
      procedure GetScores(var Message: TMessage) message 'get-scores'; // arguments: list of pairs of dynasty IDs and point indicies
   public
      constructor Create(AListener: TListenerSocket; AServer: TServer);
   end;

   TServer = class(TBaseServer)
   protected
      FInternalPassword, FDataDirectory: UTF8String;
      FGalaxyManager: TGalaxyManager;
      FUserDatabase: TUserDatabase;
      FDynastyServerDatabase, FSystemServerDatabase: TServerDatabase;
      function CreateNetworkSocket(AListenerSocket: TListenerSocket): TNetworkSocket; override;
   {$IFDEF TESTSUITE}
   private
      FDebugScoresReceived: Cardinal;
      FDebugAwaitScores: TInternalConversation;
   {$ENDIF}
   public
      constructor Create(APort: Word; AInternalPassword: UTF8String; AClock: TClock; ADataDirectory: UTF8String; AUserDatabase: TUserDatabase; ADynastyServerDatabase, ASystemServerDatabase: TServerDatabase; AGalaxyManager: TGalaxyManager);
      destructor Destroy(); override;
      procedure AddHighScoreDynasties(const DynastyIDs: TDynastyIDHashSet);
      property DataDirectory: UTF8String read FDataDirectory;
      property UserDatabase: TUserDatabase read FUserDatabase;
      property DynastyServerDatabase: TServerDatabase read FDynastyServerDatabase;
      property SystemServerDatabase: TServerDatabase read FSystemServerDatabase;
      property GalaxyManager: TGalaxyManager read FGalaxyManager;
   end;

implementation

uses
   sysutils, exceptions, isdprotocol, passwords, plasticarrays, genericutils, fileutils, configuration;

type
   TScoreRecord = packed record
      Timestamp: Int64;
      Score: Double;
   end;

constructor TConnection.Create(AListener: TListenerSocket; AServer: TServer);
begin
   inherited Create(AListener, AServer);
   FServer := AServer;
end;

function TConnection.ParseDynastyArguments(Message: TMessage): TDynasty;
var
   Username, Password: UTF8String;
begin
   Username := Message.Input.ReadString();
   Password := Message.Input.ReadString();
   Result := FServer.UserDatabase.GetAccount(Username, Password);
   if (not Assigned(Result)) then
   begin
      Message.Error(ieUnrecognizedCredentials);
   end;
end;

procedure TConnection.DoCreateDynasty(var Message: TMessage);
var
   Password: UTF8String;
   Dynasty: TDynasty;
   DynastyServerID, SystemServerID: Cardinal;
   DynastyServerDetails, SystemServerDetails: PServerEntry;
   InternalDynastyConnectionSocket: TInternalDynastyConnection;
   InternalSystemConnectionSocket: TInternalSystemConnection;
   StarID: TStarID;
   ScoreFile: File of TScoreRecord;
   PendingMessage: TPendingMessage;
begin
   if (not Message.CloseInput()) then
      exit;

   // Prepare user credentials
   Password := CreatePassword(DefaultPasswordLength);

   // Choose dynasty server and create user account / dynasty
   DynastyServerID := FServer.DynastyServerDatabase.GetLeastLoadedServer();
   DynastyServerDetails := FServer.DynastyServerDatabase[DynastyServerID];
   Dynasty := FServer.UserDatabase.CreateNewAccount(Password, DynastyServerID);
   FServer.DynastyServerDatabase.IncreaseLoadOnServer(DynastyServerID);

   Assign(ScoreFile, GenerateScoreFilename(FServer.DataDirectory + DynastyDataSubDirectory, Dynasty.ID));
   FileMode := 1;
   Rewrite(ScoreFile);
   Close(ScoreFile);

   // Prepare message for client (but don't send yet)
   Message.Reply();
   Message.Output.WriteString(Dynasty.Username);
   Message.Output.WriteString(Password);
   Message.Output.WriteString('wss://' + DynastyServerDetails^.HostName + ':' + IntToStr(DynastyServerDetails^.WebSocketPort) + '/');

   // Create a pending message that will get closed and freed when the internal messages (below) are done.
   PendingMessage := TPendingMessageInternals.Create(Message);
   
   // Connect to dynasty server and create account
   InternalDynastyConnectionSocket := TInternalDynastyConnection.Create(PendingMessage, FServer, DynastyServerDetails);
   try
      InternalDynastyConnectionSocket.Connect();
   except
      FreeAndNil(InternalDynastyConnectionSocket);
      raise;
   end;
   FServer.Add(InternalDynastyConnectionSocket);
   InternalDynastyConnectionSocket.RegisterNewAccount(Dynasty); // this will send the message if everything works

   // Choose system server and star
   SystemServerID := FServer.SystemServerDatabase.GetLeastLoadedServer();
   SystemServerDetails := FServer.SystemServerDatabase[SystemServerID];
   StarID := FServer.GalaxyManager.SelectNextHomeSystem();
   FServer.SystemServerDatabase.IncreaseLoadOnServer(SystemServerID);

   // Connect to system server and create actual system
   InternalSystemConnectionSocket := TInternalSystemConnection.Create(PendingMessage, FServer, SystemServerDetails);
   try
      InternalSystemConnectionSocket.Connect();
   except
      FreeAndNil(InternalSystemConnectionSocket);
      raise;
   end;
   FServer.Add(InternalSystemConnectionSocket);
   InternalSystemConnectionSocket.RegisterNewHome(StarID, Dynasty, DynastyServerID);

   Writeln('Created dynasty "', Dynasty.Username, '" using star ', HexStr(Int64(StarID), 7));
end;

procedure TConnection.DoLogin(var Message: TMessage);
var
   Dynasty: TDynasty;
   DynastyServerDetails: PServerEntry;
   InternalDynastyConnectionSocket: TInternalDynastyConnection;
begin
   Dynasty := ParseDynastyArguments(Message);
   if (not Assigned(Dynasty) or not Message.CloseInput()) then
      exit;
   DynastyServerDetails := FServer.DynastyServerDatabase[Dynasty.ServerID];
   Message.Reply();
   Message.Output.WriteString('wss://' + DynastyServerDetails^.HostName + ':' + IntToStr(DynastyServerDetails^.WebSocketPort) + '/');
   InternalDynastyConnectionSocket := TInternalDynastyConnection.Create(TPendingMessageInternals.Create(Message), FServer, DynastyServerDetails);
   try
      InternalDynastyConnectionSocket.Connect();
   except
      FreeAndNil(InternalDynastyConnectionSocket);
      raise;
   end;
   FServer.Add(InternalDynastyConnectionSocket);
   InternalDynastyConnectionSocket.RegisterToken(Dynasty);
end;

procedure TConnection.DoLogout(var Message: TMessage);
var
   Dynasty: TDynasty;
   DynastyServerDetails: PServerEntry;
   InternalDynastyConnectionSocket: TInternalDynastyConnection;
begin
   Dynasty := ParseDynastyArguments(Message);
   if (not Assigned(Dynasty) or not Message.CloseInput()) then
      exit;
   DynastyServerDetails := FServer.DynastyServerDatabase[Dynasty.ServerID];
   Message.Reply();
   InternalDynastyConnectionSocket := TInternalDynastyConnection.Create(TPendingMessageInternals.Create(Message), FServer, DynastyServerDetails);
   try
      InternalDynastyConnectionSocket.Connect();
   except
      FreeAndNil(InternalDynastyConnectionSocket);
      raise;
   end;
   FServer.Add(InternalDynastyConnectionSocket);
   InternalDynastyConnectionSocket.Logout(Dynasty);
end;

procedure TConnection.DoChangeUsername(var Message: TMessage);
var
   Dynasty: TDynasty;
   NewUsername: UTF8String;
begin
   Dynasty := ParseDynastyArguments(Message);
   NewUsername := Message.Input.ReadString();
   if (not Assigned(Dynasty) or not Message.CloseInput()) then
      exit;
   if (not FServer.UserDatabase.UsernameAdequate(NewUsername)) then
   begin
      Message.Error(ieInadequateUsername);
      exit;
   end;
   FServer.UserDatabase.ChangeUsername(Dynasty, NewUsername);
   Message.Reply();
   Message.CloseOutput();
end;

procedure TConnection.DoChangePassword(var Message: TMessage);
var
   Dynasty: TDynasty;
   NewPassword: UTF8String;
begin
   Dynasty := ParseDynastyArguments(Message);
   NewPassword := Message.Input.ReadString();
   if (not Assigned(Dynasty) or not Message.CloseInput()) then
      exit;
   if (not TUserDatabase.PasswordAdequate(NewPassword)) then
   begin
      Message.Error(ieInadequatePassword);
      exit;
   end;
   FServer.UserDatabase.ChangePassword(Dynasty, NewPassword);
   Message.Reply();
   Message.CloseOutput();
end;

procedure TConnection.SendBinary(var Message: TMessage; BinaryFile: TBinaryFile);
begin
   WriteFrame(BinaryFile.Buffer^, BinaryFile.Length);
   Message.Reply();
   Message.CloseOutput();
end;

procedure TConnection.GetConstants(var Message: TMessage);
begin
   if (not Message.CloseInput()) then
      exit;
   Message.Reply();
   Message.Output.WriteDouble(FServer.GalaxyManager.GalaxyDiameter);
   Message.CloseOutput();
end;

procedure TConnection.GetFile(var Message: TMessage);
var
   ID: Cardinal;
begin
   ID := Message.Input.ReadCardinal();
   if (not Message.CloseInput()) then
      exit;
   case ID of
      1: SendBinary(Message, FServer.GalaxyManager.GalaxyData);
      2: SendBinary(Message, FServer.GalaxyManager.SystemsData);
   else
      Message.Error(ieUnknownFileCode);
   end;
end;

procedure TConnection.GetHighScores(var Message: TMessage); // arguments: optional list of dynasty IDs
var
   EndOffset: QWord;
   DynastyID: Cardinal;
   DynastyIDs: TDynastyIDHashSet;
   OpenFiles: specialize PlasticArray<TFileData, specialize IncomparableUtils<TFileData>>;
   BinaryStream: TBinaryStreamWriter;
   BinaryBits: RawByteString;
   Scores: TFileData;
begin
   DynastyIDs := TDynastyIDHashSet.Create();
   try
      FServer.AddHighScoreDynasties(DynastyIDs);
      while (Message.Input.CanReadMore) do
      begin
         DynastyID := Message.Input.ReadCardinal();
         if ((DynastyID = 0) or (DynastyID > FServer.UserDatabase.DynastyCount)) then
         begin
            Message.Error(ieUnknownDynasty);
            exit;
         end;
         if (not DynastyIDs.Has(DynastyID)) then
            DynastyIDs.Add(DynastyID);
      end;
      if (DynastyIDs.Count > 16) then
      begin
         Message.Error(ieInvalidMessage);
         exit;
      end;
      if (not Message.CloseInput()) then
         exit;
      Message.Reply();
      BinaryStream := TBinaryStreamWriter.Create();
      try
         BinaryStream.WriteCardinal(0);
         for DynastyID in DynastyIDs do
         begin
            Scores := ReadFileTail(GenerateScoreFilename(FServer.DataDirectory + DynastyDataSubDirectory, DynastyID), 1024 * SizeOf(TScoreRecord), EndOffset);
            Assert(Scores.Length mod SizeOf(TScoreRecord) = 0);
            Assert(EndOffset mod SizeOf(TScoreRecord) = 0);
            BinaryStream.WriteCardinal(DynastyID);
            BinaryStream.WriteCardinal(EndOffset div SizeOf(TScoreRecord)); // $R-
            BinaryStream.WriteCardinal(Scores.Length div SizeOf(TScoreRecord)); // $R-
            BinaryStream.WriteRawBytesByPointer(Scores.Start, Scores.Length); // $R- (Scores.Length can't be too big, we only grab 1024 samples)
            OpenFiles.Push(Scores);
         end;
         BinaryBits := BinaryStream.Serialize(False);
         if (Length(BinaryBits) > 0) then
         begin
            WriteFrame(BinaryBits[1], Length(BinaryBits)); // $R-
         end
         else
         begin
            WriteFrame('', 0); // $R-
         end;
         Message.CloseOutput();
      finally
         FreeAndNil(BinaryStream);
         for Scores in OpenFiles do
            Scores.Destroy();
      end;
   finally
      FreeAndNil(DynastyIDs);
   end;
end;

procedure TConnection.GetScores(var Message: TMessage); // arguments: list of pairs of dynasty IDs and point indicies
var
   DynastyID, Index: Cardinal;
   DynastyIDs: specialize PlasticArray<Cardinal, CardinalUtils>;
   DynastyOffsets: specialize PlasticArray<Cardinal, CardinalUtils>;
   OpenFiles: specialize PlasticArray<TFileData, specialize IncomparableUtils<TFileData>>;
   BinaryStream: TBinaryStreamWriter;
   BinaryBits: RawByteString;
   Scores: TFileData;
begin
   while (Message.Input.CanReadMore) do
   begin
      DynastyID := Message.Input.ReadCardinal();
      if ((DynastyID = 0) or (DynastyID <= FServer.UserDatabase.DynastyCount)) then
      begin
         Message.Error(ieUnknownDynasty);
         exit;
      end;
      DynastyIDs.Push(DynastyID);
      DynastyOffsets.Push(Message.Input.ReadCardinal());
   end;
   if ((DynastyIDs.Length = 0) or (DynastyIDs.Length > 16)) then
   begin
      Message.Error(ieInvalidMessage);
      exit;
   end;
   if (not Message.CloseInput()) then
      exit;
   Message.Reply();
   BinaryStream := TBinaryStreamWriter.Create();
   try
      BinaryStream.WriteCardinal(0);
      for Index := 0 to DynastyIDs.Length - 1 do // $R- (we know there's at least one)
      begin
         Scores := ReadFilePart(GenerateScoreFilename(FServer.DataDirectory + DynastyDataSubDirectory, DynastyIDs[Index]), 1024 * SizeOf(TScoreRecord), DynastyOffsets[Index] * SizeOf(TScoreRecord)); // $R- (the offsets can't be more than 2^32)
         Assert(Scores.Length mod SizeOf(TScoreRecord) = 0);
         BinaryStream.WriteCardinal(DynastyID);
         BinaryStream.WriteCardinal(DynastyOffsets[Index]); // $R-
         BinaryStream.WriteCardinal(Scores.Length div SizeOf(TScoreRecord)); // $R-
         BinaryStream.WriteRawBytesByPointer(Scores.Start, Scores.Length); // $R- (Scores.Length can't be too big, we only grab 1024 samples)
         OpenFiles.Push(Scores);
      end;
      BinaryBits := BinaryStream.Serialize(False);
      WriteFrame(BinaryBits[1], Length(BinaryBits)); // $R-
      Message.CloseOutput();
   finally
      FreeAndNil(BinaryStream);
      for Scores in OpenFiles do
         Scores.Destroy();
   end;
end;

function TConnection.GetInternalPassword(): UTF8String;
begin
   Result := FServer.Password;
end;

procedure TConnection.HandleIPC(const Command: UTF8String; const Arguments: TBinaryStreamReader);
var
   DynastyID: Cardinal;
   ScoreRecord: TScoreRecord; // {BOGUS Note: Local variable "ScoreRecord" is assigned but never used}
   ScoreFile: File of TScoreRecord;
   {$IFDEF TESTSUITE}
   ExpectedScores: Cardinal;
   AwaitScores: TInternalConversation;
   {$ENDIF}
begin
   if (Command = icAddScoreDatum) then
   begin
      DynastyID := Arguments.ReadCardinal();
      if (DynastyID > FServer.UserDatabase.DynastyCount) then
      begin
         Writeln('Received an invalid dynasty ID for ', icAddScoreDatum, ' command: Dynasty ', DynastyID, ' does not exist (there are only ', FServer.UserDatabase.DynastyCount, ' dynasties).');
         Disconnect();
         exit;
      end;
      Assert(Assigned(FServer.Clock));
      ScoreRecord.TimeStamp := FServer.Clock.AsUnixEpoch();
      ScoreRecord.Score := Arguments.ReadDouble();
      Assign(ScoreFile, GenerateScoreFilename(FServer.DataDirectory + DynastyDataSubDirectory, DynastyID));
      FileMode := 2;
      Reset(ScoreFile);
      Seek(ScoreFile, FileSize(ScoreFile));
      BlockWrite(ScoreFile, ScoreRecord, 1);
      Close(ScoreFile);
      Write(#$01);
      FServer.UserDatabase.RegisterScoreUpdate(DynastyID, ScoreRecord.Score);
      {$IFDEF TESTSUITE}
      Inc(FServer.FDebugScoresReceived);
      if (Assigned(FServer.FDebugAwaitScores.Value)) then
      begin
         FServer.FDebugAwaitScores.Value.RemoveHold();
         if (not FServer.FDebugAwaitScores.Value.HasHolds) then
         begin
            FServer.FDebugAwaitScores.Free();
         end;
      end;
      {$ENDIF}
   end
   {$IFDEF TESTSUITE}
   else
   if (Command = icAwaitScores) then
   begin
      if (Assigned(FServer.FDebugAwaitScores.Value)) then
      begin
         Writeln('received multiple simultaneous score holds');
         Disconnect();
         exit;
      end;
      ExpectedScores := Arguments.ReadCardinal();
      if (ExpectedScores <= FServer.FDebugScoresReceived) then
      begin
         Write(#$01);
         exit;
      end;
      AwaitScores := TInternalConversationInternals.Create(Self);
      AwaitScores.Value.AddHold(ExpectedScores);
      AwaitScores.Value.RemoveHold(FServer.FDebugScoresReceived); 
      FServer.FDebugAwaitScores := AwaitScores;
   end
   {$ENDIF}
   else
      inherited;
end;


constructor TPendingMessageInternals.Create(AMessage: TMessage);
begin
   inherited Create();
   FMessage := AMessage;
end;

destructor TPendingMessageInternals.Destroy();
begin
   if (not FMessage.OutputClosed) then
      FMessage.CloseOutput();
end;

procedure TPendingMessageInternals.Fail(Error: UTF8String);
begin
   if (not FMessage.OutputClosed) then
      FMessage.Error(ieInternalError);
end;


constructor TDynastyServerOutgoingInternalConnection.Create(AClientMessage: TPendingMessage; AServer: TServer; ADynastyServer: PServerEntry);
begin
   inherited Create(ADynastyServer);
   FClientMessage := AClientMessage;
   FServer := AServer;
end;

procedure TDynastyServerOutgoingInternalConnection.Disconnect();
begin
   if (FClientMessage.Assigned) then
      FClientMessage.Value.Fail(ieInternalError);
   inherited;
end;

procedure TDynastyServerOutgoingInternalConnection.Done();
begin
   inherited;
   FClientMessage.Free();
end;


procedure TInternalDynastyConnection.RegisterNewAccount(Dynasty: TDynasty);
var
   Writer: TBinaryStreamWriter;
   Message: RawByteString;
begin
   Writer := TBinaryStreamWriter.Create();
   Writer.WriteStringByPointer(icCreateAccount);
   Writer.WriteCardinal(Dynasty.ID);
   Message := Writer.Serialize(True);
   ConsoleWriteln('Sending IPC to dynasty server: ', Message);
   Write(Message);
   FreeAndNil(Writer);
   RegisterToken(Dynasty);
   IncrementPendingCount();
end;

procedure TInternalDynastyConnection.RegisterToken(Dynasty: TDynasty);
var
   Token: UTF8String;
   Writer: TBinaryStreamWriter;
   Salt: TSalt;
   HashedToken: THash;
   Message: RawByteString;
begin
   Token := CreatePassword(DefaultTokenLength);
   Salt := CreateSalt();
   ComputeHash(Salt, Token, HashedToken);
   Writer := TBinaryStreamWriter.Create();
   Writer.WriteStringByPointer(icRegisterToken);
   Writer.WriteCardinal(Dynasty.ID);
   Writer.WriteRawBytesByPointer(@Salt[0], SizeOf(Salt));
   Writer.WriteRawBytesByPointer(@HashedToken[0], SizeOf(HashedToken));
   Message := Writer.Serialize(True);
   ConsoleWriteln('Sending IPC to dynasty server: ', Message);
   Write(Message);
   FreeAndNil(Writer);
   Assert(FClientMessage.Assigned);
   if (not FClientMessage.Value.Message.OutputClosed) then
      FClientMessage.Value.Message.Output.WriteString(IntToStr(Dynasty.ID) + TokenSeparator + Token);
   IncrementPendingCount();
end;

procedure TInternalDynastyConnection.Logout(Dynasty: TDynasty);
var
   Writer: TBinaryStreamWriter;
   Message: RawByteString;
begin
   Writer := TBinaryStreamWriter.Create();
   Writer.WriteStringByPointer(icLogout);
   Writer.WriteCardinal(Dynasty.ID);
   Message := Writer.Serialize(True);
   ConsoleWriteln('Sending IPC to dynasty server: ', Message);
   Write(Message);
   FreeAndNil(Writer);
   IncrementPendingCount();
end;


procedure TInternalSystemConnection.RegisterNewHome(System: TStarID; Dynasty: TDynasty; DynastyServerID: Cardinal);
var
   Writer: TBinaryStreamWriter;
   Message: RawByteString;
begin
   Assert(System >= 0);
   Writer := TBinaryStreamWriter.Create();
   Writer.WriteStringByPointer(icCreateSystem);
   FServer.GalaxyManager.SerializeSystemDescription(System, Writer);
   Message := Writer.Serialize(True);
   ConsoleWriteln('Sending IPC to system server: ', Message);
   Write(Message);
   IncrementPendingCount();
   Writer.Clear();
   Writer.WriteStringByPointer(icTriggerNewDynastyScenario);
   Writer.WriteCardinal(Dynasty.ID);
   Writer.WriteCardinal(DynastyServerID);
   Writer.WriteCardinal(System); // $R-
   Message := Writer.Serialize(True);
   ConsoleWriteln('Sending IPC to system server: ', Message);
   Write(Message);
   IncrementPendingCount();
   FreeAndNil(Writer);
end;


constructor TServer.Create(APort: Word; AInternalPassword: UTF8String; AClock: TClock; ADataDirectory: UTF8String; AUserDatabase: TUserDatabase; ADynastyServerDatabase, ASystemServerDatabase: TServerDatabase; AGalaxyManager: TGalaxyManager);
begin
   inherited Create(APort, AInternalPassword, AClock);
   FDataDirectory := ADataDirectory;
   FUserDatabase := AUserDatabase;
   FDynastyServerDatabase := ADynastyServerDatabase;
   FSystemServerDatabase := ASystemServerDatabase;
   FGalaxyManager := AGalaxyManager;
end;

function TServer.CreateNetworkSocket(AListenerSocket: TListenerSocket): TNetworkSocket;
begin
   Result := TConnection.Create(AListenerSocket, Self);
end;

destructor TServer.Destroy();
begin
   {$IFDEF TESTSUITE}
   FDebugAwaitScores.Free();
   {$ENDIF}
   inherited;
end;

procedure TServer.AddHighScoreDynasties(const DynastyIDs: TDynastyIDHashSet);
const
   HighScoreCount = 3;
type
   TEntry = record
      DynastyID: Cardinal;
      Score: Double;
   end;
   THighScoreTable = array[1..HighScoreCount] of TEntry;

   procedure Consider(DynastyID: Cardinal; Score: Double; var Table: THighScoreTable);
   var
      Index: Cardinal;
   begin
      for Index := High(Table) downto Low(Table) do
      begin
         if ((Table[Index].DynastyID = 0) or (Table[Index].Score < Score)) then
         begin
            if (Index < High(Table)) then
            begin
               Table[Index + 1].DynastyID := Table[Index].DynastyID;
               Table[Index + 1].Score := Table[Index].Score;
            end;
            Table[Index].DynastyID := DynastyID;
            Table[Index].Score := Score;
         end
         else
            exit;
      end;
   end;

   procedure AddDynastiesFrom(const Table: THighScoreTable);
   var
      Index: Cardinal;
   begin
      for Index := Low(Table) to High(Table) do
      begin
         if (Table[Index].DynastyID = 0) then
            exit;
         if (not DynastyIDs.Has(Table[Index].DynastyID)) then
            DynastyIDs.Add(Table[Index].DynastyID);
      end;
   end;

var
   TopEver: THighScoreTable;
   TopNow: THighScoreTable;
   Index: Cardinal;
   Dynasty: TDynasty;
begin
   for Index := Low(TopEver) to High(TopEver) do
      TopEver[Index] := Default(TEntry);
   for Index := Low(TopNow) to High(TopNow) do
      TopNow[Index] := Default(TEntry);
   for Dynasty in UserDatabase.Dynasties do
   begin
      Consider(Dynasty.ID, Dynasty.CurrentScore, TopNow);
      Consider(Dynasty.ID, Dynasty.TopScore, TopEver);
   end;
   AddDynastiesFrom(TopNow);
   AddDynastiesFrom(TopEver);
end;

end.
