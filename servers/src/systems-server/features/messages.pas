{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit messages;

interface

uses
   systems, serverstream;

type
   TMessageBoardFeatureClass = class(TFeatureClass)
   strict protected
      function GetFeatureNodeClass(): FeatureNodeReference; override;
   public
      function InitFeatureNode(): TFeatureNode; override;
   end;

   TMessageBoardFeatureNode = class(TFeatureNode)
   private
      FChildren: TAssetNodeArray;
   protected
      procedure AdoptChild(Child: TAssetNode); override;
      procedure DropChild(Child: TAssetNode); override;
      function GetMass(): Double; override;
      function GetSize(): Double; override;
      function GetFeatureName(): UTF8String; override;
      procedure Walk(PreCallback: TPreWalkCallback; PostCallback: TPostWalkCallback); override;
      function HandleBusMessage(Message: TBusMessage): Boolean; override;
      procedure Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter; System: TSystem); override;
   public
      destructor Destroy(); override;
      procedure UpdateJournal(Journal: TJournalWriter); override;
      procedure ApplyJournal(Journal: TJournalReader; System: TSystem); override;
   end;

implementation

uses
   isdprotocol;

type
   PMessageBoardData = ^TMessageBoardData;
   TMessageBoardData = record
      IsDirty, IsNew: Boolean;
      Index: Cardinal;
   end;

function TMessageBoardFeatureClass.GetFeatureNodeClass(): FeatureNodeReference;
begin
   Result := TMessageBoardFeatureNode;
end;

function TMessageBoardFeatureClass.InitFeatureNode(): TFeatureNode;
begin
   Result := TMessageBoardFeatureNode.Create();
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
begin
   for Child in FChildren do
   begin
      Result := Child.HandleBusMessage(Message);
      if (Result) then
         exit;
   end;
   Result := False;
end;

procedure TMessageBoardFeatureNode.Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter; System: TSystem);
var
   Child: TAssetNode;
begin
   Writer.WriteCardinal(fcMessageBoard);
   Writer.WriteCardinal(Length(FChildren)); // $R-
   for Child in FChildren do
   begin
      Writer.WriteCardinal(Child.ID(System, DynastyIndex));
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

procedure TMessageBoardFeatureNode.ApplyJournal(Journal: TJournalReader; System: TSystem);

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

end.