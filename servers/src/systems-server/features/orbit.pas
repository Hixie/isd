{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit orbit;

interface

uses
   systems, providers, serverstream, time, techtree;

type
   TOrbitBusMessage = class abstract(TBusMessage) end;

   PCrashReport = ^TCrashReport;
   TCrashReport = record
   strict private
      class operator Initialize(var Rec: TCrashReport);
   public
      // Victims are the asset that crashed, and any assets that were orbitting that asset at the time of the crash
      Victims: TAssetNode.TArray; // TODO: make populating this more efficient
      RegionDimension: Cardinal; // 0 means random
   end;

   // reporting this as handled implies that AddVictim has been called appropriately
   // otherwise, an ancestor is likely to do it instead
   TCrashReportMessage = class(TOrbitBusMessage)
   private
      FCrashReport: PCrashReport;
   public
      constructor Create(ACrashReport: PCrashReport);
      procedure AddVictim(Node: TAssetNode);
      procedure RequestRegionDimension(Dimension: Cardinal);
   end;

   TReceiveCrashingAssetMessage = class(TOrbitBusMessage)
   private
      FAssets: TAssetNode.TArray;
      FRegionDimension: Cardinal;
   public
      constructor Create(ACrashReport: PCrashReport);
      property Assets: TAssetNode.TArray read FAssets;
      property RegionDimension: Cardinal read FRegionDimension;
   end;

   TGetNearestOrbitMessage = class(TOrbitBusMessage) // inject, orbit will report itself
   private
      FOrbit: TAssetNode;
   public
      constructor Create();
      property Orbit: TAssetNode read FOrbit;
      function GetSpaceShip(FromAsset: TAssetNode): TAssetNode; // returns the child of Orbit that contains FromAsset (or nil)
   end;

type
   TOrbitFeatureClass = class(TFeatureClass)
   strict protected
      function GetFeatureNodeClass(): FeatureNodeReference; override;
   public
      constructor CreateFromTechnologyTree(Reader: TTechTreeReader); override;
      function InitFeatureNode(ASystem: TSystem): TFeatureNode; override;
   end;

   TOrbitFeatureNode = class(TFeatureNode, IHillDiameterProvider, IAssetNameProvider)
   private
      FPrimaryChild: TAssetNode;
      FChildren: TAssetNode.TArray;
      function GetOrbitName(): UTF8String;
   protected
      procedure AdoptOrbitingChild(Child: TAssetNode); // Child must be an orbit.
      procedure ParentMarkedAsDirty(ParentDirtyKinds, NewDirtyKinds: TDirtyKinds); override;
      function GetMass(): Double; override;
      function GetMassFlowRate(): TRate; override;
      function GetSize(): Double; override;
      procedure Walk(PreCallback: TPreWalkCallback; PostCallback: TPostWalkCallback); override;
      function ManageBusMessage(Message: TBusMessage): TInjectBusMessageResult; override;
      function HandleBusMessage(Message: TBusMessage): THandleBusMessageResult; override;
      procedure HandleVisibility(const DynastyIndex: Cardinal; var Visibility: TVisibility); override;
      procedure CheckVisibilityChanged(); override;
      procedure HandleKnowledge(const DynastyIndex: Cardinal; const Sensors: ISensorsProvider); override;
      procedure Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter); override;
      procedure HandleChanges(); override;
      procedure HandleCrash(var Data);
   public
      constructor Create(ASystem: TSystem);
      destructor Destroy(); override;
      procedure DropChild(Child: TAssetNode); override;
      procedure UpdateJournal(Journal: TJournalWriter); override;
      procedure ApplyJournal(Journal: TJournalReader); override;
      function GetHillDiameter(Child: TAssetNode; ChildPrimaryMass: Double): Double;
      function GetRocheLimit(ChildRadius, ChildMass: Double): Double; // returns minimum semi-major axis for a hypothetical child planetary body orbitting our primary
      function GetAverageDistance(Child: TAssetNode): Double;
      procedure SetPrimaryChild(APrimaryChild: TAssetNode); // must be called immediately after orbit is created and given a parent asset
      // given child should have a TOrbitFeatureNode, use Encyclopedia.WrapAssetForOrbit
      procedure AddOrbitingChild(Child: TAssetNode; SemiMajorAxis: Double; Eccentricity: Double; Omega: Double; TimeOrigin: TTimeInMilliseconds; Clockwise: Boolean);
      procedure UpdateOrbitingChild(Child: TAssetNode; SemiMajorAxis: Double; Eccentricity: Double; Omega: Double; TimeOrigin: TTimeInMilliseconds; Clockwise: Boolean; Index: Cardinal);
      function IAssetNameProvider.GetAssetName = GetOrbitName;
      procedure DescribeExistentiality(var IsDefinitelyReal, IsDefinitelyGhost: Boolean); override;
      property PrimaryChild: TAssetNode read FPrimaryChild;
   end;

