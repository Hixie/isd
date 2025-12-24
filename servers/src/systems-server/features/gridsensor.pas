{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit gridsensor;

interface

uses
   systems, serverstream, materials, knowledge, techtree, sensors;

type
   TGridSensorFeatureClass = class(TSensorFeatureClass)
   protected
      function GetFeatureNodeClass(): FeatureNodeReference; override;
   public
      function InitFeatureNode(ASystem: TSystem): TFeatureNode; override;
   end;

   TGridSensorFeatureNode = class(TSensorFeatureNode)
   protected
      FGrid: TAssetNode;
      FFeatureClass: TGridSensorFeatureClass;
      constructor CreateFromJournal(Journal: TJournalReader; AFeatureClass: TFeatureClass; ASystem: TSystem); override;
      procedure ApplyVisibility(); override;
      procedure ApplyKnowledge(); override;
      procedure Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter); override;
   public
      constructor Create(ASystem: TSystem; AFeatureClass: TGridSensorFeatureClass);
   end;

implementation

uses
   sysutils, orbit, isdprotocol, typedump, grid;

function TGridSensorFeatureClass.GetFeatureNodeClass(): FeatureNodeReference;
begin
   Result := TGridSensorFeatureNode;
end;

function TGridSensorFeatureClass.InitFeatureNode(ASystem: TSystem): TFeatureNode;
begin
   Result := TGridSensorFeatureNode.Create(ASystem, Self);
end;


constructor TGridSensorFeatureNode.Create(ASystem: TSystem; AFeatureClass: TGridSensorFeatureClass);
begin
   inherited Create(ASystem);
   FFeatureClass := AFeatureClass;
end;

constructor TGridSensorFeatureNode.CreateFromJournal(Journal: TJournalReader; AFeatureClass: TFeatureClass; ASystem: TSystem);
begin
   Assert(Assigned(AFeatureClass));
   FFeatureClass := AFeatureClass as TGridSensorFeatureClass;
   inherited;
end;

procedure TGridSensorFeatureNode.ApplyVisibility();
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
         Asset.HandleVisibility(OwnerIndex, Visibility);
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
   FGrid := Parent;
   while (True) do
   begin
      if (Assigned(FGrid.GetFeatureByClass(TGridFeatureClass))) then
         break;
      if (not Assigned(FGrid.Parent)) then
      begin
         FGrid := nil;
         break;
      end;
      FGrid := FGrid.Parent.Parent;
   end;
   FLastCountDetected := 0;
   if ((RateLimit = 1.0) and Assigned(FGrid)) then // TODO: do something prorated when RateLimit > 0.0 but < 1.0
   begin
      OwnerIndex := System.DynastyIndex[Parent.Owner];
      FGrid.Walk(@SenseDown, nil);
   end;
   Assert(not Assigned(FKnownMaterials));
   Assert(not Assigned(FKnownAssetClasses));
end;

procedure TGridSensorFeatureNode.ApplyKnowledge();
var
   OwnerIndex: Cardinal;

   function SenseDown(Asset: TAssetNode): Boolean;
   begin
      if (((Asset.Owner = Parent.Owner) or // we see our own ghosts
           (not Assigned(Asset.Owner)) or // we see unowned ghosts // TODO: this should be redundant, assert instead?
           Asset.IsReal())) then // and we see non-ghosts regardless of who owns them
      begin
         if (Asset.IsVisibleFor(OwnerIndex)) then
            Asset.HandleKnowledge(OwnerIndex, Self);
         Result := True;
      end
      else
         Result := False;
   end;

begin
   Assert(not Assigned(FKnownMaterials));
   Assert(not Assigned(FKnownAssetClasses));
   if ((RateLimit = 1.0) and Assigned(FGrid)) then // TODO: do something prorated when RateLimit > 0.0 but < 1.0
   begin
      OwnerIndex := System.DynastyIndex[Parent.Owner];
      FGrid.Walk(@SenseDown, nil);
   end;
   FreeAndNil(FKnownMaterials);
   FreeAndNil(FKnownAssetClasses);
end;

procedure TGridSensorFeatureNode.Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter);
var
   Visibility: TVisibility;
begin
   Visibility := Parent.ReadVisibilityFor(DynastyIndex);
   if ((dmDetectable * Visibility <> []) and (dmClassKnown in Visibility)) then
   begin
      Writer.WriteCardinal(fcGridSensor);
      Writer.WriteCardinal(Cardinal(FDisabledReasons));
      if ((RateLimit > 0.0) and (dmInternals in Visibility)) then
      begin
         Writer.WriteCardinal(fcGridSensorStatus);
         if (Assigned(FGrid)) then
         begin
            Writer.WriteCardinal(FGrid.ID(DynastyIndex));
         end
         else
         begin
            Writer.WriteCardinal(0);
         end;
         Writer.WriteCardinal(FLastCountDetected);
      end;
   end;
end;

initialization
   RegisterFeatureClass(TGridSensorFeatureClass);
end.