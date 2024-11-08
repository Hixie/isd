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
      procedure AdoptOrbitingChild(Child: TAssetNode); // Child must be an orbit.
      procedure DropOrbitingChild(Child: TAssetNode);
      procedure MarkAsDirty(DirtyKinds: TDirtyKinds; ChangeKinds: TChangeKinds); override;
      function GetMass(): Double; override;
      function GetSize(): Double; override;
      function GetFeatureName(): UTF8String; override;
      procedure Walk(PreCallback: TPreWalkCallback; PostCallback: TPostWalkCallback); override;
      function HandleBusMessage(Message: TBusMessage): Boolean; override;
      procedure ApplyVisibility(VisibilityHelper: TVisibilityHelper); override;
      procedure InferVisibilityByIndex(DynastyIndex: Cardinal; VisibilityHelper: TVisibilityHelper); override;
      procedure Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter; System: TSystem); override;
      procedure HandleCrash(var Data);
   public
      constructor Create(APrimaryChild: TAssetNode);
      destructor Destroy(); override;
      procedure RecordSnapshot(Journal: TJournalWriter); override;
      procedure ApplyJournal(Journal: TJournalReader; System: TSystem); override;
      function GetHillDiameter(Child: TAssetNode; ChildPrimaryMass: Double): Double;
      function GetRocheLimit(ChildRadius, ChildMass: Double): Double; // returns minimum semi-major axis for a hypothetical child planetary body orbitting our primary
      // given child should have a TOrbitFeatureNode, use Encyclopedia.WrapAssetForOrbit
      procedure AddOrbitingChild(System: TSystem; Child: TAssetNode; SemiMajorAxis: Double; Eccentricity: Double; Omega: Double; TimeOrigin: Int64; Clockwise: Boolean);
      procedure UpdateOrbitingChild(System: TSystem; Child: TAssetNode; SemiMajorAxis: Double; Eccentricity: Double; Omega: Double; TimeOrigin: Int64; Clockwise: Boolean);
      function IAssetNameProvider.GetAssetName = GetOrbitName;
      property PrimaryChild: TAssetNode read FPrimaryChild;
      property OrbitingChildren[Index: Cardinal]: TAssetNode read GetOrbitingChild;
      property OrbitingChildCount: Cardinal read GetOrbitingChildCount;
   end;
   
implementation

uses
   sysutils, isdprotocol, math, exceptions, encyclopedia;

type
   POrbitData = ^TOrbitData;
   TOrbitData = record
      SemiMajorAxis: Double; // meters, must be less than Size, and more than FPrimaryChild.Size
      Eccentricity: Double; // dimensionless
      Omega: Double; // radians
      TimeOrigin: Int64; // milliseconds in system time
      Clockwise: Boolean;
      CrashEvent: TSystemEvent; // if we're scheduled to crash into the primary, this is our event
      procedure Init();
      // Returns hill diameter of the child body in this orbit, with mass ChildMass, assuming the orbit is around a body of mass PrimaryMass.
      function GetHillDiameter(PrimaryMass, ChildMass: Double): Double; // meters
      // Returns whether Child can have children if it is in this orbit, around a primary Parent
      // (which must be the feature node containing the primary around which we're orbiting).
      // Child must be the actual body (not the orbit asset) that is orbiting Parent.
      function GetCanHaveOrbitalChildren(Parent: TOrbitFeatureNode; Child: TAssetNode): Boolean;
      function GetPeriod(Parent: TOrbitFeatureNode; Child: TAssetNode): Double; // seconds
   end;

procedure TOrbitData.Init();
begin
   CrashEvent := nil;
end;

function TOrbitData.GetHillDiameter(PrimaryMass, ChildMass: Double): Double;
begin
   Assert(SemiMajorAxis > 0.0, 'Cannot get hill diameter of asset with zero semimajor axis');
   Assert(Eccentricity <> 1.0, 'Cannot get hill diameter of asset with 1.0 eccentricity axis');
   Assert(PrimaryMass > 0.0, 'Cannot get hill diameter of asset orbiting primary with zero mass');
   Assert(ChildMass > 0.0, 'Cannot get hill diameter of asset with zero mass');
   Assert(PrimaryMass > ChildMass);
   Result := 2.0 * SemiMajorAxis * (1.0 - Eccentricity) * ((ChildMass / (3 * (ChildMass + PrimaryMass))) ** 1/3); // m // $R-
end;

function TOrbitData.GetCanHaveOrbitalChildren(Parent: TOrbitFeatureNode; Child: TAssetNode): Boolean;
begin
   Assert(Child.Mass > 0.0);
   Result := GetHillDiameter(Parent.PrimaryChild.Mass, Child.Mass) > Child.Size;
end;

function TOrbitData.GetPeriod(Parent: TOrbitFeatureNode; Child: TAssetNode): Double;
const
   G = 6.67430E-11; // N.m^2.kg^-2
var
   A, M: Double;
