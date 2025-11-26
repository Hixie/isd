{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit grid;

interface

uses
   systems, serverstream, basenetwork, systemdynasty, techtree, tttokenizer, time;

type
   TGridFeatureClass = class abstract (TFeatureClass) end;

   TGenericGridFeatureClass = class(TGridFeatureClass)
   strict protected
      function GetFeatureNodeClass(): FeatureNodeReference; override;
   public
      constructor CreateFromTechnologyTree(Reader: TTechTreeReader); override;
      function InitFeatureNode(ASystem: TSystem): TFeatureNode; override;
   end;

   TParameterizedGridFeatureClass = class(TGridFeatureClass)
   strict private
      FBuildEnvironment: TBuildEnvironment;
      FCellSize: Double;
      FDimension: Cardinal;
   strict protected
      function GetFeatureNodeClass(): FeatureNodeReference; override;
      function GetDefaultSize(): Double; override;
   public
      constructor Create(ABuildEnvironment: TBuildEnvironment; ACellSize: Double; ADimension: Cardinal);
      constructor CreateFromTechnologyTree(Reader: TTechTreeReader); override;
      function InitFeatureNode(ASystem: TSystem): TFeatureNode; override;
   end;

   TGridFeatureNode = class(TFeatureNode)
   strict protected
      type
         TAssetClassKnowledge = record
         strict private
            const
               DirectMarker = $01;
            type
               TDirectArray = TAssetClass.TArray;
               TIndirectArray = array of TDirectArray;
            var
               FData: Pointer;
            function IsDirect(): Boolean; inline;
            class operator Initialize(var Rec: TAssetClassKnowledge);
            class operator Finalize(var Rec: TAssetClassKnowledge);
            function GetAssetClasses(DynastyIndex: Cardinal): TAssetClass.TArray;
            procedure SetAssetClasses(DynastyIndex: Cardinal; Value: TAssetClass.TArray);
         public
            procedure Init(Count: Cardinal); inline;
            procedure Reset(); inline;
            property AssetClasses[DynastyIndex: Cardinal]: TAssetClass.TArray read GetAssetClasses write SetAssetClasses; default;
         end;
   strict private
      FBuildEnvironment: TBuildEnvironment;
      FCellSize: Double;
      FDimension: Cardinal;
      FChildren: TAssetNode.TArray; // TODO: plastic array? sorted array with binary search? map?
      FKnownClasses: TAssetClassKnowledge;
      function GetChild(X, Y: Cardinal; GhostOwner: TDynasty): TAssetNode; // to only get non-ghosts, set GhostOwner to nil
      procedure AdoptGridChild(Child: TAssetNode; X, Y: Cardinal);
   protected
      function GetMass(): Double; override;
      function GetMassFlowRate(): TRate; override;
      function GetSize(): Double; override;
      procedure Walk(PreCallback: TPreWalkCallback; PostCallback: TPostWalkCallback); override;
      procedure ResetDynastyNotes(OldDynasties: TDynastyIndexHashTable; NewDynasties: TDynasty.TArray); override;
      procedure ResetVisibility(); override;
      function HandleBusMessage(Message: TBusMessage): Boolean; override;
      procedure Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter); override;
   public
      constructor Create(ASystem: TSystem; ABuildEnvironment: TBuildEnvironment; ACellSize: Double; ADimension: Cardinal);
      destructor Destroy(); override;
      procedure DropChild(Child: TAssetNode); override;
      procedure UpdateJournal(Journal: TJournalWriter); override;
      procedure ApplyJournal(Journal: TJournalReader); override;
      function HandleCommand(Command: UTF8String; var Message: TMessage): Boolean; override;
      procedure HandleKnowledge(const DynastyIndex: Cardinal; const Sensors: ISensorsProvider); override;
      property Dimension: Cardinal read FDimension;
      property CellSize: Double read FCellSize;
   end;

implementation

uses
   sysutils, isdprotocol, orbit, exceptions, knowledge, systemnetwork, math;

type
   PGridData = ^TGridData;
   TGridData = bitpacked record
      // TODO: geology
      X, Y, Index: Cardinal;
      IsNew: Boolean;
      IsChanged: Boolean;
   end;


constructor TGenericGridFeatureClass.CreateFromTechnologyTree(Reader: TTechTreeReader);
begin
   inherited Create();
   Reader.Tokens.Error('Feature class %s is reserved for internal asset classes', [ClassName]);
end;

function TGenericGridFeatureClass.GetFeatureNodeClass(): FeatureNodeReference;
begin
   Result := TGridFeatureNode;
