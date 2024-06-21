{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit servers;

interface

uses csvdocument;

type
   TDynastyServer = record
      HostName: UTF8String;
      WebSocketPort: Word;
      DirectHost: DWord;
      DirectPort: Word;
      DirectPassword: UTF8String;
      UsageCount: Cardinal;
   end;
   
   TServerDatabase = class
   protected
      FServers: array of TDynastyServer;
      function GetServer(Index: Cardinal): TDynastyServer;
   public
      constructor Create(Source: TCSVDocument);
      function GetLeastLoadedServer(): Cardinal;
      procedure AddDynastyToServer(Server: Cardinal);
      property Servers[Index: Cardinal]: TDynastyServer read GetServer; default;
   end;

implementation

uses sysutils, sockets, configuration;

constructor TServerDatabase.Create(Source: TCSVDocument);
var
   Index: Cardinal;
begin
   inherited Create();
   SetLength(FServers, Source.RowCount);
   Assert(Length(FServers) > 0);
   for Index := 0 to Source.RowCount - 1 do // $R-
   begin
      FServers[Index].HostName := Source[DynastiesServerHostNameCell, Index]; // $R-
      FServers[Index].WebSocketPort := StrToInt(Source[DynastiesServerWebSocketPortCell, Index]); // $R-
      FServers[Index].DirectHost := StrToHostAddr(Source[DynastiesServerDirectHostCell, Index]).s_addr; // $R-
      FServers[Index].DirectPort := StrToInt(Source[DynastiesServerDirectPortCell, Index]); // $R-
      FServers[Index].DirectPassword := Source[DynastiesServerDirectPasswordCell, Index]; // $R-
      Assert(FServers[Index].UsageCount = 0);
   end;
end;

function TServerDatabase.GetServer(Index: Cardinal): TDynastyServer;
begin
   Assert(Index < Length(FServers));
   Result := FServers[Index];
end;

function TServerDatabase.GetLeastLoadedServer(): Cardinal;
var
   LeastCount, CandidateCount: Cardinal;
   Winner, Candidate: Cardinal;
begin
   LeastCount := High(LeastCount);
   Winner := High(Winner);
   for Candidate := 0 to Length(FServers)-1 do // $R-
   begin
      CandidateCount := FServers[Candidate].UsageCount;
      if (CandidateCount < LeastCount) then
      begin
         LeastCount := CandidateCount;
         Winner := Candidate;
      end;
   end;
   Assert(Winner <> High(Winner));
   Result := Winner;
end;

procedure TServerDatabase.AddDynastyToServer(Server: Cardinal);
begin
   Assert(Server < Length(FServers));
   Inc(FServers[Server].UsageCount);
end;

end.