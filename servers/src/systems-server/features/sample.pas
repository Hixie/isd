{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit sample;

interface

uses
   basenetwork, systems, serverstream, materials, techtree,
   messageport, region, time, systemdynasty, masses, annotatedpointer;

type
   TSampleFeatureClass = class(TFeatureClass)
   private
      FSize: Double;
   strict protected
      function GetFeatureNodeClass(): FeatureNodeReference; override;
   public
      constructor Create(ASize: Double);
      constructor CreateFromTechnologyTree(Reader: TTechTreeReader); override;
      function InitFeatureNode(ASystem: TSystem): TFeatureNode; override;
   end;

   TCallback = procedure of object;
   
   TSampleFeatureNode = class(TFeatureNode)
   strict private
      type
         TSampleMode = (smEmpty, smOre, smMaterial, smAsset);
         TContents = record
            case Mode: TSampleMode of
               smEmpty: ();
               smOre: (Ore: TMaterial; OreQuantity: TQuantity64);
               smMaterial: (Material: TMaterial; MaterialQuantity: TQuantity64);
               smAsset: (Child: TAssetNode);
         end;
   strict private
      FSize: Double;
      FContents: TContents;
   protected
      constructor CreateFromJournal(Journal: TJournalReader; AFeatureClass: TFeatureClass; ASystem: TSystem); override;
      function GetMass(): TMass; override;
      function GetMassFlowRate(): TMassRate; override;
      function GetSize(): Double; override;
      procedure Walk(PreCallback: TPreWalkCallback; PostCallback: TPostWalkCallback); override;
      function HandleBusMessage(Message: TBusMessage): THandleBusMessageResult; override;
      procedure Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter); override;
   public
      constructor Create(ASystem: TSystem; AFeatureClass: TSampleFeatureClass);
      destructor Destroy(); override;
      procedure AdoptChild(Child: TAssetNode); override;
      procedure DropChild(Child: TAssetNode); override;
      procedure UpdateJournal(Journal: TJournalWriter); override;
      procedure ApplyJournal(Journal: TJournalReader); override;
      function HandleCommand(PlayerDynasty: TDynasty; Command: UTF8String; var Message: TMessage): Boolean; override;
      procedure DescribeExistentiality(var IsDefinitelyReal, IsDefinitelyGhost: Boolean); override;
   end;

implementation

uses
   exceptions, sysutils, knowledge, messages, isdprotocol, rubble, commonbuses, research;


constructor TSampleFeatureClass.Create(ASize: Double);
begin
   inherited Create();
   FSize := ASize;
end;

constructor TSampleFeatureClass.CreateFromTechnologyTree(Reader: TTechTreeReader);
begin
   inherited Create();
   Reader.Tokens.ReadIdentifier('size');
   FSize := ReadLength(Reader.Tokens);
end;

function TSampleFeatureClass.GetFeatureNodeClass(): FeatureNodeReference;
begin
   Result := TSampleFeatureNode;
end;

function TSampleFeatureClass.InitFeatureNode(ASystem: TSystem): TFeatureNode;
begin
   Result := TSampleFeatureNode.Create(ASystem, Self);
end;


constructor TSampleFeatureNode.Create(ASystem: TSystem; AFeatureClass: TSampleFeatureClass);
begin
   inherited Create(ASystem);
   FSize := (AFeatureClass as TSampleFeatureClass).FSize;
end;

constructor TSampleFeatureNode.CreateFromJournal(Journal: TJournalReader; AFeatureClass: TFeatureClass; ASystem: TSystem);
begin
   inherited;
   FSize := (AFeatureClass as TSampleFeatureClass).FSize;
end;

destructor TSampleFeatureNode.Destroy();
begin
   if (FContents.Mode = smAsset) then
   begin
      FreeAndNil(FContents.Child);
      FContents.Mode := smEmpty;
   end;
   inherited;
end;

procedure TSampleFeatureNode.AdoptChild(Child: TAssetNode);
begin
   inherited;
   Assert(FContents.Mode = smEmpty);
   FContents.Mode := smAsset;
   FContents.Child := Child;
   MarkAsDirty([dkUpdateClients, dkUpdateJournal]);
end;

procedure TSampleFeatureNode.DropChild(Child: TAssetNode);
begin
   Assert(FContents.Mode = smAsset);
   Assert(FContents.Child = Child);
   FContents.Child := nil;
   FContents.Mode := smEmpty;
   MarkAsDirty([dkUpdateClients, dkUpdateJournal]);
   inherited;
end;

function TSampleFeatureNode.HandleBusMessage(Message: TBusMessage): THandleBusMessageResult;
var
   DumpOre: TDumpOreBusMessage;
   Handled: TInjectBusMessageResult;
   TopicName: UTF8String;
   Topic: TTopic;
