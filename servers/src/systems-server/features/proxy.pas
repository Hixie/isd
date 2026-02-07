{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit proxy;

interface

uses
   systems, serverstream, time, masses;

type
   TProxyFeatureClass = class(TFeatureClass)
   strict protected
      function GetFeatureNodeClass(): FeatureNodeReference; override;
   public
      constructor CreateFromTechnologyTree(const Reader: TTechTreeReader); override;
      function InitFeatureNode(ASystem: TSystem): TFeatureNode; override;
   end;

   TProxyFeatureNode = class(TFeatureNode)
   private
      FChild: TAssetNode;
   protected
      function GetMass(): TMass; override;
      function GetMassFlowRate(): TMassRate; override;
      function GetSize(): Double; override;
      procedure Walk(PreCallback: TPreWalkCallback; PostCallback: TPostWalkCallback); override;
      procedure Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter); override;
   public
      constructor Create(ASystem: TSystem; AChild: TAssetNode);
      destructor Destroy(); override;
      procedure AdoptChild(Child: TAssetNode); override;
      procedure DropChild(Child: TAssetNode); override;
      procedure UpdateJournal(Journal: TJournalWriter); override;
      procedure ApplyJournal(Journal: TJournalReader); override;
      property Child: TAssetNode read FChild;
   end;

implementation

uses
   sysutils, isdprotocol, exceptions, ttparser;


constructor TProxyFeatureClass.CreateFromTechnologyTree(const Reader: TTechTreeReader);
begin
   inherited Create();
end;

function TProxyFeatureClass.GetFeatureNodeClass(): FeatureNodeReference;
begin
   Result := TProxyFeatureNode;
end;

function TProxyFeatureClass.InitFeatureNode(ASystem: TSystem): TFeatureNode;
begin
   Result := TProxyFeatureNode.Create(ASystem, nil);
end;


constructor TProxyFeatureNode.Create(ASystem: TSystem; AChild: TAssetNode);
begin
   inherited Create(ASystem);
   try
      if (Assigned(AChild)) then
         AdoptChild(AChild);
   except
      ReportCurrentException();
      raise;
   end;
end;

destructor TProxyFeatureNode.Destroy();
begin
   FreeAndNil(FChild);
   inherited;
end;

procedure TProxyFeatureNode.AdoptChild(Child: TAssetNode);
begin
   inherited;
   FChild := Child;
end;

procedure TProxyFeatureNode.DropChild(Child: TAssetNode);
begin
   if (Child = FChild) then
      FChild := nil;
   inherited;
end;

function TProxyFeatureNode.GetMass(): TMass;
begin
   if (Assigned(FChild)) then
   begin
      Result := FChild.Mass;
   end
   else
      Result := TMass.Zero;
end;

function TProxyFeatureNode.GetMassFlowRate(): TMassRate;
begin
   if (Assigned(FChild)) then
   begin
      Result := FChild.MassFlowRate;
   end
   else
      Result := TMassRate.Zero;
end;

function TProxyFeatureNode.GetSize(): Double;
begin
   if (Assigned(FChild)) then
   begin
      Result := FChild.Size;
   end
   else
      Result := 0.0;
end;

procedure TProxyFeatureNode.Walk(PreCallback: TPreWalkCallback; PostCallback: TPostWalkCallback);
begin
   FChild.Walk(PreCallback, PostCallback);
end;

procedure TProxyFeatureNode.Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter);
begin
   Writer.WriteCardinal(fcProxy);
   if (Assigned(FChild) and FChild.IsVisibleFor(DynastyIndex)) then
   begin
      Writer.WriteCardinal(Child.ID(DynastyIndex));
   end
   else
      Writer.WriteCardinal(0);
end;

procedure TProxyFeatureNode.UpdateJournal(Journal: TJournalWriter);
begin
   Journal.WriteAssetNodeReference(FChild);
end;

procedure TProxyFeatureNode.ApplyJournal(Journal: TJournalReader);
var
   NewChild: TAssetNode;
begin
   NewChild := Journal.ReadAssetNodeReference(System);
   if (NewChild <> FChild) then
   begin
      if (Assigned(NewChild)) then
      begin
         AdoptChild(NewChild);
      end
      else
      begin
         DropChild(FChild);
      end;
   end;
end;

initialization
   RegisterFeatureClass(TProxyFeatureClass);
end.