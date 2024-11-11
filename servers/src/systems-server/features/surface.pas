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

   TRegionArray = array of TAssetNode;
   
   TSurfaceFeatureNode = class(TFeatureNode)
   private
      FSize: Double;
      FRegions: TRegionArray; // can contain nils
      procedure AdoptRegion(Region: TAssetNode);
   protected
      procedure DropChild(Child: TAssetNode); override;
      function GetMass(): Double; override;
      function GetSize(): Double; override;
      function GetFeatureName(): UTF8String; override;
      procedure Walk(PreCallback: TPreWalkCallback; PostCallback: TPostWalkCallback); override;
      function HandleBusMessage(Message: TBusMessage): Boolean; override;
      procedure Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter; System: TSystem); override;
   public
      constructor Create(ASize: Double; ARegions: TRegionArray);
      destructor Destroy(); override;
      procedure UpdateJournal(Journal: TJournalWriter); override;
      procedure ApplyJournal(Journal: TJournalReader; System: TSystem); override;
   end;
   
implementation

uses
   sysutils, isdprotocol;

type
   PSurfaceData = ^TSurfaceData;
   TSurfaceData = bitpacked record
      // TODO: geology and position
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


constructor TSurfaceFeatureNode.Create(ASize: Double; ARegions: TRegionArray);
var
   Region: TAssetNode;
begin
   inherited Create();
   FSize := ASize;
   FRegions := ARegions;
   for Region in FRegions do
      AdoptRegion(Region);
end;

destructor TSurfaceFeatureNode.Destroy();
var
   Region: TAssetNode;
begin
   for Region in FRegions do
   begin
      if (Assigned(Region)) then
      begin
         DropChild(Region);
         Region.Free();
      end;
   end;
   inherited;
end;

procedure TSurfaceFeatureNode.AdoptRegion(Region: TAssetNode);
begin
   AdoptChild(Region);
   Region.ParentData := New(PSurfaceData);
   PSurfaceData(Region.ParentData)^.IsNew := True;
   PSurfaceData(Region.ParentData)^.IsChanged := True;
end;

procedure TSurfaceFeatureNode.DropChild(Child: TAssetNode);
begin
   Dispose(PSurfaceData(Child.ParentData));
   Child.ParentData := nil;
   inherited;
end;

function TSurfaceFeatureNode.GetMass(): Double;
var
   Region: TAssetNode;
begin
   Result := 0.0;
   for Region in FRegions do
      if (Assigned(Region)) then
         Result := Result + Region.Mass;
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
   Region: TAssetNode;
begin
   for Region in FRegions do
      if (Assigned(Region)) then
         Region.Walk(PreCallback, PostCallback);
end;

function TSurfaceFeatureNode.HandleBusMessage(Message: TBusMessage): Boolean;
var
   Region: TAssetNode;
begin
   // TODO: crash messages should pick a random region
   for Region in FRegions do
   begin
      if (Assigned(Region)) then
      begin
         Result := Region.HandleBusMessage(Message);
         if (Result) then
            exit;
      end;
   end;
end;

procedure TSurfaceFeatureNode.Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter; System: TSystem);
var
   Region: TAssetNode;
begin
   Writer.WriteCardinal(fcSurface);
   Writer.WriteCardinal(Length(FRegions));
   for Region in FRegions do
   begin
      Assert(Assigned(Region));
      Writer.WritePtrUInt(Region.ID(System));
   end;
end;

procedure TSurfaceFeatureNode.UpdateJournal(Journal: TJournalWriter);
var
   Region: TAssetNode;
   Index: Cardinal;
begin
   if (Length(FRegions) > 0) then
   begin
      for Index := High(FRegions) downto Low(FRegions) do // $R-
      begin
         if (not Assigned(FRegions[Index])) then
         begin
            Journal.WriteAssetChangeKind(ckRemove);
            Journal.WriteCardinal(Index);
            Delete(FRegions, Index, 1);
         end;
      end;
      for Region in FRegions do
      begin
         Assert(Assigned(Region));
         Assert(Assigned(Region.ParentData), 'No parent data on ' + Region.ClassName);
         if (PSurfaceData(Region.ParentData)^.IsChanged) then
         begin
            if (PSurfaceData(Region.ParentData)^.IsNew) then
            begin
               Journal.WriteAssetChangeKind(ckAdd);
               PSurfaceData(Region.ParentData)^.IsNew := False;
            end
            else
            begin
               Journal.WriteAssetChangeKind(ckChange);
            end;
            Journal.WriteAssetNodeReference(Region);
            // TODO: save any other details (position, geology, etc)
            PSurfaceData(Region.ParentData)^.IsChanged := False;
         end;
      end;
   end;
   Journal.WriteAssetChangeKind(ckEndOfList);
end;

procedure TSurfaceFeatureNode.ApplyJournal(Journal: TJournalReader; System: TSystem);

   procedure AddRegion();
   var
      Region: TAssetNode;
   begin
      Region := Journal.ReadAssetNodeReference();
      AdoptRegion(Region);
      Assert(Region.Parent = Self);
      SetLength(FRegions, Length(FRegions) + 1);
      FRegions[High(FRegions)] := Region; // TODO: performance?
      // TODO: read and update region position, geology
   end;

   procedure ChangeRegion();
   var
      Region: TAssetNode;
   begin
      Region := Journal.ReadAssetNodeReference();
      // TODO: update details (position, geology, etc)
      Assert(Region.Parent = Self);
   end;
   
   procedure RemoveRegion();
   var
      Index: Cardinal;
   begin
      Index := Journal.ReadCardinal();
      Assert(Length(FRegions) > Index);
      Delete(FRegions, Index, 1);
   end;

var
   AssetChangeKind: TAssetChangeKind;
begin
   repeat
      AssetChangeKind := Journal.ReadAssetChangeKind();
      case AssetChangeKind of
         ckAdd: AddRegion();
         ckChange: ChangeRegion();
         ckRemove: RemoveRegion();
         ckEndOfList: break;
      end;
   until False;
end;

end.