begin
   A := SemiMajorAxis; // m
   M := Parent.PrimaryChild.Mass; // kg
   Result := 2.0 * pi * SqRt(A*A*A/(G*M)); // s // $R-
   Assert(not IsNan(Result));
end;


function TOrbitFeatureClass.GetFeatureNodeClass(): FeatureNodeReference;
begin
   Result := TOrbitFeatureNode;
end;

function TOrbitFeatureClass.InitFeatureNode(): TFeatureNode;
begin
   Result := nil;
   raise Exception.Create('Cannot create a TOrbitFeatureNode from a prototype; use AddChild on a TSolarSystemFeatureNode or a TOrbitFeatureNode.');
end;


constructor TOrbitFeatureNode.Create(APrimaryChild: TAssetNode);
begin
   inherited Create();
   try
      Assert(Assigned(APrimaryChild));
      Assert(APrimaryChild.Mass > 0, 'Primary child "' + APrimaryChild.AssetName + '" (class "' + APrimaryChild.AssetClass.Name + '") has zero mass');
      AdoptChild(APrimaryChild);
      FPrimaryChild := APrimaryChild;
   except
      ReportCurrentException();
      raise;
   end;
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
   POrbitData(Child.ParentData)^.Init();
end;

procedure TOrbitFeatureNode.DropOrbitingChild(Child: TAssetNode);
begin
   if (Assigned(POrbitData(Child.ParentData)^.CrashEvent)) then
   begin
      POrbitData(Child.ParentData)^.CrashEvent.Cancel();
      POrbitData(Child.ParentData)^.CrashEvent := nil;
   end;
   Dispose(POrbitData(Child.ParentData));
   Child.ParentData := nil;
   DropChild(Child);
end;

function TOrbitFeatureNode.GetHillDiameter(Child: TAssetNode; ChildPrimaryMass: Double): Double;
begin
   // Child is the Orbit asset that is spinning around our primary.
   Assert(Assigned(Child.ParentData));
   Assert(ChildPrimaryMass <= Child.Mass); // Child.Mass includes the mass of child's satellites.
   Assert(ChildPrimaryMass <= PrimaryChild.Mass); // otherwise it wouldn't be orbiting us, we'd be orbiting it
   Result := POrbitData(Child.ParentData)^.GetHillDiameter(PrimaryChild.Mass, ChildPrimaryMass);
end;

function TOrbitFeatureNode.GetRocheLimit(ChildRadius, ChildMass: Double): Double;
begin
   // This only applies to bodies that are held together purely by gravitational forces, like planets.
   // It doesn't apply to bodies that are held together by, like, screws and stuff.
   Assert(ChildMass > 0);
   Result := ChildRadius * ((2 * PrimaryChild.Mass / ChildMass) ** (1.0 / 3.0)); // $R-
end;

procedure TOrbitFeatureNode.AddOrbitingChild(System: TSystem; Child: TAssetNode; SemiMajorAxis: Double; Eccentricity: Double; Omega: Double; TimeOrigin: Int64; Clockwise: Boolean);
begin
   Assert(Child.AssetClass.ID = idOrbits);
   Assert(not Assigned(Child.Parent));
   AdoptOrbitingChild(Child);
   SetLength(FChildren, Length(FChildren) + 1);
   FChildren[High(FChildren)] := Child;
   UpdateOrbitingChild(System, Child, SemiMajorAxis, Eccentricity, Omega, TimeOrigin, Clockwise);
end;

procedure TOrbitFeatureNode.UpdateOrbitingChild(System: TSystem; Child: TAssetNode; SemiMajorAxis: Double; Eccentricity: Double; Omega: Double; TimeOrigin: Int64; Clockwise: Boolean);
var
   Period, CrashTime: Int64;
begin
   Assert(Child.Parent = Self);
   Assert(Assigned(Child.ParentData));
   if (Assigned(POrbitData(Child.ParentData)^.CrashEvent)) then
   begin
      POrbitData(Child.ParentData)^.CrashEvent.Cancel();
      POrbitData(Child.ParentData)^.CrashEvent := nil;
   end;
   POrbitData(Child.ParentData)^.SemiMajorAxis := SemiMajorAxis;
   POrbitData(Child.ParentData)^.Eccentricity := Eccentricity;
   POrbitData(Child.ParentData)^.Omega := Omega;
   POrbitData(Child.ParentData)^.TimeOrigin := TimeOrigin;
   POrbitData(Child.ParentData)^.Clockwise := Clockwise;
   if (SemiMajorAxis * (1 - Eccentricity) <= (PrimaryChild.Size + Child.Size) / 2) then
   begin
      // SemiMajorAxis * (1 - Eccentricity) is the distance between
      // the center of the focal point and the center of the body at
      // the periapsis. If that distance is less than the sum of the
      // radii of the bodies, they'll definitely collide. We pretend
      // that happens at the periapsis (even though it will actually
      // happen earlier, when the body gets to the point that the
      // separation between the bodies is less than the sum of the
      // radii). By definition the orbitting body is at periapsis
      // every period, starting at TimeOrigin, so we ask the system to
      // compute the next time that we'll be at a whole number of
      // Periods since the TimeOrigin.
      Period := Round(POrbitData(Child.ParentData)^.GetPeriod(Self, Child));
      CrashTime := System.TimeUntilNext(TimeOrigin, Period);
      POrbitData(Child.ParentData)^.CrashEvent := System.ScheduleEvent(CrashTime, @HandleCrash, Child);
   end;
