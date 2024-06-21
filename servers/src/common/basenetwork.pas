{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit basenetwork;

interface

uses
   corenetwork, corewebsocket, messages, genericutils, hashset;

type
   TConversationHashSet = specialize THashSet<TConversation, TObjectUtils>;

   TFreeObjectCallback = procedure (Victim: TObject) of object;
   
   TBaseConnection = class(TWebSocket)
   protected
      FConversations: TConversationHashSet;
      FFreeObjectCallback: TFreeObjectCallback;
      procedure HandleConversationClosure(Conversation: TConversation); virtual;
      procedure HandleMessage(Message: UTF8String); override;
   public
      constructor Create(AListenerSocket: TListenerSocket; AFreeObjectCallback: TFreeObjectCallback);
      destructor Destroy(); override;
      procedure DefaultHandlerStr(var Message); override;
      {$IFOPT C+} procedure WriteFrame(const s: UTF8String); override; {$ENDIF}
   end;

   TBaseServer = class(TNetworkServer)
   protected
      FDeadObjects: array of TObject;
   public
      procedure ScheduleDemolition(Victim: TObject);
      procedure CompleteDemolition();
      procedure Run();
   end;

   procedure ConsoleWriteln(const Prefix, S: UTF8String);

implementation

uses
   sysutils, stringstream, isderrors, utf8, unicode, exceptions, hashfunctions, sigint;

function ConversationHash32(const Key: TConversation): DWord;
begin
   Result := PtrUIntHash32(PtrUInt(Key));
end;

constructor TBaseConnection.Create(AListenerSocket: TListenerSocket; AFreeObjectCallback: TFreeObjectCallback);
begin
   inherited Create(AListenerSocket);
   FConversations := TConversationHashSet.Create(@ConversationHash32);
   FFreeObjectCallback := AFreeObjectCallback;
end;

destructor TBaseConnection.Destroy();
var
   Conversation: TConversation;
begin
   for Conversation in FConversations do
      Conversation.Free();
   FConversations.Free();
   inherited;
end;

procedure TBaseConnection.HandleConversationClosure(Conversation: TConversation);
begin
   WriteFrame(Conversation.Output.Serialize());
   FConversations.Remove(Conversation);
   FFreeObjectCallback(Conversation);
end;

procedure TBaseConnection.HandleMessage(Message: UTF8String);
var
   Command: UTF8String;
   Conversation: TConversation;
   ParsedMessage: TMessage;
begin
   ConsoleWriteln('Received: ', Message);
   Conversation := TConversation.Create(Message, @HandleConversationClosure);
   FConversations.Add(Conversation);
   Command := Conversation.Input.ReadString(TMessage.MaxMessageNameLength);
   ParsedMessage.Init(Command, Conversation);
   try
      DispatchStr(ParsedMessage);
      Assert(Conversation.InputClosed);
   except
      Conversation.Error(ieInternalError);
      ReportCurrentException();
      raise;
   end;
end;

procedure TBaseConnection.DefaultHandlerStr(var Message);
begin
   TMessage(Message).Conversation.Error(ieInvalidMessage);
end;

{$IFOPT C+}
procedure TBaseConnection.WriteFrame(const S: UTF8String);
begin
   ConsoleWriteln('Sending: ', S);
   Sleep(500); // this is to simulate bad network conditions
   inherited;
end;

procedure ConsoleWriteln(const Prefix, S: UTF8String);
var
   Index: Cardinal;
   Control, NextIsControl: Boolean;
   Color: Boolean;
begin
   Color := GetEnvironmentVariable('TERM') <> 'dumb';
   Write(Prefix);
   if (Length(S) > 0) then
   begin
      Control := False;
      if (Color) then
         Write(#$1B'[30;37;1m');
      for Index := 1 to Length(S) do // $R-
      begin
         NextIsControl := Ord(S[Index]) < $20;
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
            Write(CodepointToUTF8(TUnicodeCodepointRange(Ord(S[Index]) + $2400)).AsString);
         end
         else
         begin
            Write(S[Index]);
         end;
      end;
      if (Color) then
         Write(#$1B'[0m');
      Writeln();
   end
   else
   begin
      Writeln('<nothing>');
   end;
end;
{$ENDIF}


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
      CompleteDemolition();
   until Aborted;
end;

initialization
   InstallSigIntHandler();
end.
