{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit grid;

interface

uses
   systems, serverstream;

type
   TGridFeatureClass = class(TFeatureClass)
   strict protected
      function GetFeatureNodeClass(): FeatureNodeReference; override;
   public
      function InitFeatureNode(): TFeatureNode; override;
   end;
   
   TGridFeatureNode = class(TFeatureNode)
   strict private
      FCellSize: Double; // meters
      FDimension, FCount: Cardinal;
      FPacked: Boolean; // true=FChildren is just the list of children, unordered; false=FChildren is the full grid in order, with holes set to nil
      FChildren: TAssetNodeArray; // TODO: plastic array? sorted array with binary search? map?
      function GetChild(X, Y: Cardinal): TAssetNode;
      procedure AdoptGridChild(Child: TAssetNode; X, Y: Cardinal);
   protected
      constructor CreateFromJournal(Journal: TJournalReader; AFeatureClass: TFeatureClass; ASystem: TSystem); override;
      procedure DropChild(Child: TAssetNode); override;
      function GetMass(): Double; override;
      function GetSize(): Double; override;
      function GetFeatureName(): UTF8String; override;
      procedure Walk(PreCallback: TPreWalkCallback; PostCallback: TPostWalkCallback); override;
      function HandleBusMessage(Message: TBusMessage): Boolean; override;
      procedure Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter; CachedSystem: TSystem); override;
   public
      constructor Create(ACellSize: Double; ADimension: Cardinal);
      destructor Destroy(); override;
      procedure UpdateJournal(Journal: TJournalWriter); override;
      procedure ApplyJournal(Journal: TJournalReader; CachedSystem: TSystem); override;
      property Dimension: Cardinal read FDimension;
      property CellSize: Double read FCellSize;
   end;
   
implementation

uses
   sysutils, isdprotocol, orbit, exceptions;

type
   PGridData = ^TGridData;
   TGridData = bitpacked record
      // TODO: geology
      X, Y, Index: Cardinal;
      IsNew: Boolean;
      IsChanged: Boolean;
   end;


function TGridFeatureClass.GetFeatureNodeClass(): FeatureNodeReference;
begin
   Result := TGridFeatureNode;
end;

function TGridFeatureClass.InitFeatureNode(): TFeatureNode;
begin
   Result := nil;
   raise Exception.Create('Cannot create a TGridFeatureNode from a prototype, it must have a size.');
end;


constructor TGridFeatureNode.Create(ACellSize: Double; ADimension: Cardinal);
begin
   inherited Create();
   FCellSize := ACellSize;
   FDimension := ADimension;
   FPacked := True;
end;

constructor TGridFeatureNode.CreateFromJournal(Journal: TJournalReader; AFeatureClass: TFeatureClass; ASystem: TSystem);
begin
   FPacked := True;
   inherited;
end;

destructor TGridFeatureNode.Destroy();
var
   Child: TAssetNode;
begin
   for Child in FChildren do
      if (Assigned(Child)) then
         Child.Free();
   inherited;
end;

procedure TGridFeatureNode.AdoptGridChild(Child: TAssetNode; X, Y: Cardinal);
begin
   Assert(Assigned(Child));
   Assert(not Assigned(GetChild(X, Y)));
   AdoptChild(Child);
   Child.ParentData := New(PGridData);
   PGridData(Child.ParentData)^.IsNew := True;
   PGridData(Child.ParentData)^.IsChanged := True;
   PGridData(Child.ParentData)^.X := X;
   PGridData(Child.ParentData)^.Y := Y;
   if (FPacked) then
   begin
      SetLength(FChildren, Length(FChildren) + 1);
      FChildren[High(FChildren)] := Child;
      PGridData(Child.ParentData)^.Index := High(FChildren); // $R-
   end
   else
   begin
      FChildren[X + Y * FDimension] := Child;
   end;
   Inc(FCount);
end;

procedure TGridFeatureNode.DropChild(Child: TAssetNode);
var
   Index: Cardinal;
begin
   Assert(Assigned(Child));
   if (FPacked) then
   begin
      Delete(FChildren, PGridData(Child.ParentData)^.Index, 1);
      if (PGridData(Child.ParentData)^.Index < Length(FChildren)) then
         for Index := PGridData(Child.ParentData)^.Index to High(FChildren) do // $R-
            PGridData(FChildren[Index].ParentData)^.Index := Index;
   end
   else
   begin
      FChildren[PGridData(Child.ParentData)^.X + PGridData(Child.ParentData)^.Y * FDimension] := nil;
   end;
   Dispose(PGridData(Child.ParentData));
   Child.ParentData := nil;
   Dec(FCount);
   inherited;
end;

function TGridFeatureNode.GetChild(X, Y: Cardinal): TAssetNode;
var
   Child: TAssetNode;
begin
   Assert(X < FDimension);
   Assert(Y < FDimension);
   if (FPacked) then
   begin
      for Child in FChildren do
      begin
         if ((PGridData(Child.ParentData)^.X = X) and
             (PGridData(Child.ParentData)^.Y = Y)) then
         begin
            Result := Child;
            exit;
         end;
      end;
      Result := nil;
   end
   else
   begin
      Result := FChildren[X + Y * FDimension];
   end;
end;

function TGridFeatureNode.GetMass(): Double;
var
   Child: TAssetNode;
