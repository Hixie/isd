{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit network;

interface

uses
   corenetwork, corewebsocket, stringstream, users, dynasty, isderrors, servers, baseunix, messages, basenetwork, binaries;

const
   DefaultPasswordLength = 64;
   DefaultTokenLength = 64;
   DefaultSaltLength = 8;

type
   TServer = class;

   TInternalServerConnectionSocket = class(TNetworkSocket)
   protected
      FConversation: TConversation;
      FDynastyServer: TDynastyServer;
      FPendingCommands: Cardinal;
      function InternalRead(Data: array of byte): Boolean; override; // return false if connection is bad
      procedure Preconnect(); override;
   public
      constructor Create(AConversation: TConversation; ADynastyServer: TDynastyServer);
      procedure Connect();
      procedure ReportConnectionError(ErrorCode: cint); override;
      procedure Disconnect(); override;
      procedure RegisterNewAccount(Dynasty: TDynasty);
      procedure RegisterToken(Dynasty: TDynasty);
      procedure Logout(Dynasty: TDynasty);
   end;

   TConnection = class(TBaseConnection)
   protected
      FServer: TServer;
      function ParseDynastyArguments(Message: TMessage): TDynasty;
      procedure DoCreateDynasty(var Message: TMessage) message 'new'; // no arguments
      procedure DoLogin(var Message: TMessage) message 'login'; // arguments: username, password
      procedure DoLogout(var Message: TMessage) message 'logout'; // arguments: username, password
      procedure DoChangeUsername(var Message: TMessage) message 'change-username'; // arguments: username, password, new username
      procedure DoChangePassword(var Message: TMessage) message 'change-password'; // arguments: username, password, new password
      procedure GetStars(var Message: TMessage) message 'get-stars'; // no arguments
   public
      constructor Create(AListener: TListenerSocket; AServer: TServer);
   end;

   TServer = class(TBaseServer)
   protected
      FGalaxy: TBinaryFile;
      FUserDatabase: TUserDatabase;
      FServerDatabase: TServerDatabase;
      function CreateNetworkSocket(AListenerSocket: TListenerSocket): TNetworkSocket; override;
   public
      constructor Create(APort: Word; AUserDatabase: TUserDatabase; AServerDatabase: TServerDatabase; AGalaxy: TBinaryFile);
      property UserDatabase: TUserDatabase read FUserDatabase;
      property ServerDatabase: TServerDatabase read FServerDatabase;
      property Galaxy: TBinaryFile read FGalaxy;
   end;

implementation

uses
   sysutils, exceptions, isdprotocol, passwords, binarystream, errors;

constructor TConnection.Create(AListener: TListenerSocket; AServer: TServer);
begin
   inherited Create(AListener, @AServer.ScheduleDemolition);
   FServer := AServer;
end;

function TConnection.ParseDynastyArguments(Message: TMessage): TDynasty;
var
   Username, Password: UTF8String;
begin
   Username := Message.Conversation.Input.ReadString();
   Password := Message.Conversation.Input.ReadString();
   Result := FServer.UserDatabase.GetAccount(Username, Password);
   if (not Assigned(Result)) then
   begin
      Message.Conversation.Error(ieUnrecognizedCredentials);
   end;
end;

procedure TConnection.DoCreateDynasty(var Message: TMessage);
var
   Password: UTF8String;
   Dynasty: TDynasty;
   DynastyServerID: Cardinal;
   DynastyServerDetails: TDynastyServer;
   InternalServerConnectionSocket: TInternalServerConnectionSocket;
begin
   if (not Message.Conversation.CloseInput()) then
      exit;
   Password := CreatePassword(DefaultPasswordLength);
   DynastyServerID := FServer.ServerDatabase.GetLeastLoadedServer();
   DynastyServerDetails := FServer.ServerDatabase[DynastyServerID];
   Dynasty := FServer.UserDatabase.CreateNewAccount(Password, DynastyServerID);
   FServer.ServerDatabase.AddDynastyToServer(DynastyServerID);
   Writeln('  Created dynasty "', Dynasty.Username, '"');
   // TODO: a program that verifies everything is consistent and removes user accounts for cases where the dynasty server doesn't
   // think the user account has a matching dynasty.
   Message.Conversation.Reply();
   Message.Conversation.Output.WriteString(Dynasty.Username);
   Message.Conversation.Output.WriteString(Password);
   Message.Conversation.Output.WriteString('wss://' + DynastyServerDetails.HostName + ':' + IntToStr(DynastyServerDetails.WebSocketPort) + '/');
   InternalServerConnectionSocket := TInternalServerConnectionSocket.Create(Message.Conversation, DynastyServerDetails);
   try
      InternalServerConnectionSocket.Connect();
   except
      FreeAndNil(InternalServerConnectionSocket);
      raise;
   end;
   FServer.Add(InternalServerConnectionSocket);
   InternalServerConnectionSocket.RegisterNewAccount(Dynasty);
end;

procedure TConnection.DoLogin(var Message: TMessage);
var
   Dynasty: TDynasty;
   DynastyServerDetails: TDynastyServer;
   InternalServerConnectionSocket: TInternalServerConnectionSocket;
begin
   Dynasty := ParseDynastyArguments(Message);
   if (not Assigned(Dynasty) or not Message.Conversation.CloseInput()) then
      exit;
   DynastyServerDetails := FServer.ServerDatabase[Dynasty.ServerID];
   Message.Conversation.Reply();
   Message.Conversation.Output.WriteString('wss://' + DynastyServerDetails.HostName + ':' + IntToStr(DynastyServerDetails.WebSocketPort) + '/');
   InternalServerConnectionSocket := TInternalServerConnectionSocket.Create(Message.Conversation, DynastyServerDetails);
   try
      InternalServerConnectionSocket.Connect();
   except
      FreeAndNil(InternalServerConnectionSocket);
      raise;
   end;
   FServer.Add(InternalServerConnectionSocket);
   InternalServerConnectionSocket.RegisterToken(Dynasty);
end;

procedure TConnection.DoLogout(var Message: TMessage);
var
   Dynasty: TDynasty;
   DynastyServerDetails: TDynastyServer;
   InternalServerConnectionSocket: TInternalServerConnectionSocket;
begin
   Dynasty := ParseDynastyArguments(Message);
   if (not Assigned(Dynasty) or not Message.Conversation.CloseInput()) then
      exit;
   DynastyServerDetails := FServer.ServerDatabase[Dynasty.ServerID];
   Message.Conversation.Reply();
   InternalServerConnectionSocket := TInternalServerConnectionSocket.Create(Message.Conversation, DynastyServerDetails);
   try
      InternalServerConnectionSocket.Connect();
   except
      FreeAndNil(InternalServerConnectionSocket);
      raise;
   end;
   FServer.Add(InternalServerConnectionSocket);
   InternalServerConnectionSocket.Logout(Dynasty);
end;

procedure TConnection.DoChangeUsername(var Message: TMessage);
var
   Dynasty: TDynasty;
   NewUsername: UTF8String;
begin
   Dynasty := ParseDynastyArguments(Message);
   NewUsername := Message.Conversation.Input.ReadString();
   if (not Assigned(Dynasty) or not Message.Conversation.CloseInput()) then
      exit;
   if (not FServer.UserDatabase.UsernameAdequate(NewUsername)) then
   begin
      Message.Conversation.Error(ieInadequateUsername);
      exit;
   end;
   FServer.UserDatabase.ChangeUsername(Dynasty, NewUsername);
   Message.Conversation.Reply();
   Message.Conversation.CloseOutput();
end;

procedure TConnection.DoChangePassword(var Message: TMessage);
var
   Dynasty: TDynasty;
   NewPassword: UTF8String;
begin
   Dynasty := ParseDynastyArguments(Message);
   NewPassword := Message.Conversation.Input.ReadString();
   if (not Assigned(Dynasty) or not Message.Conversation.CloseInput()) then
      exit;
   if (not TUserDatabase.PasswordAdequate(NewPassword)) then
   begin
      Message.Conversation.Error(ieInadequatePassword);
      exit;
   end;
   FServer.UserDatabase.ChangePassword(Dynasty, NewPassword);
   Message.Conversation.Reply();
   Message.Conversation.CloseOutput();
end;

procedure TConnection.GetStars(var Message: TMessage);
begin
   if (not Message.Conversation.CloseInput()) then
      exit;
   Message.Conversation.Reply();
   Message.Conversation.Output.WriteCardinal(1);
   Message.Conversation.CloseOutput();
   WriteFrame(FServer.Galaxy.Buffer^, FServer.Galaxy.Length);
end;


constructor TInternalServerConnectionSocket.Create(AConversation: TConversation; ADynastyServer: TDynastyServer);
begin
   inherited Create();
   FConversation := AConversation;
   FDynastyServer := ADynastyServer;
end;

procedure TInternalServerConnectionSocket.Connect();
begin
   ConnectIpV4(FDynastyServer.DirectHost, FDynastyServer.DirectPort);
end;

procedure TInternalServerConnectionSocket.Preconnect();
var
   PasswordLengthPrefix: Cardinal;
begin
   inherited;
   Write(#0); // to tell server it's not websockets
   PasswordLengthPrefix := Length(FDynastyServer.DirectPassword); // $R-
   Write(@PasswordLengthPrefix, SizeOf(PasswordLengthPrefix));
   Write(FDynastyServer.DirectPassword);
end;

function TInternalServerConnectionSocket.InternalRead(Data: array of byte): Boolean;
var
   B: Byte;
begin
   Result := True;
   for B in Data do
   begin
      case (B) of
         $01:
            begin
               if (FPendingCommands = 0) then
               begin
                  Result := False;
                  exit;
               end;
               Dec(FPendingCommands);
            end;
         else
            Result := False;
            exit;
      end;
   end;
   if (FPendingCommands = 0) then
   begin
      if (Assigned(FConversation)) then
      begin
         FConversation.CloseOutput();
         FConversation := nil;
      end;
      Result := False;
   end;
end;

procedure TInternalServerConnectionSocket.ReportConnectionError(ErrorCode: cint);
begin
   Writeln('Unexpected internal error #', ErrorCode, ': ', StrError(ErrorCode));
   Writeln(GetStackTrace());
end;

procedure TInternalServerConnectionSocket.Disconnect();
begin
   if (Assigned(FConversation)) then
   begin
      FConversation.Error(ieInternalError);
      FConversation := nil;
   end;
   inherited;
end;

procedure TInternalServerConnectionSocket.RegisterNewAccount(Dynasty: TDynasty);
var
   Writer: TBinaryStreamWriter;
begin
   Writer := TBinaryStreamWriter.Create();
   Writer.WriteString(icCreateAccount);
   Writer.WriteCardinal(Dynasty.ID);
   Write(Writer.Serialize(True));
   FreeAndNil(Writer);
   RegisterToken(Dynasty);
   Inc(FPendingCommands);
end;

procedure TInternalServerConnectionSocket.RegisterToken(Dynasty: TDynasty);
var
   Token: UTF8String;
   Writer: TBinaryStreamWriter;
   Salt: TSalt;
   HashedToken: THash;
begin
   Token := CreatePassword(DefaultTokenLength);
   Salt := CreateSalt();
   ComputeHash(Salt, Token, HashedToken);
   Writer := TBinaryStreamWriter.Create();
   Writer.WriteString(icRegisterToken);
   Writer.WriteCardinal(Dynasty.ID);
   Writer.WriteRawBytes(@Salt[0], SizeOf(Salt));
   Writer.WriteRawBytes(@HashedToken[0], SizeOf(HashedToken));
   Write(Writer.Serialize(True));
   FreeAndNil(Writer);
   if (Assigned(FConversation)) then
      FConversation.Output.WriteString(IntToStr(Dynasty.ID) + TokenSeparator + Token);
   Inc(FPendingCommands);
end;

procedure TInternalServerConnectionSocket.Logout(Dynasty: TDynasty);
var
   Writer: TBinaryStreamWriter;
begin
   Writer := TBinaryStreamWriter.Create();
   Writer.WriteString(icLogout);
   Writer.WriteCardinal(Dynasty.ID);
   Write(Writer.Serialize(True));
   FreeAndNil(Writer);
   Inc(FPendingCommands);
end;


constructor TServer.Create(APort: Word; AUserDatabase: TUserDatabase; AServerDatabase: TServerDatabase; AGalaxy: TBinaryFile);
begin
   inherited Create(APort);
   FUserDatabase := AUserDatabase;
   FServerDatabase := AServerDatabase;
   FGalaxy := AGalaxy;
end;

function TServer.CreateNetworkSocket(AListenerSocket: TListenerSocket): TNetworkSocket;
begin
   Result := TConnection.Create(AListenerSocket, Self);
end;

end.
