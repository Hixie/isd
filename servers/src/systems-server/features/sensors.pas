{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit sensors;

interface

uses
   systems, serverstream, materials, knowledge;

type
   TSpaceSensorFeatureClass = class(TFeatureClass)
   protected
      FMaxStepsToOrbit, FStepsUpFromOrbit, FStepsDownFromTop: Cardinal;
      FMinSize: Double;
      FSensorKind: TVisibility;
      function GetFeatureNodeClass(): FeatureNodeReference; override;
   public
      constructor Create(AMaxStepsToOrbit, AStepsUpFromOrbit, AStepsDownFromTop: Cardinal; AMinSize: Double; ASensorKind: TVisibility);
      function InitFeatureNode(): TFeatureNode; override;
   end;

   TSpaceSensorFeatureNode = class(TFeatureNode, ISensorsProvider)
   private
      FKnownMaterials: TGetKnownMaterialsMessage;
   protected
      FFeatureClass: TSpaceSensorFeatureClass;
      FLastBottom, FLastTop: TAssetNode;
      FLastCountDetected: Cardinal;
      constructor CreateFromJournal(Journal: TJournalReader; AFeatureClass: TFeatureClass; ASystem: TSystem); override;
      procedure ApplyVisibility(VisibilityHelper: TVisibilityHelper); override;
      procedure Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter; CachedSystem: TSystem); override;
   public
      constructor Create(AFeatureClass: TSpaceSensorFeatureClass);
      procedure UpdateJournal(Journal: TJournalWriter); override;
      procedure ApplyJournal(Journal: TJournalReader; CachedSystem: TSystem); override;
      function Knows(Material: TMaterial): Boolean;
   end;

implementation

uses
   sysutils, orbit, isdprotocol, typedump;

constructor TSpaceSensorFeatureClass.Create(AMaxStepsToOrbit, AStepsUpFromOrbit, AStepsDownFromTop: Cardinal; AMinSize: Double; ASensorKind: TVisibility);
begin
   inherited Create();
   FMaxStepsToOrbit := AMaxStepsToOrbit;
   FStepsUpFromOrbit := AStepsUpFromOrbit;
   FStepsDownFromTop := AStepsDownFromTop;
   FMinSize := AMinSize;
   FSensorKind := ASensorKind;
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
   inherited CreateFromJournal(Journal, AFeatureClass, ASystem);
   Assert(Assigned(AFeatureClass));
   FFeatureClass := AFeatureClass as TSpaceSensorFeatureClass;
end;

procedure TSpaceSensorFeatureNode.ApplyVisibility(VisibilityHelper: TVisibilityHelper);
var
   Depth, Target: Cardinal;
   OwnerIndex: Cardinal;

   function SenseDown(Asset: TAssetNode): Boolean;
   var
      Visibility: TVisibility;
   begin
      if (Asset.Size >= FFeatureClass.FMinSize) then
      begin
         Visibility := FFeatureClass.FSensorKind;
         if ((Asset.Owner = Parent.Owner) or (not Assigned(Asset.Owner)) or Asset.IsReal()) then
         begin
            Asset.HandleVisibility(OwnerIndex, Visibility, Self, VisibilityHelper);
            if (Visibility <> []) then
               Inc(FLastCountDetected);
         end;
      end;
      Result := Depth < Target;
      Inc(Depth);
   end;   

   procedure SenseUp(Asset: TAssetNode);
   begin
      Dec(Depth);
   end;   
      
var
   Index, ActualStepsUp: Cardinal;
   NearestOrbit, Feature: TFeatureNode;
begin
   Assert(not Assigned(FKnownMaterials));
   FLastBottom := nil;
   FLastTop := nil;
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
   NearestOrbit := Feature;
   Index := 0;
   while (Assigned(Feature.Parent.Parent) and (Index < FFeatureClass.FStepsUpFromOrbit)) do
   begin
      Feature := Feature.Parent.Parent;
      Inc(Index);
   end;
   FLastTop := Feature.Parent;
   ActualStepsUp := Index;
   Depth := 0;
   Target := FFeatureClass.FStepsDownFromTop;
   Feature.Parent.Walk(@SenseDown, @SenseUp);
   Assert(Depth = 0);
   if (ActualStepsUp > FFeatureClass.FStepsDownFromTop) then
   begin
      Target := 2;
      Index := ActualStepsUp - FFeatureClass.FStepsDownFromTop; // $R-
      Feature := NearestOrbit;
      while (Index > 0) do
      begin
         Assert(Target = 2);
         Feature.Parent.Walk(@SenseDown, @SenseUp);
         Assert(Depth = 0);
         Feature := Feature.Parent.Parent;
         Dec(Index);
      end;
   end;
   FreeAndNil(FKnownMaterials);
end;

function TSpaceSensorFeatureNode.Knows(Material: TMaterial): Boolean;
begin
   if (not Assigned(FKnownMaterials)) then
   begin
      FKnownMaterials := TGetKnownMaterialsMessage.Create(Parent.Owner);
      InjectBusMessage(FKnownMaterials); // we ignore the result - it doesn't matter if it wasn't handled
   end;
   Result := FKnownMaterials.Knows(Material);
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

procedure TSpaceSensorFeatureNode.UpdateJournal(Journal: TJournalWriter);
begin
end;

procedure TSpaceSensorFeatureNode.ApplyJournal(Journal: TJournalReader; CachedSystem: TSystem);
begin
end;

end.