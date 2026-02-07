{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit internalsensor;

interface

uses
   systems, internals, serverstream, materials, knowledge, sensors;

type
   TInternalSensorFeatureClass = class(TSensorFeatureClass)
   protected
      function GetFeatureNodeClass(): FeatureNodeReference; override;
   public
      function InitFeatureNode(ASystem: TSystem): TFeatureNode; override;
   end;

   TInternalSensorFeatureNode = class(TSensorFeatureNode)
   protected
      FFeatureClass: TInternalSensorFeatureClass;
      constructor CreateFromJournal(Journal: TJournalReader; AFeatureClass: TFeatureClass; ASystem: TSystem); override;
      procedure ApplyVisibility(); override;
      procedure ApplyKnowledge(); override;
      procedure Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter); override;
   public
      constructor Create(ASystem: TSystem; AFeatureClass: TInternalSensorFeatureClass);
   end;

implementation

uses
   sysutils, orbit, isdprotocol, typedump, ttparser;

function TInternalSensorFeatureClass.GetFeatureNodeClass(): FeatureNodeReference;
begin
   Result := TInternalSensorFeatureNode;
end;

function TInternalSensorFeatureClass.InitFeatureNode(ASystem: TSystem): TFeatureNode;
begin
   Result := TInternalSensorFeatureNode.Create(ASystem, Self);
end;


constructor TInternalSensorFeatureNode.Create(ASystem: TSystem; AFeatureClass: TInternalSensorFeatureClass);
begin
   inherited Create(ASystem);
   FFeatureClass := AFeatureClass;
end;

constructor TInternalSensorFeatureNode.CreateFromJournal(Journal: TJournalReader; AFeatureClass: TFeatureClass; ASystem: TSystem);
begin
   Assert(Assigned(AFeatureClass));
   FFeatureClass := AFeatureClass as TInternalSensorFeatureClass;
   inherited;
end;

procedure TInternalSensorFeatureNode.ApplyVisibility();
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
   FLastCountDetected := 0;
   if (RateLimit = 1.0) then // TODO: do something prorated when RateLimit > 0.0 but < 1.0
   begin
      OwnerIndex := System.DynastyIndex[Parent.Owner];
      Parent.Walk(@SenseDown, nil);
   end;
   Assert(not Assigned(FKnownMaterials));
   Assert(not Assigned(FKnownAssetClasses));
end;

procedure TInternalSensorFeatureNode.ApplyKnowledge();
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
   if (RateLimit = 1.0) then // TODO: do something prorated when RateLimit > 0.0 but < 1.0
   begin
      OwnerIndex := System.DynastyIndex[Parent.Owner];
      Parent.Walk(@SenseDown, nil);
   end;
   FreeAndNil(FKnownMaterials);
   FreeAndNil(FKnownAssetClasses);
end;

procedure TInternalSensorFeatureNode.Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter);
var
   Visibility: TVisibility;
begin
   Visibility := Parent.ReadVisibilityFor(DynastyIndex);
   if ((dmDetectable * Visibility <> []) and (dmClassKnown in Visibility)) then
   begin
      Writer.WriteCardinal(fcInternalSensor);
      Writer.WriteCardinal(Cardinal(FDisabledReasons));
      if ((RateLimit > 0.0) and (dmInternals in Visibility)) then
      begin
         Writer.WriteCardinal(fcInternalSensorStatus);
         Writer.WriteCardinal(FLastCountDetected);
      end;
   end;
end;

initialization
   RegisterFeatureClass(TInternalSensorFeatureClass);
end.