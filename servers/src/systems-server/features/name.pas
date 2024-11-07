{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit name;

interface

uses
   systems, serverstream, providers;

type
   // For assets that have globally known fixed names (e.g. stars).
   TAssetNameFeatureClass = class(TFeatureClass)
   strict protected
      function GetFeatureNodeClass(): FeatureNodeReference; override;
   public
      function InitFeatureNode(): TFeatureNode; override;
   end;

   TAssetNameFeatureNode = class(TFeatureNode, IAssetNameProvider)
   protected
      FAssetName: UTF8String;
      function GetMass(): Double; override;
      function GetSize(): Double; override;
      function GetFeatureName(): UTF8String; override;
      procedure Walk(PreCallback: TPreWalkCallback; PostCallback: TPostWalkCallback); override;
      function HandleBusMessage(Message: TBusMessage): Boolean; override;
      procedure Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter; System: TSystem); override;
      function GetAssetName(): UTF8String;
   public
      constructor Create(AAssetName: UTF8String);
      procedure RecordSnapshot(Journal: TJournalWriter); override;
      procedure ApplyJournal(Journal: TJournalReader; System: TSystem); override;
      property AssetName: UTF8String read FAssetName;
   end;

implementation

uses
   sysutils;

function TAssetNameFeatureClass.GetFeatureNodeClass(): FeatureNodeReference;
begin
   Result := TAssetNameFeatureNode;
end;

function TAssetNameFeatureClass.InitFeatureNode(): TFeatureNode;
begin
   Result := nil;
   raise Exception.Create('Cannot create a TAssetNameFeatureClass from a prototype; it must have a specified name.');
end;


constructor TAssetNameFeatureNode.Create(AAssetName: UTF8String);
begin
   inherited Create();
   FAssetName := AAssetName;
end;

function TAssetNameFeatureNode.GetMass(): Double;
begin
   Result := 0.0;
end;

function TAssetNameFeatureNode.GetSize(): Double;
begin
   Result := 0.0;
end;

function TAssetNameFeatureNode.GetFeatureName(): UTF8String;
begin
   Result := '';
end;

procedure TAssetNameFeatureNode.Walk(PreCallback: TPreWalkCallback; PostCallback: TPostWalkCallback);
begin
end;

function TAssetNameFeatureNode.HandleBusMessage(Message: TBusMessage): Boolean;
begin
   Result := False;
end;

procedure TAssetNameFeatureNode.Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter; System: TSystem);
begin
   // client receives this as a property of the asset via IAssetNameProvider
end;

procedure TAssetNameFeatureNode.RecordSnapshot(Journal: TJournalWriter);
begin
   Journal.WriteString(FAssetName);
end;

procedure TAssetNameFeatureNode.ApplyJournal(Journal: TJournalReader; System: TSystem);
begin
   FAssetName := Journal.ReadString();
end;
   
function TAssetNameFeatureNode.GetAssetName(): UTF8String;
begin
   Result := AssetName;
end;

end.