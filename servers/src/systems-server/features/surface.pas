{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit surface;

interface

uses
   systems, serverstream, techtree, time;

type
   TCreateRegionCallback = function (CellSize: Double; Dimension: Cardinal): TAssetNode of object;

   TSurfaceFeatureClass = class(TFeatureClass)
   private
      FCellSize: Double;
      FMinRegionSize, FMaxRegionSize: Cardinal; // preferred number of cells per side - must be odd, greater than 1
      FCreateRegionCallback: TCreateRegionCallback;
   strict protected
      function GetFeatureNodeClass(): FeatureNodeReference; override;
   public
      constructor Create(ACellSize: Double; AMinRegionSize, AMaxRegionSize: Cardinal; ACreateRegionCallback: TCreateRegionCallback);
      constructor CreateFromTechnologyTree(Reader: TTechTreeReader); override;
      function InitFeatureNode(): TFeatureNode; override;
   end;

   TSurfaceFeatureNode = class(TFeatureNode)
   private
      FFeatureClass: TSurfaceFeatureClass;
      FSize: Double;
      FChildren: TAssetNode.TArray; // TODO: replace this with a region quadtree
      // X,Y coordinates are in FCellSize units with 0,0 being the center cell
      // X,Y must be within circle with radius FSize/2-Sqrt(2)*FCellSize*FMaxRegionSize/2
      procedure AdoptRegionChild(Child: TAssetNode; X, Y: Integer; Dimension: Cardinal);
      function GetRegionAt(X, Y: Integer): TAssetNode;
      function GetOrCreateRegionAt(X, Y: Integer): TAssetNode; // X,Y constrained as above
   protected
      constructor CreateFromJournal(Journal: TJournalReader; AFeatureClass: TFeatureClass; ASystem: TSystem); override;
      procedure DropChild(Child: TAssetNode); override;
      function GetMass(): Double; override;
      function GetMassFlowRate(): TRate; override;
      function GetSize(): Double; override;
      procedure Walk(PreCallback: TPreWalkCallback; PostCallback: TPostWalkCallback); override;
      function HandleBusMessage(Message: TBusMessage): Boolean; override;
      procedure Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter; CachedSystem: TSystem); override;
   public
      constructor Create(AFeatureClass: TSurfaceFeatureClass; ASize: Double);
      destructor Destroy(); override;
      procedure UpdateJournal(Journal: TJournalWriter; CachedSystem: TSystem); override;
      procedure ApplyJournal(Journal: TJournalReader; CachedSystem: TSystem); override;
      procedure DescribeExistentiality(var IsDefinitelyReal, IsDefinitelyGhost: Boolean); override;
   end;

implementation

uses
   sysutils, isdprotocol, orbit, random;

type
   PSurfaceData = ^TSurfaceData;
   TSurfaceData = bitpacked record
      X, Y: Integer; // index to center cell of region (0,0 is center of planet)
      Dimension: Cardinal; // number of cells per side in region // TODO: should we rely on the asset's own Size for this? what if it changes?
      Index: Cardinal; // index in FChildren
      IsNew: Boolean;
      IsChanged: Boolean;
   end;

const
   RootTwo = Sqrt(2.0);

constructor TSurfaceFeatureClass.Create(ACellSize: Double; AMinRegionSize, AMaxRegionSize: Cardinal; ACreateRegionCallback: TCreateRegionCallback);
begin
   inherited Create();
   FCellSize := ACellSize;
   Assert(AMinRegionSize > 1);
   Assert(AMinRegionSize mod 2 = 1, 'region sizes must be odd');
   Assert(AMaxRegionSize > AMinRegionSize);
   Assert(AMaxRegionSize mod 2 = 1, 'region sizes must be odd');
   FMinRegionSize := AMinRegionSize;
   FMaxRegionSize := AMaxRegionSize;
   FCreateRegionCallback := ACreateRegionCallback;
end;

constructor TSurfaceFeatureClass.CreateFromTechnologyTree(Reader: TTechTreeReader);
begin
   Reader.Tokens.Error('Feature class %s is reserved for internal asset classes', [ClassName]);
