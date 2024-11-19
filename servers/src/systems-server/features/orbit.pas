{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit orbit;

interface

uses
   systems, providers, serverstream, time;

type
   TOrbitBusMessage = class abstract(TBusMessage) end;
   
   PCrashReport = ^TCrashReport;
   TCrashReport = record
      Victims: TAssetNodeArray; // TODO: make populating this more efficient
   end;

   // reporting this as handled implies that AddVictim has been called appropriately
   // otherwise, an ancestor is likely to do it instead
   TCrashReportMessage = class(TOrbitBusMessage)
   private
      FCrashReport: PCrashReport;
   public
      constructor Create(ACrashReport: PCrashReport);
      procedure AddVictim(Node: TAssetNode);
   end;
   
   TReceiveCrashingAssetMessage = class(TOrbitBusMessage)
   private
      FAssets: TAssetNodeArray;
   public
      constructor Create(ACrashReport: PCrashReport);
      property Assets: TAssetNodeArray read FAssets;
   end;
   

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
      FChildren: TAssetNodeArray;
      function GetOrbitName(): UTF8String;
   protected
      procedure AdoptOrbitingChild(Child: TAssetNode); // Child must be an orbit.
      procedure DropChild(Child: TAssetNode); override;
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
      procedure UpdateJournal(Journal: TJournalWriter); override;
      procedure ApplyJournal(Journal: TJournalReader; System: TSystem); override;
      function GetHillDiameter(Child: TAssetNode; ChildPrimaryMass: Double): Double;
      function GetRocheLimit(ChildRadius, ChildMass: Double): Double; // returns minimum semi-major axis for a hypothetical child planetary body orbitting our primary
      // given child should have a TOrbitFeatureNode, use Encyclopedia.WrapAssetForOrbit
      procedure AddOrbitingChild(System: TSystem; Child: TAssetNode; SemiMajorAxis: Double; Eccentricity: Double; Omega: Double; TimeOrigin: TTimeInMilliseconds; Clockwise: Boolean);
      procedure UpdateOrbitingChild(System: TSystem; Child: TAssetNode; SemiMajorAxis: Double; Eccentricity: Double; Omega: Double; TimeOrigin: TTimeInMilliseconds; Clockwise: Boolean; Index: Cardinal);
      function IAssetNameProvider.GetAssetName = GetOrbitName;
      property PrimaryChild: TAssetNode read FPrimaryChild;
   end;
   
implementation

uses
   sysutils, isdprotocol, math, exceptions, encyclopedia;

type
   POrbitData = ^TOrbitData;
   TOrbitData = bitpacked record
      CrashEvent: TSystemEvent; // if we're scheduled to crash into the primary, this is our event
      SemiMajorAxis: Double; // meters, must be less than Size, and more than FPrimaryChild.Size
      Eccentricity: Double; // dimensionless
      Omega: Double; // radians
      TimeOrigin: TTimeInMilliseconds;
      Clockwise: Boolean;
      Dirty: Boolean;
      IsNew: Boolean;
      Index: Cardinal;
      procedure Init();
      // Returns hill diameter of the child body in this orbit, with mass ChildMass, assuming the orbit is around a body of mass PrimaryMass.
      function GetHillDiameter(PrimaryMass, ChildMass: Double): Double; // meters
      // Returns whether Child can have children if it is in this orbit, around a primary Parent
      // (which must be the feature node containing the primary around which we're orbiting).
      // Child must be the actual body (not the orbit asset) that is orbiting Parent.
      function GetCanHaveOrbitalChildren(Parent: TOrbitFeatureNode; Child: TAssetNode): Boolean;
      function GetPeriod(Parent: TOrbitFeatureNode; Child: TAssetNode): TMillisecondsDuration;
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
   Assert(Assigned(Parent.PrimaryChild));
   Result := GetHillDiameter(Parent.PrimaryChild.Mass, Child.Mass) > Child.Size;
end;

function TOrbitData.GetPeriod(Parent: TOrbitFeatureNode; Child: TAssetNode): TMillisecondsDuration;
const
   G = 6.67430E-11; // N.m^2.kg^-2
var
   A, M: Double;
begin
   Assert(Assigned(Parent.PrimaryChild));
   A := SemiMajorAxis; // m
   M := Parent.PrimaryChild.Mass; // kg
   Result := TMillisecondsDuration(1000 * 2.0 * pi * SqRt(A*A*A/(G*M))); // $R-
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


constructor TCrashReportMessage.Create(ACrashReport: PCrashReport);
begin
   inherited Create();
   FCrashReport := ACrashReport;
end;

procedure TCrashReportMessage.AddVictim(Node: TAssetNode);
begin
   SetLength(FCrashReport^.Victims, Length(FCrashReport^.Victims) + 1);
   FCrashReport^.Victims[High(FCrashReport^.Victims)] := Node;
end;

constructor TReceiveCrashingAssetMessage.Create(ACrashReport: PCrashReport);
begin
   inherited Create();
   FAssets := ACrashReport^.Victims;
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
   if (Assigned(FPrimaryChild)) then
      FreeAndNil(FPrimaryChild);
   for Child in FChildren do
   begin
      Assert(Assigned(Child));
      Child.Free();
   end;
   SetLength(FChildren, 0);
   inherited;
end;

procedure TOrbitFeatureNode.AdoptOrbitingChild(Child: TAssetNode);
begin
   AdoptChild(Child);
   Child.ParentData := New(POrbitData);
   POrbitData(Child.ParentData)^.Init();
end;

procedure TOrbitFeatureNode.DropChild(Child: TAssetNode);
var
   Index: Cardinal;
begin
   if (Assigned(Child.ParentData)) then // the primary child doesn't have parent data
   begin
      if (Assigned(POrbitData(Child.ParentData)^.CrashEvent)) then
      begin
         POrbitData(Child.ParentData)^.CrashEvent.Cancel();
         POrbitData(Child.ParentData)^.CrashEvent := nil;
      end;
      Delete(FChildren, POrbitData(Child.ParentData)^.Index, 1);
      if (POrbitData(Child.ParentData)^.Index < Length(FChildren)) then
         for Index := POrbitData(Child.ParentData)^.Index to High(FChildren) do // $R-
            POrbitData(FChildren[Index].ParentData)^.Index := Index;
      Dispose(POrbitData(Child.ParentData));
      Child.ParentData := nil;
   end
   else
      FPrimaryChild := nil;
   inherited;
end;

function TOrbitFeatureNode.GetHillDiameter(Child: TAssetNode; ChildPrimaryMass: Double): Double;
begin
   // Child is the Orbit asset that is spinning around our primary.
   Assert(Assigned(Child.ParentData));
   Assert(Assigned(FPrimaryChild));
   Assert(ChildPrimaryMass <= Child.Mass); // Child.Mass includes the mass of child's satellites.
   Assert(ChildPrimaryMass <= FPrimaryChild.Mass, 'Child=' + Child.DebugName + ' Child.Mass=' + FloatToStr(Child.Mass) + ' ChildPrimaryMass=' + FloatToStr(ChildPrimaryMass) + ' FPrimaryChild.Mass=' + FloatToStr(FPrimaryChild.Mass)); // otherwise it wouldn't be orbiting us, we'd be orbiting it
   Result := POrbitData(Child.ParentData)^.GetHillDiameter(FPrimaryChild.Mass, ChildPrimaryMass);
end;

function TOrbitFeatureNode.GetRocheLimit(ChildRadius, ChildMass: Double): Double;
begin
   // This only applies to bodies that are held together purely by gravitational forces, like planets.
   // It doesn't apply to bodies that are held together by, like, screws and stuff.
   Assert(ChildMass > 0);
   Assert(Assigned(FPrimaryChild));
   Result := ChildRadius * ((2 * FPrimaryChild.Mass / ChildMass) ** (1.0 / 3.0)); // $R-
end;

procedure TOrbitFeatureNode.AddOrbitingChild(System: TSystem; Child: TAssetNode; SemiMajorAxis: Double; Eccentricity: Double; Omega: Double; TimeOrigin: TTimeInMilliseconds; Clockwise: Boolean);
begin
   Assert(Child.AssetClass.ID = idOrbits);
   Assert(not Assigned(Child.Parent));
   AdoptOrbitingChild(Child);
   SetLength(FChildren, Length(FChildren) + 1);
   FChildren[High(FChildren)] := Child;
   UpdateOrbitingChild(System, Child, SemiMajorAxis, Eccentricity, Omega, TimeOrigin, Clockwise, High(FChildren)); // $R-
   POrbitData(Child.ParentData)^.IsNew := True;
end;

procedure TOrbitFeatureNode.UpdateOrbitingChild(System: TSystem; Child: TAssetNode; SemiMajorAxis: Double; Eccentricity: Double; Omega: Double; TimeOrigin: TTimeInMilliseconds; Clockwise: Boolean; Index: Cardinal);
var
   Period, CrashTime: TMillisecondsDuration;
begin
   Assert(Child.Parent = Self);
   Assert(Assigned(Child.ParentData));
   Assert(Assigned(FPrimaryChild));
   Assert(not IsNaN(SemiMajorAxis));
   Assert(not IsNaN(Eccentricity));
   Assert(not IsNaN(Omega));
   Assert(Eccentricity <= 0.95); // above this our approximation goes out of the window
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
   POrbitData(Child.ParentData)^.Dirty := True;
   POrbitData(Child.ParentData)^.Index := Index;
   if (SemiMajorAxis * (1 - Eccentricity) <= (FPrimaryChild.Size + Child.Size) / 2) then
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
      Period := POrbitData(Child.ParentData)^.GetPeriod(Self, Child);
      CrashTime := System.TimeUntilNext(TimeOrigin, Period);
      POrbitData(Child.ParentData)^.CrashEvent := System.ScheduleEvent(CrashTime, @HandleCrash, Child);
   end;
end;

procedure TOrbitFeatureNode.HandleCrash(var Data);
var
   Child: TAssetNode;
   ReceiveMessage: TReceiveCrashingAssetMessage;
   CrashReportMessage: TCrashReportMessage;
   CrashReport: PCrashReport;
begin
   Assert(Assigned(FPrimaryChild));
   Child := TAssetNode(Data);
   POrbitData(Child.ParentData)^.CrashEvent := nil;

   Writeln('Crashing "', Child.AssetName, '" (a ', Child.AssetClass.Name, ')');

   // TODO: send a notification to the clients a few seconds early, so they can trigger an animation
   
   CrashReport := New(PCrashReport);
   
   CrashReportMessage := TCrashReportMessage.Create(CrashReport);
   try
      Child.HandleBusMessage(CrashReportMessage);
   finally
      FreeAndNil(CrashReportMessage);
   end;
   
   ReceiveMessage := TReceiveCrashingAssetMessage.Create(CrashReport);
   try
      FPrimaryChild.HandleBusMessage(ReceiveMessage);
   finally
      FreeAndNil(ReceiveMessage);
   end;

   Dispose(CrashReport);
   
   if (Child.Parent = Self) then
   begin
      Assert(Child.Mass = 0.0);
      Child.ReportPermanentlyGone();
      DropChild(Child);
      Child.Free();
   end;
end;

procedure TOrbitFeatureNode.MarkAsDirty(DirtyKinds: TDirtyKinds; ChangeKinds: TChangeKinds);
begin
   if (ckAffectsNames in ChangeKinds) then
      Include(DirtyKinds, dkSelf);
   inherited;
end;

function TOrbitFeatureNode.GetMass(): Double;
var
   Child: TAssetNode;
begin
   Result := 0.0;
   if (Assigned(FPrimaryChild)) then
   begin
      Result := Result + FPrimaryChild.Mass;
      Assert(Result > 0.0, 'Primary child of orbit has zero mass.');
   end;
   for Child in FChildren do
   begin
      Assert(Assigned(Child));
      Result := Result + Child.Mass;
   end;
end;

function TOrbitFeatureNode.GetSize(): Double;
begin
   Assert(Assigned(FPrimaryChild));
   if (Parent.Parent is IHillDiameterProvider) then
   begin
      Result := (Parent.Parent as IHillDiameterProvider).GetHillDiameter(Parent, FPrimaryChild.Mass);
      Assert(Result > 0.0, 'Zero hill diameter returned by "' + Parent.Parent.ClassName + '" of asset "' + Parent.Parent.Parent.AssetName + '" (of class "' + Parent.Parent.Parent.AssetClass.Name + '")');
   end
   else
   begin
      Result := FPrimaryChild.Size;
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
   begin
      Assert(Assigned(Child));
      Child.Walk(PreCallback, PostCallback);
   end;
end;

function TOrbitFeatureNode.HandleBusMessage(Message: TBusMessage): Boolean;
var
   Child: TAssetNode;
   ChildHandled: Boolean;
begin
   Assert(Assigned(FPrimaryChild));
   if (Message is TCrashReportMessage) then
   begin
      ChildHandled := FPrimaryChild.HandleBusMessage(Message);
      if (not ChildHandled) then
      begin
         TCrashReportMessage(Message).AddVictim(FPrimaryChild);
      end;
      for Child in FChildren do
      begin
         Assert(Assigned(Child));
         ChildHandled := Child.HandleBusMessage(Message);
         if (not ChildHandled) then
            TCrashReportMessage(Message).AddVictim(Child);
      end;
      Result := True;
      exit;
   end;
   Result := FPrimaryChild.HandleBusMessage(Message);
   if (not Result) then
   begin
      for Child in FChildren do
      begin
         Assert(Assigned(Child));
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
   Assert(Assigned(FPrimaryChild));
   inherited;
   // The following is not an infinite loop only because the child's asset parent already has dmInference by the time we get here.
   Assert(dmInference in Parent.ReadVisibilityFor(DynastyIndex, VisibilityHelper.System));
   VisibilityHelper.AddSpecificVisibilityByIndex(DynastyIndex, [dmInference] + FPrimaryChild.ReadVisibilityFor(DynastyIndex, VisibilityHelper.System), Parent);
end;

function TOrbitFeatureNode.GetOrbitName(): UTF8String;
begin
   Assert(Assigned(FPrimaryChild));
   {$IFDEF DEBUG}
   if (not Assigned(FPrimaryChild)) then
      Result := '<orphan orbit>'
   else
   {$ENDIF}
   Result := FPrimaryChild.AssetName;
end;

procedure TOrbitFeatureNode.Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter; System: TSystem);
var
   Child: TAssetNode;