implementation

uses
   sysutils, isdprotocol, math, exceptions;

type
   POrbitData = ^TOrbitData;
   TOrbitData = bitpacked record
      CrashEvent: TSystemEvent; // if we're scheduled to crash into the primary, this is our event
      SemiMajorAxis: Double; // meters, must be less than Size, and more than FPrimaryChild.Size
      Eccentricity: Double; // dimensionless
      Omega: Double; // radians
      TimeOrigin: TTimeInMilliseconds;
      Clockwise: Boolean;
      Dirty: Boolean; // needs to be journaled and crash-checked
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
   Assert(Parent.PrimaryChild.MassFlowRate.IsNearZero);
   Assert(Child.MassFlowRate.IsNearZero);
   Result := GetHillDiameter(Parent.PrimaryChild.Mass, Child.Mass) > Child.Size;
end;

function TOrbitData.GetPeriod(Parent: TOrbitFeatureNode; Child: TAssetNode): TMillisecondsDuration;
const
   G = 6.67430E-11; // N.m^2.kg^-2
var
   A, M: Double;
begin
   Assert(Assigned(Parent.PrimaryChild));
   Assert(Parent.PrimaryChild.MassFlowRate.IsNearZero);
   Assert(Child.MassFlowRate.IsNearZero);
   // we assume the child's mass is <<< the parent's mass. // TODO: assert this
   A := SemiMajorAxis; // m
   M := Parent.PrimaryChild.Mass; // kg
   Result := TMillisecondsDuration.FromMilliseconds(1000 * 2.0 * pi * SqRt(A*A*A/(G*M))); // $R-
end;


constructor TOrbitFeatureClass.CreateFromTechnologyTree(Reader: TTechTreeReader);
begin
   Reader.Tokens.Error('Feature class %s is reserved for internal asset classes', [ClassName]);
end;

function TOrbitFeatureClass.GetFeatureNodeClass(): FeatureNodeReference;
begin
   Result := TOrbitFeatureNode;
end;

function TOrbitFeatureClass.InitFeatureNode(ASystem: TSystem): TFeatureNode;
begin
   Result := nil;
   raise Exception.Create('Cannot create a TOrbitFeatureNode from a prototype; use AddChild on a TSolarSystemFeatureNode or a TOrbitFeatureNode.');
end;


class operator TCrashReport.Initialize(var Rec: TCrashReport);
begin
   Rec.RegionDimension := 0;
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

procedure TCrashReportMessage.RequestRegionDimension(Dimension: Cardinal);
begin
   FCrashReport^.RegionDimension := Dimension;
end;

      
constructor TReceiveCrashingAssetMessage.Create(ACrashReport: PCrashReport);
begin
   inherited Create();
   FAssets := ACrashReport^.Victims;
   FRegionDimension := ACrashReport^.RegionDimension;
end;

constructor TGetNearestOrbitMessage.Create();
begin
   inherited;
end;

function TGetNearestOrbitMessage.GetSpaceShip(FromAsset: TAssetNode): TAssetNode; // returns the child of Orbit that contains FromAsset (or nil)
begin
   Assert(Assigned(FromAsset));
   Result := FromAsset;
   while (Assigned(Result.Parent) and Assigned(Result.Parent.Parent) and (Result.Parent.Parent <> Orbit)) do
      Result := Result.Parent.Parent;
end;


