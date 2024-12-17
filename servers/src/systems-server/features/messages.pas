{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit messages;

interface

uses
   systems, serverstream, time, knowledge, basenetwork;

type
   TNotificationMessage = class(TKnowledgeBusMessage)
   private
      FSource: TAssetNode;
      FSubject, FFrom, FBody: UTF8String;
   public
      constructor Create(ASource: TAssetNode; ASubject, AFrom, ABody: UTF8String);
      property Source: TAssetNode read FSource;
      property Subject: UTF8String read FSubject;
      property From: UTF8String read FFrom;
      property Body: UTF8String read FBody;
   end;

type
   TMessageBoardFeatureClass = class(TFeatureClass)
   private
      FMessageAssetClass: TAssetClass;
   strict protected
      function GetFeatureNodeClass(): FeatureNodeReference; override;
   public
      constructor Create(AMessageAssetClass: TAssetClass);
      function InitFeatureNode(): TFeatureNode; override;
   end;

   TMessageBoardFeatureNode = class(TFeatureNode)
   private
      FFeatureClass: TMessageBoardFeatureClass;
      FChildren: TAssetNodeArray;
   protected
      constructor CreateFromJournal(Journal: TJournalReader; AFeatureClass: TFeatureClass; ASystem: TSystem); override;
      procedure AdoptChild(Child: TAssetNode); override;
      procedure DropChild(Child: TAssetNode); override;
      function GetMass(): Double; override;
      function GetSize(): Double; override;
      function GetFeatureName(): UTF8String; override;
      procedure Walk(PreCallback: TPreWalkCallback; PostCallback: TPostWalkCallback); override;
      function HandleBusMessage(Message: TBusMessage): Boolean; override;
      procedure Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter; CachedSystem: TSystem); override;
   public
      constructor Create(AFeatureClass: TMessageBoardFeatureClass);
      destructor Destroy(); override;
      procedure UpdateJournal(Journal: TJournalWriter); override;
      procedure ApplyJournal(Journal: TJournalReader; CachedSystem: TSystem); override;
   end;

type
   TMessageFeatureClass = class(TFeatureClass)
   strict protected
      function GetFeatureNodeClass(): FeatureNodeReference; override;
   public
      function InitFeatureNode(): TFeatureNode; override;
   end;
   
   TMessageFeatureNode = class(TFeatureNode)
   private
      FSourceSystemID: Cardinal;
      FTimestamp: TTimeInMilliseconds;
      FIsRead: Boolean;
      FSubject, FFrom, FBody: UTF8String;
   protected
      function GetMass(): Double; override;
      function GetSize(): Double; override;
      function GetFeatureName(): UTF8String; override;
      procedure Walk(PreCallback: TPreWalkCallback; PostCallback: TPostWalkCallback); override;
      function HandleBusMessage(Message: TBusMessage): Boolean; override;
      procedure Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter; CachedSystem: TSystem); override;
   public
      constructor Create();
      constructor Create(ASourceSystemID: Cardinal; ATimestamp: TTimeInMilliseconds; AIsRead: Boolean; ASubject, AFrom, ABody: UTF8String);
      procedure SetMessage(ASourceSystemID: Cardinal; ATimestamp: TTimeInMilliseconds; ASubject, AFrom, ABody: UTF8String);
      procedure UpdateJournal(Journal: TJournalWriter); override;
      procedure ApplyJournal(Journal: TJournalReader; CachedSystem: TSystem); override;
      function HandleCommand(Command: UTF8String; var Message: TMessage): Boolean; override;
   end;

implementation

uses
   isdprotocol, sysutils;

type
   PMessageBoardData = ^TMessageBoardData;
   TMessageBoardData = record
      IsDirty, IsNew: Boolean;
      Index: Cardinal;
   end;


constructor TNotificationMessage.Create(ASource: TAssetNode; ASubject, AFrom, ABody: UTF8String);
begin
   inherited Create();
   FSource := ASource;
   FSubject := ASubject;
   FFrom := AFrom;
   FBody := ABody;
end;


constructor TMessageBoardFeatureClass.Create(AMessageAssetClass: TAssetClass);
begin
   inherited Create();
   FMessageAssetClass := AMessageAssetClass;
end;

function TMessageBoardFeatureClass.GetFeatureNodeClass(): FeatureNodeReference;
begin
   Result := TMessageBoardFeatureNode;
end;

function TMessageBoardFeatureClass.InitFeatureNode(): TFeatureNode;
begin
   Result := TMessageBoardFeatureNode.Create(Self);
end;


constructor TMessageBoardFeatureNode.Create(AFeatureClass: TMessageBoardFeatureClass);
begin
   inherited Create();
   FFeatureClass := AFeatureClass;
end;

