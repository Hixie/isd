{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit serverstream;

interface

uses
   binarystream, stringtable, pointertable;

type
   TServerStreamWriter = class(TBinaryStreamWriter)
   strict private
      FStringTable: TStringTable;
      FPointerTable: TPointerTable;
   public
      constructor Create();
      destructor Destroy(); override;
      procedure WriteStringReference(const Value: UTF8String);
      function WritePointerReference(const Value: Pointer): Boolean; // returns true if newly added
   end;

implementation

constructor TServerStreamWriter.Create();
begin
   inherited;
   FStringTable := TStringTable.Create();
   FPointerTable := TPointerTable.Create();
end;

destructor TServerStreamWriter.Destroy();
begin
   FPointerTable.Free();
   FStringTable.Free();
   inherited;
end;

procedure TServerStreamWriter.WriteStringReference(const Value: UTF8String);
var
   NewlyAdded: Boolean;
begin
   WriteCardinal(FStringTable.Encode(Value, NewlyAdded));
   if (NewlyAdded) then
      WriteString(Value);
end;

function TServerStreamWriter.WritePointerReference(const Value: Pointer): Boolean;
begin
   WriteCardinal(FPointerTable.Encode(Value, Result));
end;

end.