constructor TOrbitFeatureNode.Create(ASystem: TSystem);
begin
   inherited Create(ASystem);
end;

destructor TOrbitFeatureNode.Destroy();
var
   Child: TAssetNode;
begin
   for Child in FChildren do
   begin
      Assert(Assigned(Child));
      Child.Free(); // calls DropChild
   end;
   FreeAndNil(FPrimaryChild);
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
         CancelEvent(POrbitData(Child.ParentData)^.CrashEvent);
      end;
      Delete(FChildren, POrbitData(Child.ParentData)^.Index, 1);
      if (POrbitData(Child.ParentData)^.Index < Length(FChildren)) then
         for Index := POrbitData(Child.ParentData)^.Index to High(FChildren) do // $R-
            POrbitData(FChildren[Index].ParentData)^.Index := Index;
      Dispose(POrbitData(Child.ParentData));
      Child.ParentData := nil;
   end
   else
   begin
      FPrimaryChild := nil;
      if (Length(FChildren) > 0) then
      begin
         XXX; // TODO: reparent satellites of an orbit's primary child when the primary goes away
         // the heaviest child should probably become the new primary child? or they should start orbiting the parent?
      end;
   end;
   inherited;
end;

function TOrbitFeatureNode.GetHillDiameter(Child: TAssetNode; ChildPrimaryMass: Double): Double;
begin
   // Child is the Orbit asset that is spinning around our primary.
   Assert(Assigned(Child.ParentData));
   Assert(Assigned(FPrimaryChild));
   Assert(ChildPrimaryMass <= Child.Mass); // Child.Mass includes the mass of child's satellites.
   Assert(ChildPrimaryMass < FPrimaryChild.Mass, 'Child=' + Child.DebugName + ' Child.Mass=' + FloatToStr(Child.Mass) + ' ChildPrimaryMass=' + FloatToStr(ChildPrimaryMass) + ' FPrimaryChild.Mass=' + FloatToStr(FPrimaryChild.Mass)); // otherwise it wouldn't be orbiting us, we'd be orbiting it
   Assert(FPrimaryChild.MassFlowRate.IsNearZero);
   Result := POrbitData(Child.ParentData)^.GetHillDiameter(FPrimaryChild.Mass, ChildPrimaryMass);
end;

function TOrbitFeatureNode.GetRocheLimit(ChildRadius, ChildMass: Double): Double;
begin
   // This only applies to bodies that are held together purely by gravitational forces, like planets.
   // It doesn't apply to bodies that are held together by, like, screws and stuff.
   Assert(ChildMass > 0);
   Assert(Assigned(FPrimaryChild));
   Assert(FPrimaryChild.MassFlowRate.IsNearZero);
   Result := ChildRadius * ((2 * FPrimaryChild.Mass / ChildMass) ** (1.0 / 3.0)); // $R-
end;

function TOrbitFeatureNode.GetAverageDistance(Child: TAssetNode): Double;
var
   SemiMajorAxis, Eccentricity: Double;
begin
   // This must remain equilavent to the code in protoplanetary.pas
   Assert(Child.Parent = Self);
   Assert(Assigned(Child.ParentData));
   SemiMajorAxis := POrbitData(Child.ParentData)^.SemiMajorAxis;
   Eccentricity := POrbitData(Child.ParentData)^.Eccentricity;
   Result := SemiMajorAxis * (1 + Eccentricity * Eccentricity / 2.0);
end;

procedure TOrbitFeatureNode.SetPrimaryChild(APrimaryChild: TAssetNode);
begin
   Assert(not Assigned(FPrimaryChild));
   Assert(Assigned(APrimaryChild));
   Assert(APrimaryChild.Mass > 0, 'Primary child "' + APrimaryChild.AssetName + '" (class "' + APrimaryChild.AssetClass.Name + '") has zero mass');
   Assert(APrimaryChild.MassFlowRate.IsNearZero);
   AdoptChild(APrimaryChild);
   FPrimaryChild := APrimaryChild;
end;

