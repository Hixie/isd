{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit space;

interface

uses
   systems, providers, serverstream, techtree, time;

type
   TSolarSystemFeatureClass = class(TFeatureClass)
   strict protected
      function GetFeatureNodeClass(): FeatureNodeReference; override;
   protected
      FStarGroupingThreshold: Double;
      FGravitionalInfluenceConstant: Double;
   public
      constructor Create(AStarGroupingThreshold: Double; AGravitionalInfluenceConstant: Double);
      constructor CreateFromTechnologyTree(Reader: TTechTreeReader); override;
      function InitFeatureNode(): TFeatureNode; override;
   end;

   TSolarSystemFeatureNode = class(TFeatureNode, IAssetNameProvider, IHillDiameterProvider)
   private
      FFeatureClass: TSolarSystemFeatureClass;
      FChildren: TAssetNode.TArray;
      function GetChild(Index: Cardinal): TAssetNode;
      function GetChildCount(): Cardinal;
      function GetFurthestDistanceFromCenter(): Double;
   protected
      constructor CreateFromJournal(Journal: TJournalReader; AFeatureClass: TFeatureClass; ASystem: TSystem); override;
      procedure AdoptSolarSystemChild(Child: TAssetNode; DistanceFromCenter, Theta, HillDiameter: Double);
      procedure DropChild(Child: TAssetNode); override;
      procedure ParentMarkedAsDirty(ParentDirtyKinds, NewDirtyKinds: TDirtyKinds); override;
      procedure AddPolarChildFromJournal(Child: TAssetNode; Distance, Theta, HillDiameter: Double); // meters
      function GetMass(): Double; override;
      function GetMassFlowRate(): TRate; override;
      function GetSize(): Double; override;
      procedure Walk(PreCallback: TPreWalkCallback; PostCallback: TPostWalkCallback); override;
      function HandleBusMessage(Message: TBusMessage): Boolean; override;
      procedure ApplyVisibility(const VisibilityHelper: TVisibilityHelper); override;
      procedure Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter; CachedSystem: TSystem); override;
   public
      constructor Create(AFeatureClass: TSolarSystemFeatureClass);
      destructor Destroy(); override;
      procedure UpdateJournal(Journal: TJournalWriter; CachedSystem: TSystem); override;
      procedure ApplyJournal(Journal: TJournalReader; CachedSystem: TSystem); override;
      procedure AddCartesianChild(Child: TAssetNode; X, Y: Double); // meters, first must be at 0,0; call ComputeHillSpheres after calling AddCartesianChild for all children // marks the child as new
      procedure ComputeHillSpheres(); // call this after all stars have been added
      function GetAssetName(): UTF8String;
      function GetHillDiameter(Child: TAssetNode; ChildPrimaryMass: Double): Double;
      procedure DescribeExistentiality(var IsDefinitelyReal, IsDefinitelyGhost: Boolean); override;
      property Children[Index: Cardinal]: TAssetNode read GetChild; // child might be nil
      property ChildCount: Cardinal read GetChildCount; // some of the children might be nil
   end;

   // TODO: some different kind of system for handling lone space
   // ships traveling in real space across the galaxy.
   //
   // TEmptySpaceChild = record // 40 bytes
   //    Child: TAssetNode;
   //    DistanceFromCenter: Double; // meters at time zero
   //    Theta: Double; // radians clockwise from positive x axis at time zero
   //    TimeZero: TTime;
   //    Direction: Double; // radians clockwise from positive x axis
   //    Velocity: Double; // meters per second at time zero
   //    Acceleration: Double; // meters per second per second
   // end;

implementation

uses
   math, isdprotocol, encyclopedia;

type
   TSolarSystemJournalState = (jsNew, jsChanged);
   TSolarSystemJournalStates = set of TSolarSystemJournalState;

   PSolarSystemData = ^TSolarSystemData;
   TSolarSystemData = record
      DistanceFromCenter: Double; // meters
      Theta: Double; // radians clockwise from positive x axis
      HillDiameter: Double; // meters
      Flags: TSolarSystemJournalStates;
      Index: Cardinal;
   end;

constructor TSolarSystemFeatureClass.Create(AStarGroupingThreshold: Double; AGravitionalInfluenceConstant: Double);
begin
   inherited Create();
   FStarGroupingThreshold := AStarGroupingThreshold;
   FGravitionalInfluenceConstant := AGravitionalInfluenceConstant;
end;

