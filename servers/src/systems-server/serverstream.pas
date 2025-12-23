{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit serverstream;

interface

uses
   binarystream, stringtable, isdprotocol, hashsettight;

type
   TAssetClassIDTightHashSetUtils = record
      class function Equals(const A, B: TAssetClassID): Boolean; static; inline;
      class function Hash(const A: TAssetClassID): DWord; static; inline;
      class function IsNotEmpty(const A: TAssetClassID): Boolean; static; inline;
      class function IsOccupied(const A: TAssetClassID): Boolean; static; inline;
      class function IsDeleted(const A: TAssetClassID): Boolean; static; inline;
      class procedure Clear(var Buffer; Count: Cardinal); static; inline;
      class procedure Delete(var Buffer; Count: Cardinal); static; inline;
   end;

type
   TAssetClassIDSet = specialize TTightHashSet<TAssetClassID, TAssetClassIDTightHashSetUtils>;

type
   TServerStreamWriter = class(TBinaryStreamWriter)
   strict private
      var
         FStringTable: TStringTable;
         FAssetClassIDs: TAssetClassIDSet;
   public
      constructor Create();
      destructor Destroy(); override;
      procedure WriteStringReference(const Value: UTF8String);
      function WriteAssetClassID(const ID: TAssetClassID): Boolean; // returns true if newly added
   end;

implementation

uses
   sysutils, hashfunctions;

class function TAssetClassIDTightHashSetUtils.Equals(const A, B: TAssetClassID): Boolean;
begin
   Result := A = B;
end;

class function TAssetClassIDTightHashSetUtils.Hash(const A: TAssetClassID): DWord;
var
   CastID: DWord absolute A;
begin
   Result := Integer32Hash32(CastID);
end;

class function TAssetClassIDTightHashSetUtils.IsNotEmpty(const A: TAssetClassID): Boolean;
begin
   Result := A <> 0;
end;

class function TAssetClassIDTightHashSetUtils.IsOccupied(const A: TAssetClassID): Boolean;
begin
   Result := A <> 0;
end;

class function TAssetClassIDTightHashSetUtils.IsDeleted(const A: TAssetClassID): Boolean;
begin
   Result := False;
end;

class procedure TAssetClassIDTightHashSetUtils.Clear(var Buffer; Count: Cardinal);
begin
   FillDWord(Buffer, Count, 0);
end;

class procedure TAssetClassIDTightHashSetUtils.Delete(var Buffer; Count: Cardinal);
begin
   raise Exception.Create('cannot delete');
end;


constructor TServerStreamWriter.Create();
begin
   inherited;
   FStringTable := TStringTable.Create();
   FAssetClassIDs := TAssetClassIDSet.Create();
end;

destructor TServerStreamWriter.Destroy();
begin
   FreeAndNil(FAssetClassIDs);
   FreeAndNil(FStringTable);
   inherited;
end;

procedure TServerStreamWriter.WriteStringReference(const Value: UTF8String);
var
   NewlyAdded: Boolean;
begin
   if (Value = '') then
   begin
      WriteCardinal(0);
   end
   else
   begin
      WriteCardinal(FStringTable.Encode(Value, NewlyAdded));
      if (NewlyAdded) then
         WriteStringByPointer(Value); // safe because by definition the pointer is now in the string table
   end;
end;

function TServerStreamWriter.WriteAssetClassID(const ID: TAssetClassID): Boolean;
begin
   WriteInt32(ID);
   Result := not FAssetClassIDs.Has(ID);
   if (Result) then
      FAssetClassIDs.Add(ID);
end;

end.