{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit name;

interface

uses
   systems, serverstream, providers, tttokenizer;

type
   // For assets that have globally known fixed names (e.g. stars).
   TAssetNameFeatureClass = class(TFeatureClass)
   strict protected
      FDefaultName: UTF8String;
      function GetFeatureNodeClass(): FeatureNodeReference; override;
   public
      constructor CreateFromTechnologyTree(const Reader: TTechTreeReader); override;
      function InitFeatureNode(ASystem: TSystem): TFeatureNode; override;
   end;

   TAssetNameFeatureNode = class(TFeatureNode, IAssetNameProvider)
   protected
      FAssetName: UTF8String;
      procedure Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter); override;
      function GetAssetName(): UTF8String;
   public
      constructor Create(ASystem: TSystem; AAssetName: UTF8String);
      procedure UpdateJournal(Journal: TJournalWriter); override;
      procedure ApplyJournal(Journal: TJournalReader); override;
      property AssetName: UTF8String read FAssetName;
   end;

implementation

uses
   sysutils, ttparser;

constructor TAssetNameFeatureClass.CreateFromTechnologyTree(const Reader: TTechTreeReader);
begin
   inherited Create();
   FDefaultName := Reader.Tokens.ReadString();
end;

function TAssetNameFeatureClass.GetFeatureNodeClass(): FeatureNodeReference;
begin
   Result := TAssetNameFeatureNode;
end;

function TAssetNameFeatureClass.InitFeatureNode(ASystem: TSystem): TFeatureNode;
begin
   Result := TAssetNameFeatureNode.Create(ASystem, FDefaultName);
end;


constructor TAssetNameFeatureNode.Create(ASystem: TSystem; AAssetName: UTF8String);
begin
   inherited Create(ASystem);
   FAssetName := AAssetName;
end;

procedure TAssetNameFeatureNode.Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter);
begin
   // client receives this as a property of the asset via IAssetNameProvider
end;

procedure TAssetNameFeatureNode.UpdateJournal(Journal: TJournalWriter);
begin
   Journal.WriteString(FAssetName);
end;

procedure TAssetNameFeatureNode.ApplyJournal(Journal: TJournalReader);
begin
   FAssetName := Journal.ReadString();
end;

function TAssetNameFeatureNode.GetAssetName(): UTF8String;
begin
   Result := AssetName;
end;

initialization
   RegisterFeatureClass(TAssetNameFeatureClass);
end.