constructor TSolarSystemFeatureClass.CreateFromTechnologyTree(Reader: TTechTreeReader);
begin
   inherited Create();
   Reader.Tokens.ReadIdentifier('group');
   Reader.Tokens.ReadIdentifier('threshold');
   FStarGroupingThreshold := ReadLength(Reader.Tokens);
   Reader.Tokens.ReadComma();
   Reader.Tokens.ReadIdentifier('gravitational');
   Reader.Tokens.ReadIdentifier('influence');
   FGravitionalInfluenceConstant := ReadNumber(Reader.Tokens, 0, High(Int64));
end;

function TSolarSystemFeatureClass.GetFeatureNodeClass(): FeatureNodeReference;
begin
   Result := TSolarSystemFeatureNode;
end;

function TSolarSystemFeatureClass.InitFeatureNode(): TFeatureNode;
begin
   Result := TSolarSystemFeatureNode.Create(Self);
end;


constructor TSolarSystemFeatureNode.Create(AFeatureClass: TSolarSystemFeatureClass);
begin
   inherited Create();
   FFeatureClass := AFeatureClass;
end;

constructor TSolarSystemFeatureNode.CreateFromJournal(Journal: TJournalReader; AFeatureClass: TFeatureClass; ASystem: TSystem);
begin
   Assert(Assigned(AFeatureClass));
   FFeatureClass := AFeatureClass as TSolarSystemFeatureClass;
   inherited CreateFromJournal(Journal, AFeatureClass, ASystem);
end;

destructor TSolarSystemFeatureNode.Destroy();
var
   Child: TAssetNode;
begin
   for Child in FChildren do
      Child.Free();
   inherited;
end;

function TSolarSystemFeatureNode.GetChild(Index: Cardinal): TAssetNode;
begin
   Result := FChildren[Index];
end;

function TSolarSystemFeatureNode.GetChildCount(): Cardinal;
begin
   Result := Length(FChildren); // $R-
end;

function TSolarSystemFeatureNode.GetFurthestDistanceFromCenter(): Double;
var
   Index: Cardinal;
   Distance: Double;
begin
   // TODO: handle the case of the first child not being at the center
   Assert(Length(FChildren) > 0);
   Assert(Assigned(FChildren[0])); // this assert is not theoretically sound, but currently it is true
   Assert(PSolarSystemData(FChildren[0].ParentData)^.DistanceFromCenter = 0);
   Result := 0.0;
   if (Length(FChildren) > 1) then
   begin
      for Index := 1 to High(FChildren) do // $R-
      begin
          Distance := PSolarSystemData(FChildren[Index].ParentData)^.DistanceFromCenter;
          Assert(Distance > 0);
          if (Distance > Result) then
          begin
             Result := Distance;
          end;
       end;
   end;
end;

procedure TSolarSystemFeatureNode.AdoptSolarSystemChild(Child: TAssetNode; DistanceFromCenter, Theta, HillDiameter: Double);
begin
   SetLength(FChildren, Length(FChildren)+1);
   FChildren[High(FChildren)] := Child;
   AdoptChild(Child);
   Child.ParentData := New(PSolarSystemData);
   PSolarSystemData(Child.ParentData)^.DistanceFromCenter := DistanceFromCenter;
   PSolarSystemData(Child.ParentData)^.Theta := Theta;
   PSolarSystemData(Child.ParentData)^.HillDiameter := HillDiameter;
   PSolarSystemData(Child.ParentData)^.Flags := [jsNew, jsChanged];
   PSolarSystemData(Child.ParentData)^.Index := High(FChildren); // $R-
end;

procedure TSolarSystemFeatureNode.DropChild(Child: TAssetNode);
var
   Index: Cardinal;
begin
   Delete(FChildren, PSolarSystemData(Child.ParentData)^.Index, 1);
   if (PSolarSystemData(Child.ParentData)^.Index < Length(FChildren)) then
      for Index := PSolarSystemData(Child.ParentData)^.Index to High(FChildren) do // $R-
         PSolarSystemData(FChildren[Index].ParentData)^.Index := Index;
   Dispose(PSolarSystemData(Child.ParentData));
   Child.ParentData := nil;
   inherited;
   if (Length(FChildren) = 0) then // TODO: why only when we get to zero?
      MarkAsDirty([dkUpdateClients, dkUpdateJournal, dkAffectsNames]); // TODO: other things (than running out of children entirely) might affect the name too?
end;

procedure TSolarSystemFeatureNode.AddCartesianChild(Child: TAssetNode; X, Y: Double); // meters, first must be at 0,0 // TODO: change that
var
   DistanceFromCenter, Theta: Double;
