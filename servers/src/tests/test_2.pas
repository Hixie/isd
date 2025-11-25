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
   Verify(Grid.Children[0].X = 0);
   Verify(Grid.Children[0].Y = 3);
   Verify(ModelSystem.Assets[(ModelSystem.Assets[Grid.Children[0].AssetID].Features[TModelProxyFeature] as TModelProxyFeature).Child] = ColonyShip);

   // some digging and building tests
   AssetClass1 := GetAssetClassFromBuildingsList(HomeRegion, 'Iron team table');
   AssetClass2 := GetAssetClassFromBuildingsList(HomeRegion, 'Drilling Hole');
   AssetClass3 := GetAssetClassFromBuildingsList(HomeRegion, 'Silicon Table');
   AssetClass4 := GetAssetClassFromBuildingsList(HomeRegion, 'Builder rally point');
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

   TimePinned := True;
   SystemsServer.SendWebSocketStringMessage('0'#00'play'#00 + IntToStr(ModelSystem.SystemID) + #00 + IntToStr(HomeRegion.Parent.ID) + #00'build'#00'0'#00'1'#00 + IntToStr(AssetClass2) + #00);
   Response := TStringStreamReader.Create(SystemsServer.ReadWebSocketStringMessage());
   VerifyPositiveResponse(Response);
   FreeAndNil(Response);

   ExpectUpdate(SystemsServer, ModelSystem, MinTime, MaxTime, TimePinned, 3);
   Verify(ModelSystem.CurrentTime = MaxTime);
   with (specialize GetUpdatedFeature<TModelMaterialPileFeature>(ModelSystem)) do
   begin
      Verify(PileMass = 0.0);
      Verify(PileMassFlowRate > 0);
      Verify(MaterialName = 'Iron');
   end;

   AdvanceTime(1000 * Days); // fill the pile

   ExpectUpdate(SystemsServer, ModelSystem, MinTime, MaxTime, TimePinned, 2);
   with (specialize GetUpdatedFeature<TModelMaterialPileFeature>(ModelSystem)) do
   begin
      Verify(PileMass = 1000.0);
      Verify(PileMassFlowRate = 0);
      Verify(MaterialName = 'Iron');
   end;

   TimePinned := True;
   SystemsServer.SendWebSocketStringMessage('0'#00'play'#00 + IntToStr(ModelSystem.SystemID) + #00 + IntToStr(HomeRegion.Parent.ID) + #00'build'#00'0'#00'2'#00 + IntToStr(AssetClass3) + #00);
   Response := TStringStreamReader.Create(SystemsServer.ReadWebSocketStringMessage());
   VerifyPositiveResponse(Response);
   FreeAndNil(Response);

   ExpectUpdate(SystemsServer, ModelSystem, MinTime, MaxTime, TimePinned, 3);
   Verify(ModelSystem.CurrentTime = MaxTime);
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

   TimePinned := True;
   SystemsServer.SendWebSocketStringMessage('0'#00'play'#00 + IntToStr(ModelSystem.SystemID) + #00 + IntToStr(HomeRegion.Parent.ID) + #00'build'#00'1'#00'0'#00 + IntToStr(AssetClass4) + #00);
   Response := TStringStreamReader.Create(SystemsServer.ReadWebSocketStringMessage());
   VerifyPositiveResponse(Response);
   FreeAndNil(Response);

   ExpectUpdate(SystemsServer, ModelSystem, MinTime, MaxTime, TimePinned, 5);
   Verify(ModelSystem.CurrentTime = MaxTime);
   with (specialize GetUpdatedFeature<TModelMaterialPileFeature>(ModelSystem, 0)) do
   begin
      Verify(PileMass = 0.0);
      Verify(PileMassFlowRate > 0);
      Verify(MaterialName = 'Iron');
   end;
   with (specialize GetUpdatedFeature<TModelMaterialPileFeature>(ModelSystem, 1)) do
   begin
      Verify(PileMass = 0.0);
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