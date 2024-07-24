{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit servers;

interface

uses csvdocument;

type
   PServerEntry = ^TServerEntry;
   TServerEntry = record
   strict private
      function GetURL(): UTF8String;
   public
      HostName: UTF8String;
      WebSocketPort: Word;
      DirectHost: DWord;
      DirectPort: Word;
      DirectPassword: UTF8String;
      UsageCount: Cardinal;
      property URL: UTF8String read GetURL;
   end;
   
   TServerDatabase = class
   protected
      FServers: array of PServerEntry;
      function GetServer(Index: Cardinal): PServerEntry;
   public
      constructor Create(Source: TCSVDocument);
      destructor Destroy(); override;
      function GetLeastLoadedServer(): Cardinal;
      procedure IncreaseLoadOnServer(Server: Cardinal);
      property Servers[Index: Cardinal]: PServerEntry read GetServer; default;
   end;

implementation

uses sysutils, sockets, configuration;

function TServerEntry.GetURL(): UTF8String;
begin
   Result := 'wss://' + HostName + ':' + IntToStr(WebSocketPort) + '/';
end;


constructor TServerDatabase.Create(Source: TCSVDocument);
var
   Index: Cardinal;
begin
   inherited Create();
   SetLength(FServers, Source.RowCount);
   Assert(Length(FServers) > 0);
   for Index := 0 to Source.RowCount - 1 do // $R-
   begin
      New(FServers[Index]);
      FServers[Index]^.HostName := Source[ServerHostNameCell, Index]; // $R-
      FServers[Index]^.WebSocketPort := StrToInt(Source[ServerWebSocketPortCell, Index]); // $R-
      FServers[Index]^.DirectHost := StrToHostAddr(Source[ServerDirectHostCell, Index]).s_addr; // $R-
      FServers[Index]^.DirectPort := StrToInt(Source[ServerDirectPortCell, Index]); // $R-
      FServers[Index]^.DirectPassword := Source[ServerDirectPasswordCell, Index]; // $R-
      FServers[Index]^.UsageCount := 0;
   end;
end;

destructor TServerDatabase.Destroy();
var
   Index: Cardinal;
begin
   for Index := 0 to Length(FServers) - 1 do // $R-
   begin
      Dispose(FServers[Index]);
   end;
   inherited;
end;

function TServerDatabase.GetServer(Index: Cardinal): PServerEntry;
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
      CandidateCount := FServers[Candidate]^.UsageCount;
      if (CandidateCount < LeastCount) then
      begin
         LeastCount := CandidateCount;
         Winner := Candidate;
      end;
   end;
   Assert(Winner <> High(Winner));
   Result := Winner;
end;

procedure TServerDatabase.IncreaseLoadOnServer(Server: Cardinal);
begin
   Assert(Server < Length(FServers));
   Inc(FServers[Server]^.UsageCount);
end;

end.