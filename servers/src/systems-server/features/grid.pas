{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit grid;

interface

uses
   systems, serverstream, basenetwork, systemdynasty, techtree, tttokenizer, time;

type
   TGenericGridFeatureClass = class(TFeatureClass)
   strict protected
      function GetFeatureNodeClass(): FeatureNodeReference; override;
   public
      constructor CreateFromTechnologyTree(Reader: TTechTreeReader); override;
      function InitFeatureNode(): TFeatureNode; override;
   end;
   
   TParameterizedGridFeatureClass = class(TFeatureClass)
   strict private
      FBuildEnvironment: TBuildEnvironment;
      FCellSize: Double;
      FDimension: Cardinal;
   strict protected
      function GetFeatureNodeClass(): FeatureNodeReference; override;
   public
      constructor Create(ABuildEnvironment: TBuildEnvironment; ACellSize: Double; ADimension: Cardinal);
      constructor CreateFromTechnologyTree(Reader: TTechTreeReader); override;
      function InitFeatureNode(): TFeatureNode; override;
   end;
   
   TGridFeatureNode = class(TFeatureNode)
   strict private
      FBuildEnvironment: TBuildEnvironment;
      FCellSize: Double;
      FDimension: Cardinal;
      FChildren: TAssetNode.TArray; // TODO: plastic array? sorted array with binary search? map?
      function GetChild(X, Y: Cardinal; GhostOwner: TDynasty): TAssetNode; // to only get non-ghosts, set GhostOwner to nil
      procedure AdoptGridChild(Child: TAssetNode; X, Y: Cardinal);
   protected
      procedure DropChild(Child: TAssetNode); override;
      function GetMass(): Double; override;
      function GetMassFlowRate(): TRate; override;
      function GetSize(): Double; override;
      procedure Walk(PreCallback: TPreWalkCallback; PostCallback: TPostWalkCallback); override;
      function HandleBusMessage(Message: TBusMessage): Boolean; override;
      procedure Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter; CachedSystem: TSystem); override;
   public
      constructor Create(ABuildEnvironment: TBuildEnvironment; ACellSize: Double; ADimension: Cardinal);
      destructor Destroy(); override;
      procedure UpdateJournal(Journal: TJournalWriter; CachedSystem: TSystem); override;
      procedure ApplyJournal(Journal: TJournalReader; CachedSystem: TSystem); override;
      function HandleCommand(Command: UTF8String; var Message: TMessage): Boolean; override;
      property Dimension: Cardinal read FDimension;
      property CellSize: Double read FCellSize;
   end;
   
implementation

uses
   sysutils, isdprotocol, orbit, exceptions, knowledge, systemnetwork, isderrors;

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

function TGenericGridFeatureClass.InitFeatureNode(): TFeatureNode;
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

function TParameterizedGridFeatureClass.GetFeatureNodeClass(): FeatureNodeReference;
begin
   Result := TGridFeatureNode;
end;

function TParameterizedGridFeatureClass.InitFeatureNode(): TFeatureNode;
begin
   Result := TGridFeatureNode.Create(FBuildEnvironment, FCellSize, FDimension);
end;


constructor TGridFeatureNode.Create(ABuildEnvironment: TBuildEnvironment; ACellSize: Double; ADimension: Cardinal);
begin
   inherited Create();
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
   CachedSystem: TSystem;
begin
   if (Message is TReceiveCrashingAssetMessage) then
   begin
      Writeln(ClassName, ' handling ', Message.ClassName, ' which has ', Length(TReceiveCrashingAssetMessage(Message).Assets), ' crashing assets');
      CachedSystem := System;
      for Child in TReceiveCrashingAssetMessage(Message).Assets do
      begin
         X := CachedSystem.RandomNumberGenerator.GetCardinal(0, Dimension);
         Y := CachedSystem.RandomNumberGenerator.GetCardinal(0, Dimension);
         OldChild := GetChild(X, Y, nil);
         Crater := CachedSystem.Encyclopedia.Craterize(CellSize, OldChild, Child);
         Writeln('  Placed crater ', Crater.DebugName, ' for child ', Child.DebugName, ' at ', X, ',', Y);
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

procedure TGridFeatureNode.Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter; CachedSystem: TSystem);
var
   Child: TAssetNode;