procedure TOrbitFeatureNode.AddOrbitingChild(Child: TAssetNode; SemiMajorAxis: Double; Eccentricity: Double; Omega: Double; TimeOrigin: TTimeInMilliseconds; Clockwise: Boolean);
begin
   Assert(Child.AssetClass.ID = idOrbits);
   Assert(not Assigned(Child.Parent));
   AdoptOrbitingChild(Child);
   SetLength(FChildren, Length(FChildren) + 1);
   FChildren[High(FChildren)] := Child;
   UpdateOrbitingChild(Child, SemiMajorAxis, Eccentricity, Omega, TimeOrigin, Clockwise, High(FChildren)); // $R-
   POrbitData(Child.ParentData)^.IsNew := True;
end;

procedure TOrbitFeatureNode.UpdateOrbitingChild(Child: TAssetNode; SemiMajorAxis: Double; Eccentricity: Double; Omega: Double; TimeOrigin: TTimeInMilliseconds; Clockwise: Boolean; Index: Cardinal);
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
      CancelEvent(POrbitData(Child.ParentData)^.CrashEvent);
   end;
   POrbitData(Child.ParentData)^.SemiMajorAxis := SemiMajorAxis;
   POrbitData(Child.ParentData)^.Eccentricity := Eccentricity;
   POrbitData(Child.ParentData)^.Omega := Omega;
   POrbitData(Child.ParentData)^.TimeOrigin := TimeOrigin;
   POrbitData(Child.ParentData)^.Clockwise := Clockwise;
   POrbitData(Child.ParentData)^.Dirty := True;
   POrbitData(Child.ParentData)^.Index := Index;
   MarkAsDirty([dkUpdateClients, dkUpdateJournal, dkNeedsHandleChanges]);
end;

procedure TOrbitFeatureNode.HandleChanges();
var
   Child, ChildCopy: TAssetNode;
   OrbitData: POrbitData;
   Period, CrashTime: TMillisecondsDuration;
begin
   for Child in FChildren do
   begin
      OrbitData := POrbitData(Child.ParentData);
      if (OrbitData^.Dirty) then
      begin
         Assert(not Assigned(OrbitData^.CrashEvent));
         if (OrbitData^.SemiMajorAxis * (1 - OrbitData^.Eccentricity) <= (FPrimaryChild.Size + Child.Size) / 2) then
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
            Period := OrbitData^.GetPeriod(Self, Child);
            CrashTime := System.TimeUntilNext(OrbitData^.TimeOrigin, Period);
            ChildCopy := Child;
            OrbitData^.CrashEvent := System.ScheduleEvent(CrashTime, @HandleCrash, ChildCopy);
            Writeln('Scheduling crash for ', Child.DebugName, '; T-', CrashTime.ToString());
         end;
      end;
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

   // TODO: give the clients the predicted crash time when we know it, so they can trigger animations appropriately

   CrashReport := New(PCrashReport);

   CrashReportMessage := TCrashReportMessage.Create(CrashReport);
   Child.HandleBusMessage(CrashReportMessage);
   FreeAndNil(CrashReportMessage);

   ReceiveMessage := TReceiveCrashingAssetMessage.Create(CrashReport);
   FPrimaryChild.HandleBusMessage(ReceiveMessage);
   FreeAndNil(ReceiveMessage);

   Dispose(CrashReport);

   if (Child.Parent = Self) then
   begin
      Assert(Child.Mass = 0.0, 'unexpectedly, the crashed child still has mass ' + FloatToStr(Child.Mass) + ' after being handled');
      Child.ReportPermanentlyGone();
      DropChild(Child);
      Child.Free();
   end;
end;

procedure TOrbitFeatureNode.ParentMarkedAsDirty(ParentDirtyKinds, NewDirtyKinds: TDirtyKinds);
var
   FurtherNewKinds: TDirtyKinds;
begin
   FurtherNewKinds := [];
   if (dkChildAffectsNames in NewDirtyKinds) then
   begin
      Include(FurtherNewKinds, dkAffectsNames);
      Include(FurtherNewKinds, dkUpdateClients);
   end;
   if (dkChildren in NewDirtyKinds) then
      Include(FurtherNewKinds, dkNeedsHandleChanges);
   if (FurtherNewKinds <> []) then
      MarkAsDirty(FurtherNewKinds);
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