end;

function TGenericGridFeatureClass.InitFeatureNode(ASystem: TSystem): TFeatureNode;
begin
   Result := nil;
   Assert(False, 'Generic grid features cannot spawn feature nodes.');
end;


constructor TParameterizedGridFeatureClass.Create(ABuildEnvironment: TBuildEnvironment; ACellSize: Double; ADimension: Cardinal);
begin
   inherited Create();
   FBuildEnvironment := ABuildEnvironment;
   FCellSize := ACellSize;
   FDimension := ADimension;
end;

constructor TParameterizedGridFeatureClass.CreateFromTechnologyTree(Reader: TTechTreeReader);
var
   Value: Int64;
begin
   inherited Create();
   FDimension := ReadNumber(Reader.Tokens, 1, High(FDimension)); // $R-
   Reader.Tokens.ReadAsterisk();
   Value := Reader.Tokens.ReadNumber();
   if (Value <> FDimension) then
      Reader.Tokens.Error('Grids must be square; %dx%d is not square', [FDimension, Value]);
   Reader.Tokens.ReadComma();
   FCellSize := ReadLength(Reader.Tokens);
   Reader.Tokens.ReadComma();
   FBuildEnvironment := ReadBuildEnvironment(Reader.Tokens);
end;

function TParameterizedGridFeatureClass.GetDefaultSize(): Double;
begin
   Result := FCellSize * FDimension;
end;

function TParameterizedGridFeatureClass.GetFeatureNodeClass(): FeatureNodeReference;
begin
   Result := TGridFeatureNode;
end;

function TParameterizedGridFeatureClass.InitFeatureNode(ASystem: TSystem): TFeatureNode;
begin
   Result := TGridFeatureNode.Create(ASystem, FBuildEnvironment, FCellSize, FDimension);
end;


function TGridFeatureNode.TAssetClassKnowledge.IsDirect(): Boolean;
begin
   Result := (PtrUInt(FData) and DirectMarker) > 0;
end;

class operator TGridFeatureNode.TAssetClassKnowledge.Initialize(var Rec: TAssetClassKnowledge);
begin
   Assert(not Assigned(Rec.FData));
end;

class operator TGridFeatureNode.TAssetClassKnowledge.Finalize(var Rec: TAssetClassKnowledge);
begin
   if (Assigned(Rec.FData)) then
   begin
      if (Rec.IsDirect()) then
      begin
         Finalize(TDirectArray(PtrUInt(Rec.FData) and not DirectMarker));
      end
      else
      begin
         Finalize(TIndirectArray(Rec.FData));
      end;
   end;
end;

procedure TGridFeatureNode.TAssetClassKnowledge.Init(Count: Cardinal); inline;
var
   Address: PtrUInt;
begin
   if (Assigned(FData)) then
   begin
      if (IsDirect()) then
      begin
         if (Count = 1) then
         begin
            Address := PtrUInt(FData) and not DirectMarker;
            TDirectArray(Address) := nil;
            PtrUInt(FData) := Address or DirectMarker;
         end
         else
         begin
            Finalize(TDirectArray(PtrUInt(FData) and not DirectMarker));
            FData := nil;
            if (Count > 0) then
            begin
               Assert(Count > 1);
               Initialize(TIndirectArray(FData));
               SetLength(TIndirectArray(FData), Count);
            end;
         end;
      end
      else
      begin
         if (Count > 1) then
         begin
            SetLength(TIndirectArray(FData), Count);
         end
         else
         begin
            Finalize(TIndirectArray(FData));
            FData := nil;
            if (Count > 0) then
            begin
               Assert(Count = 1);
               Address := PtrUInt(FData) and not DirectMarker;
               Initialize(TDirectArray(Address));
               PtrUInt(FData) := Address or DirectMarker;
            end;
         end;
      end;
   end
   else
   if (Count = 1) then
   begin
      Address := PtrUInt(FData) and not DirectMarker;
      Initialize(TDirectArray(Address));
      PtrUInt(FData) := Address or DirectMarker;
   end
   else
   if (Count > 1) then
   begin
      Initialize(TIndirectArray(FData));
      SetLength(TIndirectArray(FData), Count);
   end;
end;
      
procedure TGridFeatureNode.TAssetClassKnowledge.Reset(); inline;
var
   Address: PtrUInt;
   Index: Cardinal;