constructor TMessageBoardFeatureNode.CreateFromJournal(Journal: TJournalReader; AFeatureClass: TFeatureClass; ASystem: TSystem);
begin
   inherited CreateFromJournal(Journal, AFeatureClass, ASystem);
   Assert(Assigned(AFeatureClass));
   FFeatureClass := AFeatureClass as TMessageBoardFeatureClass;
end;

destructor TMessageBoardFeatureNode.Destroy();
var
   Child: TAssetNode;
begin
   for Child in FChildren do
      Child.Free();
   SetLength(FChildren, 0);
   inherited;
end;

procedure TMessageBoardFeatureNode.AdoptChild(Child: TAssetNode);
begin
   SetLength(FChildren, Length(FChildren)+1);
   FChildren[High(FChildren)] := Child;
   inherited;
   Child.ParentData := New(PMessageBoardData);
   PMessageBoardData(Child.ParentData)^.IsNew := True;
   PMessageBoardData(Child.ParentData)^.IsDirty := True;
   PMessageBoardData(Child.ParentData)^.Index := High(FChildren); // $R-
end;

procedure TMessageBoardFeatureNode.DropChild(Child: TAssetNode);
var
   Index: Cardinal;
begin
   Delete(FChildren, PMessageBoardData(Child.ParentData)^.Index, 1);
   if (PMessageBoardData(Child.ParentData)^.Index < Length(FChildren)) then
      for Index := PMessageBoardData(Child.ParentData)^.Index to High(FChildren) do // $R-
         PMessageBoardData(FChildren[Index].ParentData)^.Index := Index;
   Dispose(PMessageBoardData(Child.ParentData));
   Child.ParentData := nil;
   inherited;
end;

function TMessageBoardFeatureNode.GetMass(): Double;
begin
   Result := 0.0;
end;

function TMessageBoardFeatureNode.GetSize(): Double;
begin
   Result := 0.0;
end;

function TMessageBoardFeatureNode.GetFeatureName(): UTF8String;
begin
   Result := '';
end;

procedure TMessageBoardFeatureNode.Walk(PreCallback: TPreWalkCallback; PostCallback: TPostWalkCallback);
var
   Child: TAssetNode;
begin
   for Child in FChildren do
      Child.Walk(PreCallback, PostCallback);
end;

function TMessageBoardFeatureNode.HandleBusMessage(Message: TBusMessage): Boolean;
var
   Child: TAssetNode;
   Notification: TNotificationMessage;
   Feature: TMessageFeatureNode;
   CachedSystem: TSystem;
begin
   if (Message is TNotificationMessage) then
   begin
      Notification := Message as TNotificationMessage;
      if (Notification.Source.Owner = Parent.Owner) then
      begin
         Child := FFeatureClass.FMessageAssetClass.Spawn(Parent.Owner);
         Feature := Child.GetFeatureByClass(TMessageFeatureClass) as TMessageFeatureNode;
         CachedSystem := System;
         Feature.SetMessage(CachedSystem.SystemID, CachedSystem.Now, Notification.Subject, Notification.From, Notification.Body);
         AdoptChild(Child);
         Result := True;
         exit;
      end;
   end;
   for Child in FChildren do
   begin
      Result := Child.HandleBusMessage(Message);
      if (Result) then
         exit;
   end;
   Result := False;
end;

procedure TMessageBoardFeatureNode.Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter; CachedSystem: TSystem);
var
   Child: TAssetNode;
   Visibility: TVisibility;
begin
   Visibility := Parent.ReadVisibilityFor(DynastyIndex, CachedSystem);
   if (dmInternals in Visibility) then
   begin
      Writer.WriteCardinal(fcMessageBoard);
      for Child in FChildren do
      begin
         if (Child.IsVisibleFor(DynastyIndex, CachedSystem)) then
            Writer.WriteCardinal(Child.ID(CachedSystem, DynastyIndex));
      end;
      Writer.WriteCardinal(0);
   end;
end;

procedure TMessageBoardFeatureNode.UpdateJournal(Journal: TJournalWriter);
var
   Child: TAssetNode;
begin
   if (Length(FChildren) > 0) then
   begin
      for Child in FChildren do
      begin
         Assert(Assigned(Child));
         if (PMessageBoardData(Child.ParentData)^.IsDirty) then
         begin
            if (PMessageBoardData(Child.ParentData)^.IsNew) then
            begin
               Journal.WriteAssetChangeKind(ckAdd);
               PMessageBoardData(Child.ParentData)^.IsNew := False;
            end
            else
            begin
               Journal.WriteAssetChangeKind(ckChange);
            end;
            Journal.WriteAssetNodeReference(Child);
            PMessageBoardData(Child.ParentData)^.IsDirty := False;
         end;
      end;
   end;
   Journal.WriteAssetChangeKind(ckEndOfList);
