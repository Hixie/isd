{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit test_1;

interface

implementation

uses
   sysutils, harness, endtoend, stringstream, isdprotocol, model, binarystream, stringutils, utils;

type
   TTest = class(TIsdServerTest)
      procedure RunTestBody(); override;
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
   DynastyID: QWord;
   DynastyServerURL, Token: UTF8String;
   SystemsServerCount: QWord;
   Index: QWord;
   LoginServer, DynastyServer, SystemsServer: TServerWebSocket;
   ColonyShip, HomeRegion, Miner: TModelAsset;
   DrillBit: TModelMiningFeature;
   Grid: TModelGridFeature;
   AssetClass, AssetClass2: Int32;
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

   LoginServerIPC.AwaitScores(1);
   
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

   LoginServerIPC.AwaitScores(2);

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
      Verify(DisabledReasons = %00000000);
      Verify(Flags = %00000000);
      Verify(CurrentRate = Double(0.001));
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
      Verify(DisabledReasons = %00000000);
      Verify(CurrentRate = 0.0);
      Verify(Flags = %00000010); // rate limited by target
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
      Verify(DisabledReasons = %00000000);
      Verify(Flags = %00000000);
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
      Verify(DisabledReasons = %00000000);
      Verify(Flags = %00000010); // rate limited by target
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
   ExpectUpdate(SystemsServer, ModelSystem, MinTime, MaxTime, TimePinned, 2);
   with (specialize GetUpdatedFeature<TModelMiningFeature>(ModelSystem)) do
   begin
      Verify(CurrentRate = 0.0);
      Verify(DisabledReasons = %00000001); // this is the miner we disabled
      Verify(Flags = %00000000);
   end;
   with (specialize GetUpdatedFeature<TModelOrePileFeature>(ModelSystem, 0)) do
   begin
      Verify(PileMass = 30000.0);
      Verify(Capacity = 30000.0);
      Verify(PileMassFlowRate = 0.0);
   end;
   with (specialize GetUpdatedFeature<TModelOrePileFeature>(ModelSystem, 1)) do // this pile isn't clever enough to know nothing changed
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
      Verify(DisabledReasons = %00000001); // still disabled
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
      Verify(DisabledReasons = %00000000);
      Verify(Flags = %00000000);
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
   Verify(Miner.FeatureCount = 3);
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
      Verify(DisabledReasons = %00000001); // still disabled
      Verify(Flags = %00000000);
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
   Verify(ModelSystem.GetUpdatedAssets()[2].FeatureCount = 3);
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
      Verify(DisabledReasons = %00000000);
      Verify(Flags = %00000010);
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
   AssetClass2 := GetAssetClassFromBuildingsList(Response, 'Builder rally point');
   FreeAndNil(Response);
   SystemsServer.SendWebSocketStringMessage('0'#00'play'#00 + IntToStr(ModelSystem.SystemID) + #00 + IntToStr(HomeRegion.ID) + #00'build'#00'2'#00'1'#00 + IntToStr(AssetClass) + #00);
   Response := TStringStreamReader.Create(SystemsServer.ReadWebSocketStringMessage());
   VerifyPositiveResponse(Response);
   FreeAndNil(Response);
   TimePinned := True;
   ExpectUpdate(SystemsServer, ModelSystem, MinTime, MaxTime, TimePinned, 5); // the grid, the piles, the new table; not the drill
   Verify(ModelSystem.CurrentTime = MaxTime);
   with (specialize GetUpdatedFeature<TModelStructureFeature>(ModelSystem)) do
   begin
      Verify(Hp = 0);
      Verify(HpRate = 0);
      Verify(Quantity = 0);
      Verify(QuantityRate = 0);
   end;
   with (specialize GetUpdatedFeature<TModelMaterialPileFeature>(ModelSystem, 0)) do
   begin
      Verify(PileMass = 1000.0);
      Verify(PileMassFlowRate = 0);
      Verify(MaterialName = 'Iron');
   end;
   with (specialize GetUpdatedFeature<TModelMaterialPileFeature>(ModelSystem, 1)) do
   begin
      Verify(PileMass = 0);
      Verify(PileMassFlowRate = 0);
      Verify(MaterialName = 'Silicon');
   end;
   with (specialize GetUpdatedFeature<TModelBuilderFeature>(ModelSystem, 0)) do
   begin
      Verify(Structures.Length = 0);
      Verify(Capacity = 1);
      Verify(Rate = 100.0 / (60.0 * 60.0 * 1000.0));
      Verify(DisabledReasons = %00000010); // not built yet
   end;
   
   SystemsServer.SendWebSocketStringMessage('0'#00'play'#00 + IntToStr(ModelSystem.SystemID) + #00 + IntToStr(HomeRegion.ID) + #00'build'#00'0'#00'2'#00 + IntToStr(AssetClass2) + #00);
   Response := TStringStreamReader.Create(SystemsServer.ReadWebSocketStringMessage());
   VerifyPositiveResponse(Response);
   FreeAndNil(Response);
   
   TimePinned := True;
   ExpectUpdate(SystemsServer, ModelSystem, MinTime, MaxTime, TimePinned, 6); // the grid, the piles, the new table, the new rally point; still not the drill
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
      Verify(PileMassFlowRate = 0);
      Verify(MaterialName = 'Silicon');
   end;
   with (specialize GetUpdatedFeature<TModelBuilderFeature>(ModelSystem, 0)) do
   begin
      Verify(Structures.Length = 0);
      Verify(Capacity = 1);
      Verify(Rate = 100.0 / (60.0 * 60.0 * 1000.0));
      Verify(DisabledReasons = %00000010); // not built yet
   end;
   with (specialize GetUpdatedFeature<TModelBuilderFeature>(ModelSystem, 1)) do
   begin
      Verify(Structures.Length = 1);
      Verify(Capacity = 1);
      Verify(Rate = 100.0 / (60.0 * 60.0 * 1000.0));
      Verify(DisabledReasons = %00000000);
   end;

   // One day later.
   AdvanceTime(1 * Days div TimeFactor);
   // This is when the table turns on.
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
   with (specialize GetUpdatedFeature<TModelMaterialPileFeature>(ModelSystem, 0)) do
   begin
      Verify(PileMassFlowRate = Parent.MassFlowRate);
   end;
   with (specialize GetUpdatedFeature<TModelMaterialPileFeature>(ModelSystem, 1)) do
   begin
      Verify(PileMassFlowRate = 0.0);
      Verify(Parent.MassFlowRate > 0.0);
   end;
   with (specialize GetUpdatedFeature<TModelStructureFeature>(ModelSystem)) do
   begin
      Verify(Hp = 2);
      Verify(HpRate > 0);
      Verify(Quantity = 2);
      Verify(QuantityRate > 0);
      Verify(Parent.MassFlowRate > 0.0);
   end;
   Verify(specialize GetUpdatedFeature<TModelMaterialPileFeature>(ModelSystem, 1).Parent = specialize GetUpdatedFeature<TModelStructureFeature>(ModelSystem).Parent);
   Verify(specialize GetUpdatedFeature<TModelOrePileFeature>(ModelSystem, 0).PileMassFlowRate
        + specialize GetUpdatedFeature<TModelOrePileFeature>(ModelSystem, 1).PileMassFlowRate
        + specialize GetUpdatedFeature<TModelMaterialPileFeature>(ModelSystem, 0).PileMassFlowRate
        + specialize GetUpdatedFeature<TModelStructureFeature>(ModelSystem, 0).Parent.MassFlowRate
        - DrillBit.CurrentRate = 0.0);

   ExpectUpdate(SystemsServer, ModelSystem, MinTime, MaxTime, TimePinned, 4); // structure completes building
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