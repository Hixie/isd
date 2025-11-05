{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit onoff;

interface

uses
   basenetwork, systems, serverstream, materials, techtree,
   messageport, isdprotocol;

type
   TOnOffFeatureClass = class(TFeatureClass)
   strict protected
      function GetFeatureNodeClass(): FeatureNodeReference; override;
   public
      constructor CreateFromTechnologyTree(Reader: TTechTreeReader); override;
      function InitFeatureNode(): TFeatureNode; override;
   end;

   TOnOffFeatureNode = class(TFeatureNode)
   strict private
      FEnabled: Boolean;
   protected
      function HandleBusMessage(Message: TBusMessage): Boolean; override;
      procedure Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter; CachedSystem: TSystem); override;
   public
      constructor Create();
      procedure UpdateJournal(Journal: TJournalWriter; CachedSystem: TSystem); override;
      procedure ApplyJournal(Journal: TJournalReader; CachedSystem: TSystem); override;
      function HandleCommand(Command: UTF8String; var Message: TMessage): Boolean; override;
   end;

implementation

uses
   exceptions, sysutils, systemnetwork, systemdynasty, isderrors,
   knowledge, messages, typedump, commonbuses;

constructor TOnOffFeatureClass.CreateFromTechnologyTree(Reader: TTechTreeReader);
begin
   inherited Create();
end;

function TOnOffFeatureClass.GetFeatureNodeClass(): FeatureNodeReference;
begin
   Result := TOnOffFeatureNode;
end;

function TOnOffFeatureClass.InitFeatureNode(): TFeatureNode;
begin
   Result := TOnOffFeatureNode.Create();
end;


constructor TOnOffFeatureNode.Create();
begin
   inherited Create();
   FEnabled := True;
end;

function TOnOffFeatureNode.HandleBusMessage(Message: TBusMessage): Boolean;
begin
   if (Message is TCheckDisabledBusMessage) then
   begin
      if (not FEnabled) then
         (Message as TCheckDisabledBusMessage).AddReason(drManuallyDisabled);
   end
   else
      Result := inherited;
end;

procedure TOnOffFeatureNode.Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter; CachedSystem: TSystem);
var
   Visibility: TVisibility;
begin
   Visibility := Parent.ReadVisibilityFor(DynastyIndex, CachedSystem);
   if ((dmDetectable * Visibility <> []) and (dmClassKnown in Visibility)) then
   begin
      Writer.WriteCardinal(fcOnOff);
      Writer.WriteBoolean(FEnabled);
   end;
end;

procedure TOnOffFeatureNode.UpdateJournal(Journal: TJournalWriter; CachedSystem: TSystem);
begin
   Journal.WriteBoolean(FEnabled);
end;

procedure TOnOffFeatureNode.ApplyJournal(Journal: TJournalReader; CachedSystem: TSystem);
begin
   FEnabled := Journal.ReadBoolean();
end;

function TOnOffFeatureNode.HandleCommand(Command: UTF8String; var Message: TMessage): Boolean;
var
   PlayerDynasty: TDynasty;
begin
   if (Command = 'enable') then
   begin
      Result := True;
      PlayerDynasty := (Message.Connection as TConnection).PlayerDynasty;
      if (PlayerDynasty <> Parent.Owner) then
      begin
         Message.Error(ieInvalidCommand);
         exit;
      end;
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
   if (Command = 'disable') then
   begin
      Result := True;
      PlayerDynasty := (Message.Connection as TConnection).PlayerDynasty;
      if (PlayerDynasty <> Parent.Owner) then
      begin
         Message.Error(ieInvalidCommand);
         exit;
      end;
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
      Result := inherited;
end;

initialization
   RegisterFeatureClass(TOnOffFeatureClass);
end.