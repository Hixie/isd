{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit pointertable;

interface

uses
   hashtable, genericutils;

type
   TPointerTable = class
   strict private
      type
         TPointerTableMap = specialize THashTable<Pointer, Cardinal, PointerUtils>;
      var
         FPointers: TPointerTableMap;
   public
      constructor Create();
      destructor Destroy(); override;
      function Encode(const S: Pointer): Cardinal;
      function Encode(const S: Pointer; out NewlyAdded: Boolean): Cardinal;
   end;
   
implementation

uses
   hashfunctions;

constructor TPointerTable.Create();
begin
   inherited;
   FPointers := TPointerTableMap.Create(@PointerHash32, 8);
end;

destructor TPointerTable.Destroy();
begin
   FPointers.Free();
   inherited;
end;

function TPointerTable.Encode(const S: Pointer): Cardinal;
begin
   Result := FPointers[S];
   if (Result = 0) then
   begin
      Assert(FPointers.Count < High(Result));
      Result := FPointers.Count + 1; // $R-
      FPointers[S] := Result;
   end;
end;

function TPointerTable.Encode(const S: Pointer; out NewlyAdded: Boolean): Cardinal;
begin
   Result := FPointers[S];
   if (Result = 0) then
   begin
      Assert(FPointers.Count < High(Result));
      Result := FPointers.Count + 1; // $R-
      FPointers[S] := Result;
      NewlyAdded := True;
   end
   else
   begin
      NewlyAdded := False;
   end;
end;

end.