function TOrbitFeatureNode.GetMassFlowRate(): TRate;
var
   Child: TAssetNode;
begin
   Result := TRate.Zero;
   if (Assigned(FPrimaryChild)) then
   begin
      Result := Result + FPrimaryChild.MassFlowRate;
   end;
   for Child in FChildren do
   begin
      Assert(Assigned(Child));
      Result := Result + Child.MassFlowRate;
   end;
   Assert(Result.IsNearZero, 'unexpected total mass flow rate for ' + Parent.DebugName + ' orbit feature: ' + Result.ToString('kg'));
end;

function TOrbitFeatureNode.GetSize(): Double;
begin
   if (Assigned(FPrimaryChild)) then
   begin
      if (Parent.Parent is IHillDiameterProvider) then
      begin
         Result := (Parent.Parent as IHillDiameterProvider).GetHillDiameter(Parent, FPrimaryChild.Mass);
         Assert(Result > 0.0, 'Zero hill diameter returned by "' + Parent.Parent.ClassName + '" of asset "' + Parent.Parent.Parent.AssetName + '" (of class "' + Parent.Parent.Parent.AssetClass.Name + '")');
      end
      else
         Result := FPrimaryChild.Size;
   end
   else
      Result := 0.0;
end;

procedure TOrbitFeatureNode.Walk(PreCallback: TPreWalkCallback; PostCallback: TPostWalkCallback);
var
   Child: TAssetNode;
begin
   if (Assigned(FPrimaryChild)) then
   begin
      // Notably FPrimaryChild is nil when we've detached the primary
      // child in preparation for us being detached and destroyed;
      // when we're detached, we walk the tree and thus get here with
      // a nil FPrimaryChild.
      FPrimaryChild.Walk(PreCallback, PostCallback);
   end;
   for Child in FChildren do
   begin
      Assert(Assigned(Child));
      Child.Walk(PreCallback, PostCallback);
   end;
end;

function TOrbitFeatureNode.ManageBusMessage(Message: TBusMessage): TInjectBusMessageResult;
begin
   if (Message is TPhysicalConnectionBusMessage) then
   begin
      Result := irRejected;
   end
   else
   if (Message is TGetNearestOrbitMessage) then
   begin
      (Message as TGetNearestOrbitMessage).FOrbit := Parent;
      Result := irHandled;
   end
   else
      Result := inherited;
end;

function TOrbitFeatureNode.HandleBusMessage(Message: TBusMessage): THandleBusMessageResult;
var
   Child: TAssetNode;
   ChildHandled: THandleBusMessageResult;
begin
   if (Message is TCrashReportMessage) then
   begin
      Assert(Assigned(FPrimaryChild));
      ChildHandled := FPrimaryChild.HandleBusMessage(Message);
      if (ChildHandled <> hrHandled) then
      begin
         TCrashReportMessage(Message).AddVictim(FPrimaryChild);
      end;
      for Child in FChildren do
      begin
         Assert(Assigned(Child));
         ChildHandled := Child.HandleBusMessage(Message);
         if (ChildHandled <> hrHandled) then
            TCrashReportMessage(Message).AddVictim(Child);
      end;
      Result := hrHandled;
      exit;
   end;
   Result := inherited;
end;

procedure TOrbitFeatureNode.HandleVisibility(const DynastyIndex: Cardinal; var Visibility: TVisibility);
begin
   FPrimaryChild.HandleVisibility(DynastyIndex, Visibility);
end;

procedure TOrbitFeatureNode.CheckVisibilityChanged();
var
   Visible: Boolean;
   DynastyIndex: Cardinal;
   Child: TAssetNode;
begin
   if (System.DynastyCount > 0) then
   begin
      for DynastyIndex := 0 to System.DynastyCount - 1 do // $R-
      begin
         Visible := Parent.IsVisibleFor(DynastyIndex) or FPrimaryChild.IsVisibleFor(DynastyIndex);
         if (not Visible) then
         begin
            for Child in FChildren do
            begin
               Visible := Visible or Child.IsVisibleFor(DynastyIndex);
               if (Visible) then
                  break;
            end;
         end;
         if (Visible) then
         begin
            System.AddSpecificVisibilityByIndex(DynastyIndex, Parent.ReadVisibilityFor(DynastyIndex), FPrimaryChild);
            System.AddSpecificVisibilityByIndex(DynastyIndex, [dmClassKnown] + FPrimaryChild.ReadVisibilityFor(DynastyIndex), Parent);
         end;
      end;
   end;