begin
   Result := 0.0;
   for Child in FChildren do
      if (Assigned(Child)) then
         Result := Result + Child.Mass;
end;

function TGridFeatureNode.GetSize(): Double;
begin
   Result := FCellSize * FDimension;
end;

function TGridFeatureNode.GetFeatureName(): UTF8String;
begin
   Result := '';
end;

procedure TGridFeatureNode.Walk(PreCallback: TPreWalkCallback; PostCallback: TPostWalkCallback);
var
   Child: TAssetNode;
begin
   for Child in FChildren do
      if (Assigned(Child)) then
         Child.Walk(PreCallback, PostCallback);
end;

function TGridFeatureNode.HandleBusMessage(Message: TBusMessage): Boolean;
var
   Child, Child2: TAssetNode;
   X, Y: Cardinal;
begin
   if (Message is TReceiveCrashingAssetMessage) then
   begin
      for Child in TReceiveCrashingAssetMessage(Message).Assets do
      begin
         // TODO: make it not precisely the center
         X := Dimension div 2; // $R-
         Y := Dimension div 2; // $R-
         if (Assigned(GetChild(X, Y))) then
         begin
            Writeln('uh, we tried to crash something into a grid that already had something: ');
            Child2 := GetChild(X, Y);
            Writeln('  victim = ', Child.DebugName);
            Writeln('  target = ', Child2.DebugName);
            // TODO: handle crashing into something that's already there
            XXX;
         end;
         AdoptGridChild(Child, X, Y);
         Result := True;
      end;
      exit;
   end;
   for Child in FChildren do
   begin
      if (Assigned(Child)) then
      begin
         Result := Child.HandleBusMessage(Message);
         if (Result) then
            exit;
      end;
   end;
   Result := False;
end;

procedure TGridFeatureNode.Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter; CachedSystem: TSystem);
var
   Child: TAssetNode;
begin
   Writer.WriteCardinal(fcGrid);
   Writer.WriteDouble(FCellSize);
   Writer.WriteCardinal(FDimension);
   Writer.WriteCardinal(FDimension);
   Writer.WriteCardinal(FCount);
   Assert((not FPacked) or (FCount = Length(FChildren)));
   for Child in FChildren do
   begin
      if (Assigned(Child)) then
      begin
         Writer.WriteCardinal(PGridData(Child.ParentData)^.X);
         Writer.WriteCardinal(PGridData(Child.ParentData)^.Y);
         Writer.WriteCardinal(Child.ID(CachedSystem, DynastyIndex));
      end;
   end;
end;

procedure TGridFeatureNode.UpdateJournal(Journal: TJournalWriter);

   procedure ReportChild(Child: TAssetNode);
   begin
      if (PGridData(Child.ParentData)^.IsChanged) then
      begin
         if (PGridData(Child.ParentData)^.IsNew) then
         begin
            Journal.WriteAssetChangeKind(ckAdd);
            Journal.WriteAssetNodeReference(Child);
            PGridData(Child.ParentData)^.IsNew := False;
         end
         else
         begin
            Journal.WriteAssetChangeKind(ckChange);
            Assert(False); // there's nothing to update, currently
            // TODO: would be more efficient when reading to actually store the node reference instead of relying on x,y lookup...
         end;
         Journal.WriteCardinal(PGridData(Child.ParentData)^.X);
         Journal.WriteCardinal(PGridData(Child.ParentData)^.Y);
         PGridData(Child.ParentData)^.IsChanged := False;
      end;
   end;

var
   Child: TAssetNode;
begin
   Journal.WriteDouble(FCellSize);
   Journal.WriteCardinal(FDimension);
   Assert(FDimension > 0);
   Assert((not FPacked) or (FCount = Length(FChildren)));
   for Child in FChildren do
      if (Assigned(Child)) then
         ReportChild(Child);
   Journal.WriteAssetChangeKind(ckEndOfList);
end;

procedure TGridFeatureNode.ApplyJournal(Journal: TJournalReader; CachedSystem: TSystem);

   procedure AddChild();
   var
      Child: TAssetNode;
      X, Y: Cardinal;
   begin
      Child := Journal.ReadAssetNodeReference();
      X := Journal.ReadCardinal();
      Y := Journal.ReadCardinal();
      Assert(X < FDimension);
      Assert(Y < FDimension);
      AdoptGridChild(Child, X, Y);
      Assert(Child.Parent = Self);
   end;

   procedure ChangeChild();
   var
      X, Y: Cardinal;
      Child: TAssetNode;
   begin
      X := Journal.ReadCardinal();
      Y := Journal.ReadCardinal();
      Assert(X < FDimension);
      Assert(Y < FDimension);
      Child := GetChild(X, Y);
      Assert(Assigned(Child));
      Assert(False); // nothing to update currently
      PGridData(Child.ParentData)^.IsChanged := True;
   end;

var
   AssetChangeKind: TAssetChangeKind;
   NewDimension: Cardinal;
begin
   FCellSize := Journal.ReadDouble();
   NewDimension := Journal.ReadCardinal();
   Assert(FDimension <= NewDimension);
   FDimension := NewDimension;
   while (True) do
   begin
      AssetChangeKind := Journal.ReadAssetChangeKind();
      case AssetChangeKind of
         ckAdd: AddChild();
         ckChange: ChangeChild();
         ckEndOfList: break;
      end;
   end;
end;

end.