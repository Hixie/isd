{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit stellar;

interface

uses
   sysutils, systems, astronomy, providers, serverstream, techtree, tttokenizer, masses;

type
   TStarFeatureClass = class(TFeatureClass)
   strict protected
      function GetFeatureNodeClass(): FeatureNodeReference; override;
   public
      constructor CreateFromTechnologyTree(Reader: TTechTreeReader); override;
      function InitFeatureNode(ASystem: TSystem): TFeatureNode; override;
   end;

   TStarFeatureNode = class(TFeatureNode, IAssetNameProvider)
   strict private
      FStarID: TStarID;
      function GetCategory(): TStarCategory; inline;
      function GetTemperature(): Double;
   protected
      function GetMass(): TMass; override;
      function GetSize(): Double; override;
      function HandleBusMessage(Message: TBusMessage): THandleBusMessageResult; override;
      procedure ApplyVisibility(); override;
      procedure Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter); override;
      function GetAssetName(): UTF8String;
   public
      constructor Create(ASystem: TSystem; AStarID: TStarID);
      procedure UpdateJournal(Journal: TJournalWriter); override;
      procedure ApplyJournal(Journal: TJournalReader); override;
      procedure DescribeExistentiality(var IsDefinitelyReal, IsDefinitelyGhost: Boolean); override;
      property Category: TStarCategory read GetCategory;
      property StarID: TStarID read FStarID;
      property Temperature: Double read GetTemperature;
   end;

implementation

uses
   isdprotocol, rubble, commonbuses;

const
   MassSalt = $04551455;
   SizeSalt = $51535153;


constructor TStarFeatureClass.CreateFromTechnologyTree(Reader: TTechTreeReader);
begin
   Reader.Tokens.Error('Feature class %s is reserved for internal asset classes', [ClassName]);
end;

function TStarFeatureClass.GetFeatureNodeClass(): FeatureNodeReference;
begin
   Result := TStarFeatureNode;
end;

function TStarFeatureClass.InitFeatureNode(ASystem: TSystem): TFeatureNode;
begin
   Result := nil;
   // TODO: create a technology that knows how to create a star and generate a new ID for it.
   raise Exception.Create('Cannot create a TStarFeatureNode from a prototype; it must have a unique ID.');
end;


constructor TStarFeatureNode.Create(ASystem: TSystem; AStarID: TStarID);
begin
   inherited Create(ASystem);
   FStarID := AStarID;
end;

function TStarFeatureNode.GetCategory(): TStarCategory;
begin
   Result := CategoryOf(StarID);
end;

function TStarFeatureNode.GetMass(): TMass;
begin
   case Category of
      2: Result := TMass.FromKg(30.0e30);
      3: Result := TMass.FromKg(0.7e30);
      4: Result := TMass.FromKg(1.0e30);
      5: Result := TMass.FromKg(8.2e30);
      6: Result := TMass.FromKg(2.0e30);
      7: Result := TMass.FromKg(15.8e30);
      8: Result := TMass.FromKg(5.2e30);
      9: Result := TMass.FromKg(10.0e30);
      10: Result := TMass.FromKg(100.0e30);
   else
      Assert(False);
      Result := TMass.Zero;
   end;
   Result := Result * Modifier(0.5, 2.0, StarID, MassSalt);
end;

function TStarFeatureNode.GetSize(): Double;
begin
   case Category of
      2: Result := 0.5e9;
      3: Result := 0.7e9;
      4: Result := 0.5e9;
      5: Result := 1.2e9;
      6: Result := 1.0e9;
      7: Result := 0.5e9;
      8: Result := 0.5e9;
      9: Result := 0.5e9;
      10: Result := 20.0e9;
   else
      Assert(False);
      Result := 0.0;
   end;
   Result := Result * Modifier(0.9, 1.1, StarID, SizeSalt);
end;

function TStarFeatureNode.GetTemperature(): Double;
begin
   case Category of
      2: Result := 3000;
      3: Result := 3000;
      4: Result := 6000;
      5: Result := 7000;
      6: Result := 10000;
      7: Result := 30000;
      8: Result := 4000;
      9: Result := 10000;
      10: Result := 5000;
   else
      Assert(False);
      Result := 0.0;
   end;
   // TODO: when we generate the description dynamically, vary the temperature also
   // Result := Result * Modifier(0.9, 1.1, StarID, TemperatureSalt);
end;

function TStarFeatureNode.HandleBusMessage(Message: TBusMessage): THandleBusMessageResult;
begin
   Assert(not ((Message is TRubbleCollectionMessage) or (Message is TDismantleMessage)), ClassName + ' should never see ' + Message.ClassName);
   Result := inherited;
end;

procedure TStarFeatureNode.ApplyVisibility();
begin
   Assert(Assigned(Parent));
   System.AddBroadVisibility([dmVisibleSpectrum], Parent);
end;

procedure TStarFeatureNode.Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter);
begin
   Writer.WriteCardinal(fcStar);
   Assert(StarID >= 0);
   Writer.WriteCardinal(StarID); // $R-
end;

procedure TStarFeatureNode.UpdateJournal(Journal: TJournalWriter);
begin
   Assert(StarID >= 0);
   Journal.WriteCardinal(StarID); // $R-
end;

procedure TStarFeatureNode.ApplyJournal(Journal: TJournalReader);
begin
   FStarID := Journal.ReadCardinal(); // $R-
end;

function TStarFeatureNode.GetAssetName(): UTF8String;
begin
   Result := StarNameOf(StarID);
end;

procedure TStarFeatureNode.DescribeExistentiality(var IsDefinitelyReal, IsDefinitelyGhost: Boolean);
begin
   IsDefinitelyReal := True;
end;

initialization
   RegisterFeatureClass(TStarFeatureClass);
end.