begin
   Assert(Assigned(FPrimaryChild));
   Writer.WriteCardinal(fcOrbit);
   Writer.WriteCardinal(FPrimaryChild.ID(System, DynastyIndex));
   Writer.WriteCardinal(Length(FChildren));
   for Child in FChildren do
   begin
      Assert(Assigned(Child));
      Writer.WriteDouble(POrbitData(Child.ParentData)^.SemiMajorAxis);
      Writer.WriteDouble(POrbitData(Child.ParentData)^.Eccentricity);
      Writer.WriteDouble(POrbitData(Child.ParentData)^.Omega);
      Writer.WriteInt64(POrbitData(Child.ParentData)^.TimeOrigin.AsInt64);
      Writer.WriteBoolean(POrbitData(Child.ParentData)^.Clockwise);
      Writer.WriteCardinal(Child.ID(System, DynastyIndex));
   end;
end;

procedure TOrbitFeatureNode.UpdateJournal(Journal: TJournalWriter);
var
   Child: TAssetNode;
begin
   Assert(Assigned(FPrimaryChild));
   Journal.WriteAssetNodeReference(FPrimaryChild);
   if (Length(FChildren) > 0) then
   begin
      for Child in FChildren do
      begin
         Assert(Assigned(Child));
         if (POrbitData(Child.ParentData)^.Dirty) then
         begin
            if (POrbitData(Child.ParentData)^.IsNew) then
            begin
               Journal.WriteAssetChangeKind(ckAdd);
               POrbitData(Child.ParentData)^.IsNew := False;
            end
            else
            begin
               Journal.WriteAssetChangeKind(ckChange);
            end;
            Journal.WriteAssetNodeReference(Child);
            Journal.WriteDouble(POrbitData(Child.ParentData)^.SemiMajorAxis);
            Journal.WriteDouble(POrbitData(Child.ParentData)^.Eccentricity);
            Journal.WriteDouble(POrbitData(Child.ParentData)^.Omega);
            Journal.WriteInt64(POrbitData(Child.ParentData)^.TimeOrigin.AsInt64);
            Journal.WriteBoolean(POrbitData(Child.ParentData)^.Clockwise);
            POrbitData(Child.ParentData)^.Dirty := False;
         end;
      end;
   end;
   Journal.WriteAssetChangeKind(ckEndOfList);