begin
   Assert(Child.AssetClass.ID = idOrbits);
   if (Length(FChildren) = 0) then
   begin
      // TODO: this is not valid
      Assert(X = 0.0);
      Assert(Y = 0.0);
      DistanceFromCenter := 0.0;
      Theta := 0.0;
   end
   else
   begin
      DistanceFromCenter := SqRt(X*X+Y*Y);
      if (X = 0) then
      begin
         if (Y = 0) then
         begin
            Theta := 0.0;
         end
         else
         if (Y >= 0) then
         begin
            Theta := Pi; // $R-
         end
         else
         begin
            Theta := 3.0 * Pi / 2.0; // $R-
         end;
      end
      else
      begin
         Theta := ArcTan2(Y, X); // $R-
      end;
   end;
   AdoptSolarSystemChild(Child, DistanceFromCenter, Theta, NaN);
end;

procedure TSolarSystemFeatureNode.AddPolarChildFromJournal(Child: TAssetNode; Distance, Theta, HillDiameter: Double); // meters
begin
   Assert(Child.AssetClass.ID = idOrbits);
   AdoptSolarSystemChild(Child, Distance, Theta, HillDiameter);
end;

procedure TSolarSystemFeatureNode.ParentMarkedAsDirty(ParentDirtyKinds, NewDirtyKinds: TDirtyKinds);
begin
   if (dkChildAffectsNames in NewDirtyKinds) then
      MarkAsDirty([dkUpdateClients, dkUpdateJournal, dkAffectsNames]);
   inherited;
end;

function TSolarSystemFeatureNode.GetMass(): Double;
var
   Child: TAssetNode;
begin
   Result := 0.0;
   for Child in FChildren do
      Result := Result + Child.Mass;
end;

function TSolarSystemFeatureNode.GetMassFlowRate(): TRate;
var
   Child: TAssetNode;
begin
   Result := TRate.Zero;
   for Child in FChildren do
      Result := Result + Child.MassFlowRate;
end;

function TSolarSystemFeatureNode.GetSize(): Double;
begin
   // The _radius_ of a solar system is the distance from the center
   // to the furthest star plus half the distance that would lead you
   // to the next system (because the next system is similarly going
   // to have that kind of padding). The diameter (our size) is twice
   // that. Hence:
   Result := GetFurthestDistanceFromCenter() * 2.0 + FFeatureClass.FStarGroupingThreshold;
end;

procedure TSolarSystemFeatureNode.Walk(PreCallback: TPreWalkCallback; PostCallback: TPostWalkCallback);
var
   Child: TAssetNode;
begin
   for Child in FChildren do
      Child.Walk(PreCallback, PostCallback);
end;

function TSolarSystemFeatureNode.HandleBusMessage(Message: TBusMessage): Boolean;
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

procedure TSolarSystemFeatureNode.ApplyVisibility(const VisibilityHelper: TVisibilityHelper);
begin
   Assert(Assigned(Parent));
   Writeln(DebugName, ' is always known.');
   VisibilityHelper.AddBroadVisibility([dmVisibleSpectrum, dmClassKnown], Parent);
end;

procedure TSolarSystemFeatureNode.Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter; CachedSystem: TSystem);
var
   Child: TAssetNode;
   Index: Cardinal;
begin
   // TODO: the first child might not be at the origin
   Writer.WriteCardinal(fcSpace);
   Assert(Length(FChildren) > 0); // otherwise who are we reporting this to?
   Assert(Assigned(FChildren[0]));
   Writer.WriteCardinal(FChildren[0].ID(CachedSystem, DynastyIndex)); // TODO: only if visible
   if (Length(FChildren) > 1) then
      for Index := 1 to Length(FChildren) - 1 do // $R-
      begin
         Child := FChildren[Index];
         Assert(Assigned(Child));
         if (Child.IsVisibleFor(DynastyIndex, CachedSystem)) then
         begin
            Writer.WriteCardinal(Child.ID(CachedSystem, DynastyIndex));
            Writer.WriteDouble(PSolarSystemData(Child.ParentData)^.DistanceFromCenter);
            Writer.WriteDouble(PSolarSystemData(Child.ParentData)^.Theta);
         end;
      end;
   Writer.WriteCardinal(0);
end;

procedure TSolarSystemFeatureNode.UpdateJournal(Journal: TJournalWriter; CachedSystem: TSystem);
var
   Child: TAssetNode;