begin
   Assert(Assigned(FData));
   if (IsDirect()) then
   begin
      Address := PtrUInt(FData) and not DirectMarker;
      TDirectArray(Address) := nil;
      PtrUInt(FData) := Address or DirectMarker;
   end
   else
   begin
      Assert(Length(TIndirectArray(FData)) > 0);
      for Index := Low(TIndirectArray(FData)) to High(TIndirectArray(FData)) do // $R-
      begin
         TIndirectArray(FData)[Index] := nil;
      end;
   end;
end;      

function TGridFeatureNode.TAssetClassKnowledge.GetAssetClasses(DynastyIndex: Cardinal): TAssetClass.TArray;
begin
   Assert(Assigned(FData));
   if (IsDirect()) then
   begin
      Assert(DynastyIndex = 0);
      Result := TDirectArray(PtrUInt(FData) and not DirectMarker);
   end
   else
   begin
      Result := TIndirectArray(FData)[DynastyIndex];
   end;
end;

procedure TGridFeatureNode.TAssetClassKnowledge.SetAssetClasses(DynastyIndex: Cardinal; Value: TAssetClass.TArray);
var
   Address: PtrUInt;
begin
   Assert(Assigned(FData));
   if (IsDirect()) then
   begin
      Assert(DynastyIndex = 0);
      Address := PtrUInt(FData) and not DirectMarker;
      TDirectArray(Address) := Value;
      PtrUInt(FData) := Address or DirectMarker;
   end
   else
   begin
      TIndirectArray(FData)[DynastyIndex] := Value;
   end;
end;


constructor TGridFeatureNode.Create(ASystem: TSystem; ABuildEnvironment: TBuildEnvironment; ACellSize: Double; ADimension: Cardinal);
begin
   inherited Create(ASystem);
   FBuildEnvironment := ABuildEnvironment;
   FCellSize := ACellSize;
   FDimension := ADimension;
end;

destructor TGridFeatureNode.Destroy();
var
   Child: TAssetNode;
begin
   for Child in FChildren do
      Child.Free();
   inherited;
end;

procedure TGridFeatureNode.AdoptGridChild(Child: TAssetNode; X, Y: Cardinal);
var
   OldChild: TAssetNode;
begin
   Assert(Assigned(Child));
   Assert(not Assigned(GetChild(X, Y, nil)));
   AdoptChild(Child);
   Child.ParentData := New(PGridData);
   PGridData(Child.ParentData)^.IsNew := True;
   PGridData(Child.ParentData)^.IsChanged := True;
   PGridData(Child.ParentData)^.X := X;
   PGridData(Child.ParentData)^.Y := Y;
   SetLength(FChildren, Length(FChildren) + 1);
   FChildren[High(FChildren)] := Child;
   PGridData(Child.ParentData)^.Index := High(FChildren); // $R-
   if (Child.IsReal()) then
   begin
      for OldChild in FChildren do
      begin
         if ((PGridData(OldChild.ParentData)^.X = X) and
             (PGridData(OldChild.ParentData)^.Y = Y)) then
         begin
            if (not OldChild.IsReal()) then
            begin
               DropChild(OldChild);
            end;
         end;
      end;
   end;
end;

procedure TGridFeatureNode.DropChild(Child: TAssetNode);
var
   Index: Cardinal;
begin
   Assert(Assigned(Child));
   Delete(FChildren, PGridData(Child.ParentData)^.Index, 1);
   if (PGridData(Child.ParentData)^.Index < Length(FChildren)) then
      for Index := PGridData(Child.ParentData)^.Index to High(FChildren) do // $R-
         PGridData(FChildren[Index].ParentData)^.Index := Index;
   Dispose(PGridData(Child.ParentData));
   Child.ParentData := nil;
   inherited;
end;

function TGridFeatureNode.GetChild(X, Y: Cardinal; GhostOwner: TDynasty): TAssetNode;
var
   Child: TAssetNode;
begin
   Assert(X < FDimension);
   Assert(Y < FDimension);
   for Child in FChildren do
   begin
      if ((PGridData(Child.ParentData)^.X = X) and
          (PGridData(Child.ParentData)^.Y = Y)) then
      begin
         if (Child.IsReal() or (Child.Owner = GhostOwner)) then
         begin
            Result := Child;
            exit;
         end;
      end;
   end;
   Result := nil;
end;

function TGridFeatureNode.GetMass(): Double;
var
   Child: TAssetNode;
begin
   Result := 0.0;
   for Child in FChildren do
      Result := Result + Child.Mass;
end;

function TGridFeatureNode.GetMassFlowRate(): TRate;
var
   Child: TAssetNode;
begin
   Result := TRate.Zero;
   for Child in FChildren do
      Result := Result + Child.MassFlowRate;
