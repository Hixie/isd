{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit utils;

interface

uses
   model, endtoend, stringstream;

const
   TimeFactor = 500;
   Seconds = 1000;
   Minutes = 60 * 1000;
   Hours = 60 * Minutes;
   Days = 24 * Hours;

procedure DescribeUpdate(ModelSystem: TModelSystem);
function FindColonyShip(ModelSystem: TModelSystem): TModelAsset;
procedure ExpectUpdate(SystemsServer: TServerWebSocket; ModelSystem: TModelSystem; var MinTime, MaxTime: Int64; var TimePinned: Boolean; ExpectedAssetCount: Cardinal);
procedure ExpectTechnology(SystemsServer: TServerWebSocket; ModelSystem: TModelSystem; var MinTime, MaxTime: Int64; var TimePinned: Boolean; ExpectBody: UTF8String = ''; FetchUpdate: Boolean = True);
function GetAssetClassFromBuildingsList(Response: TStringStreamReader; Target: UTF8String): Int32;
generic function GetUpdatedFeature<T: TModelFeature>(ModelSystem: TModelSystem; Index: Integer = -1): T;

implementation

uses
   sysutils, harness, plasticarrays, stringutils;

procedure DescribeUpdate(ModelSystem: TModelSystem);
var
   UpdatedNodes: TAssetList;
   Asset: TModelAsset;
   S: UTF8String;
   Description: specialize PlasticArray<UTF8String, UTF8StringUtils>;
begin
   UpdatedNodes := ModelSystem.GetUpdatedAssets();
   Writeln('-- ', Length(UpdatedNodes), ' nodes updated -- system ID ', ModelSystem.SystemID, ' --');
   for Asset in UpdatedNodes do
   begin
      Writeln(' - #', Asset.ID, ' ', Asset.ToString(), ' (', Asset.FeatureCount, ' features)');
      Description.Empty();
      Asset.Describe(Description, '   ');
      for S in Description do
         Writeln(S);
   end;
   Writeln('----');
end;

function FindColonyShip(ModelSystem: TModelSystem): TModelAsset;

   function IsColonyShip(Asset: TModelAsset): Boolean;
   var
      Feature: TModelFeature;
   begin
      Feature := Asset.Features[TModelPlotControlFeature];
      Result := Assigned(Feature) and ((Feature as TModelPlotControlFeature).Kind = $01);
   end;

var
   Assets: array of TModelAsset;
begin
   Assets := ModelSystem.FindAssets(@IsColonyShip);
   Verify(Length(Assets) = 1);
   Result := Assets[0];
end;

procedure ExpectUpdate(SystemsServer: TServerWebSocket; ModelSystem: TModelSystem; var MinTime, MaxTime: Int64; var TimePinned: Boolean; ExpectedAssetCount: Cardinal);
var
   Update: TServerStreamReader;
begin
   Update := SystemsServer.GetStreamReader(SystemsServer.ReadWebSocketBinaryMessage());
   ModelSystem.UpdateFrom(Update);
   Update.ReadEnd();
   FreeAndNil(Update);
   if (TimePinned) then
   begin
      Verify(ModelSystem.CurrentTime >= MinTime);
      TimePinned := False;
   end
   else
   begin
      Verify(ModelSystem.CurrentTime > MinTime);
   end;
   MinTime := ModelSystem.CurrentTime;
   Verify(ModelSystem.CurrentTime <= MaxTime);
   if (ModelSystem.UpdateCount <> ExpectedAssetCount) then
   begin
      DescribeUpdate(ModelSystem);
      raise Exception.CreateFmt('Expected %d assets to be updated, but got %d updates', [ExpectedAssetCount, ModelSystem.UpdateCount]);
   end;
end;

procedure ExpectTechnology(SystemsServer: TServerWebSocket; ModelSystem: TModelSystem; var MinTime, MaxTime: Int64; var TimePinned: Boolean; ExpectBody: UTF8String = ''; FetchUpdate: Boolean = True);
var
   UpdatedNodes: TAssetList;
   Asset, InnerAsset: TModelAsset;
   Feature: TModelFeature;
   FoundColonyShip, FoundMessage: Boolean;
   Body, S: UTF8String;
   Description: specialize PlasticArray<UTF8String, UTF8StringUtils>;
begin
   Assert(FetchUpdate or (ExpectBody <> ''));
   if (FetchUpdate) then
      ExpectUpdate(SystemsServer, ModelSystem, MinTime, MaxTime, TimePinned, 2);
   UpdatedNodes := ModelSystem.GetUpdatedAssets();
   FoundColonyShip := False;
   FoundMessage := False;
   for Asset in UpdatedNodes do
   begin
      Feature := Asset.Features[TModelPlotControlFeature];
      if (Assigned(Feature)) then
      begin
         Verify(not FoundColonyShip);
         FoundColonyShip := True;
      end;
      Feature := Asset.Features[TModelMessageFeature];
      if (Assigned(Feature)) then
      begin
         if (ExpectBody <> '') then
         begin
            if (FoundMessage) then
            begin
               UpdatedNodes := ModelSystem.GetUpdatedAssets();
               // TODO: refactor so the following code isn't duplicated here and below
               Writeln('-- detected multiple messages (expected one) --');
               for InnerAsset in UpdatedNodes do
               begin
                  Writeln(' - #', InnerAsset.ID, ' ', InnerAsset.ToString(), ' (', InnerAsset.FeatureCount, ' features)');
                  Description.Empty();
                  InnerAsset.Describe(Description, '   ');
                  for S in Description do
                     Writeln(S);
               end;
               Writeln('----');
               raise Exception.Create('Detected multiple messages, expected one');
            end;
            Verify(not FoundMessage);
            Body := (Feature as TModelMessageFeature).Body;
            if (Pos(ExpectBody, Body) <> 1) then
            begin
               raise Exception.CreateFmt('unexpected technology; wanted "%s" but found: %s', [ExpectBody, Body]);
            end;
         end;
         FoundMessage := True;
      end;
   end;
   if ((not FoundColonyShip) or (not FoundMessage)) then
   begin
      // TODO: refactor so the following code isn't duplicated here and above
      Writeln('-- missing message or colony ship --');
      for InnerAsset in UpdatedNodes do
      begin
         Writeln(' - #', InnerAsset.ID, ' ', InnerAsset.ToString(), ' (', InnerAsset.FeatureCount, ' features)');
         Description.Empty();
         InnerAsset.Describe(Description, '   ');
         for S in Description do
            Writeln(S);
      end;
      Writeln('----');
      raise Exception.Create('Missing message or colony ship');
   end;
end;

function GetAssetClassFromBuildingsList(Response: TStringStreamReader; Target: UTF8String): Int32;
begin
   Response.Rewind();
   VerifyPositiveResponse(Response);
   while (Response.CanReadMore) do
   begin
      Result := Response.ReadLongint();
      Response.ReadString(); // icon
      if (Response.ReadString() = Target) then // name
      begin
         // found building, exit
         Response.Bail();
         exit;
      end;
      Response.ReadString(); // description
   end;
   Result := 0;
   raise Exception.CreateFmt('could not find "%s" in server buildings list (%s)', [Target, Response.DebugMessage]);
end;

generic function GetUpdatedFeature<T>(ModelSystem: TModelSystem; Index: Integer = -1): T;
var
   UpdatedNodes: TAssetList;
   Asset: TModelAsset;
   Feature: TModelFeature;
begin
   Result := nil;
   UpdatedNodes := ModelSystem.GetUpdatedAssets();
   for Asset in UpdatedNodes do
   begin
      Feature := Asset.Features[T];
      if (Assigned(Feature)) then
      begin
         if (Index < 0) then
         begin
            if (Assigned(Result)) then
               raise Exception.CreateFmt('multiple updated nodes have requested feature (%s)', [T.ClassName]);
            Result := T(Feature); {as T}
         end
         else
         if (Index = 0) then
         begin
            Result := T(Feature); {as T}
            exit;
         end
         else
         begin
            Dec(Index);
         end;
      end;
   end;
   if (not Assigned(Result)) then
   begin
      Writeln('Updated assets:');
      for Asset in UpdatedNodes do
      begin
         Writeln(' + ', Asset.ToString(), ': ');
         if (Asset.FeatureCount > 0) then
         begin
            for Feature in Asset.GetFeatures() do
            begin
               Writeln('    - ', Feature.ToString());
            end;
         end
         else
            Writeln('     No features.');
      end;
      raise Exception.CreateFmt('could not find enough updated nodes with requested feature (%s)', [T.ClassName]);
   end;
   Verify(Assigned(Result));
end;

end.