{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit orbit;

interface

uses
   systems, providers, serverstream;

type
   TOrbitFeatureClass = class(TFeatureClass)
   strict protected
      function GetFeatureNodeClass(): FeatureNodeReference; override;
   public
      function InitFeatureNode(): TFeatureNode; override;
   end;

   TOrbitFeatureNode = class(TFeatureNode, IHillDiameterProvider, IAssetNameProvider)
   private
      FPrimaryChild: TAssetNode;
      FChildren: array of TAssetNode;
      function GetOrbitingChild(Index: Cardinal): TAssetNode;
      function GetOrbitingChildCount(): Cardinal;
      function GetOrbitName(): UTF8String;
   protected
      procedure AdoptOrbitingChild(Child: TAssetNode);
      procedure DropOrbitingChild(Child: TAssetNode);
      procedure MarkAsDirty(DirtyKinds: TDirtyKinds; ChangeKinds: TChangeKinds); override;
      function GetMass(): Double; override;
      function GetSize(): Double; override;
      function GetFeatureName(): UTF8String; override;
      procedure Walk(PreCallback: TPreWalkCallback; PostCallback: TPostWalkCallback); override;
      procedure ApplyVisibility(VisibilityHelper: TVisibilityHelper); override;
      procedure InferVisibilityByIndex(DynastyIndex: Cardinal; VisibilityHelper: TVisibilityHelper); override;
      procedure Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter; System: TSystem); override;
   public
      constructor Create(APrimaryChild: TAssetNode);
      destructor Destroy(); override;
      procedure RecordSnapshot(Journal: TJournalWriter); override;
      procedure ApplyJournal(Journal: TJournalReader); override;
      function GetHillDiameter(Child: TAssetNode): Double;
      procedure AddOrbitingChild(Child: TAssetNode; SemiMajorAxis: Double; Eccentricity: Double; ThetaZero: Double; Omega: Double);
      function IAssetNameProvider.GetAssetName = GetOrbitName;
      property PrimaryChild: TAssetNode read FPrimaryChild;
      property OrbitingChildren[Index: Cardinal]: TAssetNode read GetOrbitingChild;
      property OrbitingChildCount: Cardinal read GetOrbitingChildCount;
   end;
   
implementation

uses
   sysutils, isdprotocol, encyclopedia;

type
   POrbitData = ^TOrbitData;
   TOrbitData = record
      SemiMajorAxis: Double; // meters, must be less than Size, and more than FPrimaryChild.Size
      Eccentricity: Double; // dimensionless
      ThetaZero: Double; // radians
      Omega: Double; // radians
      function GetHillDiameter(Parent: TOrbitFeatureNode; Child: TAssetNode): Double; // meters
      function GetCanHaveOrbitalChildren(Parent: TOrbitFeatureNode; Child: TAssetNode): Boolean;
      function GetPeriod(Parent: TOrbitFeatureNode; Child: TAssetNode): Double; // seconds
   end;

function TOrbitData.GetHillDiameter(Parent: TOrbitFeatureNode; Child: TAssetNode): Double;
begin
   Result := 2.0 * SemiMajorAxis * (1.0 - Eccentricity) * SqRt(Child.Mass / (3 * Parent.PrimaryChild.Mass)); // m
end;

function TOrbitData.GetCanHaveOrbitalChildren(Parent: TOrbitFeatureNode; Child: TAssetNode): Boolean;
begin
   Result := GetHillDiameter(Parent, Child) > Child.Size;
end;

function TOrbitData.GetPeriod(Parent: TOrbitFeatureNode; Child: TAssetNode): Double;
const
   G = 6.67430E-11; // N.m^2.kg^-2
var
   A, M: Double;
begin
   A := SemiMajorAxis; // m
   M := Parent.PrimaryChild.Mass; // kg
   Result := 2.0 * pi * SqRt(A*A*A/G*M); // s // $R-
end;


function TOrbitFeatureClass.GetFeatureNodeClass(): FeatureNodeReference;
begin
   Result := TOrbitFeatureNode;
end;

function TOrbitFeatureClass.InitFeatureNode(): TFeatureNode;
begin
   Result := nil;
   raise Exception.Create('Cannot create a TOrbitFeatureClass from a prototype; use AddChild on a TSolarSystemFeatureNode or a TOrbitFeatureNode.');