end;

procedure TOrbitFeatureNode.ApplyJournal(Journal: TJournalReader; System: TSystem);

   procedure AddChild();
   var
      Child: TAssetNode;
      SemiMajorAxis, Eccentricity, Omega: Double;
      TimeOrigin: TTimeInMilliseconds;
      Clockwise: Boolean;
   begin
      Child := Journal.ReadAssetNodeReference();
      SemiMajorAxis := Journal.ReadDouble();
      Eccentricity := Journal.ReadDouble();
      Omega := Journal.ReadDouble();
      TimeOrigin := TTimeInMilliseconds(Journal.ReadInt64());
      Clockwise := Journal.ReadBoolean();
      AddOrbitingChild(System, Child, SemiMajorAxis, Eccentricity, Omega, TimeOrigin, Clockwise);
      Assert(Child.Parent = Self);
   end;

   procedure ChangeChild();
   var
      Child: TAssetNode;
      SemiMajorAxis, Eccentricity, Omega: Double;
      TimeOrigin: TTimeInMilliseconds;
      Clockwise: Boolean;
      Index: Cardinal;
   begin
      Child := Journal.ReadAssetNodeReference();
      SemiMajorAxis := Journal.ReadDouble();
      Eccentricity := Journal.ReadDouble();
      Omega := Journal.ReadDouble();
      TimeOrigin := TTimeInMilliseconds(Journal.ReadInt64());
      Clockwise := Journal.ReadBoolean();
      Index := POrbitData(Child.ParentData)^.Index; // it doesn't change
      UpdateOrbitingChild(System, Child, SemiMajorAxis, Eccentricity, Omega, TimeOrigin, Clockwise, Index);
      Assert(Child.Parent = Self);
   end;

var
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