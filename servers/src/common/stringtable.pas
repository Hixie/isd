{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit stringtable;

interface

uses
   hashtable, stringutils;

type
   TStringTable = class
   strict private
      type
         TStringTableMap = specialize THashTable<UTF8String, Cardinal, UTF8StringUtils>;
      var
         FStrings: TStringTableMap;
   public
      constructor Create();
      destructor Destroy(); override;
      function Encode(const S: UTF8String): Cardinal;
      function Encode(const S: UTF8String; out NewlyAdded: Boolean): Cardinal;
   end;

implementation

uses
   hashfunctions;

constructor TStringTable.Create();
begin
   inherited;
   FStrings := TStringTableMap.Create(@UTF8StringHash32, 8);
end;

destructor TStringTable.Destroy();
begin
   FStrings.Free();
   inherited;
end;

function TStringTable.Encode(const S: UTF8String): Cardinal;
begin
   Result := FStrings[S];
   if (Result = 0) then
   begin
      Assert(FStrings.Count < High(Result));
      Result := FStrings.Count + 1; // $R-
      FStrings[S] := Result;
   end;
end;

function TStringTable.Encode(const S: UTF8String; out NewlyAdded: Boolean): Cardinal;
begin
   Result := FStrings[S];
   if (Result = 0) then
   begin
      Assert(FStrings.Count < High(Result));
      Result := FStrings.Count + 1; // $R-
      FStrings[S] := Result;
      NewlyAdded := True;
   end
   else
   begin
      NewlyAdded := False;
   end;
end;

end.
