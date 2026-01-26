{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit test_4;

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
   Hole, IronTable, SiliconTable, Rally: TModelAsset;
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

   ExpectUpdate(SystemsServer, ModelSystem, MinTime, MaxTime, TimePinned, 311); // 127 if we fix the bug where structure dirties itself even when knowledge didn't change

   SystemsServerIPC.ResetRNG(2112348, 4796929787397293412);

   AdvanceTime(1000 * Days);
   ExpectTechnology(SystemsServer, ModelSystem, MinTime, MaxTime, TimePinned, 'Technology unlocked.');
   ExpectUpdate(SystemsServer, ModelSystem, MinTime, MaxTime, TimePinned, 31); // crash // 18 if we fix the bug where structure dirties itself even when knowledge didn't change

   HomeRegion := specialize GetUpdatedFeature<TModelGridFeature>(ModelSystem);

   AssetClass1 := GetAssetClassFromBuildingsList(HomeRegion, 'Drilling Hole');
   AssetClass2 := GetAssetClassFromBuildingsList(HomeRegion, 'Iron team table');
   AssetClass3 := GetAssetClassFromBuildingsList(HomeRegion, 'Silicon Table');
   AssetClass4 := GetAssetClassFromBuildingsList(HomeRegion, 'Builder rally point');

   TimePinned := True;
   SystemsServer.SendWebSocketStringMessage('0'#00'play'#00 + IntToStr(ModelSystem.SystemID) + #00 + IntToStr(HomeRegion.Parent.ID) + #00'build'#00'0'#00'0'#00 + IntToStr(AssetClass1) + #00);
   Response := TStringStreamReader.Create(SystemsServer.ReadWebSocketStringMessage());
   VerifyPositiveResponse(Response);
   FreeAndNil(Response);
   ExpectUpdate(SystemsServer, ModelSystem, MinTime, MaxTime, TimePinned, 3); // 2 if we fix the bug where structure dirties itself even when knowledge didn't change
   with (specialize GetUpdatedFeature<TModelMiningFeature>(ModelSystem)) do
   begin
      Verify(DisabledReasons = %01000000); // rate limited by target (no piles)
      Verify(CurrentRate = 0.0);
      Hole := Parent;
   end;

   TimePinned := True;
   SystemsServer.SendWebSocketStringMessage('0'#00'play'#00 + IntToStr(ModelSystem.SystemID) + #00 + IntToStr(HomeRegion.Parent.ID) + #00'build'#00'0'#00'1'#00 + IntToStr(AssetClass2) + #00);
   Response := TStringStreamReader.Create(SystemsServer.ReadWebSocketStringMessage());
   VerifyPositiveResponse(Response);
   FreeAndNil(Response);
   ExpectUpdate(SystemsServer, ModelSystem, MinTime, MaxTime, TimePinned, 4); // 3 if we fix the bug where structure dirties itself even when knowledge didn't change
   with (specialize GetUpdatedFeature<TModelMiningFeature>(ModelSystem)) do
   begin
      Verify(DisabledReasons = %01000000); // rate limited by target (no piles, so we can't mine faster than the refining)
      Verify(CurrentRate > 0.0);
      Verify(Parent = Hole);
   end;
   with (specialize GetUpdatedFeature<TModelRefiningFeature>(ModelSystem)) do
   begin
      Verify(DisabledReasons = %00100000); // rate limited by source (no piles, so we can't refine faster than the mining)
      Verify(CurrentRate > 0.0);
      IronTable := Parent;
   end;

   AdvanceTime(1000 * Days);
   ExpectUpdate(SystemsServer, ModelSystem, MinTime, MaxTime, TimePinned, 1); // no update if we fix the bug where structure dirties itself even when knowledge didn't change
   with (specialize GetUpdatedFeature<TModelRefiningFeature>(ModelSystem)) do
   begin
      Verify(DisabledReasons = %00100000); // rate limited by source (no piles, so we can't refine faster than the mining)
      Verify(CurrentRate > 0.0);
      IronTable := Parent;
   end;

   ExpectUpdate(SystemsServer, ModelSystem, MinTime, MaxTime, TimePinned, 2);
   with (specialize GetUpdatedFeature<TModelMiningFeature>(ModelSystem)) do
   begin
      Verify(DisabledReasons = %01000000); // rate limited by target (no piles, so we can't mine faster than the refining)
      Verify(CurrentRate = 0.0);
      Verify(Parent = Hole);
   end;
   with (specialize GetUpdatedFeature<TModelRefiningFeature>(ModelSystem)) do
   begin
      Verify(DisabledReasons = %01100000); // rate limited by source (no piles, so we can't refine faster than the mining) and target (pile full)
      Verify(CurrentRate = 0.0);
      Verify(Parent = IronTable);
   end;
   with (specialize GetUpdatedFeature<TModelMaterialPileFeature>(ModelSystem)) do
   begin
      Verify(PileMass = 1000);
      Verify(PileMassFlowRate = 0);
      Verify(Capacity = 1000);
      Verify(Parent = IronTable);
   end;
   
   TimePinned := True;
   SystemsServer.SendWebSocketStringMessage('0'#00'play'#00 + IntToStr(ModelSystem.SystemID) + #00 + IntToStr(IronTable.ID) + #00'disable' + #00); // first disable of the test
   Response := TStringStreamReader.Create(SystemsServer.ReadWebSocketStringMessage());
   VerifyPositiveResponse(Response);
   FreeAndNil(Response);
   ExpectUpdate(SystemsServer, ModelSystem, MinTime, MaxTime, TimePinned, 1);
   with (specialize GetUpdatedFeature<TModelRefiningFeature>(ModelSystem)) do
   begin
      Verify(DisabledReasons = %00000100); // disabled
      Verify(CurrentRate = 0.0);
      Verify(Parent = IronTable);
   end;
   with (specialize GetUpdatedFeature<TModelMaterialPileFeature>(ModelSystem)) do
   begin
      Verify(PileMass = 1000);
      Verify(PileMassFlowRate = 0);
      Verify(Capacity = 1000);
      Verify(Parent = IronTable);
   end;

   TimePinned := True;
   SystemsServer.SendWebSocketStringMessage('0'#00'play'#00 + IntToStr(ModelSystem.SystemID) + #00 + IntToStr(HomeRegion.Parent.ID) + #00'build'#00'0'#00'2'#00 + IntToStr(AssetClass3) + #00);
   Response := TStringStreamReader.Create(SystemsServer.ReadWebSocketStringMessage());
   VerifyPositiveResponse(Response);
   FreeAndNil(Response);
   ExpectUpdate(SystemsServer, ModelSystem, MinTime, MaxTime, TimePinned, 4); // 3 if we fix the bug where structure dirties itself even when knowledge didn't change
   with (specialize GetUpdatedFeature<TModelRefiningFeature>(ModelSystem, 0)) do
   begin
      Verify(DisabledReasons = %00000100);
      Verify(CurrentRate = 0.0);
      Verify(Parent = IronTable);
   end;
   with (specialize GetUpdatedFeature<TModelMaterialPileFeature>(ModelSystem, 0)) do
   begin
      Verify(PileMass = 1000);
      Verify(PileMassFlowRate = 0);
      Verify(Capacity = 1000);
      Verify(Parent = IronTable);
   end;
   with (specialize GetUpdatedFeature<TModelRefiningFeature>(ModelSystem, 1)) do
   begin
      Verify(DisabledReasons = %00000010);
      Verify(CurrentRate = 0.0);
      SiliconTable := Parent;
   end;
   with (specialize GetUpdatedFeature<TModelMaterialPileFeature>(ModelSystem, 1)) do
   begin
      Verify(PileMass = 0);
      Verify(PileMassFlowRate = 0);
      Verify(Capacity = 1000);
      Verify(Parent = SiliconTable);
   end;
   with (specialize GetUpdatedFeature<TModelBuilderFeature>(ModelSystem, 0)) do
   begin
      Verify(DisabledReasons = %00000010);
      Verify(Capacity = 1);
      Verify(Structures.Length = 0);
      Verify(Parent = SiliconTable);
   end;
   
   TimePinned := True;
   SystemsServer.SendWebSocketStringMessage('0'#00'play'#00 + IntToStr(ModelSystem.SystemID) + #00 + IntToStr(HomeRegion.Parent.ID) + #00'build'#00'1'#00'0'#00 + IntToStr(AssetClass4) + #00);
   Response := TStringStreamReader.Create(SystemsServer.ReadWebSocketStringMessage());
   VerifyPositiveResponse(Response);
   FreeAndNil(Response);
   ExpectUpdate(SystemsServer, ModelSystem, MinTime, MaxTime, TimePinned, 5); // 4 if we fix the bug where structure dirties itself even when knowledge didn't change
   with (specialize GetUpdatedFeature<TModelRefiningFeature>(ModelSystem, 0)) do
   begin
      Verify(DisabledReasons = %00000100);
      Verify(CurrentRate = 0.0);
      Verify(Parent = IronTable);
   end;
   with (specialize GetUpdatedFeature<TModelMaterialPileFeature>(ModelSystem, 0)) do
   begin
      Verify(PileMass = 0);
      Verify(PileMassFlowRate = 0);
      Verify(Capacity = 1000);
      Verify(Parent = IronTable);
   end;
   with (specialize GetUpdatedFeature<TModelRefiningFeature>(ModelSystem, 1)) do
   begin
      Verify(DisabledReasons = %00000010);
      Verify(CurrentRate = 0.0);
      Verify(Parent = SiliconTable);
   end;
   with (specialize GetUpdatedFeature<TModelMaterialPileFeature>(ModelSystem, 1)) do
   begin
      Verify(PileMass = 0);
      Verify(PileMassFlowRate = 0);
      Verify(Capacity = 1000);
      Verify(Parent = SiliconTable);
   end;
   with (specialize GetUpdatedFeature<TModelStructureFeature>(ModelSystem, 0)) do // not present if we fix the bug where structure dirties itself even when knowledge didn't change
   begin
      Verify(Parent <> SiliconTable);
   end;
   with (specialize GetUpdatedFeature<TModelStructureFeature>(ModelSystem, 1)) do
   begin
      Verify(Quantity = 1);
      Verify(QuantityRate = 0);
      Verify(Hp = 0);
      Verify(HpRate > 0);
      Verify(MinHp = 1);
      Verify(Parent = SiliconTable);
   end;
   with (specialize GetUpdatedFeature<TModelBuilderFeature>(ModelSystem, 0)) do
   begin
      Verify(DisabledReasons = %00000010);
      Verify(Capacity = 1);
      Verify(Structures.Length = 0);
      Verify(Parent = SiliconTable);
   end;
   with (specialize GetUpdatedFeature<TModelBuilderFeature>(ModelSystem, 1)) do
   begin
      Verify(DisabledReasons = %00000000);
      Verify(Capacity = 1);
      Verify(Structures.Length = 1);
      Verify(ModelSystem.Assets[Structures[0]] = SiliconTable);
      Rally := Parent;
   end;
   
   AdvanceTime(10 * Days);
   ExpectUpdate(SystemsServer, ModelSystem, MinTime, MaxTime, TimePinned, 4);
   with (specialize GetUpdatedFeature<TModelMiningFeature>(ModelSystem)) do
   begin
      Verify(DisabledReasons = %01000000); // rate limited by target (no piles, so we can't mine faster than the refining)
      Verify(CurrentRate > 0.0);
      Verify(Parent = Hole);
   end;
   with (specialize GetUpdatedFeature<TModelRefiningFeature>(ModelSystem, 0)) do
   begin
      Verify(DisabledReasons = %00000100);
      Verify(CurrentRate = 0.0);
      Verify(Parent = IronTable);
   end;
   with (specialize GetUpdatedFeature<TModelMaterialPileFeature>(ModelSystem, 0)) do
   begin
      Verify(PileMass = 0);
      Verify(PileMassFlowRate = 0);
      Verify(Capacity = 1000);
      Verify(Parent = IronTable);
   end;
   with (specialize GetUpdatedFeature<TModelRefiningFeature>(ModelSystem, 1)) do
   begin
      Verify(DisabledReasons = %00100000); // rate limited by source
      Verify(CurrentRate > 0.0);
      Verify(Parent = SiliconTable);
   end;
   with (specialize GetUpdatedFeature<TModelMaterialPileFeature>(ModelSystem, 1)) do
   begin
      Verify(PileMass = 0);
      Verify(PileMassFlowRate > 0);
      Verify(Capacity = 1000);
      Verify(Parent = SiliconTable);
   end;
   with (specialize GetUpdatedFeature<TModelStructureFeature>(ModelSystem, 0)) do
   begin
      Verify(Quantity = 1);
      Verify(QuantityRate = 0);
      Verify(Hp = 1);
      Verify(HpRate > 0);
      Verify(MinHp = 1);
      Verify(Parent = SiliconTable);
   end;
   with (specialize GetUpdatedFeature<TModelBuilderFeature>(ModelSystem, 0)) do
   begin
      Verify(Parent = SiliconTable);
      Verify(DisabledReasons = %00000000);
      Verify(Capacity = 1);
      Verify(Structures.Length = 0);
   end;
   with (specialize GetUpdatedFeature<TModelBuilderFeature>(ModelSystem, 1)) do
   begin
      Verify(Parent = Rally);
      Verify(DisabledReasons = %00000000);
      Verify(Capacity = 1);
      Verify(Structures.Length = 1);
   end;

   ExpectUpdate(SystemsServer, ModelSystem, MinTime, MaxTime, TimePinned, 2);
   with (specialize GetUpdatedFeature<TModelRefiningFeature>(ModelSystem, 0)) do
   begin
      Verify(DisabledReasons = %00000100);
      Verify(CurrentRate = 0.0);
      Verify(Parent = IronTable);
   end;
   with (specialize GetUpdatedFeature<TModelMaterialPileFeature>(ModelSystem, 0)) do
   begin
      Verify(PileMass = 0);
      Verify(PileMassFlowRate = 0);
      Verify(Capacity = 1000);
      Verify(Parent = IronTable);
   end;
   with (specialize GetUpdatedFeature<TModelRefiningFeature>(ModelSystem, 1)) do
   begin
      Verify(DisabledReasons = %00100000); // rate limited by source
      Verify(CurrentRate > 0.0);
      Verify(Parent = SiliconTable);
   end;
   with (specialize GetUpdatedFeature<TModelMaterialPileFeature>(ModelSystem, 1)) do
   begin
      Verify(PileMass = 0);
      Verify(PileMassFlowRate > 0);
      Verify(Capacity = 1000);
      Verify(Parent = SiliconTable);
   end;
   with (specialize GetUpdatedFeature<TModelStructureFeature>(ModelSystem, 0)) do
   begin
      Verify(Quantity = 1);
      Verify(QuantityRate = 0);
      Verify(Hp = 1);
      Verify(HpRate > 0);
      Verify(MinHp = 1);
      Verify(Parent = SiliconTable);
   end;
   with (specialize GetUpdatedFeature<TModelBuilderFeature>(ModelSystem, 0)) do
   begin
      Verify(DisabledReasons = %00000000);
      Verify(Capacity = 1);
      Verify(Structures.Length = 0);
      Verify(Parent = SiliconTable);
   end;

   ExpectUpdate(SystemsServer, ModelSystem, MinTime, MaxTime, TimePinned, 3);
   with (specialize GetUpdatedFeature<TModelMiningFeature>(ModelSystem)) do
   begin
      Verify(DisabledReasons = %01000000); // rate limited by target (no piles, so we can't mine faster than the refining)
      Verify(CurrentRate = 0.0);
      Verify(Parent = Hole);
   end;
   with (specialize GetUpdatedFeature<TModelRefiningFeature>(ModelSystem, 0)) do
   begin
      Verify(DisabledReasons = %00000100);
      Verify(CurrentRate = 0.0);
      Verify(Parent = IronTable);
   end;
   with (specialize GetUpdatedFeature<TModelMaterialPileFeature>(ModelSystem, 0)) do
   begin
      Verify(PileMass = 0);
      Verify(PileMassFlowRate = 0);
      Verify(Capacity = 1000);
      Verify(Parent = IronTable);
   end;
   with (specialize GetUpdatedFeature<TModelRefiningFeature>(ModelSystem, 1)) do
   begin
      Verify(DisabledReasons = %01100000); // rate limited by source and target
      Verify(CurrentRate = 0.0);
      Verify(Parent = SiliconTable);
   end;
   with (specialize GetUpdatedFeature<TModelMaterialPileFeature>(ModelSystem, 1)) do
   begin
      Verify(PileMass = 1000);
      Verify(PileMassFlowRate = 0);
      Verify(Capacity = 1000);
      Verify(Parent = SiliconTable);
   end;
   with (specialize GetUpdatedFeature<TModelStructureFeature>(ModelSystem, 0)) do
   begin
      Verify(Quantity = 1);
      Verify(QuantityRate = 0);
      Verify(Hp = 1);
      Verify(HpRate > 0);
      Verify(MinHp = 1);
      Verify(Parent = SiliconTable);
   end;
   with (specialize GetUpdatedFeature<TModelBuilderFeature>(ModelSystem, 0)) do
   begin
      Verify(DisabledReasons = %00000000);
      Verify(Capacity = 1);
      Verify(Structures.Length = 0);
      Verify(Parent = SiliconTable);
   end;
   
   TimePinned := True;
   SystemsServer.SendWebSocketStringMessage('0'#00'play'#00 + IntToStr(ModelSystem.SystemID) + #00 + IntToStr(Rally.ID) + #00'disable' + #00);
   Response := TStringStreamReader.Create(SystemsServer.ReadWebSocketStringMessage());
   VerifyPositiveResponse(Response);
   FreeAndNil(Response);
   ExpectUpdate(SystemsServer, ModelSystem, MinTime, MaxTime, TimePinned, 3);
   with (specialize GetUpdatedFeature<TModelRefiningFeature>(ModelSystem, 1)) do
   begin
      Verify(DisabledReasons = %01100000); // rate limited by source
      Verify(CurrentRate = 0.0);
      Verify(Parent = SiliconTable);
   end;
   with (specialize GetUpdatedFeature<TModelMaterialPileFeature>(ModelSystem, 1)) do
   begin
      Verify(PileMass = 1000);
      Verify(PileMassFlowRate = 0);
      Verify(Capacity = 1000);
      Verify(Parent = SiliconTable);
   end;
   with (specialize GetUpdatedFeature<TModelStructureFeature>(ModelSystem, 0)) do
   begin
      Verify(Quantity = 1);
      Verify(QuantityRate = 0);
      Verify(Hp = 1);
      Verify(HpRate > 0);
      Verify(MinHp = 1);
      Verify(Parent = SiliconTable);
   end;
   with (specialize GetUpdatedFeature<TModelBuilderFeature>(ModelSystem, 0)) do
   begin
      Verify(DisabledReasons = %00000000);
      Verify(Capacity = 1);
      Verify(Structures.Length = 1);
      Verify(ModelSystem.Assets[Structures[0]] = SiliconTable);
      Verify(Parent = SiliconTable);
   end;
   with (specialize GetUpdatedFeature<TModelBuilderFeature>(ModelSystem, 1)) do
   begin
      Verify(DisabledReasons = %00000100);
      Verify(Capacity = 1);
      Verify(Structures.Length = 0);
      Verify(Parent = Rally);
   end;

   TimePinned := True;
   SystemsServer.SendWebSocketStringMessage('0'#00'play'#00 + IntToStr(ModelSystem.SystemID) + #00 + IntToStr(SiliconTable.ID) + #00'dismantle' + #00);
   Response := TStringStreamReader.Create(SystemsServer.ReadWebSocketStringMessage());
   VerifyPositiveResponse(Response);
   FreeAndNil(Response);
   ExpectUpdate(SystemsServer, ModelSystem, MinTime, MaxTime, TimePinned, 4); // 3 if we fix the bug where structure dirties itself even when knowledge didn't change
   with (specialize GetUpdatedFeature<TModelRubblePileFeature>(ModelSystem)) do
   begin
      Verify(KnownContents.Length = 1);
      Verify(KnownContents[0].MaterialID = 9); // Iron
      Verify(KnownContents[0].Quantity = 1);
   end;

   AdvanceTime(10 * Days);

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