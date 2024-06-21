{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit messages;

interface

uses
   stringstream, isderrors;

type
   TConversation = class;

   TCloseHandler = procedure(Conversation: TConversation) of object;
   
   TConversation = class
   protected
      FConversationID: Cardinal;
      FInput: TStringStreamReader;
      FOutput: TStringStreamWriter;
      FOnClose: TCloseHandler;
      function GetInputClosed(): Boolean;
      function GetOutputClosed(): Boolean;
   public
      constructor Create(Message: UTF8String; AOnClose: TCloseHandler);
      destructor Destroy(); override;
      function CloseInput(): Boolean;
      procedure CloseOutput();
      procedure Error(const Code: UTF8String);
      procedure Reply();
      property Input: TStringStreamReader read FInput;
      property Output: TStringStreamWriter read FOutput;
      property InputClosed: Boolean read GetInputClosed;
      property OutputClosed: Boolean read GetOutputClosed;
   end;

   TMessage = record // this is passed by value so must not contain mutable state
   public
      const
         MaxMessageNameLength = 32;
      type
         CommandString = String[MaxMessageNameLength];
   strict private
      FCommand: CommandString;
      FConversation: TConversation;
   public
      constructor Init(ACommand: CommandString; AConversation: TConversation);
      property Conversation: TConversation read FConversation;
   end;

implementation

constructor TConversation.Create(Message: UTF8String; AOnClose: TCloseHandler);
begin
   inherited Create();
   FInput := TStringStreamReader.Create(Message);
   FConversationID := FInput.ReadCardinal();
   FOutput := TStringStreamWriter.Create();
   FOnClose := AOnClose;
end;

destructor TConversation.Destroy();
begin
   FInput.Free();
   FOutput.Free();
   inherited;
end;

function TConversation.GetInputClosed(): Boolean;
begin
   Result := Input.Ended;
end;

function TConversation.CloseInput(): Boolean;
begin
   Input.ReadEnd();
   Result := Input.Ended;
   if (not Result) then
   begin
      Error(ieInvalidMessage);
   end;
end;

function TConversation.GetOutputClosed(): Boolean;
begin
   Result := Output.Closed;
end;

procedure TConversation.CloseOutput();
begin
   Assert(not OutputClosed);
   Output.Close();
   FOnClose(Self);
end;

procedure TConversation.Error(const Code: UTF8String);
begin
   if (not InputClosed) then
   begin
      Input.Bail();
   end;
   if (not OutputClosed) then
   begin
      Output.Reset();
      Output.WriteString('reply');
      Output.WriteCardinal(FConversationID);
      Output.WriteBoolean(False);
      Output.WriteString(Code);
      CloseOutput();
   end;
end;

procedure TConversation.Reply();
begin
   {$IFOPT C+} Assert(not Output.DebugStarted); {$ENDIF}
   {$IFOPT C+} Assert(not OutputClosed); {$ENDIF}
   Output.WriteString('reply');
   Output.WriteCardinal(FConversationID);
   Output.WriteBoolean(True);
end;


constructor TMessage.Init(ACommand: CommandString; AConversation: TConversation);
begin
   FCommand := ACommand;
   FConversation := AConversation;
end;

end.