end;

procedure TOrbitFeatureNode.HandleKnowledge(const DynastyIndex: Cardinal; const Sensors: ISensorsProvider);
begin
   FPrimaryChild.HandleKnowledge(DynastyIndex, Sensors);
end;

function TOrbitFeatureNode.GetOrbitName(): UTF8String;
begin
   {$IFDEF DEBUG}
   if (not Assigned(FPrimaryChild)) then
      Result := '<orphan orbit>'
   else
   {$ENDIF}
   Result := FPrimaryChild.AssetName;
end;

procedure TOrbitFeatureNode.Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter);
var
   Child: TAssetNode;
   Visibility: TVisibility;
begin
   Visibility := Parent.ReadVisibilityFor(DynastyIndex);
   if (Visibility <> []) then
   begin
      Assert(Assigned(FPrimaryChild));
      Writer.WriteCardinal(fcOrbit);
      Assert(FPrimaryChild.IsVisibleFor(DynastyIndex), 'Unexpected inconsistency in visibility between orbit and primary child');
      Writer.WriteCardinal(FPrimaryChild.ID(DynastyIndex));
      for Child in FChildren do
      begin
         Assert(Assigned(Child));
         if (Child.IsVisibleFor(DynastyIndex)) then
         begin
            Writer.WriteCardinal(Child.ID(DynastyIndex));
            Writer.WriteDouble(POrbitData(Child.ParentData)^.SemiMajorAxis);
            Writer.WriteDouble(POrbitData(Child.ParentData)^.Eccentricity);
            Writer.WriteDouble(POrbitData(Child.ParentData)^.Omega);
            Writer.WriteInt64(POrbitData(Child.ParentData)^.TimeOrigin.AsInt64);
            Writer.WriteBoolean(POrbitData(Child.ParentData)^.Clockwise);
         end;
      end;
      Writer.WriteCardinal(0);
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

procedure TOrbitFeatureNode.ApplyJournal(Journal: TJournalReader);

   procedure AddChild();
   var
      Child: TAssetNode;
      SemiMajorAxis, Eccentricity, Omega: Double;
      TimeOrigin: TTimeInMilliseconds;
      Clockwise: Boolean;
   begin
      Child := Journal.ReadAssetNodeReference(System);
      SemiMajorAxis := Journal.ReadDouble();
      Eccentricity := Journal.ReadDouble();
      Omega := Journal.ReadDouble();
      TimeOrigin := TTimeInMilliseconds.FromMilliseconds(Journal.ReadInt64());
      Clockwise := Journal.ReadBoolean();
      AddOrbitingChild(Child, SemiMajorAxis, Eccentricity, Omega, TimeOrigin, Clockwise);
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
      Child := Journal.ReadAssetNodeReference(System);
      SemiMajorAxis := Journal.ReadDouble();
      Eccentricity := Journal.ReadDouble();
      Omega := Journal.ReadDouble();
      TimeOrigin := TTimeInMilliseconds.FromMilliseconds(Journal.ReadInt64());
      Clockwise := Journal.ReadBoolean();
      Index := POrbitData(Child.ParentData)^.Index; // it doesn't change
      UpdateOrbitingChild(Child, SemiMajorAxis, Eccentricity, Omega, TimeOrigin, Clockwise, Index);
      Assert(Child.Parent = Self);
   end;

var
   Child: TAssetNode;
   AssetChangeKind: TAssetChangeKind;
begin
   Child := Journal.ReadAssetNodeReference(System);
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

procedure TOrbitFeatureNode.DescribeExistentiality(var IsDefinitelyReal, IsDefinitelyGhost: Boolean);
begin
   Assert(FPrimaryChild.IsReal()); // TODO: if this is not true, we must not have orbitting children
   IsDefinitelyReal := True;
end;

initialization
   RegisterFeatureClass(TOrbitFeatureClass);
end.