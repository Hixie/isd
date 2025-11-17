{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit test_3;

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
   HomeRegion, Jobs1, Jobs2: TModelAsset;
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

   AdvanceTime(1000 * Days); // crash the colony ship, unlock technologies
   ExpectTechnology(SystemsServer, ModelSystem, MinTime, MaxTime, TimePinned, 'Technology unlocked.');
   ExpectUpdate(SystemsServer, ModelSystem, MinTime, MaxTime, TimePinned, 18); // crash
   HomeRegion := specialize GetUpdatedFeature<TModelGridFeature>(ModelSystem).Parent;
   with (specialize GetUpdatedFeature<TModelPopulationFeature>(ModelSystem)) do
   begin
      Verify(Total = 2000);
      Verify(Jobs = 0);
   end;

   // add 1000 jobs
   SystemsServer.SendWebSocketStringMessage('0'#00'play'#00 + IntToStr(ModelSystem.SystemID) + #00 + IntToStr(HomeRegion.ID) + #00'build'#00'0'#00'0'#00'1000'#00);
   Response := TStringStreamReader.Create(SystemsServer.ReadWebSocketStringMessage());
   VerifyPositiveResponse(Response);
   FreeAndNil(Response);

   TimePinned := True;
   ExpectUpdate(SystemsServer, ModelSystem, MinTime, MaxTime, TimePinned, 3);
   with (specialize GetUpdatedFeature<TModelPopulationFeature>(ModelSystem)) do
   begin
      Verify(Total = 2000);
      Verify(Jobs = 1000);
   end;
   with (specialize GetUpdatedFeature<TModelStaffingFeature>(ModelSystem)) do
   begin
      Verify(Jobs = 1000);
      Verify(Workers = 1000);
      Jobs1 := Parent;
   end;

   // add 2000 jobs
   SystemsServer.SendWebSocketStringMessage('0'#00'play'#00 + IntToStr(ModelSystem.SystemID) + #00 + IntToStr(HomeRegion.ID) + #00'build'#00'1'#00'0'#00'1001'#00);
   Response := TStringStreamReader.Create(SystemsServer.ReadWebSocketStringMessage());
   VerifyPositiveResponse(Response);
   FreeAndNil(Response);

   TimePinned := True;
   ExpectUpdate(SystemsServer, ModelSystem, MinTime, MaxTime, TimePinned, 2);
   with (specialize GetUpdatedFeature<TModelStaffingFeature>(ModelSystem)) do
   begin
      Verify(Jobs = 2000);
      Verify(Workers = 0);
      Jobs2 := Parent;
   end;

   // add 1000 jobs
   SystemsServer.SendWebSocketStringMessage('0'#00'play'#00 + IntToStr(ModelSystem.SystemID) + #00 + IntToStr(HomeRegion.ID) + #00'build'#00'2'#00'0'#00'1000'#00);
   Response := TStringStreamReader.Create(SystemsServer.ReadWebSocketStringMessage());
   VerifyPositiveResponse(Response);
   FreeAndNil(Response);

   TimePinned := True;
   ExpectUpdate(SystemsServer, ModelSystem, MinTime, MaxTime, TimePinned, 3);
   with (specialize GetUpdatedFeature<TModelPopulationFeature>(ModelSystem)) do
   begin
      Verify(Total = 2000);
      Verify(Jobs = 2000);
   end;
   with (specialize GetUpdatedFeature<TModelStaffingFeature>(ModelSystem)) do
   begin
      Verify(Jobs = 1000);
      Verify(Workers = 1000);
   end;

   // disable the first one
   SystemsServer.SendWebSocketStringMessage('0'#00'play'#00 + IntToStr(ModelSystem.SystemID) + #00 + IntToStr(Jobs1.ID) + #00'disable'#00);
   Response := TStringStreamReader.Create(SystemsServer.ReadWebSocketStringMessage());
   VerifyPositiveResponse(Response);
   FreeAndNil(Response);

   TimePinned := True;
   ExpectUpdate(SystemsServer, ModelSystem, MinTime, MaxTime, TimePinned, 3);
   with (specialize GetUpdatedFeature<TModelStaffingFeature>(ModelSystem, 0)) do
   begin
      Verify(Jobs = 1000);
      Verify(Workers = 0);
   end;
   with (specialize GetUpdatedFeature<TModelStaffingFeature>(ModelSystem, 1)) do
   begin
      Verify(Jobs = 2000);
      Verify(Workers = 2000);
   end;
   with (specialize GetUpdatedFeature<TModelStaffingFeature>(ModelSystem, 2)) do
   begin
      Verify(Jobs = 1000);
      Verify(Workers = 0);
   end;

   // disable the first one
   SystemsServer.SendWebSocketStringMessage('0'#00'play'#00 + IntToStr(ModelSystem.SystemID) + #00 + IntToStr(Jobs2.ID) + #00'disable'#00);
   Response := TStringStreamReader.Create(SystemsServer.ReadWebSocketStringMessage());
   VerifyPositiveResponse(Response);
   FreeAndNil(Response);

   TimePinned := True;
   ExpectUpdate(SystemsServer, ModelSystem, MinTime, MaxTime, TimePinned, 3);
   with (specialize GetUpdatedFeature<TModelPopulationFeature>(ModelSystem)) do
   begin
      Verify(Total = 2000);
      Verify(Jobs = 1000);
   end;
   with (specialize GetUpdatedFeature<TModelStaffingFeature>(ModelSystem, 0)) do
   begin
      Verify(Jobs = 2000);
      Verify(Workers = 0);
   end;
   with (specialize GetUpdatedFeature<TModelStaffingFeature>(ModelSystem, 1)) do
   begin
      Verify(Jobs = 1000);
      Verify(Workers = 1000);
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