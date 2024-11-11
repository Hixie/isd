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
      FDimension: Cardinal;
      FChildren: array of TAssetNode; // TODO: we should use a more memory-efficient way of storing this when it's sparse
      function GetChild(X, Y: Cardinal): TAssetNode;
      procedure AdoptGridChild(Child: TAssetNode);
   protected
      procedure DropChild(Child: TAssetNode); override;
      function GetMass(): Double; override;
      function GetSize(): Double; override;
      function GetFeatureName(): UTF8String; override;
      procedure Walk(PreCallback: TPreWalkCallback; PostCallback: TPostWalkCallback); override;
      function HandleBusMessage(Message: TBusMessage): Boolean; override;
      procedure Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter; System: TSystem); override;
   public
      constructor Create(ACellSize: Double; ADimension: Cardinal);
      destructor Destroy(); override;
      procedure UpdateJournal(Journal: TJournalWriter); override;
      procedure ApplyJournal(Journal: TJournalReader; System: TSystem); override;
      property Children[X, Y: Cardinal]: TAssetNode read GetChild;
      property Dimension: Cardinal read FDimension;
      property CellSize: Double read FCellSize;
   end;
   
implementation

uses
   sysutils, isdprotocol, orbit, exceptions;

type
   PGridData = ^TGridData;
   TGridData = bitpacked record
      // TODO: geology and position
      IsNew: Boolean;
      IsChanged: Boolean;
   end;

var
   DeletedAsset: TAssetNode;

function Assigned(Child: TAssetNode): Boolean; inline;
begin
   Result := PtrUInt(Child) > PtrUInt(DeletedAsset);
end;

function Assigned(Child: TFeatureNode): Boolean; inline;
begin
   Result := system.Assigned(Child);
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
   SetLength(FChildren, FDimension * FDimension);
end;

destructor TGridFeatureNode.Destroy();
var
   Child: TAssetNode;
begin
   for Child in FChildren do
   begin
      if (Assigned(Child)) then
      begin
         DropChild(Child);
         Child.Free();
      end;
   end;
   inherited;
end;

// TODO: here and elsewhere, why don't we just override AdoptChild?
procedure TGridFeatureNode.AdoptGridChild(Child: TAssetNode);
begin
   Assert(Assigned(Child));
   AdoptChild(Child);
   Child.ParentData := New(PGridData);
   PGridData(Child.ParentData)^.IsNew := True;
   PGridData(Child.ParentData)^.IsChanged := True;
end;

procedure TGridFeatureNode.DropChild(Child: TAssetNode);
begin
   Assert(Assigned(Child));
   Dispose(PGridData(Child.ParentData));
   Child.ParentData := nil;
   inherited;
end;

function TGridFeatureNode.GetChild(X, Y: Cardinal): TAssetNode;
begin
   Assert(X < FDimension);
   Assert(Y < FDimension);
   Result := FChildren[X + Y * FDimension];
   if (Result = DeletedAsset) then
      Result := nil;
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
   Child: TAssetNode;
   X, Y: Cardinal;
begin
   if (Message is TReceiveCrashingAssetMessage) then
   begin
      for Child in TReceiveCrashingAssetMessage(Message).Assets do
      begin
         // TODO: make it not precisely the center
         X := Dimension div 2; // $R-
         Y := Dimension div 2; // $R-
         if (Assigned(FChildren[X + Y * FDimension])) then
         begin
            // TODO: handle crashing into something that's already there
            XXX;
         end;
         AdoptGridChild(Child);
         FChildren[X + Y * FDimension] := Child;
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
end;

procedure TGridFeatureNode.Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter; System: TSystem);
var
   Child: TAssetNode;
begin
   Writer.WriteCardinal(fcGrid);
   Writer.WriteDouble(FCellSize);
   Writer.WriteCardinal(FDimension);
   Writer.WriteCardinal(FDimension);
   for Child in FChildren do
   begin
      if (Assigned(Child)) then
         Writer.WritePtrUInt(Child.ID(System))
      else
         Writer.WritePtrUInt(0);
   end;
end;

procedure TGridFeatureNode.UpdateJournal(Journal: TJournalWriter);
var
   Child: TAssetNode;
   X, Y: Cardinal;
begin
   Journal.WriteDouble(FCellSize);
   Journal.WriteCardinal(FDimension);
   Assert(FDimension > 0);
   for X := 0 to FDimension - 1 do // $R-
      for Y := 0 to FDimension - 1 do // $R-
      begin
         Child := FChildren[X + Y * FDimension];
         if (Child = DeletedAsset) then
         begin
            Journal.WriteAssetChangeKind(ckRemove);
            Journal.WriteCardinal(X);
            Journal.WriteCardinal(Y);
            FChildren[X + Y * FDimension] := nil;
         end
         else
         if (Assigned(Child) and PGridData(Child.ParentData)^.IsChanged) then
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
            end;
            Journal.WriteCardinal(X);
            Journal.WriteCardinal(Y);
            PGridData(Child.ParentData)^.IsChanged := False;
         end;
      end;
   Journal.WriteAssetChangeKind(ckEndOfList);
end;

procedure TGridFeatureNode.ApplyJournal(Journal: TJournalReader; System: TSystem);

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
      AdoptGridChild(Child);
      Assert(Child.Parent = Self);
      Assert(not Assigned(FChildren[X + Y * FDimension]));
      FChildren[X + Y * FDimension] := Child;
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
      Child := FChildren[X + Y * FDimension];
      Assert(Assigned(Child));
      Assert(False); // nothing to update currently
      PGridData(Child.ParentData)^.IsChanged := True;
   end;

   procedure RemoveChild();
   var
      X, Y: Cardinal;
   begin
      X := Journal.ReadCardinal();
      Y := Journal.ReadCardinal();
      Assert(X < FDimension);
      Assert(Y < FDimension);
      Assert(Assigned(FChildren[X + Y * FDimension]));
      FChildren[X + Y * FDimension] := nil;
   end;

var
   AssetChangeKind: TAssetChangeKind;
   NewDimension: Cardinal;
begin
   FCellSize := Journal.ReadDouble();
   NewDimension := Journal.ReadCardinal();
   Assert(FDimension <= NewDimension);
   FDimension := NewDimension;
   SetLength(FChildren, FDimension * FDimension);
   while (True) do
   begin
      AssetChangeKind := Journal.ReadAssetChangeKind();
      case AssetChangeKind of
         ckAdd: AddChild();
         ckChange: ChangeChild();
         ckRemove: RemoveChild();
         ckEndOfList: break;
      end;
   end;
end;

initialization
   DeletedAsset := TAssetNode($01);
end.