begin
   if (Message is TRubbleCollectionMessage) then
   begin
      case (FContents.Mode) of
         smEmpty: ;
         smOre: begin
            DumpOre := TDumpOreBusMessage.Create(TOres(FContents.Ore.ID), FContents.OreQuantity);
            Handled := InjectBusMessage(DumpOre);
            Assert(Handled = irHandled);
            FreeAndNil(DumpOre);
            FContents.Mode := smEmpty;
            MarkAsDirty([dkUpdateClients, dkUpdateJournal]);
         end;
         smMaterial: begin
            (Message as TRubbleCollectionMessage).AddMaterial(FContents.Material, FContents.MaterialQuantity);
            FContents.Mode := smEmpty;
            MarkAsDirty([dkUpdateClients, dkUpdateJournal]);
         end;
         smAsset: ; // child will get handled by the message being sent up
      end;
      Result := hrActive;
   end
   else

   if (Message is TDismantleMessage) then
   begin
      Writeln(DebugName, ' received ', Message.ClassName);
      case (FContents.Mode) of
         smEmpty: ;
         smOre: begin
            DumpOre := TDumpOreBusMessage.Create(TOres(FContents.Ore.ID), FContents.OreQuantity);
            Handled := InjectBusMessage(DumpOre);
            Assert(Handled = irHandled);
            FreeAndNil(DumpOre);
            FContents.Mode := smEmpty;
            MarkAsDirty([dkUpdateClients, dkUpdateJournal]);
         end;
         smMaterial: begin
            (Message as TDismantleMessage).AddExcessMaterial(FContents.Material, FContents.MaterialQuantity);
            FContents.Mode := smEmpty;
            MarkAsDirty([dkUpdateClients, dkUpdateJournal]);
         end;
         smAsset: begin
            (Message as TDismantleMessage).AddExcessAsset(FContents.Child);
            FContents.Mode := smEmpty;
            MarkAsDirty([dkUpdateClients, dkUpdateJournal]);
         end;
      end;
      Result := hrActive;
   end
   else

   if (Message is TFindResearchFacilitiesBusMessage) then
   begin
      case (FContents.Mode) of
         smEmpty: TopicName := '@empty';
         smOre: TopicName := FContents.Ore.Name;
         smMaterial: TopicName := FContents.Material.Name;
         smAsset: TopicName := FContents.Child.AssetClass.Name;
      end;
      Topic := System.Encyclopedia.Topics['@sample ' + TopicName];
      if (Assigned(Topic)) then
      begin
         Writeln(DebugName, ' was asked to report facilities; found "', '@sample ' + TopicName, '"');
         (Message as TFindResearchFacilitiesBusMessage).AddTopic(Topic);
      end
      else
         Writeln(DebugName, ' was asked to report facilities; but "', '@sample ' + TopicName, '" does not exist');
      if (FContents.Mode <> smEmpty) then
      begin
         Topic := System.Encyclopedia.Topics['@sample @present'];
         (Message as TFindResearchFacilitiesBusMessage).AddTopic(Topic);
      end;
      Result := hrActive;
   end
   else
      Result := inherited;
end;

function TSampleFeatureNode.GetMass(): TMass;
begin
   case (FContents.Mode) of
      smEmpty: Result := TMass.Zero;
      smOre: Result := FContents.OreQuantity * FContents.Ore.MassPerUnit;
      smMaterial: Result := FContents.MaterialQuantity * FContents.Material.MassPerUnit;
      smAsset: Result := FContents.Child.Mass;
   end;
end;

function TSampleFeatureNode.GetMassFlowRate(): TMassRate;
begin
   case (FContents.Mode) of
      smEmpty: Result := TMassRate.Zero;
      smOre: Result := TMassRate.Zero;
      smMaterial: Result := TMassRate.Zero;
      smAsset: Result := FContents.Child.MassFlowRate;
   end;
end;

function TSampleFeatureNode.GetSize(): Double;
begin
   Result := FSize;
end;

procedure TSampleFeatureNode.Walk(PreCallback: TPreWalkCallback; PostCallback: TPostWalkCallback);
begin
   case (FContents.Mode) of
      smEmpty: ;
      smOre: ;
      smMaterial: ;
      smAsset: FContents.Child.Walk(PreCallback, PostCallback);
   end;
end;

procedure TSampleFeatureNode.Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter);
var
   Visibility: TVisibility;
   KnownMaterials: TGetKnownMaterialsMessage;