end;

function TSurfaceFeatureClass.GetFeatureNodeClass(): FeatureNodeReference;
begin
   Result := TSurfaceFeatureNode;
end;

function TSurfaceFeatureClass.InitFeatureNode(): TFeatureNode;
begin
   Result := nil;
   raise Exception.Create('Cannot create a TSurfaceFeatureNode from a prototype, it must have a size.');
end;


constructor TSurfaceFeatureNode.Create(AFeatureClass: TSurfaceFeatureClass; ASize: Double);
begin
   inherited Create();
   FFeatureClass := AFeatureClass;
   Assert(ASize > 0);
   FSize := ASize;
end;

constructor TSurfaceFeatureNode.CreateFromJournal(Journal: TJournalReader; AFeatureClass: TFeatureClass; ASystem: TSystem);
begin
   Assert(Assigned(AFeatureClass));
   FFeatureClass := AFeatureClass as TSurfaceFeatureClass;
   inherited CreateFromJournal(Journal, AFeatureClass, ASystem);
end;

destructor TSurfaceFeatureNode.Destroy();
var
   Child: TAssetNode;
begin
   for Child in FChildren do
      Child.Free();
   inherited;
end;

function TSurfaceFeatureNode.GetRegionAt(X, Y: Integer): TAssetNode;
var
   Index, HalfDimension: Cardinal;
   ChildData: PSurfaceData;
begin
   Assert(FSize > 0.0);
   Assert(FSize / 2.0 > RootTwo * FFeatureClass.FCellSize * FFeatureClass.FMaxRegionSize / 2.0);
   Assert(X * X + Y * Y < Sqr(FSize / 2.0 - RootTwo * FFeatureClass.FCellSize * FFeatureClass.FMaxRegionSize / 2.0));
   // TODO: use a region quadtree instead
   if (Length(FChildren) > 0) then
      for Index := Low(FChildren) to High(FChildren) do
      begin
         ChildData := FChildren[Index].ParentData;
         HalfDimension := ChildData^.Dimension div 2; // $R- (how can integer dividing a Cardinal by 2 not fit in a Cardinal??)
         if ((ChildData^.X - HalfDimension >= X) and
             (ChildData^.Y - HalfDimension >= Y) and
             (ChildData^.X + HalfDimension <= X) and
             (ChildData^.Y + HalfDimension <= Y)) then
         begin
            Result := FChildren[Index];
            exit;
         end;
      end;
   Result := nil;
end;

function TSurfaceFeatureNode.GetOrCreateRegionAt(X, Y: Integer): TAssetNode;
var
   Index, Dimension: Cardinal;
   XA, YA: Integer;
begin
   Assert(FSize > 0.0);
   Assert(RootTwo * FSize > FFeatureClass.FCellSize * FFeatureClass.FMaxRegionSize);
   Assert(X * X + Y * Y < Sqr(FSize - RootTwo * FFeatureClass.FCellSize * FFeatureClass.FMaxRegionSize / 2.0));
   Result := GetRegionAt(X, Y);
   if (not Assigned(Result)) then
   begin
      Dimension := System.RandomNumberGenerator.GetCardinal(FFeatureClass.FMinRegionSize div 2, FFeatureClass.FMaxRegionSize div 2) * 2 + 1; // $R-
      Assert(Dimension mod 2 = 1);
      Assert(Dimension >= 3);
      // If we get here, we know for certain that at least a 1x1 region at X,Y will be empty.
      // Let's see if we can find a bigger region though (up to size Dimension).
      // TODO: this is stupid expensive, there's got to be a better way with a region quadtree or something
      for Index := 1 to Dimension div 2 do // $R-
      begin
         for XA := X - Index to X + Index do // $R-
         begin
            if (Assigned(GetRegionAt(XA, Y - Index)) or // $R-
                Assigned(GetRegionAt(XA, Y + Index))) then // $R-
            begin
               Dimension := (Index - 1) * 2 + 1; // $R-
               break;
            end;
         end;
         for YA := Y - Index + 1 to Y + Index - 1 do // $R-
         begin
            if (Assigned(GetRegionAt(X - Index, YA)) or // $R-
                Assigned(GetRegionAt(X + Index, YA))) then // $R-
            begin
               Dimension := (Index - 1) * 2 + 1; // $R-
               break;
            end;
         end;
      end;
      Result := FFeatureClass.FCreateRegionCallback(FFeatureClass.FCellSize, Dimension);
      AdoptRegionChild(Result, X, Y, Dimension);
   end;