begin
   if (Length(FChildren) > 0) then
   begin
      for Child in FChildren do
      begin
         Assert(Assigned(Child));
         if (jsChanged in PSolarSystemData(Child.ParentData)^.Flags) then
         begin
            if (jsNew in PSolarSystemData(Child.ParentData)^.Flags) then
            begin
               Journal.WriteAssetChangeKind(ckAdd);
               Exclude(PSolarSystemData(Child.ParentData)^.Flags, jsNew);
            end
            else
            begin
               Journal.WriteAssetChangeKind(ckChange);
            end;
            Journal.WriteAssetNodeReference(Child);
            Journal.WriteDouble(PSolarSystemData(Child.ParentData)^.DistanceFromCenter);
            Journal.WriteDouble(PSolarSystemData(Child.ParentData)^.Theta);
            Journal.WriteDouble(PSolarSystemData(Child.ParentData)^.HillDiameter);
            Exclude(PSolarSystemData(Child.ParentData)^.Flags, jsChanged);
         end;
      end;
   end;
   Journal.WriteAssetChangeKind(ckEndOfList);
end;

procedure TSolarSystemFeatureNode.ApplyJournal(Journal: TJournalReader; CachedSystem: TSystem);

   procedure AddChild();
   var
      AssetNode: TAssetNode;
      Distance, Theta, HillDiameter: Double;
   begin
      AssetNode := Journal.ReadAssetNodeReference();
      Distance := Journal.ReadDouble();
      Theta := Journal.ReadDouble();
      HillDiameter := Journal.ReadDouble();
      AddPolarChildFromJournal(AssetNode, Distance, Theta, HillDiameter);
   end;

   procedure ChangeChild();
   var
      Child: TAssetNode;
      Distance, Theta, HillDiameter: Double;
   begin
      Child := Journal.ReadAssetNodeReference();
      Distance := Journal.ReadDouble();
      Theta := Journal.ReadDouble();
      HillDiameter := Journal.ReadDouble();
      PSolarSystemData(Child.ParentData)^.DistanceFromCenter := Distance;
      PSolarSystemData(Child.ParentData)^.Theta := Theta;
      PSolarSystemData(Child.ParentData)^.HillDiameter := HillDiameter;
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

procedure TSolarSystemFeatureNode.ComputeHillSpheres();

   function ComputeDistance(Child1, Child2: TAssetNode): Double; inline;
   var
      R1, R2, Theta1, Theta2: Double;
   begin
      R1 := PSolarSystemData(Child1.ParentData)^.DistanceFromCenter;
      Theta1 := PSolarSystemData(Child1.ParentData)^.Theta;
      R2 := PSolarSystemData(Child2.ParentData)^.DistanceFromCenter;
      Theta2 := PSolarSystemData(Child2.ParentData)^.Theta;
      Result := Sqrt(R1 * R1 + R2 * R2 - 2 * R1 * R2 * Cos(Theta1 - Theta2)); // $R-
   end;

var
   CandidateHillRadius: Double;
   MaxRadius: Double;
   HalfDistance: Double;
   Index, SubIndex: Cardinal;
begin
   Assert(Length(FChildren) > 0);
   MaxRadius := FFeatureClass.FStarGroupingThreshold / 2.0;
   for Index := Low(FChildren) to High(FChildren) do // $R-
   begin
      CandidateHillRadius := FChildren[Index].Mass * FFeatureClass.FGravitionalInfluenceConstant / 2.0;
      if (CandidateHillRadius > MaxRadius) then
         CandidateHillRadius := MaxRadius;
      for SubIndex := Low(FChildren) to High(FChildren) do // $R-
      begin
         if ((Index <> SubIndex) and Assigned(FChildren[SubIndex])) then
         begin
            HalfDistance := ComputeDistance(FChildren[Index], FChildren[SubIndex]) / 2.0;
            if (CandidateHillRadius > HalfDistance) then
               CandidateHillRadius := HalfDistance;
         end;
      end;
      PSolarSystemData(FChildren[Index].ParentData)^.HillDiameter := CandidateHillRadius * 2.0;
   end;
end;

function TSolarSystemFeatureNode.GetAssetName(): UTF8String;
begin
   if (Length(FChildren) > 0) then
   begin
      Assert(Assigned(FChildren[0])); // TODO: this assert is invalid
      Result := FChildren[0].AssetName;
   end
   else
   begin
      Result := 'Unchartered space'; // TODO: find a better name for this? "Sector 13" or whatever
   end;
end;

function TSolarSystemFeatureNode.GetHillDiameter(Child: TAssetNode; ChildPrimaryMass: Double): Double;
begin
   Result := PSolarSystemData(Child.ParentData)^.HillDiameter;
end;

procedure TSolarSystemFeatureNode.DescribeExistentiality(var IsDefinitelyReal, IsDefinitelyGhost: Boolean);
begin
   IsDefinitelyReal := True;
end;

initialization
   RegisterFeatureClass(TSolarSystemFeatureClass);
end.