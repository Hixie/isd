{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit size;

interface

uses
   systems, techtree;

type
   TSizeFeatureClass = class(TFeatureClass)
   strict private
      FSize: Double;
   strict protected
      function GetFeatureNodeClass(): FeatureNodeReference; override;
   public
      constructor Create(ASize: Double);
      constructor CreateFromTechnologyTree(Reader: TTechTreeReader); override;
      function InitFeatureNode(): TFeatureNode; override;
      property Size: Double read FSize;
   end;

   TSizeFeatureNode = class(TFeatureNode)
   protected
      FFeatureClass: TSizeFeatureClass;
      constructor CreateFromJournal(Journal: TJournalReader; AFeatureClass: TFeatureClass; ASystem: TSystem); override;
      function GetSize(): Double; override; // m
   public
      constructor Create(AFeatureClass: TSizeFeatureClass);
   end;

implementation

uses
   exceptions;

constructor TSizeFeatureClass.Create(ASize: Double);
begin
   inherited Create();
   FSize := ASize;
end;

constructor TSizeFeatureClass.CreateFromTechnologyTree(Reader: TTechTreeReader);
begin
   inherited Create();
   // feature: TSizeFeatureClass 20m;
   FSize := ReadLength(Reader.Tokens);
end;

function TSizeFeatureClass.GetFeatureNodeClass(): FeatureNodeReference;
begin
   Result := TSizeFeatureNode;
end;

function TSizeFeatureClass.InitFeatureNode(): TFeatureNode;
begin
   Result := TSizeFeatureNode.Create(Self);
end;


constructor TSizeFeatureNode.Create(AFeatureClass: TSizeFeatureClass);
begin
   inherited Create();
   FFeatureClass := AFeatureClass;
end;

constructor TSizeFeatureNode.CreateFromJournal(Journal: TJournalReader; AFeatureClass: TFeatureClass; ASystem: TSystem);
begin
   Assert(Assigned(AFeatureClass));
   FFeatureClass := AFeatureClass as TSizeFeatureClass;
   inherited CreateFromJournal(Journal, AFeatureClass, ASystem);
end;

function TSizeFeatureNode.GetSize(): Double;
begin
   Result := FFeatureClass.Size;
end;

initialization
   RegisterFeatureClass(TSizeFeatureClass);
end.