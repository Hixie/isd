{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit surface;

interface

uses
   systems, serverstream;

type
   TSurfaceFeatureClass = class(TFeatureClass)
   strict protected
      function GetFeatureNodeClass(): FeatureNodeReference; override;
   public
      function InitFeatureNode(): TFeatureNode; override;
   end;
   
   TSurfaceFeatureNode = class(TFeatureNode)
   private
      FSize: Double;
      FChildren: TAssetNodeArray;
      procedure AdoptRegionChild(Child: TAssetNode);
   protected
      procedure DropChild(Child: TAssetNode); override;
      function GetMass(): Double; override;
      function GetSize(): Double; override;
      function GetFeatureName(): UTF8String; override;
      procedure Walk(PreCallback: TPreWalkCallback; PostCallback: TPostWalkCallback); override;
      function HandleBusMessage(Message: TBusMessage): Boolean; override;
      procedure Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter; CachedSystem: TSystem); override;
   public
      constructor Create(ASize: Double; AChildren: TAssetNodeArray);
      destructor Destroy(); override;
      procedure UpdateJournal(Journal: TJournalWriter); override;
      procedure ApplyJournal(Journal: TJournalReader; CachedSystem: TSystem); override;
   end;
   
implementation

uses
   sysutils, isdprotocol;

type
   PSurfaceData = ^TSurfaceData;
   TSurfaceData = bitpacked record
      // TODO: geology and position
      Index: Cardinal;
      IsNew: Boolean;
      IsChanged: Boolean;
   end;


function TSurfaceFeatureClass.GetFeatureNodeClass(): FeatureNodeReference;
begin
   Result := TSurfaceFeatureNode;
end;

function TSurfaceFeatureClass.InitFeatureNode(): TFeatureNode;
begin
   Result := nil;
   raise Exception.Create('Cannot create a TSurfaceFeatureNode from a prototype, it must have a size.');
end;


constructor TSurfaceFeatureNode.Create(ASize: Double; AChildren: TAssetNodeArray);
var
   Child: TAssetNode;
begin
   inherited Create();
   FSize := ASize;
   for Child in AChildren do
      AdoptRegionChild(Child);
end;

destructor TSurfaceFeatureNode.Destroy();
var
   Child: TAssetNode;
begin
   for Child in FChildren do
      Child.Free();
   inherited;
end;

procedure TSurfaceFeatureNode.AdoptRegionChild(Child: TAssetNode);
begin
   AdoptChild(Child);
   Child.ParentData := New(PSurfaceData);
   PSurfaceData(Child.ParentData)^.IsNew := True;
   PSurfaceData(Child.ParentData)^.IsChanged := True;
   SetLength(FChildren, Length(FChildren) + 1);
   FChildren[High(FChildren)] := Child;
   PSurfaceData(Child.ParentData)^.Index := High(FChildren); // $R-
end;

procedure TSurfaceFeatureNode.DropChild(Child: TAssetNode);
var
   Index: Cardinal;
begin
   Delete(FChildren, PSurfaceData(Child.ParentData)^.Index, 1);
   if (PSurfaceData(Child.ParentData)^.Index < Length(FChildren)) then
      for Index := PSurfaceData(Child.ParentData)^.Index to High(FChildren) do // $R-
         PSurfaceData(FChildren[Index].ParentData)^.Index := Index;
   Dispose(PSurfaceData(Child.ParentData));
   Child.ParentData := nil;
   inherited;
end;

function TSurfaceFeatureNode.GetMass(): Double;
var
   Child: TAssetNode;
begin
   Result := 0.0;
   for Child in FChildren do
      Result := Result + Child.Mass;
end;

function TSurfaceFeatureNode.GetSize(): Double;
begin
   Result := FSize;
end;

function TSurfaceFeatureNode.GetFeatureName(): UTF8String;
begin
   Result := '';
end;

procedure TSurfaceFeatureNode.Walk(PreCallback: TPreWalkCallback; PostCallback: TPostWalkCallback);
var
   Child: TAssetNode;
begin
   for Child in FChildren do
      Child.Walk(PreCallback, PostCallback);
end;

function TSurfaceFeatureNode.HandleBusMessage(Message: TBusMessage): Boolean;
var
   Child: TAssetNode;
begin
   // TODO: crash messages should pick a random region
   for Child in FChildren do
   begin
      Result := Child.HandleBusMessage(Message);
      if (Result) then
         exit;
   end;
   Result := False;
end;

procedure TSurfaceFeatureNode.Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter; CachedSystem: TSystem);
var
   Child: TAssetNode;
begin
   Writer.WriteCardinal(fcSurface);
   Writer.WriteCardinal(Length(FChildren));
   for Child in FChildren do
   begin
      Assert(Assigned(Child));
      Writer.WriteCardinal(Child.ID(CachedSystem, DynastyIndex));
   end;
end;

procedure TSurfaceFeatureNode.UpdateJournal(Journal: TJournalWriter);
var
   Child: TAssetNode;
begin
   if (Length(FChildren) > 0) then
   begin
      for Child in FChildren do
      begin
         Assert(Assigned(Child));
         Assert(Assigned(Child.ParentData), 'No parent data on ' + Child.ClassName);
         if (PSurfaceData(Child.ParentData)^.IsChanged) then
         begin
            if (PSurfaceData(Child.ParentData)^.IsNew) then
            begin
               Journal.WriteAssetChangeKind(ckAdd);
               PSurfaceData(Child.ParentData)^.IsNew := False;
            end
            else
            begin
               Journal.WriteAssetChangeKind(ckChange);
            end;
            Journal.WriteAssetNodeReference(Child);
            // TODO: save any other details (position, geology, etc)
            PSurfaceData(Child.ParentData)^.IsChanged := False;
         end;
      end;
   end;
   Journal.WriteAssetChangeKind(ckEndOfList);
end;

procedure TSurfaceFeatureNode.ApplyJournal(Journal: TJournalReader; CachedSystem: TSystem);

   procedure AddChild();
   var
      Child: TAssetNode;
   begin
      Child := Journal.ReadAssetNodeReference();
      AdoptRegionChild(Child); // TODO: performance?
      // TODO: read and update region position, geology
      Assert(Child.Parent = Self);
   end;

   procedure ChangeChild();
   var
      Child: TAssetNode;
   begin
      Child := Journal.ReadAssetNodeReference();
      // TODO: update details (position, geology, etc)
      Assert(Child.Parent = Self);
   end;

var
   AssetChangeKind: TAssetChangeKind;
begin
   repeat
      AssetChangeKind := Journal.ReadAssetChangeKind();
      case AssetChangeKind of
         ckAdd: AddChild();
         ckChange: ChangeChild();
         ckEndOfList: break;
      end;
   until False;
end;

end.