end;

procedure TMessageBoardFeatureNode.ApplyJournal(Journal: TJournalReader; CachedSystem: TSystem);

   procedure AddChild();
   var
      AssetNode: TAssetNode;
   begin
      AssetNode := Journal.ReadAssetNodeReference();
      AdoptChild(AssetNode);
      Assert(AssetNode.Parent = Self);
   end;

   procedure ChangeChild();
   var
      Child: TAssetNode;
   begin
      Child := Journal.ReadAssetNodeReference();
      // nothing to do
      Assert(Child.Parent = Self);
   end;

var
   AssetChangeKind: TAssetChangeKind;
begin
   repeat
      AssetChangeKind := Journal.ReadAssetChangeKind();
      case AssetChangeKind of
         ckAdd: AddChild();
         ckChange: ChangeChild();
         ckEndOfList: break;
      end;
   until False;
end;


function TMessageFeatureClass.GetFeatureNodeClass(): FeatureNodeReference;
begin
   Result := TMessageFeatureNode;
end;

function TMessageFeatureClass.InitFeatureNode(): TFeatureNode;
begin
   Result := TMessageFeatureNode.Create();
end;


constructor TMessageFeatureNode.Create();
begin
   inherited Create();
end;

constructor TMessageFeatureNode.Create(ASourceSystemID: Cardinal; ATimestamp: TTimeInMilliseconds; AIsRead: Boolean; ASubject, AFrom, ABody: UTF8String);
begin
   inherited Create();
   FSourceSystemID := ASourceSystemID;
   FTimestamp := ATimestamp; 
   FIsRead := AIsRead;
   FSubject := ASubject;
   FFrom := AFrom;
   FBody := ABody;
end;

function TMessageFeatureNode.GetMass(): Double;
begin
   Result := 0.0;
end;

function TMessageFeatureNode.GetSize(): Double;
begin
   // Result := 1.0e-8;
   Result := 50.0;
end;

function TMessageFeatureNode.GetFeatureName(): UTF8String;
begin
   Result := '';
end;

procedure TMessageFeatureNode.Walk(PreCallback: TPreWalkCallback; PostCallback: TPostWalkCallback);
begin
end;

function TMessageFeatureNode.HandleBusMessage(Message: TBusMessage): Boolean;
begin
   Result := False;
end;

procedure TMessageFeatureNode.Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter; CachedSystem: TSystem);
begin
   Writer.WriteCardinal(fcMessage);
   Writer.WriteCardinal(FSourceSystemID);
   Writer.WriteInt64(FTimestamp.AsInt64);
   Writer.WriteBoolean(FIsRead); // if we add more flags, they should go into this byte
   Writer.WriteStringReference(FSubject);
   Writer.WriteStringReference(FFrom);
   Writer.WriteStringReference(FBody);
end;

procedure TMessageFeatureNode.UpdateJournal(Journal: TJournalWriter);
begin
   Journal.WriteCardinal(FSourceSystemID);
   Journal.WriteInt64(FTimestamp.AsInt64);
   Journal.WriteBoolean(FIsRead);
   Journal.WriteString(FSubject);
   Journal.WriteString(FFrom);
   Journal.WriteString(FBody);
end;

procedure TMessageFeatureNode.ApplyJournal(Journal: TJournalReader; CachedSystem: TSystem);
begin
   FSourceSystemID := Journal.ReadCardinal();
   FTimestamp := TTimeInMilliseconds(Journal.ReadInt64());
   FIsRead := Journal.ReadBoolean();
   FSubject := Journal.ReadString();
   FFrom := Journal.ReadString();
   FBody := Journal.ReadString();
end;

procedure TMessageFeatureNode.SetMessage(ASourceSystemID: Cardinal; ATimestamp: TTimeInMilliseconds; ASubject, AFrom, ABody: UTF8String);
begin
   FSourceSystemID := ASourceSystemID;
   FTimestamp := ATimestamp;
   FSubject := ASubject;
   FFrom := AFrom;
   FBody := ABody;
end;

function TMessageFeatureNode.HandleCommand(Command: UTF8String; var Message: TMessage): Boolean;
begin
   if (Command = 'mark-read') then
   begin
      Message.CloseInput();
      Message.Reply();
      Message.CloseOutput();
      FIsRead := True;
      MarkAsDirty([dkSelf]);
      Result := True;
   end
   else
   if (Command = 'mark-unread') then
   begin
      Message.CloseInput();
      Message.Reply();
      Message.CloseOutput();
      FIsRead := False;
      MarkAsDirty([dkSelf]);
      Result := True;
   end
   else
      Result := inherited;
end;

end.
