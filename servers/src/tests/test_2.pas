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
   ColonyShip, HomeRegion: TModelAsset;
   AssetClass1, AssetClass2: Integer;
begin
   LoginServer := FLoginServer.ConnectWebSocket();
   LoginServer.SendWebSocketStringMessage('0'#00'new'#00);
   Response := TStringStreamReader.Create(LoginServer.ReadWebSocketStringMessage());
   VerifyPositiveResponse(Response);
   {Username :=} Response.ReadString();
   {Password :=} Response.ReadString();
   DynastyServerURL := Response.ReadString();
   Token := Response.ReadString();
   VerifyEndOfResponse(Response);

   DynastyServer := FDynastiesServers[0].ConnectWebSocket();
   DynastyServer.SendWebSocketStringMessage('0'#00'login'#00 + Token + #00);
   Response := TStringStreamReader.Create(DynastyServer.ReadWebSocketStringMessage());
   VerifyPositiveResponse(Response);
   DynastyID := Response.ReadQWord();
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
   ColonyShip := FindColonyShip(ModelSystem);

   AdvanceTime(1000 * Days); // crash the colony ship, get lots of technologies
   ExpectTechnology(SystemsServer, ModelSystem, MinTime, MaxTime, TimePinned, 'Don''t mind the holes');
   ExpectTechnology(SystemsServer, ModelSystem, MinTime, MaxTime, TimePinned, 'Apologies please don''t evict us');
   ExpectUpdate(SystemsServer, ModelSystem, MinTime, MaxTime, TimePinned, 10); // crash
   HomeRegion := specialize GetUpdatedFeature<TModelGridFeature>(ModelSystem).Parent;
   ExpectTechnology(SystemsServer, ModelSystem, MinTime, MaxTime, TimePinned, 'Drill!'#10);
   ExpectTechnology(SystemsServer, ModelSystem, MinTime, MaxTime, TimePinned, 'Iron team'#10);
   ExpectTechnology(SystemsServer, ModelSystem, MinTime, MaxTime, TimePinned, 'Silicon'#10);
   ExpectTechnology(SystemsServer, ModelSystem, MinTime, MaxTime, TimePinned, 'Congratulations'#10);
   ExpectTechnology(SystemsServer, ModelSystem, MinTime, MaxTime, TimePinned, 'Breakthrough in City Planning'#10);
   ExpectTechnology(SystemsServer, ModelSystem, MinTime, MaxTime, TimePinned, 'Congratulations'#10);
   ExpectTechnology(SystemsServer, ModelSystem, MinTime, MaxTime, TimePinned, 'Mining'#10);
   ExpectTechnology(SystemsServer, ModelSystem, MinTime, MaxTime, TimePinned, 'Storage for mining'#10);
   ExpectTechnology(SystemsServer, ModelSystem, MinTime, MaxTime, TimePinned, 'Stuff in holes'#10);
   ExpectTechnology(SystemsServer, ModelSystem, MinTime, MaxTime, TimePinned, 'Where we come from'#10);
   ExpectTechnology(SystemsServer, ModelSystem, MinTime, MaxTime, TimePinned, 'Communicating with our creator'#10);
   ExpectTechnology(SystemsServer, ModelSystem, MinTime, MaxTime, TimePinned, '"Powerful Being" nonsense'#10);
   ExpectTechnology(SystemsServer, ModelSystem, MinTime, MaxTime, TimePinned, 'The Impact of Religion on Society'#10);
   ExpectTechnology(SystemsServer, ModelSystem, MinTime, MaxTime, TimePinned, 'Reorganisation'#10);
   
   // Build a drill
   SystemsServer.SendWebSocketStringMessage('0'#00'play'#00 + IntToStr(ModelSystem.SystemID) + #00 + IntToStr(HomeRegion.ID) + #00'get-buildings'#00'1'#00'1'#00);
   Response := TStringStreamReader.Create(SystemsServer.ReadWebSocketStringMessage());
   VerifyPositiveResponse(Response);
   AssetClass1 := GetAssetClassFromBuildingsList(Response, 'Iron team table');
   AssetClass2 := GetAssetClassFromBuildingsList(Response, 'Drilling Hole');
   FreeAndNil(Response);
   SystemsServer.SendWebSocketStringMessage('0'#00'play'#00 + IntToStr(ModelSystem.SystemID) + #00 + IntToStr(HomeRegion.ID) + #00'build'#00'1'#00'1'#00 + IntToStr(AssetClass1) + #00);
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
   SystemsServer.SendWebSocketStringMessage('0'#00'play'#00 + IntToStr(ModelSystem.SystemID) + #00 + IntToStr(HomeRegion.ID) + #00'build'#00'1'#00'2'#00 + IntToStr(AssetClass2) + #00);
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