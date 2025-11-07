{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit internalsensor;

interface

uses
   systems, serverstream, materials, knowledge, techtree, sensors;

type
   TInternalSensorFeatureClass = class(TSensorFeatureClass)
   protected
      function GetFeatureNodeClass(): FeatureNodeReference; override;
   public
      function InitFeatureNode(): TFeatureNode; override;
   end;

   TInternalSensorFeatureNode = class(TSensorFeatureNode)
   protected
      FFeatureClass: TInternalSensorFeatureClass;
      constructor CreateFromJournal(Journal: TJournalReader; AFeatureClass: TFeatureClass; ASystem: TSystem); override;
      procedure ApplyVisibility(const VisibilityHelper: TVisibilityHelper); override;
      procedure ApplyKnowledge(const VisibilityHelper: TVisibilityHelper); override;
      procedure Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter; CachedSystem: TSystem); override;
   public
      constructor Create(AFeatureClass: TInternalSensorFeatureClass);
   end;

implementation

uses
   sysutils, orbit, isdprotocol, typedump;

function TInternalSensorFeatureClass.GetFeatureNodeClass(): FeatureNodeReference;
begin
   Result := TInternalSensorFeatureNode;
end;

function TInternalSensorFeatureClass.InitFeatureNode(): TFeatureNode;
begin
   Result := TInternalSensorFeatureNode.Create(Self);
end;


constructor TInternalSensorFeatureNode.Create(AFeatureClass: TInternalSensorFeatureClass);
begin
   inherited Create();
   FFeatureClass := AFeatureClass;
end;

constructor TInternalSensorFeatureNode.CreateFromJournal(Journal: TJournalReader; AFeatureClass: TFeatureClass; ASystem: TSystem);
begin
   Assert(Assigned(AFeatureClass));
   FFeatureClass := AFeatureClass as TInternalSensorFeatureClass;
   inherited CreateFromJournal(Journal, AFeatureClass, ASystem);
end;

procedure TInternalSensorFeatureNode.ApplyVisibility(const VisibilityHelper: TVisibilityHelper);
var
   OwnerIndex: Cardinal;

   function SenseDown(Asset: TAssetNode): Boolean;
   var
      Visibility: TVisibility;
   begin
      if ((Asset.Owner = Parent.Owner) or // we see our own ghosts
          (not Assigned(Asset.Owner)) or // we see unowned ghosts // TODO: this should be redundant, assert instead?
          Asset.IsReal()) then // and we see non-ghosts regardless of who owns them
      begin
         Visibility := FFeatureClass.FSensorKind;
         Asset.HandleVisibility(OwnerIndex, Visibility, VisibilityHelper);
         if (Visibility <> []) then
            Inc(FLastCountDetected);
         Result := True;
      end
      else
         Result := False;
   end;

begin
   Assert(not Assigned(FKnownMaterials));
   Assert(not Assigned(FKnownAssetClasses));
   FLastCountDetected := 0;
   OwnerIndex := VisibilityHelper.GetDynastyIndex(Parent.Owner);
   Parent.Walk(@SenseDown, nil);
   Assert(not Assigned(FKnownMaterials));
   Assert(not Assigned(FKnownAssetClasses));
end;

procedure TInternalSensorFeatureNode.ApplyKnowledge(const VisibilityHelper: TVisibilityHelper);
var
   OwnerIndex: Cardinal;

   function SenseDown(Asset: TAssetNode): Boolean;
   begin
      if (((Asset.Owner = Parent.Owner) or // we see our own ghosts
           (not Assigned(Asset.Owner)) or // we see unowned ghosts // TODO: this should be redundant, assert instead?
           Asset.IsReal())) then // and we see non-ghosts regardless of who owns them
      begin
         if (Asset.IsVisibleFor(OwnerIndex, VisibilityHelper.System)) then
            Asset.HandleKnowledge(OwnerIndex, VisibilityHelper, Self);
         Result := True;
      end
      else
         Result := False;
   end;

begin
   Assert(not Assigned(FKnownMaterials));
   Assert(not Assigned(FKnownAssetClasses));
   OwnerIndex := VisibilityHelper.GetDynastyIndex(Parent.Owner);
   Parent.Walk(@SenseDown, nil);
   FreeAndNil(FKnownMaterials);
   FreeAndNil(FKnownAssetClasses);
end;

procedure TInternalSensorFeatureNode.Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter; CachedSystem: TSystem);
var
   Visibility: TVisibility;
begin
   Visibility := Parent.ReadVisibilityFor(DynastyIndex, CachedSystem);
   if ((dmDetectable * Visibility <> []) and (dmClassKnown in Visibility)) then
   begin
      Writer.WriteCardinal(fcInternalSensor);
      if (dmInternals in Visibility) then
      begin
         Writer.WriteCardinal(fcInternalSensorStatus);
         Writer.WriteCardinal(FLastCountDetected);
      end;
   end;
end;

initialization
   RegisterFeatureClass(TInternalSensorFeatureClass);
end.