end;

function TGridFeatureNode.GetSize(): Double;
begin
   Result := FCellSize * FDimension;
end;

procedure TGridFeatureNode.Walk(PreCallback: TPreWalkCallback; PostCallback: TPostWalkCallback);
var
   Child: TAssetNode;
begin
   for Child in FChildren do
      Child.Walk(PreCallback, PostCallback);
end;

function TGridFeatureNode.HandleBusMessage(Message: TBusMessage): Boolean;
var
   Child, Crater, OldChild: TAssetNode;
   X, Y: Cardinal;
begin
   if (Message is TReceiveCrashingAssetMessage) then
   begin
      for Child in TReceiveCrashingAssetMessage(Message).Assets do
      begin
         X := System.RandomNumberGenerator.GetCardinal(0, Dimension);
         Y := System.RandomNumberGenerator.GetCardinal(0, Dimension);
         OldChild := GetChild(X, Y, nil);
         Assert(CellSize >= Child.Size);
         Crater := System.Encyclopedia.Craterize(CellSize, OldChild, Child);
         AdoptGridChild(Crater, X, Y);
      end;
      Result := True;
      exit;
   end;
   for Child in FChildren do
   begin
      Result := Child.HandleBusMessage(Message);
      if (Result) then
         exit;
   end;
   Result := False;
end;

procedure TGridFeatureNode.Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter);
var
   Visibility: TVisibility;
   Child: TAssetNode;
   AssetClass: TAssetClass;
   Cells: Double;
begin
   // You always know the size of a grid because if anything is inferred inside it, we need the size to place it.
   Visibility := Parent.ReadVisibilityFor(DynastyIndex);
   if (Visibility <> []) then
   begin
      Writer.WriteCardinal(fcGrid);
      Writer.WriteDouble(FCellSize);
      Writer.WriteCardinal(FDimension);
      for Child in FChildren do
      begin
         if (Child.IsVisibleFor(DynastyIndex)) then
         begin
            Writer.WriteCardinal(Child.ID(DynastyIndex));
            Writer.WriteCardinal(PGridData(Child.ParentData)^.X);
            Writer.WriteCardinal(PGridData(Child.ParentData)^.Y);
         end;
      end;
      Writer.WriteCardinal(0);
      for AssetClass in FKnownClasses[DynastyIndex] do
      begin
         Cells := Double(AssetClass.DefaultSize) / Double(FCellSize);
         if ((Cells > 0.0) and (Cells <= 255.0)) then
         begin
            AssetClass.Serialize(Writer);
            Writer.WriteByte(Ceil(Cells)); // $R-
         end;
      end;
      Writer.WriteCardinal(0);
   end;
end;

procedure TGridFeatureNode.UpdateJournal(Journal: TJournalWriter);

   procedure ReportChild(Child: TAssetNode);
   begin
      if (PGridData(Child.ParentData)^.IsChanged) then
      begin
         if (PGridData(Child.ParentData)^.IsNew) then
         begin
            Journal.WriteAssetChangeKind(ckAdd);
            Journal.WriteAssetNodeReference(Child);
            Journal.WriteCardinal(PGridData(Child.ParentData)^.X);
            Journal.WriteCardinal(PGridData(Child.ParentData)^.Y);
            PGridData(Child.ParentData)^.IsNew := False;
         end
         else
         begin
            Journal.WriteAssetChangeKind(ckChange);
            Journal.WriteAssetNodeReference(Child);
            Assert(False); // nothing to actually update right now...
         end;
         PGridData(Child.ParentData)^.IsChanged := False;
      end;
   end;

var
   Child: TAssetNode;
begin
   Journal.WriteDouble(FCellSize);
   Journal.WriteCardinal(FDimension);
   Assert(FDimension > 0);
   for Child in FChildren do
      ReportChild(Child);
   Journal.WriteAssetChangeKind(ckEndOfList);
end;

procedure TGridFeatureNode.ApplyJournal(Journal: TJournalReader);

   procedure AddChild();
   var
      Child: TAssetNode;
      X, Y: Cardinal;
   begin
      Child := Journal.ReadAssetNodeReference();
      X := Journal.ReadCardinal();
      Y := Journal.ReadCardinal();
      Assert(X < FDimension);
      Assert(Y < FDimension);
      AdoptGridChild(Child, X, Y);
      Assert(Child.Parent = Self);
   end;

   procedure ChangeChild();
   var
      Child: TAssetNode;
   begin
      Child := Journal.ReadAssetNodeReference();
      Assert(Assigned(Child));
      Assert(False); // nothing to update currently
      PGridData(Child.ParentData)^.IsChanged := True;
   end;

