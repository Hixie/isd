{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit spacesensor;

interface

uses
   systems, serverstream, materials, knowledge, techtree, tttokenizer, sensors;

type
   TSpaceSensorFeatureClass = class(TSensorFeatureClass)
   protected
      FMaxStepsToOrbit, FStepsUpFromOrbit, FStepsDownFromTop: Cardinal;
      FMinSize: Double;
      function GetFeatureNodeClass(): FeatureNodeReference; override;
   public
      constructor Create(AMaxStepsToOrbit, AStepsUpFromOrbit, AStepsDownFromTop: Cardinal; AMinSize: Double; ASensorKind: TVisibility);
      constructor CreateFromTechnologyTree(Reader: TTechTreeReader); override;
      function InitFeatureNode(): TFeatureNode; override;
   end;

   TSpaceSensorFeatureNode = class(TSensorFeatureNode)
   protected
      FFeatureClass: TSpaceSensorFeatureClass;
      FLastBottom, FLastTop: TAssetNode;
      FActualStepsUp: Cardinal;
      constructor CreateFromJournal(Journal: TJournalReader; AFeatureClass: TFeatureClass; ASystem: TSystem); override;
      procedure ApplyVisibility(const VisibilityHelper: TVisibilityHelper); override;
      procedure ApplyKnowledge(const VisibilityHelper: TVisibilityHelper); override;
      procedure Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter; CachedSystem: TSystem); override;
   public
      constructor Create(AFeatureClass: TSpaceSensorFeatureClass);
   end;

implementation

uses
   sysutils, orbit, isdprotocol, typedump;

constructor TSpaceSensorFeatureClass.Create(AMaxStepsToOrbit, AStepsUpFromOrbit, AStepsDownFromTop: Cardinal; AMinSize: Double; ASensorKind: TVisibility);
begin
   inherited Create(ASensorKind);
   FMaxStepsToOrbit := AMaxStepsToOrbit;
   FStepsUpFromOrbit := AStepsUpFromOrbit;
   FStepsDownFromTop := AStepsDownFromTop;
   FMinSize := AMinSize;
end;

constructor TSpaceSensorFeatureClass.CreateFromTechnologyTree(Reader: TTechTreeReader);
begin
   FMaxStepsToOrbit := ReadNumber(Reader.Tokens, Low(FMaxStepsToOrbit), High(FMaxStepsToOrbit)); // $R-
   Reader.Tokens.ReadIdentifier('to');
   Reader.Tokens.ReadIdentifier('orbit');
   Reader.Tokens.ReadComma();
   Reader.Tokens.ReadIdentifier('up');
   FStepsUpFromOrbit := ReadNumber(Reader.Tokens, Low(FStepsUpFromOrbit), High(FStepsUpFromOrbit)); // $R-
   Reader.Tokens.ReadIdentifier('down');
   FStepsDownFromTop := ReadNumber(Reader.Tokens, Low(FStepsDownFromTop), High(FStepsDownFromTop)); // $R-
   Reader.Tokens.ReadComma();
   Reader.Tokens.ReadIdentifier('min');
   Reader.Tokens.ReadIdentifier('size');
   FMinSize := ReadLength(Reader.Tokens);
   inherited CreateFromTechnologyTree(Reader);
end;

function TSpaceSensorFeatureClass.GetFeatureNodeClass(): FeatureNodeReference;
begin
   Result := TSpaceSensorFeatureNode;
end;

function TSpaceSensorFeatureClass.InitFeatureNode(): TFeatureNode;
begin
   Result := TSpaceSensorFeatureNode.Create(Self);
end;


constructor TSpaceSensorFeatureNode.Create(AFeatureClass: TSpaceSensorFeatureClass);
begin
   inherited Create();
   FFeatureClass := AFeatureClass;
end;

constructor TSpaceSensorFeatureNode.CreateFromJournal(Journal: TJournalReader; AFeatureClass: TFeatureClass; ASystem: TSystem);
begin
   Assert(Assigned(AFeatureClass));
   FFeatureClass := AFeatureClass as TSpaceSensorFeatureClass;
   inherited CreateFromJournal(Journal, AFeatureClass, ASystem);
end;

procedure TSpaceSensorFeatureNode.ApplyVisibility(const VisibilityHelper: TVisibilityHelper);
var
   Depth, Target: Cardinal;
   OwnerIndex: Cardinal;

   function SenseDown(Asset: TAssetNode): Boolean;
   var
      Visibility: TVisibility;
   begin
      if ((Asset.Size >= FFeatureClass.FMinSize) and // must be big enough
          ((Asset.Owner = Parent.Owner) or // we see our own ghosts
           (not Assigned(Asset.Owner)) or // we see unowned ghosts // TODO: this should be redundant, assert instead?
           Asset.IsReal())) then // and we see non-ghosts regardless of who owns them
      begin
         Writeln('  - ', Asset.DebugName);
         Visibility := FFeatureClass.FSensorKind;
         Asset.HandleVisibility(OwnerIndex, Visibility, VisibilityHelper);
         if (Visibility <> []) then
            Inc(FLastCountDetected)
         else
            Writeln('    DENIED');
      end;
      Result := Depth < Target;
      Inc(Depth);
   end;

   procedure SenseUp(Asset: TAssetNode);
   begin
      Dec(Depth);
   end;

var
   Index: Cardinal;
   Feature: TFeatureNode;
   Node: TAssetNode;