end;

procedure TSurfaceFeatureNode.AdoptRegionChild(Child: TAssetNode; X, Y: Integer; Dimension: Cardinal);
begin
   AdoptChild(Child);
   Child.ParentData := New(PSurfaceData);
   PSurfaceData(Child.ParentData)^.X := X;
   PSurfaceData(Child.ParentData)^.Y := Y;
   PSurfaceData(Child.ParentData)^.Dimension := Dimension; // TODO: should this just be the asset's Size? (not necessarily right?)
   PSurfaceData(Child.ParentData)^.IsNew := True;
   PSurfaceData(Child.ParentData)^.IsChanged := True;
   SetLength(FChildren, Length(FChildren) + 1);
   FChildren[High(FChildren)] := Child;
   PSurfaceData(Child.ParentData)^.Index := High(FChildren); // $R-
end;

procedure TSurfaceFeatureNode.DropChild(Child: TAssetNode);
var
   Index: Cardinal;
begin
   Delete(FChildren, PSurfaceData(Child.ParentData)^.Index, 1);
   if (PSurfaceData(Child.ParentData)^.Index < Length(FChildren)) then
      for Index := PSurfaceData(Child.ParentData)^.Index to High(FChildren) do // $R-
         PSurfaceData(FChildren[Index].ParentData)^.Index := Index;
   Dispose(PSurfaceData(Child.ParentData));
   Child.ParentData := nil;
   inherited;
end;

function TSurfaceFeatureNode.GetMass(): Double;
var
   Child: TAssetNode;
begin
   Result := 0.0;
   for Child in FChildren do
      Result := Result + Child.Mass;
end;

function TSurfaceFeatureNode.GetMassFlowRate(): TRate;
var
   Child: TAssetNode;
begin
   Result := TRate.Zero;
   for Child in FChildren do
      Result := Result + Child.MassFlowRate;
end;

function TSurfaceFeatureNode.GetSize(): Double;
begin
   Result := FSize;
end;

procedure TSurfaceFeatureNode.Walk(PreCallback: TPreWalkCallback; PostCallback: TPostWalkCallback);
var
   Child: TAssetNode;
begin
   for Child in FChildren do
      Child.Walk(PreCallback, PostCallback);
end;

function TSurfaceFeatureNode.HandleBusMessage(Message: TBusMessage): Boolean;
var
   Child: TAssetNode;
   Theta, Radius, X, Y: Double;
   RandomNumberGenerator: TRandomNumberGenerator;
begin
   if (Message is TReceiveCrashingAssetMessage) then
   begin
      RandomNumberGenerator := System.RandomNumberGenerator;
      // hat tip to Andreas Lundblad
      Assert(FSize > 0.0);
      Assert(FFeatureClass.FCellSize > 0.0);
      Assert(FFeatureClass.FMaxRegionSize > 0);
      Theta := RandomNumberGenerator.GetDouble(0, Pi * 2.0); // $R-
      Radius := SqRt(RandomNumberGenerator.GetDouble(0.0, 1.0)) * (FSize / 2.0 - RootTwo * FFeatureClass.FCellSize * FFeatureClass.FMaxRegionSize / 2.0); // $R-
      X := (Radius * Cos(Theta)) / FFeatureClass.FCellSize; // $R-
      Y := (Radius * Sin(Theta)) / FFeatureClass.FCellSize; // $R-
      Child := GetOrCreateRegionAt(Trunc(X), Trunc(Y)); // $R-
      Result := Child.HandleBusMessage(Message);
   end
   else
   begin
      for Child in FChildren do
      begin
         Result := Child.HandleBusMessage(Message);
         if (Result) then
            exit;
      end;
      Result := False;
   end;
