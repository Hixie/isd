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
   corenetwork, stringstream, users, logindynasty, isderrors,
   servers, basenetwork, binaries, galaxy, astronomy;

const
   DefaultPasswordLength = 64;
   DefaultTokenLength = 64;
   DefaultSaltLength = 8;

type
   TServer = class;

   TInternalDynastyConnection = class(TBaseOutgoingInternalConnection)
   protected
      FClientMessage: TMessage;
      procedure Done(); override;
   public
      constructor Create(AClientMessage: TMessage; ADynastyServer: PServerEntry);
      procedure Disconnect(); override;
      procedure RegisterNewAccount(Dynasty: TDynasty);
      procedure RegisterToken(Dynasty: TDynasty);
      procedure Logout(Dynasty: TDynasty);
   end;

   TInternalSystemConnection = class(TBaseOutgoingInternalConnection)
   protected
      FServer: TServer;
   public
      constructor Create(AServer: TServer; ASystemServer: PServerEntry);
      procedure RegisterNewHome(System: TStarID; Dynasty: TDynasty; DynastyServerID: Cardinal);
   end;

   TConnection = class(TBaseIncomingCapableConnection)
   protected
      FServer: TServer;
      function ParseDynastyArguments(Message: TMessage): TDynasty;
      procedure SendBinary(var Message: TMessage; BinaryFile: TBinaryFile);
   protected
      procedure DoCreateDynasty(var Message: TMessage) message 'new'; // no arguments
      procedure DoLogin(var Message: TMessage) message 'login'; // arguments: username, password
      procedure DoLogout(var Message: TMessage) message 'logout'; // arguments: username, password
      procedure DoChangeUsername(var Message: TMessage) message 'change-username'; // arguments: username, password, new username
      procedure DoChangePassword(var Message: TMessage) message 'change-password'; // arguments: username, password, new password
      procedure GetConstants(var Message: TMessage) message 'get-constants'; // no arguments
      procedure GetFile(var Message: TMessage) message 'get-file'; // arguments: file id
   public
      constructor Create(AListener: TListenerSocket; AServer: TServer);
   end;

   TServer = class(TBaseServer)
   protected
      FGalaxyManager: TGalaxyManager;
      FUserDatabase: TUserDatabase;
      FDynastyServerDatabase, FSystemServerDatabase: TServerDatabase;
      function CreateNetworkSocket(AListenerSocket: TListenerSocket): TNetworkSocket; override;
   public
      constructor Create(APort: Word; AUserDatabase: TUserDatabase; ADynastyServerDatabase, ASystemServerDatabase: TServerDatabase; AGalaxyManager: TGalaxyManager);
      property UserDatabase: TUserDatabase read FUserDatabase;
      property DynastyServerDatabase: TServerDatabase read FDynastyServerDatabase;
      property SystemServerDatabase: TServerDatabase read FSystemServerDatabase;
      property GalaxyManager: TGalaxyManager read FGalaxyManager;
   end;

implementation

uses
   sysutils, exceptions, isdprotocol, passwords, binarystream;

constructor TConnection.Create(AListener: TListenerSocket; AServer: TServer);
begin
   inherited Create(AListener);
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

   // Prepare message for client (but don't send yet)
   Message.Reply();
   Message.Output.WriteString(Dynasty.Username);
   Message.Output.WriteString(Password);
   Message.Output.WriteString('wss://' + DynastyServerDetails^.HostName + ':' + IntToStr(DynastyServerDetails^.WebSocketPort) + '/');

   // Connect to dynasty server and create account
   InternalDynastyConnectionSocket := TInternalDynastyConnection.Create(Message, DynastyServerDetails);
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
   InternalSystemConnectionSocket := TInternalSystemConnection.Create(FServer, SystemServerDetails);
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
   InternalDynastyConnectionSocket := TInternalDynastyConnection.Create(Message, DynastyServerDetails);
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
   InternalDynastyConnectionSocket := TInternalDynastyConnection.Create(Message, DynastyServerDetails);
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
   Message.Reply();
   Message.CloseOutput();
   WriteFrame(BinaryFile.Buffer^, BinaryFile.Length);
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
      1: SendBinary(Message, FServer.GalaxyManager.SystemsData);
      2: SendBinary(Message, FServer.GalaxyManager.GalaxyData);
   else
      Message.Error(ieUnknownFileCode);
   end;
