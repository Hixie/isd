{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit stellar;

interface

uses
   sysutils, systems, astronomy, providers, serverstream;

type
   TStarFeatureClass = class(TFeatureClass)
   strict protected
      function GetFeatureNodeClass(): FeatureNodeReference; override;
   public
      function InitFeatureNode(): TFeatureNode; override;
   end;

   TStarFeatureNode = class(TFeatureNode, IAssetNameProvider)
   protected
      FStarID: TStarID;
      function GetCategory(): TStarCategory; inline;
      function GetMass(): Double; override;
      function GetSize(): Double; override;
      function GetFeatureName(): UTF8String; override;
      procedure Walk(PreCallback: TPreWalkCallback; PostCallback: TPostWalkCallback); override;
      function HandleBusMessage(Message: TBusMessage): Boolean; override;
      procedure ApplyVisibility(VisibilityHelper: TVisibilityHelper); override;
      procedure Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter; System: TSystem); override;
      function GetAssetName(): UTF8String;
   public
      constructor Create(AStarID: TStarID);
      procedure RecordSnapshot(Journal: TJournalWriter); override;
      procedure ApplyJournal(Journal: TJournalReader); override;
      property Category: TStarCategory read GetCategory;
      property StarID: TStarID read FStarID;
   end;

implementation

uses
   isdprotocol;

const
   MassSalt = $04551455;
   SizeSalt = $51535153;

function TStarFeatureClass.GetFeatureNodeClass(): FeatureNodeReference;
begin
   Result := TStarFeatureNode;
end;

function TStarFeatureClass.InitFeatureNode(): TFeatureNode;
begin
   Result := nil;
   // TODO: create a technology that knows how to create a star and generate a new ID for it.
   raise Exception.Create('Cannot create a TStarFeatureNode from a prototype; it must have a unique ID.');
end;


constructor TStarFeatureNode.Create(AStarID: TStarID);
begin
   inherited Create();
   FStarID := AStarID;
end;

function TStarFeatureNode.GetCategory(): TStarCategory;
begin
   Result := CategoryOf(StarID);
end;

function TStarFeatureNode.GetMass(): Double;
begin
   case Category of
      2: Result := 30.0e30;
      3: Result := 0.7e30;
      4: Result := 1.0e30;
      5: Result := 8.2e30;
      6: Result := 2.0e30;
      7: Result := 15.8e30;
      8: Result := 5.2e30;
      9: Result := 10.0e30;
      10: Result := 100.0e30;
   else
      Assert(False);
      Result := 0.0;
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

function TStarFeatureNode.GetFeatureName(): UTF8String;
begin
   Result := '';
end;

procedure TStarFeatureNode.Walk(PreCallback: TPreWalkCallback; PostCallback: TPostWalkCallback);
begin
end;

function TStarFeatureNode.HandleBusMessage(Message: TBusMessage): Boolean;
begin
   Result := False;
end;

procedure TStarFeatureNode.ApplyVisibility(VisibilityHelper: TVisibilityHelper);
begin
   Assert(Assigned(Parent));
   VisibilityHelper.AddBroadVisibility([dmVisibleSpectrum], Parent);
end;

procedure TStarFeatureNode.Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter; System: TSystem);
begin
   Writer.WriteCardinal(fcStar);
   Assert(StarID >= 0);
   Writer.WriteCardinal(StarID); // $R-
end;

procedure TStarFeatureNode.RecordSnapshot(Journal: TJournalWriter);
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

end.