end;

procedure TSurfaceFeatureNode.Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter; CachedSystem: TSystem);
var
   Visibility: TVisibility;
   Child: TAssetNode;
   ChildData: PSurfaceData;
begin
   Visibility := Parent.ReadVisibilityFor(DynastyIndex, CachedSystem);
   if (Visibility <> []) then
   begin
      Writer.WriteCardinal(fcSurface);
      for Child in FChildren do
      begin
         Assert(Assigned(Child));
         if (Child.IsVisibleFor(DynastyIndex, CachedSystem)) then
         begin
            ChildData := Child.ParentData;
            Writer.WriteCardinal(Child.ID(CachedSystem, DynastyIndex));
            Writer.WriteDouble(ChildData^.X * FFeatureClass.FCellSize);
            Writer.WriteDouble(ChildData^.Y * FFeatureClass.FCellSize);
         end;
      end;
      Writer.WriteCardinal(0);
   end;
end;

procedure TSurfaceFeatureNode.UpdateJournal(Journal: TJournalWriter; CachedSystem: TSystem);
var
   Child: TAssetNode;
   SurfaceData: PSurfaceData;
begin
   Journal.WriteDouble(FSize);
   if (Length(FChildren) > 0) then
   begin
      for Child in FChildren do
      begin
         Assert(Assigned(Child));
         Assert(Assigned(Child.ParentData), 'No parent data on ' + Child.ClassName);
         SurfaceData := PSurfaceData(Child.ParentData);
         if (SurfaceData^.IsChanged) then
         begin
            if (SurfaceData^.IsNew) then
            begin
               Journal.WriteAssetChangeKind(ckAdd);
               SurfaceData^.IsNew := False;
            end
            else
            begin
               Journal.WriteAssetChangeKind(ckChange);
            end;
            Journal.WriteAssetNodeReference(Child);
            Journal.WriteInt32(SurfaceData^.X);
            Journal.WriteInt32(SurfaceData^.Y);
            Journal.WriteCardinal(SurfaceData^.Dimension);
            PSurfaceData(Child.ParentData)^.IsChanged := False;
         end;
      end;
   end;
   Journal.WriteAssetChangeKind(ckEndOfList);
end;

procedure TSurfaceFeatureNode.ApplyJournal(Journal: TJournalReader; CachedSystem: TSystem);

   procedure AddChild();
   var
      Child: TAssetNode;
      X, Y: Integer;
      Dimension: Cardinal;
   begin
      Child := Journal.ReadAssetNodeReference();
      X := Journal.ReadInt32();
      Y := Journal.ReadInt32();
      Dimension := Journal.ReadCardinal(); // TODO: is this redundant with Child.Size?
      AdoptRegionChild(Child, X, Y, Dimension); // TODO: performance?
      Assert(Child.Parent = Self);
   end;

   procedure ChangeChild();
   var
      Child: TAssetNode;
      SurfaceData: PSurfaceData;
   begin
      Child := Journal.ReadAssetNodeReference();
      Assert(Child.Parent = Self);
      SurfaceData := Child.ParentData;
      SurfaceData^.X := Journal.ReadInt32();
      SurfaceData^.Y := Journal.ReadInt32();
      SurfaceData^.Dimension := Journal.ReadCardinal(); // TODO: is this redundant with Child.Size?
   end;

var
   AssetChangeKind: TAssetChangeKind;
begin
   FSize := Journal.ReadDouble();
   repeat
      AssetChangeKind := Journal.ReadAssetChangeKind();
      case AssetChangeKind of
         ckAdd: AddChild();
         ckChange: ChangeChild();
         ckEndOfList: break;
      end;
   until False;
end;

procedure TSurfaceFeatureNode.DescribeExistentiality(var IsDefinitelyReal, IsDefinitelyGhost: Boolean);
begin
   IsDefinitelyReal := True;
end;

initialization
   RegisterFeatureClass(TSurfaceFeatureClass);
end.