end;


constructor TOrbitFeatureNode.Create(APrimaryChild: TAssetNode);
begin
   inherited Create();
   Assert(Assigned(APrimaryChild));
   AdoptChild(APrimaryChild);
   FPrimaryChild := APrimaryChild;
end;

destructor TOrbitFeatureNode.Destroy();
var
   Child: TAssetNode;
begin
   DropChild(FPrimaryChild);
   FPrimaryChild.Free();
   for Child in FChildren do
   begin
      DropOrbitingChild(Child);
      Child.Free();
   end;
   inherited;
end;

procedure TOrbitFeatureNode.AdoptOrbitingChild(Child: TAssetNode);
begin
   AdoptChild(Child);
   Child.ParentData := New(POrbitData);
end;

procedure TOrbitFeatureNode.DropOrbitingChild(Child: TAssetNode);
begin
   Dispose(POrbitData(Child.ParentData));
   Child.ParentData := nil;
   DropChild(Child);
end;

function TOrbitFeatureNode.GetHillDiameter(Child: TAssetNode): Double;
begin
   Assert(Assigned(Child.ParentData));
   Result := POrbitData(Child.ParentData)^.GetHillDiameter(Self, Child);
end;

procedure TOrbitFeatureNode.AddOrbitingChild(Child: TAssetNode; SemiMajorAxis: Double; Eccentricity: Double; ThetaZero: Double; Omega: Double);
begin
   Assert(Child.AssetClass.ID = idOrbits);
   AdoptOrbitingChild(Child);
   POrbitData(Child.ParentData)^.SemiMajorAxis := SemiMajorAxis;
   POrbitData(Child.ParentData)^.Eccentricity := Eccentricity;
   POrbitData(Child.ParentData)^.ThetaZero := ThetaZero;
   POrbitData(Child.ParentData)^.Omega := Omega;
   SetLength(FChildren, Length(FChildren) + 1);
   FChildren[High(FChildren)] := Child;
end;

function TOrbitFeatureNode.GetOrbitingChild(Index: Cardinal): TAssetNode;
begin
   Result := FChildren[Index];
end;

function TOrbitFeatureNode.GetOrbitingChildCount(): Cardinal;
begin
   Result := Length(FChildren); // $R-
end;

procedure TOrbitFeatureNode.MarkAsDirty(DirtyKinds: TDirtyKinds; ChangeKinds: TChangeKinds);
begin
   if (ckAffectsNames in ChangeKinds) then
      Include(DirtyKinds, dkSelf);
   inherited;
end;

function TOrbitFeatureNode.GetMass(): Double;
var
   Index: Cardinal;
begin
   Result := PrimaryChild.Mass;
   if (OrbitingChildCount > 0) then
      for Index := 0 to OrbitingChildCount-1 do // $R-
         Result := Result + OrbitingChildren[Index].Mass;
end;

function TOrbitFeatureNode.GetSize(): Double;
begin
   if (Parent.Parent is IHillDiameterProvider) then
   begin
      Result := (Parent.Parent as IHillDiameterProvider).GetHillDiameter(Parent);
   end
   else
   begin
      Result := PrimaryChild.Size;
   end;
end;

function TOrbitFeatureNode.GetFeatureName(): UTF8String;
begin
   Result := '';
end;

procedure TOrbitFeatureNode.Walk(PreCallback: TPreWalkCallback; PostCallback: TPostWalkCallback);
var
   Child: TAssetNode;
begin
   Assert(Assigned(FPrimaryChild));
   FPrimaryChild.Walk(PreCallback, PostCallback);
   for Child in FChildren do
      Child.Walk(PreCallback, PostCallback);
end;

procedure TOrbitFeatureNode.ApplyVisibility(VisibilityHelper: TVisibilityHelper);
begin
   VisibilityHelper.AddBroadVisibility([dmClassKnown], Parent);
end;

