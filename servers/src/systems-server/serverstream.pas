{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit serverstream;

interface

uses
   binarystream, stringtable;

type
   TServerStreamWriter = class(TBinaryStreamWriter)
   strict private
      FStringTable: TStringTable;
   public
      constructor Create();
      destructor Destroy(); override;
      procedure WriteStringReference(const Value: UTF8String);
   end;

implementation

constructor TServerStreamWriter.Create();
begin
   inherited;
   FStringTable := TStringTable.Create();
end;

destructor TServerStreamWriter.Destroy();
begin
   FStringTable.Free();
   inherited;
end;

procedure TServerStreamWriter.WriteStringReference(const Value: UTF8String);
var
   NewlyAdded: Boolean;
begin
   WriteCardinal(FStringTable.Encode(Value, NewlyAdded));
   if (NewlyAdded) then
      WriteStringByPointer(Value); // safe because by definition the pointer is now in the string table
end;

end.