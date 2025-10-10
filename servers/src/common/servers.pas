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
      DirectHost: DWord; // Host endianness; network code will convert to network endianness when necessary.
      DirectPort: Word;
      DirectPassword: UTF8String;
      UsageCount: Cardinal;
      property URL: UTF8String read GetURL;
   end;

   TServerDatabase = class
   protected
      FServers: array of PServerEntry;
      function GetServer(Index: Cardinal): PServerEntry;
      function GetCount(): Cardinal; inline;
   public
      constructor Create(Source: TCSVDocument);
      destructor Destroy(); override;
      function GetLeastLoadedServer(): Cardinal;
      procedure IncreaseLoadOnServer(Server: Cardinal);
      property Servers[Index: Cardinal]: PServerEntry read GetServer; default;
      property Count: Cardinal read GetCount;
   end;

implementation

uses
   sysutils, sockets, configuration, intutils;

function TServerEntry.GetURL(): UTF8String;
begin
   Result := 'wss://' + HostName + ':' + IntToStr(WebSocketPort) + '/';
end;


constructor TServerDatabase.Create(Source: TCSVDocument);
var
   Index: Cardinal;
begin
   inherited Create();
   if (Source.RowCount = 0) then
      raise Exception.Create('No servers specified in configuration file.');
   SetLength(FServers, Source.RowCount);
   Assert(Length(FServers) > 0);
   for Index := 0 to Source.RowCount - 1 do // $R-
   begin
      if (Source.ColCount[Index] < 5) then // $R-
         raise Exception.CreateFmt('Server on row %d of server configuration file is incomplete.', [Index + 1]);
      New(FServers[Index]);
      FServers[Index]^.HostName := Source[ServerHostNameCell, Index]; // $R-
      FServers[Index]^.WebSocketPort := ParseInt32(Source[ServerWebSocketPortCell, Index]); // $R-
      FServers[Index]^.DirectHost := StrToHostAddr(Source[ServerDirectHostCell, Index]).s_addr; // $R-
      FServers[Index]^.DirectPort := ParseInt32(Source[ServerDirectPortCell, Index]); // $R-
      FServers[Index]^.DirectPassword := Source[ServerDirectPasswordCell, Index]; // $R-
      FServers[Index]^.UsageCount := 0;
   end;
end;

destructor TServerDatabase.Destroy();
var
   Index: Cardinal;
begin
   if (Length(FServers) > 0) then
      for Index := 0 to Length(FServers) - 1 do // $R-
         Dispose(FServers[Index]);
   inherited;
end;

function TServerDatabase.GetServer(Index: Cardinal): PServerEntry;
begin
   Assert(Index < Length(FServers));
   Result := FServers[Index];
end;

function TServerDatabase.GetCount(): Cardinal;
begin
   Result := Length(FServers); // $R-
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