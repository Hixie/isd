{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit size;

interface

uses
   systems;

type
   TSizeFeatureClass = class(TFeatureClass)
   strict private
      FSize: Double;
   strict protected
      function GetFeatureNodeClass(): FeatureNodeReference; override;
      function GetDefaultSize(): Double; override;
   public
      constructor Create(ASize: Double);
      constructor CreateFromTechnologyTree(const Reader: TTechTreeReader); override;
      function InitFeatureNode(ASystem: TSystem): TFeatureNode; override;
      property Size: Double read FSize;
   end;

   TSizeFeatureNode = class(TFeatureNode)
   protected
      FFeatureClass: TSizeFeatureClass;
      constructor CreateFromJournal(Journal: TJournalReader; AFeatureClass: TFeatureClass; ASystem: TSystem); override;
      function GetSize(): Double; override; // m
   public
      constructor Create(ASystem: TSystem; AFeatureClass: TSizeFeatureClass);
   end;

implementation

uses
   exceptions, ttparser;

constructor TSizeFeatureClass.Create(ASize: Double);
begin
   inherited Create();
   FSize := ASize;
end;

constructor TSizeFeatureClass.CreateFromTechnologyTree(const Reader: TTechTreeReader);
begin
   inherited Create();
   // feature: TSizeFeatureClass 20m;
   FSize := ReadLength(Reader.Tokens);
end;

function TSizeFeatureClass.GetDefaultSize(): Double;
begin
   Result := FSize;
end;

function TSizeFeatureClass.GetFeatureNodeClass(): FeatureNodeReference;
begin
   Result := TSizeFeatureNode;
end;

function TSizeFeatureClass.InitFeatureNode(ASystem: TSystem): TFeatureNode;
begin
   Result := TSizeFeatureNode.Create(ASystem, Self);
end;


constructor TSizeFeatureNode.Create(ASystem: TSystem; AFeatureClass: TSizeFeatureClass);
begin
   inherited Create(ASystem);
   FFeatureClass := AFeatureClass;
end;

constructor TSizeFeatureNode.CreateFromJournal(Journal: TJournalReader; AFeatureClass: TFeatureClass; ASystem: TSystem);
begin
   Assert(Assigned(AFeatureClass));
   FFeatureClass := AFeatureClass as TSizeFeatureClass;
   inherited;
end;

function TSizeFeatureNode.GetSize(): Double;
begin
   Result := FFeatureClass.Size;
end;

initialization
   RegisterFeatureClass(TSizeFeatureClass);
end.