begin
   Writeln('Space Sensor for ', Parent.DebugName);
   Assert(not Assigned(FKnownMaterials));
   Assert(not Assigned(FKnownAssetClasses));
   FLastBottom := nil;
   FLastTop := nil;
   FActualStepsUp := 0;
   FLastCountDetected := 0;
   if (not Assigned(Parent.Owner)) then
      exit; // no dynasty owns this sensor, nothing to apply
   OwnerIndex := VisibilityHelper.GetDynastyIndex(Parent.Owner);
   Feature := Self;
   Index := 0;
   while (Assigned(Feature) and not (Feature is TOrbitFeatureNode) and (Index < FFeatureClass.FMaxStepsToOrbit)) do
   begin
      Feature := Feature.Parent.Parent;
      Inc(Index);
   end;
   if (not (Feature is TOrbitFeatureNode)) then
      exit; // could not find orbits within allowed range
   FLastBottom := Feature.Parent;
   Index := 0;
   while (Assigned(Feature.Parent.Parent) and (Index < FFeatureClass.FStepsUpFromOrbit)) do
   begin
      Feature := Feature.Parent.Parent;
      Inc(Index);
   end;
   FLastTop := Feature.Parent;
   FActualStepsUp := Index;
   Depth := 0;
   Target := FFeatureClass.FStepsDownFromTop;
   FLastTop.Walk(@SenseDown, @SenseUp);
   Assert(Depth = 0);
   if (FActualStepsUp > FFeatureClass.FStepsDownFromTop) then
   begin
      Target := 2;
      Index := FActualStepsUp - FFeatureClass.FStepsDownFromTop; // $R-
      Node := FLastBottom;
      while (Index > 0) do
      begin
         Assert(Target = 2);
         Node.Walk(@SenseDown, @SenseUp);
         Assert(Depth = 0);
         Node := Node.Parent.Parent;
         Dec(Index);
      end;
   end;
   Assert(not Assigned(FKnownMaterials));
   Assert(not Assigned(FKnownAssetClasses));
end;

procedure TSpaceSensorFeatureNode.ApplyKnowledge(const VisibilityHelper: TVisibilityHelper);
var
   Depth, Target: Cardinal;
   OwnerIndex: Cardinal;

   function SenseDown(Asset: TAssetNode): Boolean;
   begin
      if ((Asset.Size >= FFeatureClass.FMinSize) and // must be big enough
          ((Asset.Owner = Parent.Owner) or // we see our own ghosts
           (not Assigned(Asset.Owner)) or // we see unowned ghosts // TODO: this should be redundant, assert instead?
           Asset.IsReal())) then // and we see non-ghosts regardless of who owns them
      begin
         if (Asset.IsVisibleFor(OwnerIndex, VisibilityHelper.System)) then
            Asset.HandleKnowledge(OwnerIndex, VisibilityHelper, Self);
      end;
      Result := Depth < Target;
      Inc(Depth);
   end;

   procedure SenseUp(Asset: TAssetNode);
   begin
      Dec(Depth);
   end;

var
   Index: Cardinal;
   Node: TAssetNode;
begin
   Assert(not Assigned(FKnownMaterials));
   Assert(not Assigned(FKnownAssetClasses));
   if (not Assigned(FLastBottom)) then
      exit;
   Assert(Assigned(FLastTop));
   OwnerIndex := VisibilityHelper.GetDynastyIndex(Parent.Owner);
   Depth := 0;
   Target := FFeatureClass.FStepsDownFromTop;
   FLastTop.Walk(@SenseDown, @SenseUp);
   Assert(Depth = 0);
   if (FActualStepsUp > FFeatureClass.FStepsDownFromTop) then
   begin
      Target := 2;
      Index := FActualStepsUp - FFeatureClass.FStepsDownFromTop; // $R-
      Node := FLastBottom;
      while (Index > 0) do
      begin
         Assert(Target = 2);
         Node.Walk(@SenseDown, @SenseUp);
         Assert(Depth = 0);
         Node := Node.Parent.Parent;
         Dec(Index);
      end;
   end;
   FreeAndNil(FKnownMaterials);
   FreeAndNil(FKnownAssetClasses);
end;

procedure TSpaceSensorFeatureNode.Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter; CachedSystem: TSystem);
var
   Visibility: TVisibility;
begin
   Visibility := Parent.ReadVisibilityFor(DynastyIndex, CachedSystem);
   if ((dmDetectable * Visibility <> []) and (dmClassKnown in Visibility)) then
   begin
      Writer.WriteCardinal(fcSpaceSensor);
      Writer.WriteCardinal(FFeatureClass.FMaxStepsToOrbit);
      Writer.WriteCardinal(FFeatureClass.FStepsUpFromOrbit);
      Writer.WriteCardinal(FFeatureClass.FStepsDownFromTop);
      Writer.WriteDouble(FFeatureClass.FMinSize);
      if (dmInternals in Visibility) then
      begin
         Writer.WriteCardinal(fcSpaceSensorStatus);
         Writer.WriteCardinal(FLastBottom.ID(CachedSystem, DynastyIndex));
         Writer.WriteCardinal(FLastTop.ID(CachedSystem, DynastyIndex));
         Writer.WriteCardinal(FLastCountDetected);
      end;
   end;
end;

initialization
   RegisterFeatureClass(TSpaceSensorFeatureClass);
end.