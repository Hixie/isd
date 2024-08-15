{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit space;

interface

uses
   systems, providers, serverstream;

type
   TSolarSystemFeatureClass = class(TFeatureClass)
   strict protected
      function GetFeatureNodeClass(): FeatureNodeReference; override;
   protected
      FStarGroupingThreshold: Double;
   public
      constructor Create(AStarGroupingThreshold: Double);
      function InitFeatureNode(): TFeatureNode; override;
   end;

   TSolarSystemFeatureNode = class(TFeatureNode, IAssetNameProvider)
   private
      FFeatureClass: TSolarSystemFeatureClass;
      FChildren: array of TAssetNode;
      function GetChild(Index: Cardinal): TAssetNode;
      function GetChildCount(): Cardinal;
      function GetFurthestDistanceFromCenter(): Double;
   protected
      constructor CreateFromJournal(Journal: TJournalReader; AFeatureClass: TFeatureClass); override;
      procedure AdoptSolarSystemChild(Child: TAssetNode);
      procedure DropSolarSystemChild(Child: TAssetNode);
      procedure MarkAsDirty(DirtyKinds: TDirtyKinds; ChangeKinds: TChangeKinds); override;
      function GetMass(): Double; override;
      function GetSize(): Double; override;
      function GetFeatureName(): UTF8String; override;
      procedure Walk(PreCallback: TPreWalkCallback; PostCallback: TPostWalkCallback); override;
      procedure ApplyVisibility(VisibilityHelper: TVisibilityHelper); override;
      procedure Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter; System: TSystem); override;
   public
      constructor Create(AFeatureClass: TSolarSystemFeatureClass);
      destructor Destroy(); override;
      procedure RecordSnapshot(Journal: TJournalWriter); override;
      procedure ApplyJournal(Journal: TJournalReader); override;
      procedure AddCartesianChild(Child: TAssetNode; X, Y: Double); // meters, first must be at 0,0
      procedure AddPolarChild(Child: TAssetNode; Distance, Theta: Double); // meters
      function GetAssetName(): UTF8String;
      property Children[Index: Cardinal]: TAssetNode read GetChild;
      property ChildCount: Cardinal read GetChildCount;
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
   PSolarSystemData = ^TSolarSystemData;
   TSolarSystemData = record
      DistanceFromCenter: Double; // meters
      Theta: Double; // radians clockwise from positive x axis
   end;

constructor TSolarSystemFeatureClass.Create(AStarGroupingThreshold: Double);
begin
   inherited Create();
   FStarGroupingThreshold := AStarGroupingThreshold;
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

constructor TSolarSystemFeatureNode.CreateFromJournal(Journal: TJournalReader; AFeatureClass: TFeatureClass);
begin
   inherited CreateFromJournal(Journal, AFeatureClass);
   Assert(Assigned(AFeatureClass));
   FFeatureClass := AFeatureClass as TSolarSystemFeatureClass;
end;

destructor TSolarSystemFeatureNode.Destroy();
var
   Child: TAssetNode;
begin
   for Child in FChildren do
   begin
      DropSolarSystemChild(Child);
      Child.Free();
   end;
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
   Assert(Length(FChildren) > 0);
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

procedure TSolarSystemFeatureNode.AdoptSolarSystemChild(Child: TAssetNode);
begin
   AdoptChild(Child);
   Child.ParentData := New(PSolarSystemData);
end;

procedure TSolarSystemFeatureNode.DropSolarSystemChild(Child: TAssetNode);
begin
   Dispose(PSolarSystemData(Child.ParentData));
   Child.ParentData := nil;
   DropChild(Child);
   if (Length(FChildren) = 0) then
      MarkAsDirty([dkSelf], [ckAffectsNames]);
end;

procedure TSolarSystemFeatureNode.AddCartesianChild(Child: TAssetNode; X, Y: Double); // meters, first must be at 0,0
begin
   Assert(Child.AssetClass.ID = idOrbits);
   AdoptSolarSystemChild(Child);
   if (Length(FChildren) = 0) then
   begin
      Assert(X = 0.0);
      Assert(Y = 0.0);
      SetLength(FChildren, 1);
      FChildren[0] := Child;
      PSolarSystemData(Child.ParentData)^.DistanceFromCenter := 0.0;
      PSolarSystemData(Child.ParentData)^.Theta := 0.0;
   end
   else
   begin
      SetLength(FChildren, Length(FChildren)+1);
      FChildren[High(FChildren)] := Child;
      PSolarSystemData(Child.ParentData)^.DistanceFromCenter := SqRt(X*X+Y*Y);
      if (X = 0) then
      begin
         if (Y = 0) then
         begin
            PSolarSystemData(Child.ParentData)^.Theta := 0.0;
         end
         else
         if (Y >= 0) then
         begin
            PSolarSystemData(Child.ParentData)^.Theta := Pi; // $R-
         end
         else
         begin
            PSolarSystemData(Child.ParentData)^.Theta := 3.0 * Pi / 2.0; // $R-
         end;
      end
      else
      begin
         PSolarSystemData(Child.ParentData)^.Theta := ArcTan2(Y, X); // $R-
      end;
   end;