begin
   // You always know the size of a grid because if anything is inferred inside it, we need the size to place it.
   Writer.WriteCardinal(fcGrid);
   Writer.WriteDouble(FCellSize);
   Writer.WriteCardinal(FDimension);
   Writer.WriteCardinal(FDimension);
   for Child in FChildren do
   begin
      if (Child.IsVisibleFor(DynastyIndex, CachedSystem)) then
      begin
         Writer.WriteCardinal(Child.ID(CachedSystem, DynastyIndex));
         Writer.WriteCardinal(PGridData(Child.ParentData)^.X);
         Writer.WriteCardinal(PGridData(Child.ParentData)^.Y);
      end;
   end;
   Writer.WriteCardinal(0);
end;

procedure TGridFeatureNode.UpdateJournal(Journal: TJournalWriter; CachedSystem: TSystem);

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

procedure TGridFeatureNode.ApplyJournal(Journal: TJournalReader; CachedSystem: TSystem);

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
   KnownAssetClasses: TGetKnownAssetClassesMessage;
   X, Y: Cardinal;
   AssetClassID: TAssetClassID;
   AssetClass: TAssetClass;
   Asset: TAssetNode;
   PlayerDynasty: TDynasty;
   CachedSystem: TSystem;
begin
   // what can i build at coordinates x,y?
   // build something at coordinates x,y
   if (Command = 'get-buildings') then
   begin
      Result := True;
      X := Message.Input.ReadCardinal();
      Y := Message.Input.ReadCardinal();
      if ((X >= FDimension) or (Y >= FDimension)) then
      begin
         Message.Error(ieInvalidCommand);
         exit;
      end;
      PlayerDynasty := (Message.Connection as TConnection).PlayerDynasty;
      if (Assigned(GetChild(X, Y, PlayerDynasty))) then
      begin
         Message.Error(ieInvalidCommand);
         exit;
      end;
      if (Message.CloseInput()) then
      begin
         Message.Reply();
         KnownAssetClasses := TGetKnownAssetClassesMessage.Create(PlayerDynasty);
         InjectBusMessage(KnownAssetClasses); // we ignore the result - it doesn't matter if it wasn't handled
         for AssetClass in KnownAssetClasses do
         begin
            if (AssetClass.CanBuild(FBuildEnvironment)) then
            begin
               AssetClass.Serialize(Message.Output);
            end;
         end;
         KnownAssetClasses.Free();
         Message.CloseOutput();
      end;
   end
   else
   if (Command = 'build') then
   begin
      Result := True;
      X := Message.Input.ReadCardinal();
      Y := Message.Input.ReadCardinal();
      if ((X >= FDimension) or (Y >= FDimension)) then
      begin
         Message.Error(ieInvalidCommand);
         exit;
      end;
      PlayerDynasty := (Message.Connection as TConnection).PlayerDynasty;
      if (Assigned(GetChild(X, Y, PlayerDynasty))) then
      begin
         Message.Error(ieInvalidCommand);
         exit;
      end;
      AssetClassID := Message.Input.ReadLongint();
      CachedSystem := System;
      AssetClass := CachedSystem.Encyclopedia.AssetClasses[AssetClassID];
      if (not Assigned(AssetClass)) then
      begin
         Message.Error(ieInvalidCommand);
         exit;
      end;
      KnownAssetClasses := TGetKnownAssetClassesMessage.Create((Message.Connection as TConnection).PlayerDynasty);
      try
         InjectBusMessage(KnownAssetClasses); // we ignore the result - it doesn't matter if it wasn't handled
         if (not KnownAssetClasses.Knows(AssetClass)) then
         begin
            Message.Error(ieInvalidCommand);
            exit;
         end;
         if (not AssetClass.CanBuild(FBuildEnvironment)) then
         begin
            Message.Error(ieInvalidCommand);
            exit;
         end;
         if (Message.CloseInput()) then
         begin
            Message.Reply();
            Asset := AssetClass.Spawn(PlayerDynasty);
            AdoptGridChild(Asset, X, Y);
            Assert(Asset.Mass = 0); // if you put something down, it shouldn't immediately have mass
            Assert(Asset.Size <= FCellSize, 'Tried to put ' + Asset.DebugName + ' of size ' + FloatToStr(Asset.Size) + 'm in cell size ' + FloatToStr(FCellSize) + 'm');
            Message.CloseOutput();
         end;
      finally
         KnownAssetClasses.Free();
      end;
   end
   else
      Result := inherited;
end;

initialization
   RegisterFeatureClass(TGenericGridFeatureClass);
   RegisterFeatureClass(TParameterizedGridFeatureClass);
end.