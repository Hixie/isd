{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit test_2;

interface

implementation

uses
   sysutils, harness, endtoend, stringstream, model, stringutils, utils;

type
   TTest = class(TIsdServerTest)
      procedure RunTestBody(); override;
   end;

procedure TTest.RunTestBody();
var
   ModelSystem: TModelSystem;
   SystemsServerIPC, LoginServerIPC: TServerIPCSocket;
   MinTime, MaxTime: Int64;
   TimePinned: Boolean; // means that time is not currently advancing for the server

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
   Token: UTF8String;
   SystemsServerCount: QWord;
   Index: QWord;
   LoginServer, DynastyServer, SystemsServer: TServerWebSocket;
   Grid: TModelGridFeature;
   ColonyShip: TModelAsset;
   HomeRegion: TModelGridFeature;
   AssetClass1, AssetClass2, AssetClass3, AssetClass4: Integer;
   LastTime, ExpectedTimeChange, ExpectedNextTime: Int64;
   Rate: Double;
begin
   LoginServer := FLoginServer.ConnectWebSocket();
   LoginServer.SendWebSocketStringMessage('0'#00'new'#00);
   Response := TStringStreamReader.Create(LoginServer.ReadWebSocketStringMessage());
   VerifyPositiveResponse(Response);
   {Username :=} Response.ReadString();
   {Password :=} Response.ReadString();
   {DynastyServerURL :=} Response.ReadString();
   Token := Response.ReadString();
   VerifyEndOfResponse(Response);

   DynastyServer := FDynastiesServers[0].ConnectWebSocket();
   DynastyServer.SendWebSocketStringMessage('0'#00'login'#00 + Token + #00);
   Response := TStringStreamReader.Create(DynastyServer.ReadWebSocketStringMessage());
   VerifyPositiveResponse(Response);
   {DynastyID :=} Response.ReadQWord();
   SystemsServerCount := Response.ReadQWord();
   for Index := 0 to SystemsServerCount - 1 do // $R-
      Response.ReadString();
   VerifyEndOfResponse(Response);

   SystemsServer := FSystemsServers[0].ConnectWebSocket();
   SystemsServer.SendWebSocketStringMessage('0'#00'login'#00 + Token + #00);
   Response := TStringStreamReader.Create(SystemsServer.ReadWebSocketStringMessage());
   VerifyPositiveResponse(Response);
   {ServerVersion :=} Response.ReadQWord();
   VerifyEndOfResponse(Response);

   SystemsServerIPC := FSystemsServers[0].ConnectIPCSocket();
   LoginServerIPC := FLoginServer.ConnectIPCSocket();

   ModelSystem := TModelSystem.Create();
   MinTime := 0;
   MaxTime := 0;
   TimePinned := True;

   ExpectUpdate(SystemsServer, ModelSystem, MinTime, MaxTime, TimePinned, 127);

   AdvanceTime(1000 * Days); // crash the colony ship, get lots of technologies
   ExpectTechnology(SystemsServer, ModelSystem, MinTime, MaxTime, TimePinned, 'Technology unlocked.');

   ExpectUpdate(SystemsServer, ModelSystem, MinTime, MaxTime, TimePinned, 18); // crash
   Grid := specialize GetUpdatedFeature<TModelGridFeature>(ModelSystem);
   HomeRegion := Grid;
   ColonyShip := FindColonyShip(ModelSystem);
   Verify(Grid.Children.Length = 1);
   Verify(Grid.Children[0].X = 8);
   Verify(Grid.Children[0].Y = 2);
   Verify(ModelSystem.Assets[(ModelSystem.Assets[Grid.Children[0].AssetID].Features[TModelProxyFeature] as TModelProxyFeature).Child] = ColonyShip);

   // some digging and building tests
   AssetClass1 := GetAssetClassFromBuildingsList(HomeRegion, 'Iron team table');
   AssetClass2 := GetAssetClassFromBuildingsList(HomeRegion, 'Drilling Hole');
   AssetClass3 := GetAssetClassFromBuildingsList(HomeRegion, 'Silicon Table');
   AssetClass4 := GetAssetClassFromBuildingsList(HomeRegion, 'Builder rally point');

   // BUILD AN IRON TEAM TABLE
   SystemsServer.SendWebSocketStringMessage('0'#00'play'#00 + IntToStr(ModelSystem.SystemID) + #00 + IntToStr(HomeRegion.Parent.ID) + #00'build'#00'0'#00'0'#00 + IntToStr(AssetClass1) + #00);
   Response := TStringStreamReader.Create(SystemsServer.ReadWebSocketStringMessage());
   VerifyPositiveResponse(Response);
   FreeAndNil(Response);

   TimePinned := True;
   ExpectUpdate(SystemsServer, ModelSystem, MinTime, MaxTime, TimePinned, 2);
   Verify(ModelSystem.CurrentTime = MaxTime);
   with (specialize GetUpdatedFeature<TModelMaterialPileFeature>(ModelSystem)) do
   begin
      Verify(PileMass = 0.0);
      Verify(PileMassFlowRate = 0);
      Verify(MaterialName = 'Iron');
   end;

   // BUILD A DRILLING HOLE (time has not advanced, we expect pile to start growing)
   TimePinned := True;
   SystemsServer.SendWebSocketStringMessage('0'#00'play'#00 + IntToStr(ModelSystem.SystemID) + #00 + IntToStr(HomeRegion.Parent.ID) + #00'build'#00'0'#00'1'#00 + IntToStr(AssetClass2) + #00);
   Response := TStringStreamReader.Create(SystemsServer.ReadWebSocketStringMessage());
   VerifyPositiveResponse(Response);
   FreeAndNil(Response);

   ExpectUpdate(SystemsServer, ModelSystem, MinTime, MaxTime, TimePinned, 3);
   Verify(ModelSystem.CurrentTime = MaxTime);
   LastTime := ModelSystem.CurrentTime;
   with (specialize GetUpdatedFeature<TModelMiningFeature>(ModelSystem)) do
   begin
      Verify(CurrentRate > 0.0);
      Verify(Flags = 2); // no piles
   end;
   with (specialize GetUpdatedFeature<TModelMaterialPileFeature>(ModelSystem)) do
   begin
      Verify(PileMass = 0.0);
      Verify(PileMassFlowRate > 0);
      Verify(MaterialName = 'Iron');
   end;

   // ADVANCE TIME
   AdvanceTime(1000 * Days); // fill the pile

   ExpectUpdate(SystemsServer, ModelSystem, MinTime, MaxTime, TimePinned, 2);
   LastTime := ModelSystem.CurrentTime;
   with (specialize GetUpdatedFeature<TModelMaterialPileFeature>(ModelSystem)) do
   begin
      Verify(PileMass = 1000.0);
      Verify(PileMassFlowRate = 0);
      Verify(MaterialName = 'Iron');
   end;

   // BUILD SILICON TABLE (without any builders present)
   TimePinned := True;
   SystemsServer.SendWebSocketStringMessage('0'#00'play'#00 + IntToStr(ModelSystem.SystemID) + #00 + IntToStr(HomeRegion.Parent.ID) + #00'build'#00'6'#00'6'#00 + IntToStr(AssetClass3) + #00);
   Response := TStringStreamReader.Create(SystemsServer.ReadWebSocketStringMessage());
   VerifyPositiveResponse(Response);
   FreeAndNil(Response);

   ExpectUpdate(SystemsServer, ModelSystem, MinTime, MaxTime, TimePinned, 3);
   Verify(ModelSystem.CurrentTime = MaxTime);
   Verify(ModelSystem.CurrentTime = 86400000000000);
   LastTime := ModelSystem.CurrentTime;
   with (specialize GetUpdatedFeature<TModelMaterialPileFeature>(ModelSystem, 0)) do
   begin
      Verify(PileMass = 1000.0);
      Verify(PileMassFlowRate = 0);
      Verify(MaterialName = 'Iron');
   end;
   with (specialize GetUpdatedFeature<TModelMaterialPileFeature>(ModelSystem, 1)) do
   begin
      Verify(PileMass = 0.0);
      Verify(PileMassFlowRate = 0);
      Verify(MaterialName = 'Silicon');
   end;

   // BUILD RALLY POINT (instabuild silicon table, resume refining iron)
   TimePinned := True;
   SystemsServer.SendWebSocketStringMessage('0'#00'play'#00 + IntToStr(ModelSystem.SystemID) + #00 + IntToStr(HomeRegion.Parent.ID) + #00'build'#00'6'#00'12'#00 + IntToStr(AssetClass4) + #00);
   Response := TStringStreamReader.Create(SystemsServer.ReadWebSocketStringMessage());
   VerifyPositiveResponse(Response);
   FreeAndNil(Response);

   ExpectUpdate(SystemsServer, ModelSystem, MinTime, MaxTime, TimePinned, 5);
   Verify(ModelSystem.CurrentTime = MaxTime);
   LastTime := ModelSystem.CurrentTime;
   with (specialize GetUpdatedFeature<TModelMaterialPileFeature>(ModelSystem, 0)) do
   begin
      Verify(PileMass = 0.0);
      Verify(PileMassFlowRate = 0); // any iron refined is going to the silicon table
      Verify(MaterialName = 'Iron');
   end;
   with (specialize GetUpdatedFeature<TModelRefiningFeature>(ModelSystem, 0)) do
   begin
      Verify(CurrentRate > 0);
      ExpectedNextTime := LastTime + Round(2000.0 / CurrentRate); // this is how fast the silicon table can get its 2kg iron
      // TODO: actually use this time, instead of resetting the clock each time we do an update
   end;
   with (specialize GetUpdatedFeature<TModelMaterialPileFeature>(ModelSystem, 1)) do
   begin
      Verify(PileMass = 0.0);
      Verify(PileMassFlowRate = 0); // HP is still zero
      Verify(MaterialName = 'Silicon');
   end;
   with (specialize GetUpdatedFeature<TModelStructureFeature>(ModelSystem)) do
   begin
      Verify(Quantity = 1);
      Verify(QuantityRate > 0.0);
      Verify(Hp = 0);
      Verify(HpRate > 0.0);
      ExpectedTimeChange := Round(1 / HpRate);
   end;
   with (specialize GetUpdatedFeature<TModelBuilderFeature>(ModelSystem, 0)) do
   begin
      Verify(Structures.Length = 0);
      Verify(DisabledReasons = 2); // drStructuralIntegrity
   end;
   with (specialize GetUpdatedFeature<TModelBuilderFeature>(ModelSystem, 1)) do
   begin
      Verify(Structures.Length = 1);
      Verify(DisabledReasons = 0);
   end;

   // ADVANCE TIME
   AdvanceTime(1000 * Days); // complete everything

   // silicon table reaches viability and begins filling its pile
   ExpectUpdate(SystemsServer, ModelSystem, MinTime, MaxTime, TimePinned, 3);
   Verify(ModelSystem.CurrentTime = LastTime + ExpectedTimeChange);
   LastTime := ModelSystem.CurrentTime;
   with (specialize GetUpdatedFeature<TModelMaterialPileFeature>(ModelSystem, 0)) do
   begin
      Verify(PileMass = 0.0);
      Verify(PileMassFlowRate = 0); // still feeding silicon table
      Verify(MaterialName = 'Iron');
   end;
   with (specialize GetUpdatedFeature<TModelMaterialPileFeature>(ModelSystem, 1)) do
   begin
      Verify(PileMass = 0.0);
      Verify(PileMassFlowRate > 0); // it's finally finished, so we're refining now
      ExpectedTimeChange := Round(1000.0 / PileMassFlowRate);
      Verify(MaterialName = 'Silicon');
   end;
   with (specialize GetUpdatedFeature<TModelStructureFeature>(ModelSystem)) do
   begin
      Verify(Quantity = 1);
      Verify(QuantityRate > 0.0);
      Verify(Hp = 1);
      Verify(HpRate > 0.0);
   end;

   // this update comes from floating point error -- we refine 0.999999986 of a
   // silicon and just slightly fail to fill the silicon material pile
   ExpectUpdate(SystemsServer, ModelSystem, MinTime, MaxTime, TimePinned, 2);
   Verify(ModelSystem.CurrentTime = LastTime + ExpectedTimeChange);
   LastTime := ModelSystem.CurrentTime;
   with (specialize GetUpdatedFeature<TModelMaterialPileFeature>(ModelSystem, 0)) do
   begin
      Verify(PileMass = 0.0);
      Verify(PileMassFlowRate = 0);
      Verify(MaterialName = 'Iron');
   end;
   with (specialize GetUpdatedFeature<TModelMaterialPileFeature>(ModelSystem, 1)) do
   begin
      Verify(PileMass = 0.0);
      Verify(PileMassFlowRate > 0.0);
      Verify(MaterialName = 'Silicon');
   end;

   // silicon pile is full
   ExpectUpdate(SystemsServer, ModelSystem, MinTime, MaxTime, TimePinned, 2);
   Verify(ModelSystem.CurrentTime = LastTime + ExpectedTimeChange); // TODO: should prorate this somehow
   LastTime := ModelSystem.CurrentTime;
   with (specialize GetUpdatedFeature<TModelMaterialPileFeature>(ModelSystem, 0)) do
   begin
      Verify(PileMass = 0.0);
      Verify(PileMassFlowRate = 0); // all going into iron table
      Verify(MaterialName = 'Iron');
   end;
   with (specialize GetUpdatedFeature<TModelRefiningFeature>(ModelSystem, 0)) do
   begin
      Verify(Ore = 12); // Iron
      Verify(CurrentRate > 0);
      ExpectedNextTime := LastTime + Round(1000.0 / CurrentRate); // this is how fast the silicon table can get its 1000kg of iron
      // TODO: we should be prorating this and using the earlier time, rather than this one (see above)
      Rate := CurrentRate;
   end;
   with (specialize GetUpdatedFeature<TModelMaterialPileFeature>(ModelSystem, 1)) do
   begin
      Verify(PileMass = 1000.0);
      Verify(PileMassFlowRate = 0.0);
      Verify(MaterialName = 'Silicon');
   end;
   with (specialize GetUpdatedFeature<TModelRefiningFeature>(ModelSystem, 1)) do
   begin
      Verify(Ore = 9); // Silicon
      Verify(CurrentRate = 0.0); // full
   end;
   with (specialize GetUpdatedFeature<TModelStructureFeature>(ModelSystem)) do
   begin
      Verify(Quantity = 1);
      Verify(QuantityRate > 0.0);
      Verify(QuantityRate = Rate / 1000); // should be same as refining rate, except units are different (kg vs units)
      Verify(Hp = 1);
      Verify(HpRate > 0.0);
   end;

   // silicon table finishes getting its iron, and gets all its silicon instantly
   ExpectUpdate(SystemsServer, ModelSystem, MinTime, MaxTime, TimePinned, 2);
   Verify(ModelSystem.CurrentTime = ExpectedNextTime);
   LastTime := ModelSystem.CurrentTime;
   with (specialize GetUpdatedFeature<TModelMaterialPileFeature>(ModelSystem, 0)) do
   begin
      Verify(PileMass = 0.0);
      Verify(PileMassFlowRate > 0); // finished building table
      Verify(MaterialName = 'Iron');
   end;
   with (specialize GetUpdatedFeature<TModelMaterialPileFeature>(ModelSystem, 1)) do
   begin
      Verify(PileMass = 0.0);
      Verify(PileMassFlowRate > 0.0);
      Verify(MaterialName = 'Silicon');
      ExpectedNextTime := LastTime + Round(1000 / PileMassFlowRate); // TODO: use this time by prorating expected times
   end;
   with (specialize GetUpdatedFeature<TModelStructureFeature>(ModelSystem)) do
   begin
      Verify(Quantity = 3);
      Verify(QuantityRate = 0.0);
      Verify(Hp = 2);
      Verify(HpRate > 0.0);
      ExpectedTimeChange := Round(1 / HpRate);
   end;

   // table finishes healing
   ExpectUpdate(SystemsServer, ModelSystem, MinTime, MaxTime, TimePinned, 2);
   Verify(ModelSystem.CurrentTime = LastTime + ExpectedTimeChange);
   LastTime := ModelSystem.CurrentTime;
   with (specialize GetUpdatedFeature<TModelMaterialPileFeature>(ModelSystem)) do
   begin
      Verify(PileMass = 0.0);
      Verify(PileMassFlowRate > 0.0);
      Verify(MaterialName = 'Silicon');
   end;
   with (specialize GetUpdatedFeature<TModelStructureFeature>(ModelSystem)) do
   begin
      Verify(Quantity = 3);
      Verify(QuantityRate = 0.0);
      Verify(Hp = 3);
      Verify(HpRate = 0.0);
   end;
   with (specialize GetUpdatedFeature<TModelBuilderFeature>(ModelSystem, 0)) do
   begin
      Verify(Structures.Length = 0);
   end;
   with (specialize GetUpdatedFeature<TModelBuilderFeature>(ModelSystem, 1)) do
   begin
      Verify(Structures.Length = 0);
   end;

   // silicon table finishes filling
   ExpectUpdate(SystemsServer, ModelSystem, MinTime, MaxTime, TimePinned, 2);
   Verify(ModelSystem.CurrentTime = ExpectedNextTime);
   LastTime := ModelSystem.CurrentTime;
   with (specialize GetUpdatedFeature<TModelMaterialPileFeature>(ModelSystem, 0)) do
   begin
      Verify(MaterialName = 'Iron');
      Verify(PileMass = 0.0);
      Verify(PileMassFlowRate > 0.0);
      ExpectedTimeChange := Round(1000 / PileMassFlowRate);
   end;
   with (specialize GetUpdatedFeature<TModelMaterialPileFeature>(ModelSystem, 1)) do
   begin
      Verify(MaterialName = 'Silicon');
      Verify(PileMass = 1000.0);
      Verify(PileMassFlowRate = 0.0);
   end;

   // iron table finishes filling, mining stops
   ExpectUpdate(SystemsServer, ModelSystem, MinTime, MaxTime, TimePinned, 3);
   Verify(ModelSystem.CurrentTime = LastTime + ExpectedTimeChange);
   LastTime := ModelSystem.CurrentTime;
   with (specialize GetUpdatedFeature<TModelMaterialPileFeature>(ModelSystem, 0)) do
   begin
      Verify(MaterialName = 'Iron');
      Verify(PileMass = 1000.0);
      Verify(PileMassFlowRate = 0.0);
   end;
   with (specialize GetUpdatedFeature<TModelMaterialPileFeature>(ModelSystem, 1)) do
   begin
      Verify(MaterialName = 'Silicon');
      Verify(PileMass = 1000.0);
      Verify(PileMassFlowRate = 0.0);
   end;
   with (specialize GetUpdatedFeature<TModelMiningFeature>(ModelSystem, 0)) do
   begin
      Verify(CurrentRate = 0.0);
      Verify(Flags = 2); // piles full
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