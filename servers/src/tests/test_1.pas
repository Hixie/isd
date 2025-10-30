{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit test_1;

interface

implementation

uses
   sysutils, harness, endtoend, stringstream, isdprotocol, model, binarystream, plasticarrays, stringutils;

const
   TimeFactor = 500;
   Minutes = 60 * 1000;
   Hours = 60 * Minutes;
   Days = 24 * Hours;

type
   TTest = class(TIsdServerTest)
      procedure RunTestBody(); override;
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
   UpdatedNodes: TAssetList;
   Asset: TModelAsset;
   S: UTF8String;
   Description: specialize PlasticArray<UTF8String, UTF8StringUtils>;
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
      Description.Init();
      UpdatedNodes := ModelSystem.GetUpdatedAssets();
      Writeln('-- ', Length(UpdatedNodes), ' nodes updated (expected ', ExpectedAssetCount, ') -- system ID ', ModelSystem.SystemID, ' --');
      for Asset in UpdatedNodes do
      begin
         Writeln(' - #', Asset.ID, ' ', Asset.ToString(), ' (', Asset.FeatureCount, ' features)');
         Description.Empty();
         Asset.Describe(Description, '   ');
         for S in Description do
            Writeln(S);
      end;
      Writeln('----');
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
               Description.Init();
               UpdatedNodes := ModelSystem.GetUpdatedAssets();
               // TODO: refactor so the following code isn't duplicated here and above
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

generic function GetUpdatedFeature<T: TModelFeature>(ModelSystem: TModelSystem; Index: Integer = -1): T;
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
            Result := Feature as T;
         end
         else
         if (Index = 0) then
         begin
            Result := Feature as T;
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

function GetAssetClassFromBuildingsList(List: TStringStreamReader; Target: UTF8String): Int32;
begin
   while (List.CanReadMore) do
   begin
      Result := List.ReadLongint();
      List.ReadString(); // icon
      if (List.ReadString() = Target) then // name
      begin
         // found building, exit
         List.Bail();
         exit;
      end;
      List.ReadString(); // description
   end;
   Result := 0;
   raise Exception.CreateFmt('could not find "%s" in server buildings list (%s)', [Target, List.DebugMessage]);
end;

procedure TTest.RunTestBody();
var
   ModelSystem: TModelSystem;
   SystemsServerIPC, LoginServerIPC: TServerIPCSocket;
   MinTime, MaxTime: Int64;
   TimePinned: Boolean;

   procedure AdvanceTime(Delta: Int64);
   begin
      Verify(ModelSystem.CurrentTime = MinTime);
      Verify(ModelSystem.CurrentTime <= MaxTime);
      MinTime := MaxTime;
      SystemsServerIPC.AdvanceClock(Delta);
      LoginServerIPC.AdvanceClock(Delta);
      TimePinned := False;
      Inc(MaxTime, Delta * TimeFactor);
   end;

var
   Response: TStringStreamReader;
   // Username, Password: UTF8String;
   DynastyID: QWord;
   DynastyServerURL, Token: UTF8String;
   SystemsServerCount: QWord;
   Index: QWord;
   LoginServer, DynastyServer, SystemsServer: TServerWebSocket;
   ColonyShip, HomeRegion, Miner: TModelAsset;
   DrillBit: TModelMiningFeature;
   Grid: TModelGridFeature;
   AssetClass: Int32;
   Scores: TBinaryStreamReader;
begin
   // Check high scores with no players.
   LoginServer := FLoginServer.ConnectWebSocket();
   LoginServer.SendWebSocketStringMessage('0'#00'get-high-scores'#00);
   Scores := LoginServer.GetStreamReader(LoginServer.ReadWebSocketBinaryMessage());
   Verify(Scores.ReadCardinal() = 0); // high score marker
   Scores.ReadEnd();
   FreeAndNil(Scores);
   Response := TStringStreamReader.Create(LoginServer.ReadWebSocketStringMessage());
   VerifyPositiveResponse(Response);
   VerifyEndOfResponse(Response);

   // Create account.
   LoginServer.SendWebSocketStringMessage('0'#00'new'#00);
   Response := TStringStreamReader.Create(LoginServer.ReadWebSocketStringMessage());
   VerifyPositiveResponse(Response);
   {Username :=} Response.ReadString();
   {Password :=} Response.ReadString();
   DynastyServerURL := Response.ReadString();
   Token := Response.ReadString();
   Verify(DynastyServerURL = 'wss://127.0.0.1:40001/');
   VerifyEndOfResponse(Response);

   // Check high scores.
   LoginServer.SendWebSocketStringMessage('0'#00'get-high-scores'#00);
   Scores := LoginServer.GetStreamReader(LoginServer.ReadWebSocketBinaryMessage());
   Verify(Scores.ReadCardinal() = 0); // high score marker
   Verify(Scores.ReadCardinal() = 1); // dynasty
   Verify(Scores.ReadCardinal() = 1); // last data point
   Verify(Scores.ReadCardinal() = 1); // number of data points
   Verify(Scores.ReadInt64() = 0); // system start time
   Verify(Scores.ReadDouble() = 100.0); // default happiness
   Scores.ReadEnd();
   FreeAndNil(Scores);
   Response := TStringStreamReader.Create(LoginServer.ReadWebSocketStringMessage());
   VerifyPositiveResponse(Response);
   VerifyEndOfResponse(Response);

   // Check with dynasty server.
   DynastyServer := FDynastiesServers[0].ConnectWebSocket();
   DynastyServer.SendWebSocketStringMessage('0'#00'login'#00 + Token + #00);
   Response := TStringStreamReader.Create(DynastyServer.ReadWebSocketStringMessage());
   VerifyPositiveResponse(Response);
   DynastyID := Response.ReadQWord();
   Verify(DynastyID = 1);
   SystemsServerCount := Response.ReadQWord();
   Verify(SystemsServerCount = 1);
   for Index := 0 to SystemsServerCount - 1 do // $R-
      Verify(Response.ReadString() = 'wss://127.0.0.1:40002/');
   VerifyEndOfResponse(Response);

   // Log in to system server.
   SystemsServer := FSystemsServers[0].ConnectWebSocket();
   SystemsServer.SendWebSocketStringMessage('0'#00'login'#00 + Token + #00);
   Response := TStringStreamReader.Create(SystemsServer.ReadWebSocketStringMessage());
   VerifyPositiveResponse(Response);
   Verify(Response.ReadQWord() = fcHighestKnownFeatureCode);
   VerifyEndOfResponse(Response);

   SystemsServerIPC := FSystemsServers[0].ConnectIPCSocket();
   LoginServerIPC := FLoginServer.ConnectIPCSocket();

   ModelSystem := TModelSystem.Create();
   MinTime := 0;
   MaxTime := 0;
   TimePinned := True;

   // Check update from system server.
   ExpectUpdate(SystemsServer, ModelSystem, MinTime, MaxTime, TimePinned, 127);
   Verify(ModelSystem.CurrentTime = MaxTime);
   ColonyShip := FindColonyShip(ModelSystem);
   Verify(ColonyShip.Parent.HasFeature(TModelOrbitFeature));

   AdvanceTime(2 * Minutes); // (wall-clock minutes, not in-game minutes) crash the colony ship
   ExpectTechnology(SystemsServer, ModelSystem, MinTime, MaxTime, TimePinned, 'Don''t mind the holes');
   Verify(ModelSystem.CurrentTime = 1 * Hours);

   ExpectTechnology(SystemsServer, ModelSystem, MinTime, MaxTime, TimePinned, 'Apologies please don''t evict us');
   Verify(ModelSystem.CurrentTime = 3 * Hours);

   // Expect: Crash and technology.
   ExpectUpdate(SystemsServer, ModelSystem, MinTime, MaxTime, TimePinned, 10);
   Verify(ModelSystem.CurrentTime < 1 * Days);
   Verify(FindColonyShip(ModelSystem) = ColonyShip);
   Verify(ColonyShip.Parent.HasFeature(TModelRubblePileFeature));
   Grid := specialize GetUpdatedFeature<TModelGridFeature>(ModelSystem);
   HomeRegion := Grid.Parent;
   Verify(Grid.Width = 3);
   Verify(Grid.Height = 3);
   Verify(Grid.Children.Length = 1);
   Verify(ModelSystem.Assets[Grid.Children[0].AssetID] = ColonyShip.Parent);

   ExpectTechnology(SystemsServer, ModelSystem, MinTime, MaxTime, TimePinned, 'Drill!'#10);
   ExpectTechnology(SystemsServer, ModelSystem, MinTime, MaxTime, TimePinned, 'Iron team'#10);
   ExpectTechnology(SystemsServer, ModelSystem, MinTime, MaxTime, TimePinned, 'Silicon'#10);

   // Check high scores.
   LoginServer.SendWebSocketStringMessage('0'#00'get-high-scores'#00);
   Scores := LoginServer.GetStreamReader(LoginServer.ReadWebSocketBinaryMessage());
   Verify(Scores.ReadCardinal() = 0); // high score marker
   Verify(Scores.ReadCardinal() = 1); // dynasty
   Verify(Scores.ReadCardinal() = 2); // last data point
   Verify(Scores.ReadCardinal() = 2); // number of data points
   Verify(Scores.ReadInt64() = 0); // system start time
   Verify(Scores.ReadDouble() = 100.0); // default happiness
   Verify(Scores.ReadInt64() = 120); // login server time at time of crash
   Verify(Round(Scores.ReadDouble()) = -100); // updated happiness
   Scores.ReadEnd();
   FreeAndNil(Scores);
   Response := TStringStreamReader.Create(LoginServer.ReadWebSocketStringMessage());
   VerifyPositiveResponse(Response);
   VerifyEndOfResponse(Response);

   // Build a mine
   SystemsServer.SendWebSocketStringMessage('0'#00'play'#00 + IntToStr(ModelSystem.SystemID) + #00 + IntToStr(HomeRegion.ID) + #00'get-buildings'#00'0'#00'0'#00);
   Response := TStringStreamReader.Create(SystemsServer.ReadWebSocketStringMessage());
   VerifyPositiveResponse(Response);
   TimePinned := True;
   AssetClass := GetAssetClassFromBuildingsList(Response, 'Mining hole');
   FreeAndNil(Response);
   SystemsServer.SendWebSocketStringMessage('0'#00'play'#00 + IntToStr(ModelSystem.SystemID) + #00 + IntToStr(HomeRegion.ID) + #00'build'#00'0'#00'0'#00 + IntToStr(AssetClass) + #00);
   Response := TStringStreamReader.Create(SystemsServer.ReadWebSocketStringMessage());
   VerifyPositiveResponse(Response);
   TimePinned := True;
   FreeAndNil(Response);
   ExpectUpdate(SystemsServer, ModelSystem, MinTime, MaxTime, TimePinned, 2);
   with (specialize GetUpdatedFeature<TModelMiningFeature>(ModelSystem)) do
   begin
      Verify(CurrentRate = Double(0.001));
      Verify(Flags = %00000011); // enabled, active
   end;
   with (specialize GetUpdatedFeature<TModelOrePileFeature>(ModelSystem)) do
   begin
      Verify(PileMass = 0.0);
      Verify(Capacity = 30000.0);
      Verify(PileMassFlowRate = Double(0.001));
   end;

   AdvanceTime(1 * Days div TimeFactor);
   ExpectUpdate(SystemsServer, ModelSystem, MinTime, MaxTime, TimePinned, 1);
   with (specialize GetUpdatedFeature<TModelMiningFeature>(ModelSystem)) do
   begin
      Verify(CurrentRate = 0.0);
      Verify(Flags = %00001011); // enabled, active, but rate limited by target
   end;
   with (specialize GetUpdatedFeature<TModelOrePileFeature>(ModelSystem)) do
   begin
      Verify(PileMass = 30000.0);
      Verify(Capacity = 30000.0);
      Verify(PileMassFlowRate = 0.0);
   end;

   ExpectTechnology(SystemsServer, ModelSystem, MinTime, MaxTime, TimePinned, 'Congratulations'#10);

   AdvanceTime(100 * Days div TimeFactor);
   ExpectTechnology(SystemsServer, ModelSystem, MinTime, MaxTime, TimePinned, 'Breakthrough in City Planning'#10);
   ExpectTechnology(SystemsServer, ModelSystem, MinTime, MaxTime, TimePinned, 'Congratulations'#10);
   ExpectTechnology(SystemsServer, ModelSystem, MinTime, MaxTime, TimePinned, 'Mining'#10);
   ExpectTechnology(SystemsServer, ModelSystem, MinTime, MaxTime, TimePinned, 'Stuff in holes'#10);
   ExpectTechnology(SystemsServer, ModelSystem, MinTime, MaxTime, TimePinned, 'Where we come from'#10);
   ExpectTechnology(SystemsServer, ModelSystem, MinTime, MaxTime, TimePinned, 'Storage for mining'#10);
   ExpectTechnology(SystemsServer, ModelSystem, MinTime, MaxTime, TimePinned, 'Communicating with our creator'#10);

   // Build a pile
   SystemsServer.SendWebSocketStringMessage('0'#00'play'#00 + IntToStr(ModelSystem.SystemID) + #00 + IntToStr(HomeRegion.ID) + #00'get-buildings'#00'1'#00'0'#00);
   Response := TStringStreamReader.Create(SystemsServer.ReadWebSocketStringMessage());
   VerifyPositiveResponse(Response);
   TimePinned := True;
   AssetClass := GetAssetClassFromBuildingsList(Response, 'Big ore pile');
   FreeAndNil(Response);
   SystemsServer.SendWebSocketStringMessage('0'#00'play'#00 + IntToStr(ModelSystem.SystemID) + #00 + IntToStr(HomeRegion.ID) + #00'build'#00'1'#00'0'#00 + IntToStr(AssetClass) + #00);
   Response := TStringStreamReader.Create(SystemsServer.ReadWebSocketStringMessage());
   VerifyPositiveResponse(Response);
   TimePinned := True;
   FreeAndNil(Response);
   ExpectUpdate(SystemsServer, ModelSystem, MinTime, MaxTime, TimePinned, 3);
   with (specialize GetUpdatedFeature<TModelMiningFeature>(ModelSystem)) do
   begin
      Verify(CurrentRate = Double(0.001));
      Verify(Flags = %00000011); // enabled, active
   end;
   with (specialize GetUpdatedFeature<TModelOrePileFeature>(ModelSystem, 0)) do
   begin
      Verify(PileMass = Double((30000.0 / 3030000.0) * 30000.0));
      Verify(Capacity = 30000.0);
      Verify(PileMassFlowRate = Double((30000.0 / 3030000.0) * 0.001));
   end;
   with (specialize GetUpdatedFeature<TModelOrePileFeature>(ModelSystem, 1)) do
   begin
      Verify(Capacity = 3000000.0);
      Verify(PileMass = Double(30000.0 / 3030000.0 * 3000000.0));
      Verify(PileMassFlowRate = Double((3000000.0 / 3030000.0) * 0.001));
   end;

   // Two hundred days later.
   AdvanceTime(200 * Days div TimeFactor);
   ExpectUpdate(SystemsServer, ModelSystem, MinTime, MaxTime, TimePinned, 2);
   with (specialize GetUpdatedFeature<TModelMiningFeature>(ModelSystem)) do
   begin
      Miner := ModelSystem.Assets[Parent.ID];
      Verify(CurrentRate = 0.0);
      Verify(Flags = %00001011); // enabled, active, but rate limited by target
   end;
   with (specialize GetUpdatedFeature<TModelOrePileFeature>(ModelSystem, 0)) do
   begin
      Verify(PileMass = 30000.0);
      Verify(Capacity = 30000.0);
      Verify(PileMassFlowRate = 0.0);
   end;
   with (specialize GetUpdatedFeature<TModelOrePileFeature>(ModelSystem, 1)) do
   begin
      Verify(PileMass = 3000000.0);
      Verify(Capacity = 3000000.0);
      Verify(PileMassFlowRate = 0.0);
   end;

   // Build a pile
   SystemsServer.SendWebSocketStringMessage('0'#00'play'#00 + IntToStr(ModelSystem.SystemID) + #00 + IntToStr(Miner.ID) + #00'disable'#00);
   Response := TStringStreamReader.Create(SystemsServer.ReadWebSocketStringMessage());
   VerifyPositiveResponse(Response);
   TimePinned := True;
   FreeAndNil(Response);
   ExpectUpdate(SystemsServer, ModelSystem, MinTime, MaxTime, TimePinned, 2); // the second is the second pile, which isn't clever enough to know it didn't change
   with (specialize GetUpdatedFeature<TModelMiningFeature>(ModelSystem)) do
   begin
      Verify(CurrentRate = 0.0);
      Verify(Flags = %00000000); // disabled, inactive
   end;
   with (specialize GetUpdatedFeature<TModelOrePileFeature>(ModelSystem, 0)) do
   begin
      Verify(PileMass = 30000.0);
      Verify(Capacity = 30000.0);
      Verify(PileMassFlowRate = 0.0);
   end;
   with (specialize GetUpdatedFeature<TModelOrePileFeature>(ModelSystem, 1)) do
   begin
      Verify(PileMass = 3000000.0);
      Verify(Capacity = 3000000.0);
      Verify(PileMassFlowRate = 0.0);
   end;

   // Build an iron table
   SystemsServer.SendWebSocketStringMessage('0'#00'play'#00 + IntToStr(ModelSystem.SystemID) + #00 + IntToStr(HomeRegion.ID) + #00'get-buildings'#00'0'#00'1'#00);
   Response := TStringStreamReader.Create(SystemsServer.ReadWebSocketStringMessage());
   VerifyPositiveResponse(Response);
   TimePinned := True;
   AssetClass := GetAssetClassFromBuildingsList(Response, 'Iron team table');
   FreeAndNil(Response);
   SystemsServer.SendWebSocketStringMessage('0'#00'play'#00 + IntToStr(ModelSystem.SystemID) + #00 + IntToStr(HomeRegion.ID) + #00'build'#00'0'#00'1'#00 + IntToStr(AssetClass) + #00);
   Response := TStringStreamReader.Create(SystemsServer.ReadWebSocketStringMessage());
   VerifyPositiveResponse(Response);
   TimePinned := True;
   FreeAndNil(Response);
   ExpectUpdate(SystemsServer, ModelSystem, MinTime, MaxTime, TimePinned, 4);
   with (specialize GetUpdatedFeature<TModelMiningFeature>(ModelSystem)) do
   begin
      Verify(CurrentRate = 0.0);
      Verify(Flags = %00000000);
   end;
   with (specialize GetUpdatedFeature<TModelMaterialPileFeature>(ModelSystem)) do
   begin
      Verify(PileMass = 0.0);
      Verify(PileMassFlowRate = Double(1000 / 3.6e6));
      Verify(Capacity = 1000);
      Verify(MaterialName = 'Iron');
      Verify(MaterialID = 12);
   end;
   with (specialize GetUpdatedFeature<TModelRefiningFeature>(ModelSystem)) do
   begin
      Verify(Ore = 12);
      Verify(MaxRate = Double(1000 / 3.6e6));
      Verify(Flags = %0011);
      Verify(CurrentRate = Double(1000 / 3.6e6));
   end;
   with (specialize GetUpdatedFeature<TModelOrePileFeature>(ModelSystem, 0)) do
   begin
      Verify(PileMass = 30000.0);
      Verify(Capacity = 30000.0);
      Verify(PileMassFlowRate = -Double(30000.0 / 3030000.0 * 1000 / 3.6e6));
   end;
   with (specialize GetUpdatedFeature<TModelOrePileFeature>(ModelSystem, 1)) do
   begin
      Verify(Capacity = 3000000.0);
      Verify(PileMass = 3000000.0);
      Verify(PileMassFlowRate = -Double(3000000.0 / 3030000.0 * 1000 / 3.6e6));
   end;

   // One day later.
   AdvanceTime(1 * Days div TimeFactor);

   ExpectUpdate(SystemsServer, ModelSystem, MinTime, MaxTime, TimePinned, 3);
   Verify(ModelSystem.CurrentTime < MaxTime);
   Verify(Miner = ModelSystem.GetUpdatedAssets()[0]);
   Verify(Miner.FeatureCount = 2);
   with (Miner) do
   begin
      Verify(Owner = 1);
      Verify(Mass = Double((3000000.0 + 30000.0 - 1000.0) / (3000000.0 + 30000.0) * 30000.0));
      Verify(MassFlowRate = 0);
      Verify(Size = 50);
      Verify(AssetClassID = 5000);
      Verify(AssetClassName = 'Mining hole');
   end;
   with (specialize GetUpdatedFeature<TModelMiningFeature>(ModelSystem)) do
   begin
      Verify(Parent = Miner);
      Verify(CurrentRate = 0.0);
      Verify(Flags = %00000000); // still disabled
   end;
   with (specialize GetUpdatedFeature<TModelOrePileFeature>(ModelSystem, 0)) do
   begin
      Verify(Parent = Miner);
      Verify(PileMass = Double((3000000.0 + 30000.0 - 1000.0) / (3000000.0 + 30000.0) * 30000.0));
      Verify(Capacity = 30000.0);
      Verify(PileMassFlowRate = 0.0);
   end;
   Verify(ModelSystem.GetUpdatedAssets()[1].FeatureCount = 1);
   with (ModelSystem.GetUpdatedAssets()[1]) do
   begin
      Verify(Owner = 1);
      Verify(Mass = Double(3000000.0 * (3000000.0 + 30000.0 - 1000.0) / (3000000.0 + 30000.0)));
      Verify(MassFlowRate = 0);
      Verify(Size = 100);
      Verify(AssetClassID = 4);
      Verify(AssetClassName = 'Big ore pile');
   end;
   with (specialize GetUpdatedFeature<TModelOrePileFeature>(ModelSystem, 1)) do
   begin
      Verify(Parent = ModelSystem.GetUpdatedAssets()[1]);
      Verify(PileMass = Double(3000000.0 * (3000000.0 + 30000.0 - 1000.0) / (3000000.0 + 30000.0)));
      Verify(Capacity = 3000000.0);
      Verify(PileMassFlowRate = 0.0);
   end;
   Verify(ModelSystem.GetUpdatedAssets()[2].FeatureCount = 2);
   with (ModelSystem.GetUpdatedAssets()[2]) do
   begin
      Verify(Owner = 1);
      Verify(Mass = 1000);
      Verify(MassFlowRate = 0);
      Verify(Size = 10);
      Verify(AssetClassID = 6);
      Verify(AssetClassName = 'Iron team table');
   end;
   with (specialize GetUpdatedFeature<TModelRefiningFeature>(ModelSystem)) do
   begin
      Verify(Parent = ModelSystem.GetUpdatedAssets()[2]);
      Verify(Ore = 12);
      Verify(Flags = %00001011);
      Verify(CurrentRate = 0.0);
   end;
   with (specialize GetUpdatedFeature<TModelMaterialPileFeature>(ModelSystem)) do
   begin
      Verify(Parent = ModelSystem.GetUpdatedAssets()[2]);
      Verify(MaterialID = 12);
      Verify(MaterialName = 'Iron');
      Verify(PileMass = 1000.0);
      Verify(Capacity = 1000.0);
      Verify(PileMassFlowRate = 0.0);
   end;

   // Build a drill
   SystemsServer.SendWebSocketStringMessage('0'#00'play'#00 + IntToStr(ModelSystem.SystemID) + #00 + IntToStr(HomeRegion.ID) + #00'get-buildings'#00'1'#00'1'#00);
   Response := TStringStreamReader.Create(SystemsServer.ReadWebSocketStringMessage());
   VerifyPositiveResponse(Response);
   TimePinned := True;
   AssetClass := GetAssetClassFromBuildingsList(Response, 'Drilling Hole');
   FreeAndNil(Response);
   SystemsServer.SendWebSocketStringMessage('0'#00'play'#00 + IntToStr(ModelSystem.SystemID) + #00 + IntToStr(HomeRegion.ID) + #00'build'#00'1'#00'1'#00 + IntToStr(AssetClass) + #00);
   Response := TStringStreamReader.Create(SystemsServer.ReadWebSocketStringMessage());
   VerifyPositiveResponse(Response);
   TimePinned := True;
   FreeAndNil(Response);
   ExpectUpdate(SystemsServer, ModelSystem, MinTime, MaxTime, TimePinned, 5); // the grid, the piles, and the new drilling hole
   Verify(ModelSystem.CurrentTime = MaxTime);
   DrillBit := specialize GetUpdatedFeature<TModelMiningFeature>(ModelSystem, 1); // the mining hole is the first, because it has a pile
   with (specialize GetUpdatedFeature<TModelMaterialPileFeature>(ModelSystem)) do
   begin
      Verify(PileMass = 1000.0);
      Verify(PileMassFlowRate = 0); // we're full
      Verify(MaterialName = 'Iron');
   end;

   // Build a silicon table
   SystemsServer.SendWebSocketStringMessage('0'#00'play'#00 + IntToStr(ModelSystem.SystemID) + #00 + IntToStr(HomeRegion.ID) + #00'get-buildings'#00'2'#00'1'#00);
   Response := TStringStreamReader.Create(SystemsServer.ReadWebSocketStringMessage());
   VerifyPositiveResponse(Response);
   TimePinned := True;
   AssetClass := GetAssetClassFromBuildingsList(Response, 'Silicon Table');
   FreeAndNil(Response);
   SystemsServer.SendWebSocketStringMessage('0'#00'play'#00 + IntToStr(ModelSystem.SystemID) + #00 + IntToStr(HomeRegion.ID) + #00'build'#00'2'#00'1'#00 + IntToStr(AssetClass) + #00);
   Response := TStringStreamReader.Create(SystemsServer.ReadWebSocketStringMessage());
   VerifyPositiveResponse(Response);
   TimePinned := True;
   FreeAndNil(Response);
   ExpectUpdate(SystemsServer, ModelSystem, MinTime, MaxTime, TimePinned, 5); // the grid, the piles, and the new table (not the drill)
   Verify(ModelSystem.CurrentTime = MaxTime);
   with (specialize GetUpdatedFeature<TModelStructureFeature>(ModelSystem)) do
   begin
      Verify(Hp = 0);
      Verify(HpRate > 0);
      Verify(Quantity = 1); // instant fill from iron table
      Verify(QuantityRate > 0);
   end;
   with (specialize GetUpdatedFeature<TModelMaterialPileFeature>(ModelSystem, 0)) do
   begin
      Verify(PileMass = 0); // it all went into the silicon table
      Verify(PileMassFlowRate = 0); // we're using it all right away
      Verify(MaterialName = 'Iron');
   end;
   with (specialize GetUpdatedFeature<TModelMaterialPileFeature>(ModelSystem, 1)) do
   begin
      Verify(PileMass = 0);
      Verify(PileMassFlowRate > 0);
      Verify(MaterialName = 'Silicon');
   end;

   // One day later.
   AdvanceTime(1 * Days div TimeFactor);
   // This is when the table is fully built.
   ExpectUpdate(SystemsServer, ModelSystem, MinTime, MaxTime, TimePinned, 4); // the piles and the structure
   Verify(DrillBit <> specialize GetUpdatedFeature<TModelMiningFeature>(ModelSystem));
   with (specialize GetUpdatedFeature<TModelMiningFeature>(ModelSystem)) do
   begin
      Verify(Parent = Miner);
      Verify(CurrentRate = 0);
   end;
   with (specialize GetUpdatedFeature<TModelOrePileFeature>(ModelSystem, 0)) do
   begin
      Verify(Parent = Miner);
      Verify(PileMassFlowRate = Parent.MassFlowRate);
   end;
   with (specialize GetUpdatedFeature<TModelOrePileFeature>(ModelSystem, 1)) do
   begin
      Verify(PileMassFlowRate = Parent.MassFlowRate);
   end;
   with (specialize GetUpdatedFeature<TModelStructureFeature>(ModelSystem)) do
   begin
      Verify(Hp = 2);
      Verify(HpRate > 0);
      Verify(Quantity = 3);
      Verify(QuantityRate = 0);
   end;
   Verify(specialize GetUpdatedFeature<TModelOrePileFeature>(ModelSystem, 0).PileMassFlowRate
        + specialize GetUpdatedFeature<TModelOrePileFeature>(ModelSystem, 1).PileMassFlowRate
        + specialize GetUpdatedFeature<TModelMaterialPileFeature>(ModelSystem, 0).PileMassFlowRate
        + specialize GetUpdatedFeature<TModelMaterialPileFeature>(ModelSystem, 1).PileMassFlowRate
        - DrillBit.CurrentRate = 0.0);

   ExpectUpdate(SystemsServer, ModelSystem, MinTime, MaxTime, TimePinned, 1); // structure completes building
   with (specialize GetUpdatedFeature<TModelStructureFeature>(ModelSystem)) do
   begin
      Verify(Hp = 3);
      Verify(HpRate = 0);
      Verify(Quantity = 3);
      Verify(QuantityRate = 0);
   end;

   ExpectUpdate(SystemsServer, ModelSystem, MinTime, MaxTime, TimePinned, 4); // table pile full

   ExpectUpdate(SystemsServer, ModelSystem, MinTime, MaxTime, TimePinned, 5); // the structure (with its pile, giving data to a new anchor time)
   with (specialize GetUpdatedFeature<TModelStructureFeature>(ModelSystem)) do
   begin
      Verify(Hp = 3);
      Verify(HpRate = 0);
      Verify(Quantity = 3);
      Verify(QuantityRate = 0);
   end;
   with (specialize GetUpdatedFeature<TModelMaterialPileFeature>(ModelSystem, 0)) do
   begin
      Verify(PileMass = 1000);
      Verify(Capacity = 1000);
      Verify(PileMassFlowRate = 0);
      Verify(MaterialName = 'Iron');
   end;
   with (specialize GetUpdatedFeature<TModelMaterialPileFeature>(ModelSystem, 1)) do
   begin
      Verify(PileMass = 1000);
      Verify(Capacity = 1000);
      Verify(PileMassFlowRate = 0);
      Verify(MaterialName = 'Silicon');
   end;

   FreeAndNil(ModelSystem);

   SystemsServerIPC.CloseSocket();
   FreeAndNil(SystemsServerIPC);
   LoginServerIPC.CloseSocket();
   FreeAndNil(LoginServerIPC);
   LoginServer.CloseWebSocket();
   FreeAndNil(LoginServer);
   DynastyServer.CloseWebSocket();
   FreeAndNil(DynastyServer);
   SystemsServer.CloseWebSocket();
   FreeAndNil(SystemsServer);
end;

initialization
   RegisterTest(TTest.Create());
end.