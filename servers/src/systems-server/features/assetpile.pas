{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit assetpile;

interface

uses
   systems, serverstream, knowledge, basenetwork, techtree;

type
   TAssetPileFeatureClass = class(TFeatureClass)
   strict protected
      function GetFeatureNodeClass(): FeatureNodeReference; override;
   public
      constructor CreateFromTechnologyTree(Reader: TTechTreeReader); override;
      function InitFeatureNode(ASystem: TSystem): TFeatureNode; override;
   end;

   TAssetPileFeatureNode = class(TFeatureNode)
   private
      FChildren: TAssetNode.TArray;
   protected
      procedure Walk(PreCallback: TPreWalkCallback; PostCallback: TPostWalkCallback); override;
      function HandleBusMessage(Message: TBusMessage): Boolean; override;
      procedure Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter); override;
   public
      destructor Destroy(); override;
      procedure AdoptChild(Child: TAssetNode); override;
      procedure DropChild(Child: TAssetNode); override;
      procedure UpdateJournal(Journal: TJournalWriter); override;
      procedure ApplyJournal(Journal: TJournalReader); override;
   end;

implementation

uses
   isdprotocol, sysutils;

type
   PAssetPileData = ^TAssetPileData;
   TAssetPileData = record
      IsDirty, IsNew: Boolean;
      Index: Cardinal;
   end;


constructor TAssetPileFeatureClass.CreateFromTechnologyTree(Reader: TTechTreeReader);
begin
   inherited Create();
end;

function TAssetPileFeatureClass.GetFeatureNodeClass(): FeatureNodeReference;
begin
   Result := TAssetPileFeatureNode;
end;

function TAssetPileFeatureClass.InitFeatureNode(ASystem: TSystem): TFeatureNode;
begin
   Result := TAssetPileFeatureNode.Create(ASystem);
end;


destructor TAssetPileFeatureNode.Destroy();
var
   Child: TAssetNode;
begin
   for Child in FChildren do
      Child.Free();
   inherited;
end;

procedure TAssetPileFeatureNode.AdoptChild(Child: TAssetNode);
begin
   SetLength(FChildren, Length(FChildren)+1);
   FChildren[High(FChildren)] := Child;
   inherited;
   Child.ParentData := New(PAssetPileData);
   PAssetPileData(Child.ParentData)^.IsNew := True;
   PAssetPileData(Child.ParentData)^.IsDirty := True;
   PAssetPileData(Child.ParentData)^.Index := High(FChildren); // $R-
end;

procedure TAssetPileFeatureNode.DropChild(Child: TAssetNode);
var
   Index: Cardinal;
begin
   Delete(FChildren, PAssetPileData(Child.ParentData)^.Index, 1);
   if (PAssetPileData(Child.ParentData)^.Index < Length(FChildren)) then
      for Index := PAssetPileData(Child.ParentData)^.Index to High(FChildren) do // $R-
         PAssetPileData(FChildren[Index].ParentData)^.Index := Index;
   Dispose(PAssetPileData(Child.ParentData));
   Child.ParentData := nil;
   inherited;
end;

procedure TAssetPileFeatureNode.Walk(PreCallback: TPreWalkCallback; PostCallback: TPostWalkCallback);
var
   Child: TAssetNode;
begin
   for Child in FChildren do
      Child.Walk(PreCallback, PostCallback);
end;

function TAssetPileFeatureNode.HandleBusMessage(Message: TBusMessage): Boolean;
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

procedure TAssetPileFeatureNode.Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter);
var
   Child: TAssetNode;
   Visibility: TVisibility;
begin
   if (Length(FChildren) > 0) then
   begin
      Visibility := Parent.ReadVisibilityFor(DynastyIndex);
      if (Visibility <> []) then
      begin
         Writer.WriteCardinal(fcAssetPile);
         for Child in FChildren do
         begin
            if (Child.IsVisibleFor(DynastyIndex)) then
            begin
               Writer.WriteCardinal(Child.ID(DynastyIndex));
            end;
         end;
         Writer.WriteCardinal(0);
      end;
   end;
end;

procedure TAssetPileFeatureNode.UpdateJournal(Journal: TJournalWriter);
var
   Child: TAssetNode;
begin
   if (Length(FChildren) > 0) then
   begin
      for Child in FChildren do
      begin
         Assert(Assigned(Child));
         if (PAssetPileData(Child.ParentData)^.IsDirty) then
         begin
            if (PAssetPileData(Child.ParentData)^.IsNew) then
            begin
               Journal.WriteAssetChangeKind(ckAdd);
               PAssetPileData(Child.ParentData)^.IsNew := False;
            end
            else
            begin
               Journal.WriteAssetChangeKind(ckChange);
            end;
            Journal.WriteAssetNodeReference(Child);
            PAssetPileData(Child.ParentData)^.IsDirty := False;
         end;
      end;
   end;
   Journal.WriteAssetChangeKind(ckEndOfList);
end;

procedure TAssetPileFeatureNode.ApplyJournal(Journal: TJournalReader);

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

initialization
   RegisterFeatureClass(TAssetPileFeatureClass);
end.