begin
   Visibility := Parent.ReadVisibilityFor(DynastyIndex);
   if (dmDetectable * Visibility <> []) then
   begin
      Writer.WriteCardinal(fcSample);
      Writer.WriteByte(Byte(FContents.Mode));
      Writer.WriteDouble(Size);
      Writer.WriteDouble(Mass.AsDouble);
      Writer.WriteDouble(MassFlowRate.AsDouble);
      KnownMaterials := TGetKnownMaterialsMessage.Create(System.DynastyByIndex[DynastyIndex]);
      InjectBusMessage(KnownMaterials); // we ignore the result - it doesn't matter if it wasn't handled
      case (FContents.Mode) of
         smEmpty:
            Writer.WriteInt32(0);
         smOre:
            if (KnownMaterials.Knows(FContents.Ore)) then
               Writer.WriteInt32(FContents.Ore.ID)
            else
               Writer.WriteInt32(0);
         smMaterial:
            if (KnownMaterials.Knows(FContents.Material)) then
               Writer.WriteInt32(FContents.Material.ID)
            else
               Writer.WriteInt32(0);
         smAsset:
            Writer.WriteCardinal(FContents.Child.ID(DynastyIndex));
      end;
      FreeAndNil(KnownMaterials);
   end;
end;

procedure TSampleFeatureNode.UpdateJournal(Journal: TJournalWriter);
begin
   Journal.WriteByte(Byte(FContents.Mode));
   case (FContents.Mode) of
      smEmpty: ;
      smOre: begin
         Journal.WriteMaterialReference(FContents.Ore);
         Journal.WriteInt64(FContents.OreQuantity.AsInt64);
      end;
      smMaterial: begin
         Journal.WriteMaterialReference(FContents.Material);
         Journal.WriteInt64(FContents.MaterialQuantity.AsInt64);
      end;
      smAsset:
         Journal.WriteAssetNodeReference(FContents.Child);
   end;
end;

procedure TSampleFeatureNode.ApplyJournal(Journal: TJournalReader);
var
   NewChild: TAssetNode;
   NewMode: TSampleMode;
begin
   NewMode := TSampleMode(Journal.ReadByte());
   if (NewMode <> FContents.Mode) then
   begin
      if (FContents.Mode = smAsset) then
         DropChild(FContents.Child);
      FContents.Mode := NewMode;
      if (FContents.Mode = smAsset) then
         FContents.Child := nil;
   end;
   case (FContents.Mode) of
      smEmpty: ;
      smOre: begin
         FContents.Ore := Journal.ReadMaterialReference();
         FContents.OreQuantity := TQuantity64.FromUnits(Journal.ReadInt64());
      end;
      smMaterial: begin
         FContents.Material := Journal.ReadMaterialReference();
         FContents.MaterialQuantity := TQuantity64.FromUnits(Journal.ReadInt64());
      end;
      smAsset: begin
         NewChild := Journal.ReadAssetNodeReference(System);
         AdoptChild(NewChild);
      end;
   end;
end;

function TSampleFeatureNode.HandleCommand(PlayerDynasty: TDynasty; Command: UTF8String; var Message: TMessage): Boolean;
var
   SampleOre: TSampleOreBusMessage;
   StoreMaterial: TStoreMaterialBusMessage;
   StoreOre: TStoreOreBusMessage;
   DumpOre: TDumpOreBusMessage;
   KnownMaterials: TGetKnownMaterialsMessage;
   Manifest: TMaterialQuantity64;
   Changed: TResearchFacilityChangedBusMessage;