end;

procedure TOrbitFeatureNode.HandleCrash(var Data);
var
   Child: TAssetNode;
begin
   Child := TAssetNode(Data);
   POrbitData(Child.ParentData)^.CrashEvent := nil;
   Writeln('Crash!');
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
   Assert(Result > 0.0, 'Primary child of orbit has zero mass.');
   if (OrbitingChildCount > 0) then
      for Index := 0 to OrbitingChildCount-1 do // $R-
         Result := Result + OrbitingChildren[Index].Mass;
end;

function TOrbitFeatureNode.GetSize(): Double;
begin
   if (Parent.Parent is IHillDiameterProvider) then
   begin
      Result := (Parent.Parent as IHillDiameterProvider).GetHillDiameter(Parent, PrimaryChild.Mass);
      Assert(Result > 0.0, 'Zero hill diameter returned by "' + Parent.Parent.ClassName + '" of asset "' + Parent.Parent.Parent.AssetName + '" (of class "' + Parent.Parent.Parent.AssetClass.Name + '")');
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

function TOrbitFeatureNode.HandleBusMessage(Message: TBusMessage): Boolean;
var
   Child: TAssetNode;
begin
   Result := FPrimaryChild.HandleBusMessage(Message);
   if (not Result) then
   begin
      for Child in FChildren do
      begin
         Result := Child.HandleBusMessage(Message);
         if (Result) then
            exit;
      end;
   end;
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
   VisibilityHelper.AddSpecificVisibilityByIndex(DynastyIndex, [dmInference] + PrimaryChild.ReadVisibilityFor(DynastyIndex, VisibilityHelper.System), Parent);
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
      Writer.WriteDouble(POrbitData(Child.ParentData)^.Omega);
      Writer.WriteInt64(POrbitData(Child.ParentData)^.TimeOrigin);
      Writer.WriteBoolean(POrbitData(Child.ParentData)^.Clockwise);
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
      Journal.WriteDouble(POrbitData(Child.ParentData)^.Omega);
      Journal.WriteInt64(POrbitData(Child.ParentData)^.TimeOrigin);
      Journal.WriteBoolean(POrbitData(Child.ParentData)^.Clockwise);
   end;
end;

procedure TOrbitFeatureNode.ApplyJournal(Journal: TJournalReader; System: TSystem);

   procedure AddChild();
   var
      Child: TAssetNode;
      SemiMajorAxis, Eccentricity, Omega: Double;
      TimeOrigin: Int64;
      Clockwise: Boolean;
   begin
      Child := Journal.ReadAssetNodeReference();
      SemiMajorAxis := Journal.ReadDouble();
      Eccentricity := Journal.ReadDouble();
      Omega := Journal.ReadDouble();
      TimeOrigin := Journal.ReadInt64();
      Clockwise := Journal.ReadBoolean();
      if (not Assigned(Child.Parent)) then
      begin
         AddOrbitingChild(System, Child, SemiMajorAxis, Eccentricity, Omega, TimeOrigin, Clockwise);
      end
      else
      begin
         Assert(Child.Parent = Self);
         UpdateOrbitingChild(System, Child, SemiMajorAxis, Eccentricity, Omega, TimeOrigin, Clockwise);
      end;
   end;

   procedure DeleteChild(Child: TAssetNode);
   var
      Index: Cardinal;
   begin
      Assert(Child <> FPrimaryChild);
      Assert(Length(FChildren) > 0);
      for Index := Low(FChildren) to High(FChildren) do // $R-
      begin
         if (FChildren[Index] = Child) then
         begin
            Delete(FChildren, Index, 1);
            DropOrbitingChild(Child);
            exit;
         end;
      end;
      Assert(False);
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
      FPrimaryChild := Child;
   end;
   Assert(Child.Parent = Self);
   Assert(Child = FPrimaryChild);
   Count := Journal.ReadCardinal();
   while (Count > 0) do
   begin
      // TODO: should we just always apply a fresh list of children, and figure out which ones left and which did not?
      // (and put the ones that were removed into some list that we check later to free the right ones?)
      // see also surfaces, space
      AssetChangeKind := Journal.ReadAssetChangeKind();
      case AssetChangeKind of
         ckAdd: AddChild();
         ckRemove: RemoveChild();
         ckMove: MoveChild();
         ckNone: Assert(False);
      end;
      Dec(Count);
   end;
end;

end.