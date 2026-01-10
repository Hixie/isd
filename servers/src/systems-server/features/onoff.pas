{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit onoff;

interface

uses
   basenetwork, systems, serverstream, materials, techtree,
   messageport, isdprotocol, systemdynasty;

type
   TOnOffFeatureClass = class(TFeatureClass)
   strict protected
      function GetFeatureNodeClass(): FeatureNodeReference; override;
   public
      constructor CreateFromTechnologyTree(Reader: TTechTreeReader); override;
      function InitFeatureNode(ASystem: TSystem): TFeatureNode; override;
   end;

   TOnOffFeatureNode = class(TFeatureNode)
   strict private
      FEnabled: Boolean;
   protected
      function HandleBusMessage(Message: TBusMessage): THandleBusMessageResult; override;
      procedure Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter); override;
   public
      constructor Create(ASystem: TSystem);
      procedure UpdateJournal(Journal: TJournalWriter); override;
      procedure ApplyJournal(Journal: TJournalReader); override;
      function HandleCommand(PlayerDynasty: TDynasty; Command: UTF8String; var Message: TMessage): Boolean; override;
   end;

implementation

uses
   exceptions, sysutils, knowledge, messages, typedump, commonbuses;

constructor TOnOffFeatureClass.CreateFromTechnologyTree(Reader: TTechTreeReader);
begin
   inherited Create();
end;

function TOnOffFeatureClass.GetFeatureNodeClass(): FeatureNodeReference;
begin
   Result := TOnOffFeatureNode;
end;

function TOnOffFeatureClass.InitFeatureNode(ASystem: TSystem): TFeatureNode;
begin
   Result := TOnOffFeatureNode.Create(ASystem);
end;


constructor TOnOffFeatureNode.Create(ASystem: TSystem);
begin
   inherited Create(ASystem);
   FEnabled := True;
end;

function TOnOffFeatureNode.HandleBusMessage(Message: TBusMessage): THandleBusMessageResult;
begin
   if (Message is TCheckDisabledBusMessage) then
   begin
      if (not FEnabled) then
         (Message as TCheckDisabledBusMessage).AddReason(drManuallyDisabled);
   end;
   Result := inherited;
end;

procedure TOnOffFeatureNode.Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter);
var
   Visibility: TVisibility;
begin
   Visibility := Parent.ReadVisibilityFor(DynastyIndex);
   if ((dmDetectable * Visibility <> []) and (dmClassKnown in Visibility)) then
   begin
      Writer.WriteCardinal(fcOnOff);
      Writer.WriteBoolean(FEnabled);
   end;
end;

procedure TOnOffFeatureNode.UpdateJournal(Journal: TJournalWriter);
begin
   Journal.WriteBoolean(FEnabled);
end;

procedure TOnOffFeatureNode.ApplyJournal(Journal: TJournalReader);
begin
   FEnabled := Journal.ReadBoolean();
end;

function TOnOffFeatureNode.HandleCommand(PlayerDynasty: TDynasty; Command: UTF8String; var Message: TMessage): Boolean;
begin
   if (Command = ccEnable) then
   begin
      Result := True;
      if (Message.CloseInput()) then
      begin
         Message.Reply();
         if (FEnabled) then
         begin
            Message.Output.WriteBoolean(False);
         end
         else
         begin
            Message.Output.WriteBoolean(True);
            FEnabled := True;
            MarkAsDirty([dkUpdateClients, dkUpdateJournal, dkNeedsHandleChanges]);
         end;
         Message.CloseOutput();
      end;
   end
   else
   if (Command = ccDisable) then
   begin
      Result := True;
      if (Message.CloseInput()) then
      begin
         Message.Reply();
         if (FEnabled) then
         begin
            Message.Output.WriteBoolean(True);
            FEnabled := False;
            MarkAsDirty([dkUpdateClients, dkUpdateJournal, dkNeedsHandleChanges]);
         end
         else
            Message.Output.WriteBoolean(False);
         Message.CloseOutput();
      end;
   end
   else
      Result := False;
end;

initialization
   RegisterFeatureClass(TOnOffFeatureClass);
end.