var
   AssetChangeKind: TAssetChangeKind;
   NewDimension: Cardinal;
begin
   FCellSize := Journal.ReadDouble();
   NewDimension := Journal.ReadCardinal();
   Assert(FDimension <= NewDimension); // otherwise we have to check all the existing children and make sure they're in the new grid as well
   FDimension := NewDimension;
   while (True) do
   begin
      AssetChangeKind := Journal.ReadAssetChangeKind();
      case AssetChangeKind of
         ckAdd: AddChild();
         ckChange: ChangeChild();
         ckEndOfList: break;
      end;
   end;
end;

function TGridFeatureNode.HandleCommand(Command: UTF8String; var Message: TMessage): Boolean;
var
   X, Y, Index: Cardinal;
   PlayerDynasty: TDynasty;
   AssetClassID: TAssetClassID;
   AssetClasses: TAssetClassArray;
   AssetClass: TAssetClass;
   Asset: TAssetNode;
begin
   if (Command = ccBuild) then
   begin
      Result := True;
      X := Message.Input.ReadCardinal();
      Y := Message.Input.ReadCardinal();
      PlayerDynasty := (Message.Connection as TConnection).PlayerDynasty;
      AssetClassID := Message.Input.ReadLongint();
      AssetClasses := FKnownClasses[System.DynastyIndex[PlayerDynasty]];
      if (Length(AssetClasses) = 0) then
      begin
         Writeln('Client requested a build for a grid where they have no knowledge.');
         Message.Error(ieInvalidMessage);
         exit;
      end;
      if ((X >= FDimension) or (Y >= FDimension)) then
      begin
         Writeln('Client requested a build for a cell out of range: ', X, ',', Y);
         Message.Error(ieInvalidMessage);
         exit;
      end;
      if (Assigned(GetChild(X, Y, PlayerDynasty))) then
      begin
         Writeln('Client requested a build for that already has a child: ', X, ',', Y);
         Message.Error(ieInvalidMessage);
         exit;
      end;
      AssetClass := nil;
      for Index := Low(AssetClasses) to High(AssetClasses) do // $R-
      begin
         if (AssetClasses[Index].ID = AssetClassID) then
         begin
            AssetClass := AssetClasses[Index];
            break;
         end;
      end;
      if (not Assigned(AssetClass)) then
      begin
         Writeln('Client requested a build for an asset class ID they do not know: ', AssetClassID);
         Message.Error(ieInvalidMessage);
         exit;
      end;
      if (not AssetClass.CanBuild(FBuildEnvironment)) then
      begin
         Writeln('Client requested a build with a non-matching build environment.');
         Message.Error(ieInvalidMessage);
         exit;
      end;
      if (Message.CloseInput()) then
      begin
         Message.Reply();
         Asset := AssetClass.Spawn(PlayerDynasty, System);
         AdoptGridChild(Asset, X, Y);
         Assert(Asset.Mass = 0); // if you put something down, it shouldn't immediately have mass
         Assert(Asset.Size <= FCellSize, 'Tried to put ' + Asset.DebugName + ' of size ' + FloatToStr(Asset.Size) + 'm in cell size ' + FloatToStr(FCellSize) + 'm');
         Message.CloseOutput();
      end;
   end
   else
      Result := False;
end;

procedure TGridFeatureNode.ResetDynastyNotes(OldDynasties: TDynastyIndexHashTable; NewDynasties: TDynasty.TArray);
begin
   FKnownClasses.Init(Length(NewDynasties)); // $R-
end;

procedure TGridFeatureNode.ResetVisibility();
begin
   FKnownClasses.Reset();
end;

procedure TGridFeatureNode.HandleKnowledge(const DynastyIndex: Cardinal; const Sensors: ISensorsProvider);

   function Filter(AssetClass: TAssetClass): Boolean;
   var
      BuildableSize: Double;
   begin
      BuildableSize := AssetClass.DefaultSize;
      Result := AssetClass.CanBuild(FBuildEnvironment) and (BuildableSize > 0.0) and (BuildableSize <= GetSize());
   end;

begin
   FKnownClasses[DynastyIndex] := Sensors.CollectMatchingAssetClasses(@Filter);
   MarkAsDirty([dkUpdateClients]);
end;

initialization
   RegisterFeatureClass(TGenericGridFeatureClass);
   RegisterFeatureClass(TParameterizedGridFeatureClass);
end.