{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit name;

interface

uses
   systems, serverstream, providers, techtree, tttokenizer;

type
   // For assets that have globally known fixed names (e.g. stars).
   TAssetNameFeatureClass = class(TFeatureClass)
   strict protected
      function GetFeatureNodeClass(): FeatureNodeReference; override;
   public
      constructor CreateFromTechnologyTree(Reader: TTechTreeReader); override;
      function InitFeatureNode(): TFeatureNode; override;
   end;

   TAssetNameFeatureNode = class(TFeatureNode, IAssetNameProvider)
   protected
      FAssetName: UTF8String;
      procedure Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter; CachedSystem: TSystem); override;
      function GetAssetName(): UTF8String;
   public
      constructor Create(AAssetName: UTF8String);
      procedure UpdateJournal(Journal: TJournalWriter; CachedSystem: TSystem); override;
      procedure ApplyJournal(Journal: TJournalReader; CachedSystem: TSystem); override;
      property AssetName: UTF8String read FAssetName;
   end;

implementation

uses
   sysutils;

constructor TAssetNameFeatureClass.CreateFromTechnologyTree(Reader: TTechTreeReader);
begin
   Reader.Tokens.Error('Feature class %s is reserved for internal asset classes', [ClassName]);
end;

function TAssetNameFeatureClass.GetFeatureNodeClass(): FeatureNodeReference;
begin
   Result := TAssetNameFeatureNode;
end;

function TAssetNameFeatureClass.InitFeatureNode(): TFeatureNode;
begin
   Result := nil;
   raise Exception.Create('Cannot create a TAssetNameFeatureNode from a prototype; it must have a specified name.');
end;


constructor TAssetNameFeatureNode.Create(AAssetName: UTF8String);
begin
   inherited Create();
   FAssetName := AAssetName;
end;

procedure TAssetNameFeatureNode.Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter; CachedSystem: TSystem);
begin
   // client receives this as a property of the asset via IAssetNameProvider
end;

procedure TAssetNameFeatureNode.UpdateJournal(Journal: TJournalWriter; CachedSystem: TSystem);
begin
   Journal.WriteString(FAssetName);
end;

procedure TAssetNameFeatureNode.ApplyJournal(Journal: TJournalReader; CachedSystem: TSystem);
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