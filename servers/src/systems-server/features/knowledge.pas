{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit knowledge;

interface

uses
   systems, systemdynasty, serverstream;

type
   TKnowledgeBusMessage = class abstract(TBusMessage) end;
   
   TCollectKnownMaterialsMessage = class(TKnowledgeBusMessage)
      FKnownMaterials: TMaterialHashSet;
      FOwner: TDynasty;
   public
      constructor Create(AKnownMaterials: TMaterialHashSet; AOwner: TDynasty);
      procedure AddKnownMaterial(Material: TMaterial); inline;
      property Owner: TDynasty read FOwner;
   end;

type
   TKnowledgeBusFeatureClass = class(TFeatureClass)
   strict protected
      function GetFeatureNodeClass(): FeatureNodeReference; override;
   public
      function InitFeatureNode(): TFeatureNode; override;
   end;

   TKnowledgeBusFeatureNode = class(TFeatureNode)
   protected
      function GetMass(): Double; override;
      function GetSize(): Double; override;
      function GetFeatureName(): UTF8String; override;
      procedure Walk(PreCallback: TPreWalkCallback; PostCallback: TPostWalkCallback); override;
      procedure InjectBusMessage(Message: TBusMessage); override;
      function HandleBusMessage(Message: TBusMessage): Boolean; override;
      procedure Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter; System: TSystem); override;
   public
      procedure RecordSnapshot(Journal: TJournalWriter); override;
      procedure ApplyJournal(Journal: TJournalReader); override;
   end;

implementation

uses
   sysutils;

constructor TCollectKnownMaterialsMessage.Create(AKnownMaterials: TMaterialHashSet; AOwner: TDynasty);
begin
   inherited Create();
   FKnownMaterials := AKnownMaterials;
   FOwner := AOwner;
end;

procedure TCollectKnownMaterialsMessage.AddKnownMaterial(Material: TMaterial);
begin
   FKnownMaterials.Add(Material);
end;


function TKnowledgeBusFeatureClass.GetFeatureNodeClass(): FeatureNodeReference;
begin
   Result := TKnowledgeBusFeatureNode;
end;

function TKnowledgeBusFeatureClass.InitFeatureNode(): TFeatureNode;
begin
   Result := TKnowledgeBusFeatureNode.Create();
end;


function TKnowledgeBusFeatureNode.GetMass(): Double;
begin
   Result := 0.0;
end;

function TKnowledgeBusFeatureNode.GetSize(): Double;
begin
   Result := 0.0;
end;

function TKnowledgeBusFeatureNode.GetFeatureName(): UTF8String;
begin
   Result := '';
end;

procedure TKnowledgeBusFeatureNode.Walk(PreCallback: TPreWalkCallback; PostCallback: TPostWalkCallback);
begin
end;

procedure TKnowledgeBusFeatureNode.InjectBusMessage(Message: TBusMessage);
var
   Handled: Boolean;
begin
   if (Message is TKnowledgeBusMessage) then
   begin
      Handled := Parent.HandleBusMessage(Message);
      if (not Handled) then
         Message.Unhandled();
   end;
end;

function TKnowledgeBusFeatureNode.HandleBusMessage(Message: TBusMessage): Boolean;
begin
   Result := False;
end;

procedure TKnowledgeBusFeatureNode.Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter; System: TSystem);
begin
end;

procedure TKnowledgeBusFeatureNode.RecordSnapshot(Journal: TJournalWriter);
begin
end;

procedure TKnowledgeBusFeatureNode.ApplyJournal(Journal: TJournalReader);
begin
end;

end.