begin
   if (Command = ccSampleOre) then
   begin
      Result := True;
      if (FContents.Mode <> smEmpty) then
      begin
         Message.Error(ieInvalidMessage);
      end
      else
      if (PlayerDynasty <> Parent.Owner) then
      begin
         Message.Error(ieNotOwner);
      end
      else
      begin
         if (Message.CloseInput()) then
         begin
            Message.Reply();
            Writeln(DebugName, ' sampling ore...');
            SampleOre := TSampleOreBusMessage.Create(PlayerDynasty, FSize);
            if (InjectBusMessage(SampleOre) = irHandled) then
            begin
               Message.Output.WriteBoolean(True);
               Manifest := SampleOre.Accept();
               FContents.Mode := smOre;
               Assert(Manifest.Material.ID >= Low(TOres));
               Assert(Manifest.Material.ID <= High(TOres));
               FContents.Ore := Manifest.Material;
               FContents.OreQuantity := Manifest.Quantity;
               Writeln(DebugName, ' now contains ', FContents.OreQuantity.ToString(), ' of ', FContents.Ore.Name);
               MarkAsDirty([dkUpdateClients, dkUpdateJournal]);
               Changed := TResearchFacilityChangedBusMessage.Create(Parent.Owner);
               InjectBusMessage(Changed);
               FreeAndNil(Changed);
            end
            else
            begin
               Message.Output.WriteBoolean(False);
            end;
            Message.CloseOutput();
            FreeAndNil(SampleOre);
         end;
      end;
   end
   else

   if (Command = ccClearSamples) then
   begin
      Result := True;
      if (not (FContents.Mode in [smOre, smMaterial])) then
      begin
         Message.Error(ieInvalidMessage);
      end
      else
      if (PlayerDynasty <> Parent.Owner) then
      begin
         Message.Error(ieNotOwner);
      end
      else
      begin
         if (Message.CloseInput()) then
         begin
            Message.Reply();
            KnownMaterials := TGetKnownMaterialsMessage.Create(PlayerDynasty);
            InjectBusMessage(KnownMaterials); // we ignore the result - it doesn't matter if it wasn't handled
            if (FContents.Mode = smOre) then
            begin
               Writeln('clearing ore sample, ', FContents.OreQuantity.ToString(), ' of ', FContents.Ore.Name);
               if (KnownMaterials.Knows(FContents.Ore)) then
               begin
                  StoreMaterial := TStoreMaterialBusMessage.Create(Parent, Parent.Owner, FContents.Ore, FContents.OreQuantity);
                  InjectBusMessage(StoreMaterial);
                  FContents.OreQuantity := StoreMaterial.RemainingQuantity;
                  FreeAndNil(StoreMaterial);
                  Writeln('  stored material; ', FContents.OreQuantity.ToString(), ' left');
               end;
               if (FContents.OreQuantity.IsPositive) then
               begin
                  StoreOre := TStoreOreBusMessage.Create(Parent.Owner, TOres(FContents.Ore.ID), FContents.OreQuantity);
                  if (InjectBusMessage(StoreOre) = irHandled) then
                     FContents.OreQuantity := TQuantity64.Zero;
                  FreeAndNil(StoreOre);
                  Writeln('  stored ore; ', FContents.OreQuantity.ToString(), ' left');
               end;
               if (FContents.OreQuantity.IsPositive) then
               begin
                  DumpOre := TDumpOreBusMessage.Create(TOres(FContents.Ore.ID), FContents.OreQuantity);
                  if (InjectBusMessage(DumpOre) = irHandled) then
                     FContents.OreQuantity := TQuantity64.Zero;
                  FreeAndNil(DumpOre);
                  Writeln('  dumped ore; ', FContents.OreQuantity.ToString(), ' left');
               end;
               if (FContents.OreQuantity.IsZero) then
               begin
                  Writeln('  successfully emptied ore sample');
                  FContents.Mode := smEmpty;
                  Changed := TResearchFacilityChangedBusMessage.Create(Parent.Owner);
                  InjectBusMessage(Changed);
                  FreeAndNil(Changed);
               end;
               MarkAsDirty([dkUpdateClients, dkUpdateJournal]);
            end
            else
            begin
               Assert(FContents.Mode = smMaterial);
               if (KnownMaterials.Knows(FContents.Ore)) then
               begin
                  StoreMaterial := TStoreMaterialBusMessage.Create(Parent, Parent.Owner, FContents.Material, FContents.MaterialQuantity);
                  InjectBusMessage(StoreMaterial);
                  FContents.MaterialQuantity := StoreMaterial.RemainingQuantity;
                  FreeAndNil(StoreMaterial);
               end;
               if ((FContents.MaterialQuantity.IsPositive) and FContents.Material.IsOre) then
               begin
                  if (FContents.MaterialQuantity.IsPositive) then
                  begin
                     StoreOre := TStoreOreBusMessage.Create(Parent.Owner, TOres(FContents.Material.ID), FContents.MaterialQuantity);
                     if (InjectBusMessage(StoreOre) = irHandled) then
                        FContents.MaterialQuantity := TQuantity64.Zero;
                     FreeAndNil(StoreOre);
                  end;
                  if (FContents.MaterialQuantity.IsPositive) then
                  begin
                     DumpOre := TDumpOreBusMessage.Create(TOres(FContents.Material.ID), FContents.MaterialQuantity);
                     if (InjectBusMessage(DumpOre) = irHandled) then
                        FContents.MaterialQuantity := TQuantity64.Zero;
                     FreeAndNil(DumpOre);
                  end;
               end;
               if (FContents.MaterialQuantity.IsZero) then
               begin
                  FContents.Mode := smEmpty;
                  Changed := TResearchFacilityChangedBusMessage.Create(Parent.Owner);
                  InjectBusMessage(Changed);
                  FreeAndNil(Changed);
               end;
               MarkAsDirty([dkUpdateClients, dkUpdateJournal]);
            end;
            Message.Output.WriteBoolean(FContents.Mode = smEmpty);
            Message.CloseOutput();
            FreeAndNil(KnownMaterials);
         end;
      end;
   end
   else
      Result := False;
end;

procedure TSampleFeatureNode.DescribeExistentiality(var IsDefinitelyReal, IsDefinitelyGhost: Boolean);
begin
   IsDefinitelyReal := FContents.Mode <> smEmpty;
end;

initialization
   RegisterFeatureClass(TSampleFeatureClass);
end.