{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit network;

interface

uses
   corenetwork, corewebsocket, stringstream, users, dynasty, isderrors;

type
   TMessage = record // this is passed by value so must not contain mutable state
   public
      const
         MaxMessageNameLength = 32;
      type
         CommandString = String[MaxMessageNameLength];
   strict private
      FCommand: CommandString;
      FArguments: TStringStreamReader;
      FReplyStream: TStringStreamWriter;
   public
      constructor Init(ACommand: CommandString; AArguments: TStringStreamReader; AReplyStream: TStringStreamWriter);
      function Reply(const Success: Boolean): TStringStreamWriter;
      property Arguments: TStringStreamReader read FArguments;
   end;
   
   TConnection = class(TWebSocket)
   protected
      FUserDatabase: TUserDatabase;
      procedure HandleMessage(Message: UTF8String); override;
      function ParseDynastyArguments(Message: TMessage): TDynasty;
      function ParseEnd(Message: TMessage): Boolean;
      procedure DoCreateDynasty(var Message: TMessage) message 'new'; // no arguments
      procedure DoLogin(var Message: TMessage) message 'login'; // arguments: username, password
      procedure DoLogout(var Message: TMessage) message 'logout'; // arguments: username, password
      procedure DoChangeUsername(var Message: TMessage) message 'change-username'; // arguments: username, password, new username
      procedure DoChangePassword(var Message: TMessage) message 'change-password'; // arguments: username, password, new password
   public
      constructor Create(AListener: TListenerSocket; AUserDatabase: TUserDatabase);
      destructor Destroy(); override;
      procedure DefaultHandlerStr(var Message); override;
      procedure WriteFrame(const s: UTF8String); override;
   end;

   TServer = class(TNetworkServer)
   protected
      FUserDatabase: TUserDatabase;
      function CreateNetworkSocket(AListenerSocket: TListenerSocket): TNetworkSocket; override;
   public
      constructor Create(APort: Word; AUserDatabase: TUserDatabase);
   end;

implementation

uses
   sysutils;

type
   TStringStreamWebSocketWriter = class(TStringStreamWriter)
   private
      FWebSocket: TConnection;
   protected
      procedure ProcessValue(const Value: UTF8String); override; // called by Close()
   public
      constructor Create(AWebSocket: TConnection);
   end;

constructor TMessage.Init(ACommand: CommandString; AArguments: TStringStreamReader; AReplyStream: TStringStreamWriter);
begin
   FCommand := ACommand;
   FArguments := AArguments;
   FReplyStream := AReplyStream;
end;
   
function TMessage.Reply(const Success: Boolean): TStringStreamWriter;
begin
   {$IFOPT C+} Assert(not FReplyStream.DebugStarted); {$ENDIF}
   FReplyStream.WriteString('reply');
   FReplyStream.WriteBoolean(Success);
   Result := FReplyStream;
end;


constructor TStringStreamWebSocketWriter.Create(AWebSocket: TConnection);
begin
   FWebSocket := AWebSocket;
end;

procedure TStringStreamWebSocketWriter.ProcessValue(const Value: UTF8String);
begin
   FWebSocket.WriteFrame(Value);
end;


constructor TConnection.Create(AListener: TListenerSocket; AUserDatabase: TUserDatabase);
begin
   inherited Create(AListener);
   FUserDatabase := AUserDatabase;
end;

destructor TConnection.Destroy();
begin
   inherited;
end;

procedure TConnection.HandleMessage(Message: UTF8String);
var
   Command: UTF8String;
   Arguments: TStringStreamReader;
   ReplyStream: TStringStreamWebSocketWriter;
   ParsedMessage: TMessage;
begin
   Writeln('Received: ', Message);
   Arguments := TStringStreamReader.Create(Message);
   ReplyStream := TStringStreamWebSocketWriter.Create(Self);
   Command := Arguments.ReadString(TMessage.MaxMessageNameLength);
   ParsedMessage.Init(Command, Arguments, ReplyStream);
   DispatchStr(ParsedMessage);
   Assert(Arguments.Ended);
   {$IFOPT C+} Assert(ReplyStream.DebugStarted); {$ENDIF}
   ReplyStream.Close(); // calls WriteFrame
   Arguments.Destroy();
   ReplyStream.Destroy();
end;

function TConnection.ParseDynastyArguments(Message: TMessage): TDynasty;
var
   Username, Password: UTF8String;
   Dynasty: TDynasty;
begin
   Username := Message.Arguments.ReadString();
   Password := Message.Arguments.ReadString();
   Dynasty := FUserDatabase.GetAccount(Username, Password);
   if (not Assigned(Dynasty)) then
   begin
      Message.Arguments.Bail();
      Message.Reply(False).WriteString(EUnrecognizedCredentials);
      Result := nil;
      exit;
   end;
   Result := Dynasty;
end;

function TConnection.ParseEnd(Message: TMessage): Boolean;
begin
   Message.Arguments.ReadEnd();
   if (not Message.Arguments.Ended) then
   begin
      Message.Arguments.Bail();
      Message.Reply(False).WriteString(EInvalidMessage);
      Result := False;
   end;
   Result := True;
end;

procedure TConnection.DoCreateDynasty(var Message: TMessage);
var
   Password: UTF8String;
   Dynasty: TDynasty;
begin
   if (not ParseEnd(Message)) then
      exit;
   Password := FUserDatabase.CreatePassword();
   Dynasty := FUserDatabase.CreateNewAccount(Password);
   with (Message.Reply(True)) do
   begin
      Writeln('  Created dynasty "', Dynasty.Username, '"');
      WriteString(Dynasty.Username);
      WriteString(Password);
   end;    
end;

procedure TConnection.DoLogin(var Message: TMessage);
var
   Dynasty: TDynasty;
begin
   Dynasty := ParseDynastyArguments(Message);
   if (not Assigned(Dynasty) or not ParseEnd(Message)) then
      exit;
   Message.Reply(True);
   // ...
end;

procedure TConnection.DoLogout(var Message: TMessage);
var
   Dynasty: TDynasty;
begin
   Dynasty := ParseDynastyArguments(Message);
   if (not Assigned(Dynasty) or not ParseEnd(Message)) then
      exit;
   Message.Reply(True);
   // ...
end;

procedure TConnection.DoChangeUsername(var Message: TMessage);
var
   Dynasty: TDynasty;
   NewUsername: UTF8String;
begin
   Dynasty := ParseDynastyArguments(Message);
   NewUsername := Message.Arguments.ReadString();
   if (not Assigned(Dynasty) or not ParseEnd(Message)) then
      exit;
   if (not FUserDatabase.UsernameAdequate(NewUsername)) then
   begin
      Message.Reply(False).WriteString(EInadequateUsername);
      exit;
   end;
   FUserDatabase.ChangeUsername(Dynasty, NewUsername);
   Message.Reply(True);
end;

procedure TConnection.DoChangePassword(var Message: TMessage);
var
   Dynasty: TDynasty;
   NewPassword: UTF8String;
begin
   Dynasty := ParseDynastyArguments(Message);
   NewPassword := Message.Arguments.ReadString();
   if (not Assigned(Dynasty) or not ParseEnd(Message)) then
      exit;
   if (not TUserDatabase.PasswordAdequate(NewPassword)) then
   begin
      Message.Reply(False).WriteString(EInadequatePassword);
      exit;
   end;
   FUserDatabase.ChangePassword(Dynasty, NewPassword);
   Message.Reply(True);
end;

procedure TConnection.DefaultHandlerStr(var Message);
begin
   TMessage(Message).Reply(False).WriteString(EInvalidMessage);
end;

procedure TConnection.WriteFrame(const S: UTF8String);
begin
   Writeln('Sending: ', S);
   {$IFOPT C+} Sleep(100); {$ENDIF} // this is to simulate bad network conditions
   inherited;
end;


constructor TServer.Create(APort: Word; AUserDatabase: TUserDatabase);
begin
   inherited Create(APort);
   FUserDatabase := AUserDatabase;
end;

function TServer.CreateNetworkSocket(AListenerSocket: TListenerSocket): TNetworkSocket;
begin
   Result := TConnection.Create(AListenerSocket, FUserDatabase);
end;

end.