end;

procedure TSolarSystemFeatureNode.AddPolarChild(Child: TAssetNode; Distance, Theta: Double); // meters
begin
   Assert(Child.AssetClass.ID = idOrbits);
   AdoptSolarSystemChild(Child);
   SetLength(FChildren, Length(FChildren)+1);
   FChildren[High(FChildren)] := Child;
   PSolarSystemData(Child.ParentData)^.DistanceFromCenter := Distance;
   PSolarSystemData(Child.ParentData)^.Theta := Theta;
end;

procedure TSolarSystemFeatureNode.MarkAsDirty(DirtyKinds: TDirtyKinds; ChangeKinds: TChangeKinds);
begin
   if (ckAffectsNames in ChangeKinds) then
      Include(DirtyKinds, dkSelf);
   inherited;
end;

function TSolarSystemFeatureNode.GetMass(): Double;
var
   Index: Cardinal;
begin
   Result := 0.0;
   if (ChildCount > 0) then
      for Index := 0 to ChildCount-1 do // $R-
         Result := Result + Children[Index].Mass;
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

function TSolarSystemFeatureNode.GetFeatureName(): UTF8String;
begin
   Result := '';
end;

procedure TSolarSystemFeatureNode.Walk(PreCallback: TPreWalkCallback; PostCallback: TPostWalkCallback);
var
   Child: TAssetNode;
begin
   for Child in FChildren do
      Child.Walk(PreCallback, PostCallback);
end;

procedure TSolarSystemFeatureNode.ApplyVisibility(VisibilityHelper: TVisibilityHelper);
begin
   Assert(Assigned(Parent));
   VisibilityHelper.AddBroadVisibility([dmVisibleSpectrum, dmClassKnown], Parent);
end;

procedure TSolarSystemFeatureNode.Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter; System: TSystem);
var
   Child: TAssetNode;
   Index: Cardinal;
begin
   Writer.WriteCardinal(fcSpace);
   Assert(Length(FChildren) > 0);
   Writer.WritePtrUInt(FChildren[0].ID(System));
   Writer.WriteCardinal(Length(FChildren) - 1); // $R-
   if (Length(FChildren) > 1) then
      for Index := 1 to Length(FChildren) - 1 do // $R-
      begin
         Child := FChildren[Index];
         Writer.WriteDouble(PSolarSystemData(Child.ParentData)^.DistanceFromCenter);
         Writer.WriteDouble(PSolarSystemData(Child.ParentData)^.Theta);
         Writer.WritePtrUInt(Child.ID(System));
      end;
end;

procedure TSolarSystemFeatureNode.RecordSnapshot(Journal: TJournalWriter);
var
   Child: TAssetNode;
begin
   Journal.WriteCardinal(Length(FChildren));
   for Child in FChildren do
   begin
      Journal.WriteAssetChangeKind(ckAdd);
      Journal.WriteAssetNodeReference(Child);
      Journal.WriteDouble(PSolarSystemData(Child.ParentData)^.DistanceFromCenter);
      Journal.WriteDouble(PSolarSystemData(Child.ParentData)^.Theta);
   end;
end;

procedure TSolarSystemFeatureNode.ApplyJournal(Journal: TJournalReader);

   procedure AddChild();
   var
      AssetNode: TAssetNode;
      Distance, Theta: Double;
   begin
      AssetNode := Journal.ReadAssetNodeReference();
      Distance := Journal.ReadDouble();
      Theta := Journal.ReadDouble();
      AddPolarChild(AssetNode, Distance, Theta);
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
   AssetChangeKind: TAssetChangeKind;
begin
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

function TSolarSystemFeatureNode.GetAssetName(): UTF8String;
begin
   if (Length(FChildren) > 0) then
   begin
      Result := FChildren[0].AssetName;
   end
   else
   begin
      Result := 'Unchartered space'; // TODO: find a better name for this? "Sector 13" or whatever
   end;
end;

end.