procedure TOrbitFeatureNode.InferVisibilityByIndex(DynastyIndex: Cardinal; VisibilityHelper: TVisibilityHelper);
begin
   inherited;
   // The following is not an infinite loop only because the child's asset parent already has dmInference by the time we get here.
   Assert(dmInference in Parent.ReadVisibilityFor(DynastyIndex, VisibilityHelper.System));
   VisibilityHelper.AddSpecificVisibilityByIndex(DynastyIndex, [dmInference], PrimaryChild);
end;

function TOrbitFeatureNode.GetOrbitName(): UTF8String;
begin
   Result := PrimaryChild.AssetName;
end;

procedure TOrbitFeatureNode.Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter; System: TSystem);
var
   Child: TAssetNode;
begin
   Writer.WriteCardinal(fcOrbit);
   Assert(Assigned(FPrimaryChild));
   Writer.WritePtrUInt(FPrimaryChild.ID(System));
   Writer.WriteCardinal(Length(FChildren));
   for Child in FChildren do
   begin
      Writer.WriteDouble(POrbitData(Child.ParentData)^.SemiMajorAxis);
      Writer.WriteDouble(POrbitData(Child.ParentData)^.Eccentricity);
      Writer.WriteDouble(POrbitData(Child.ParentData)^.ThetaZero);
      Writer.WriteDouble(POrbitData(Child.ParentData)^.Omega);
      Writer.WritePtrUInt(Child.ID(System));
   end;
end;

procedure TOrbitFeatureNode.RecordSnapshot(Journal: TJournalWriter);
var
   Child: TAssetNode;
begin
   Journal.WriteAssetNodeReference(FPrimaryChild);
   Journal.WriteCardinal(Length(FChildren));
   for Child in FChildren do
   begin
      Journal.WriteAssetChangeKind(ckAdd);
      Journal.WriteAssetNodeReference(Child);
      Journal.WriteDouble(POrbitData(Child.ParentData)^.SemiMajorAxis);
      Journal.WriteDouble(POrbitData(Child.ParentData)^.Eccentricity);
      Journal.WriteDouble(POrbitData(Child.ParentData)^.ThetaZero);
      Journal.WriteDouble(POrbitData(Child.ParentData)^.Omega);
   end;
end;

procedure TOrbitFeatureNode.ApplyJournal(Journal: TJournalReader);

   procedure AddChild();
   var
      Child: TAssetNode;
      SemiMajorAxis, Eccentricity, ThetaZero, Omega: Double;
   begin
      Child := Journal.ReadAssetNodeReference();
      SemiMajorAxis := Journal.ReadDouble();
      Eccentricity := Journal.ReadDouble();
      ThetaZero := Journal.ReadDouble();
      Omega := Journal.ReadDouble();
      AddOrbitingChild(Child, SemiMajorAxis, Eccentricity, ThetaZero, Omega);
   end;

   procedure DeleteChild(Child: TAssetNode);
   var
      Index: Cardinal;
   begin
      Child := Journal.ReadAssetNodeReference();
      Assert(Length(FChildren) > 0);
      for Index := Low(FChildren) to High(FChildren) do // $R-
      begin
         if (FChildren[Index] = Child) then
         begin
            Delete(FChildren, Index, 1);
            Child.Free();
            exit;
         end;
      end;
   end;

   procedure RemoveChild();
   var
      Child: TAssetNode;
   begin
      Child := Journal.ReadAssetNodeReference();
      DeleteChild(Child);
      Child.Free();
   end;

   procedure MoveChild();
   var
      Child: TAssetNode;
   begin
      Child := Journal.ReadAssetNodeReference();
      DeleteChild(Child);
   end;

var
   Count: Cardinal;
   Child: TAssetNode;
   AssetChangeKind: TAssetChangeKind;
begin
   Child := Journal.ReadAssetNodeReference();
   Assert((not Assigned(FPrimaryChild)) or (Child = FPrimaryChild));
   if (not Assigned(FPrimaryChild)) then
   begin
      AdoptChild(Child);
   end;
   Assert(Child.Parent = Self);
   FPrimaryChild := Child;
   Count := Journal.ReadCardinal();
   while (Count > 0) do
   begin
      AssetChangeKind := Journal.ReadAssetChangeKind();
      case AssetChangeKind of
         ckAdd: AddChild();
         ckRemove: RemoveChild();
         ckMove: MoveChild();
      end;
      Dec(Count);
   end;
end;

end.