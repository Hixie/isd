{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit test_5;

interface

implementation

uses
   sysutils, harness, endtoend, stringstream, model, stringutils, utils;

type
   TTest = class(TIsdServerTest)
      FTestDirectory: UTF8String;
      procedure RunTest(const BaseDirectory, TestDirectory: UTF8String); override;
      procedure RunTestBody(); override;
   end;

procedure TTest.RunTest(const BaseDirectory, TestDirectory: UTF8String);
begin
   FTestDirectory := TestDirectory;
   inherited;
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
   Success: Boolean;
   HomeRegion: TModelGridFeature;
   AssetClass: Int32;
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
   Verify(SystemsServerCount = 1);
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

   AdvanceTime(10 * Seconds);
   ExpectTechnology(SystemsServer, ModelSystem, MinTime, MaxTime, TimePinned, 'Technology unlocked.');

   AdvanceTime(1 * Hours);
   ExpectUpdate(SystemsServer, ModelSystem, MinTime, MaxTime, TimePinned, 31); // crash // 18 if we fix the bug where structure dirties itself even when knowledge didn't change
   HomeRegion := specialize GetUpdatedFeature<TModelGridFeature>(ModelSystem);

   LoginServerIPC.AwaitScores(1);

  // unlocks asset "Iron Mine";
  // unlocks asset "Factory";
  // unlocks asset "Structure";

   AssetClass := GetAssetClassFromBuildingsList(HomeRegion, 'Iron Mine');
   SystemsServer.SendWebSocketStringMessage('0'#00'play'#00 + IntToStr(ModelSystem.SystemID) + #00 + IntToStr(HomeRegion.Parent.ID) + #00'build'#00'0'#00'0'#00 + IntToStr(AssetClass) + #00);
   Response := TStringStreamReader.Create(SystemsServer.ReadWebSocketStringMessage());
   VerifyPositiveResponse(Response);
   FreeAndNil(Response);
   TimePinned := True;
   ExpectUpdate(SystemsServer, ModelSystem, MinTime, MaxTime, TimePinned, 3);

   AssetClass := GetAssetClassFromBuildingsList(HomeRegion, 'Structure');
   SystemsServer.SendWebSocketStringMessage('0'#00'play'#00 + IntToStr(ModelSystem.SystemID) + #00 + IntToStr(HomeRegion.Parent.ID) + #00'build'#00'1'#00'0'#00 + IntToStr(AssetClass) + #00);
   Response := TStringStreamReader.Create(SystemsServer.ReadWebSocketStringMessage());
   VerifyPositiveResponse(Response);
   FreeAndNil(Response);
   TimePinned := True;
   ExpectUpdate(SystemsServer, ModelSystem, MinTime, MaxTime, TimePinned, 4);

   SystemsServer.SendWebSocketStringMessage('0'#00'play'#00 + IntToStr(ModelSystem.SystemID) + #00 + IntToStr(HomeRegion.Parent.ID) + #00'build'#00'2'#00'0'#00 + IntToStr(AssetClass) + #00);
   Response := TStringStreamReader.Create(SystemsServer.ReadWebSocketStringMessage());
   VerifyPositiveResponse(Response);
   FreeAndNil(Response);
   TimePinned := True;
   ExpectUpdate(SystemsServer, ModelSystem, MinTime, MaxTime, TimePinned, 5);

   AssetClass := GetAssetClassFromBuildingsList(HomeRegion, 'Factory');
   SystemsServer.SendWebSocketStringMessage('0'#00'play'#00 + IntToStr(ModelSystem.SystemID) + #00 + IntToStr(HomeRegion.Parent.ID) + #00'build'#00'0'#00'1'#00 + IntToStr(AssetClass) + #00);
   Response := TStringStreamReader.Create(SystemsServer.ReadWebSocketStringMessage());
   VerifyPositiveResponse(Response);
   FreeAndNil(Response);
   TimePinned := True;
   ExpectUpdate(SystemsServer, ModelSystem, MinTime, MaxTime, TimePinned, 6);

   with (specialize GetUpdatedFeature<TModelFactoryFeature>(ModelSystem, 0)) do
   begin
      Verify(DisabledReasons = %00000000);
   end;

   AdvanceTime(10000000 * Days);

   ExpectUpdate(SystemsServer, ModelSystem, MinTime, MaxTime, TimePinned, 3);
   ExpectUpdate(SystemsServer, ModelSystem, MinTime, MaxTime, TimePinned, 3);
   ExpectUpdate(SystemsServer, ModelSystem, MinTime, MaxTime, TimePinned, 3);
   
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

   Success := True;
   CloseServers(Success);
   if (not Success) then
      raise Exception.Create('failed to shut down servers');
   FreeAndNil(ModelSystem);

   StartServers(FTestDirectory);

   SystemsServer := FSystemsServers[0].ConnectWebSocket();
   SystemsServer.SendWebSocketStringMessage('0'#00'login'#00 + Token + #00);
   Response := TStringStreamReader.Create(SystemsServer.ReadWebSocketStringMessage());
   VerifyPositiveResponse(Response);
   {ServerVersion :=} Response.ReadQWord();
   VerifyEndOfResponse(Response);

   ModelSystem := TModelSystem.Create();

   TimePinned := True;
   ExpectUpdate(SystemsServer, ModelSystem, MinTime, MaxTime, TimePinned, 68);

   FreeAndNil(ModelSystem);
   SystemsServer.CloseWebSocket();
   FreeAndNil(SystemsServer);
end;

initialization
   RegisterTest(TTest.Create());
end.