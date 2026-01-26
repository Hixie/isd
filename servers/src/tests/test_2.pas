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

   ExpectUpdate(SystemsServer, ModelSystem, MinTime, MaxTime, TimePinned, 311); // 127 if we fix the bug where structure dirties itself even when knowledge didn't change

   SystemsServerIPC.ResetRNG(2112348, 4796929787397293412);
   
   AdvanceTime(1000 * Days); // crash the colony ship, get lots of technologies
   ExpectTechnology(SystemsServer, ModelSystem, MinTime, MaxTime, TimePinned, 'Technology unlocked.');

   ExpectUpdate(SystemsServer, ModelSystem, MinTime, MaxTime, TimePinned, 31); // crash // 18 if we fix the bug where structure dirties itself even when knowledge didn't change
   Grid := specialize GetUpdatedFeature<TModelGridFeature>(ModelSystem);
   HomeRegion := Grid;
   ColonyShip := FindColonyShip(ModelSystem);
   Verify(Grid.Children.Length = 1);
   Verify(Grid.Children[0].X = 9);
   Verify(Grid.Children[0].Y = 15);
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
   ExpectUpdate(SystemsServer, ModelSystem, MinTime, MaxTime, TimePinned, 3); // 2 if we fix the bug where structure dirties itself even when knowledge didn't change
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

   ExpectUpdate(SystemsServer, ModelSystem, MinTime, MaxTime, TimePinned, 4); // 3 if we fix the bug where structure dirties itself even when knowledge didn't change
   Verify(ModelSystem.CurrentTime = MaxTime);
   LastTime := ModelSystem.CurrentTime;
   with (specialize GetUpdatedFeature<TModelMiningFeature>(ModelSystem)) do
   begin
      Verify(DisabledReasons = %01000000); // no piles
      Verify(CurrentRate > 0.0);
   end;
   with (specialize GetUpdatedFeature<TModelMaterialPileFeature>(ModelSystem)) do
   begin
      Verify(PileMass = 0.0);
      Verify(PileMassFlowRate > 0);
      Verify(MaterialName = 'Iron');
   end;

   // ADVANCE TIME
   AdvanceTime(1000 * Days); // fill the pile

   ExpectUpdate(SystemsServer, ModelSystem, MinTime, MaxTime, TimePinned, 1); // skipped if we fix the bug where structure dirties itself even when knowledge didn't change
   
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

   ExpectUpdate(SystemsServer, ModelSystem, MinTime, MaxTime, TimePinned, 4); // 3 if we fix the bug where structure dirties itself even when knowledge didn't change
   Verify(ModelSystem.CurrentTime = MaxTime);
   Verify(ModelSystem.CurrentTime = 86400000000000);
   LastTime := ModelSystem.CurrentTime;
   with (specialize GetUpdatedFeature<TModelRefiningFeature>(ModelSystem, 0)) do
   begin
      Verify(Ore = 12);
      Verify(CurrentRate = 0); // iron table is filled
   end;
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
   with (specialize GetUpdatedFeature<TModelStructureFeature>(ModelSystem, 1)) do // doesn't need index if we fix the bug where structure dirties itself even when knowledge didn't change
   begin
      Verify(Quantity = 0);
      Verify(QuantityRate = 0.0); // no builders
      Verify(Hp = 0);
      Verify(HpRate = 0.0); // no builders
   end;

   // BUILD RALLY POINT (instabuild silicon table, resume refining iron)
   TimePinned := True;
   SystemsServer.SendWebSocketStringMessage('0'#00'play'#00 + IntToStr(ModelSystem.SystemID) + #00 + IntToStr(HomeRegion.Parent.ID) + #00'build'#00'6'#00'12'#00 + IntToStr(AssetClass4) + #00);
   Response := TStringStreamReader.Create(SystemsServer.ReadWebSocketStringMessage());
   VerifyPositiveResponse(Response);
   FreeAndNil(Response);

   ExpectUpdate(SystemsServer, ModelSystem, MinTime, MaxTime, TimePinned, 6); // 5 if we fix the bug where structure dirties itself even when knowledge didn't change
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
      Verify(Ore = 12); // iron
      Verify(CurrentRate > 0);
      ExpectedNextTime := LastTime + Round(1000.0 / CurrentRate); // this is how fast the silicon table can get its 2kg iron (it already has 1kg)
      Rate := CurrentRate;
   end;
   with (specialize GetUpdatedFeature<TModelMaterialPileFeature>(ModelSystem, 1)) do
   begin
      Verify(PileMass = 0.0);
      Verify(PileMassFlowRate = 0); // HP is still zero, so can't refine yet
      Verify(MaterialName = 'Silicon');
   end;
   with (specialize GetUpdatedFeature<TModelStructureFeature>(ModelSystem, 1)) do // doesn't need index if we fix the bug where structure dirties itself even when knowledge didn't change
   begin
      Verify(Quantity = 1);
      Verify(QuantityRate > 0.0);
      Verify(QuantityRate = Rate / 1000.0);
      Verify(Hp = 0); // just got builders (iron was instabuilt)
      Verify(HpRate > 0.0);
      Verify(HpRate > QuantityRate);
      ExpectedTimeChange := Round(1 / HpRate); // time until we are viable
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
   with (specialize GetUpdatedFeature<TModelRefiningFeature>(ModelSystem, 0)) do
   begin
      Verify(Ore = 12); // iron
      Verify(CurrentRate > 0);
      Verify(LastTime < ExpectedNextTime);
      // we reset the timer because something happened // TODO: we shouldn't reset the timer
      ExpectedNextTime := LastTime + Round(1000.0 / CurrentRate); // this is how fast the silicon table can get its 2kg iron (it already has 1kg)
      Rate := CurrentRate;
   end;
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
      Verify(MaterialName = 'Silicon');
   end;
   with (specialize GetUpdatedFeature<TModelStructureFeature>(ModelSystem)) do
   begin
      Verify(Quantity = 1);
      Verify(QuantityRate > 0.0); // still getting iron
      Verify(QuantityRate = Rate / 1000.0);
      Verify(Hp = 1);
      Verify(HpRate > 0.0);
      Verify(HpRate > QuantityRate);
   end;

   // silicon table finishes getting its iron, starts giving itself silicon and allowing iron to pile up
   ExpectUpdate(SystemsServer, ModelSystem, MinTime, MaxTime, TimePinned, 2);
   Verify(ModelSystem.CurrentTime >= ExpectedNextTime);
   Verify(ModelSystem.CurrentTime - ExpectedNextTime < 150); // TODO: for some reason there's a 149ms error here?
   LastTime := ModelSystem.CurrentTime;
   with (specialize GetUpdatedFeature<TModelRefiningFeature>(ModelSystem, 0)) do
   begin
      Verify(Ore = 12); // iron
      Verify(CurrentRate > 0);
      ExpectedNextTime := LastTime + Round(1000.0 / CurrentRate); // this is how fast we can fill up on iron
      Rate := CurrentRate;
   end;
   with (specialize GetUpdatedFeature<TModelMaterialPileFeature>(ModelSystem, 0)) do
   begin
      Verify(PileMass = 0.0);
      Verify(PileMassFlowRate > 0);
      Verify(PileMassFlowRate = Rate);
      Verify(MaterialName = 'Iron');
   end;
   with (specialize GetUpdatedFeature<TModelRefiningFeature>(ModelSystem, 1)) do
   begin
      Verify(Ore = 9); // silicon
      Verify(CurrentRate > 0);
      Rate := CurrentRate;
   end;
   with (specialize GetUpdatedFeature<TModelMaterialPileFeature>(ModelSystem, 1)) do
   begin
      Verify(PileMass = 0.0);
      Verify(PileMassFlowRate = 0.0);
      Verify(MaterialName = 'Silicon');
   end;
   with (specialize GetUpdatedFeature<TModelStructureFeature>(ModelSystem)) do
   begin
      Verify(Quantity = 2);
      Verify(QuantityRate > 0.0);
      Verify(QuantityRate = Rate / 1000.0);
      Verify(Hp = 2);
      Verify(HpRate > 0.0);
   end;

   // iron table finishes filling, mining stops
   ExpectUpdate(SystemsServer, ModelSystem, MinTime, MaxTime, TimePinned, 2);
   Verify(ModelSystem.CurrentTime >= ExpectedNextTime);
   Verify(ModelSystem.CurrentTime - ExpectedNextTime < 150); // TODO: for some reason there's a 149ms error here?
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
      Verify(PileMass = 0.0);
      Verify(PileMassFlowRate = 0.0);
   end;
   with (specialize GetUpdatedFeature<TModelRefiningFeature>(ModelSystem, 1)) do
   begin
      Verify(Ore = 9); // silicon
      Verify(CurrentRate > 0);
      Rate := CurrentRate;
   end;
   with (specialize GetUpdatedFeature<TModelStructureFeature>(ModelSystem)) do
   begin
      Verify(Quantity = 2);
      Verify(QuantityRate > 0.0);
      Verify(QuantityRate = Rate / 1000.0);
      Verify(Hp = 2);
      Verify(HpRate > 0.0);
      Verify(HpRate > QuantityRate);
      ExpectedNextTime := LastTime + Round(1 / QuantityRate);
   end;
   
   // table finishes getting its silicon
   ExpectUpdate(SystemsServer, ModelSystem, MinTime, MaxTime, TimePinned, 3);
   Verify(ModelSystem.CurrentTime = ExpectedNextTime);
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
      Verify(PileMass = 0.0);
      Verify(PileMassFlowRate > 0.0);
      ExpectedNextTime := LastTime + Round(1000 / PileMassFlowRate);
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
   ExpectUpdate(SystemsServer, ModelSystem, MinTime, MaxTime, TimePinned, 3);
   Verify(ModelSystem.CurrentTime = ExpectedNextTime);
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