end;


constructor TInternalDynastyConnection.Create(AClientMessage: TMessage; ADynastyServer: PServerEntry);
begin
   inherited Create(ADynastyServer);
   FClientMessage := AClientMessage;
end;

procedure TInternalDynastyConnection.Done();
begin
   if (not FClientMessage.OutputClosed) then
      FClientMessage.CloseOutput();
end;

procedure TInternalDynastyConnection.Disconnect();
begin
   if (not FClientMessage.OutputClosed) then
      FClientMessage.Error(ieInternalError);
   inherited;
end;

procedure TInternalDynastyConnection.RegisterNewAccount(Dynasty: TDynasty);
var
   Writer: TBinaryStreamWriter;
   Message: RawByteString;
begin
   Writer := TBinaryStreamWriter.Create();
   Writer.WriteString(icCreateAccount);
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
   Writer.WriteString(icRegisterToken);
   Writer.WriteCardinal(Dynasty.ID);
   Writer.WriteRawBytes(@Salt[0], SizeOf(Salt));
   Writer.WriteRawBytes(@HashedToken[0], SizeOf(HashedToken));
   Message := Writer.Serialize(True);
   ConsoleWriteln('Sending IPC to dynasty server: ', Message);
   Write(Message);
   FreeAndNil(Writer);
   if (not FClientMessage.OutputClosed) then
      FClientMessage.Output.WriteString(IntToStr(Dynasty.ID) + TokenSeparator + Token);
   IncrementPendingCount();
end;

procedure TInternalDynastyConnection.Logout(Dynasty: TDynasty);
var
   Writer: TBinaryStreamWriter;
   Message: RawByteString;
begin
   Writer := TBinaryStreamWriter.Create();
   Writer.WriteString(icLogout);
   Writer.WriteCardinal(Dynasty.ID);
   Message := Writer.Serialize(True);
   ConsoleWriteln('Sending IPC to dynasty server: ', Message);
   Write(Message);
   FreeAndNil(Writer);
   IncrementPendingCount();
end;


constructor TInternalSystemConnection.Create(AServer: TServer; ASystemServer: PServerEntry);
begin
   inherited Create(ASystemServer);
   FServer := AServer;
end;

procedure TInternalSystemConnection.RegisterNewHome(System: TStarID; Dynasty: TDynasty; DynastyServerID: Cardinal);
var
   Writer: TBinaryStreamWriter;
   Message: RawByteString;
begin
   Assert(System >= 0);
   Writer := TBinaryStreamWriter.Create();
   Writer.WriteString(icCreateSystem);
   FServer.GalaxyManager.SerializeSystemDescription(System, Writer);
   Message := Writer.Serialize(True);
   ConsoleWriteln('Sending IPC to system server: ', Message);
   Write(Message);
   IncrementPendingCount();
   Writer.Clear();
   Writer.WriteString(icTriggerNewDynastyScenario);
   Writer.WriteCardinal(Dynasty.ID);
   Writer.WriteCardinal(DynastyServerID);
   Writer.WriteCardinal(System); // $R-
   Message := Writer.Serialize(True);
   ConsoleWriteln('Sending IPC to system server: ', Message);
   Write(Message);
   IncrementPendingCount();
   FreeAndNil(Writer);
end;


constructor TServer.Create(APort: Word; AUserDatabase: TUserDatabase; ADynastyServerDatabase, ASystemServerDatabase: TServerDatabase; AGalaxyManager: TGalaxyManager);
begin
   inherited Create(APort);
   FUserDatabase := AUserDatabase;
   FDynastyServerDatabase := ADynastyServerDatabase;
   FSystemServerDatabase := ASystemServerDatabase;
   FGalaxyManager := AGalaxyManager;
end;

function TServer.CreateNetworkSocket(AListenerSocket: TListenerSocket): TNetworkSocket;
begin
   Result := TConnection.Create(AListenerSocket, Self);
end;

end.
