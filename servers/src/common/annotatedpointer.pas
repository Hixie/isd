{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit annotatedpointer;

interface

type
   generic TAnnotatedPointer<PType, TFlags> = record
   {$IF SIZEOF(PtrUInt) <> 8} {$FATAL} {$ENDIF} // we assume 64 bits with 8 byte alignment (3 bits of slack).
   strict private
      FValue: PtrUInt;
      function GetAssigned(): Boolean; inline;
   public
      class operator := (Value: PType): specialize TAnnotatedPointer<PType, TFlags>; inline;
      procedure Clear(); inline;
      function Unwrap(): PType; inline;
      procedure SetFlag(Flag: TFlags); inline;
      procedure ClearFlag(Flag: TFlags); inline;
      function IsFlagSet(Flag: TFlags): Boolean; inline;
      function IsFlagClear(Flag: TFlags): Boolean; inline;
      property Assigned: Boolean read GetAssigned;
   end;

implementation

class operator TAnnotatedPointer.:= (Value: PType): specialize TAnnotatedPointer<PType, TFlags>;
begin
   Assert(SizeOf(Value) = SizeOf(PtrUInt));
   Assert(PtrUInt(High(TFlags)) <= 3);
   Assert((PtrUInt(Value) and $07) = 0);
   Result.FValue := PtrUInt(Value);
end;

procedure TAnnotatedPointer.Clear();
begin
   FValue := $00;
end;

function TAnnotatedPointer.Unwrap(): PType;
begin
   Result := PType(FValue and not $07);
   Assert(system.Assigned(Result));
end;

function TAnnotatedPointer.GetAssigned(): Boolean;
begin
   Result := system.Assigned(PType(FValue and not $07));
end;

procedure TAnnotatedPointer.SetFlag(Flag: TFlags);
begin
   Assert(PtrUInt(Flag) <= 3);
   FValue := FValue or PtrUInt(1 shl Ord(Flag));
end;

procedure TAnnotatedPointer.ClearFlag(Flag: TFlags);
begin
   Assert(PtrUInt(Flag) <= 3);
   FValue := FValue and not PtrUInt(1 shl Ord(Flag));
end;

function TAnnotatedPointer.IsFlagSet(Flag: TFlags): Boolean;
begin
   Assert(PtrUInt(Flag) <= 3);
   Result := (FValue and PtrUInt(1 shl Ord(Flag))) > 0;
end;

function TAnnotatedPointer.IsFlagClear(Flag: TFlags): Boolean;
begin
   Assert(PtrUInt(Flag) <= 3);
   Result := (FValue and PtrUInt(1 shl Ord(Flag))) = 0;
end;

{$IFDEF TESTS}
type
   TFoo = class end;

procedure Test();
type
   TFlags = (tfA, tfB, tfC);
   PFoo = specialize TAnnotatedPointer<TFoo, TFlags>;
var
   P: PFoo;
begin
   P := TFoo.Create();
   Assert(P.Assigned);
   Assert(P.IsFlagClear(tfA));
   Assert(P.IsFlagClear(tfB));
   Assert(P.IsFlagClear(tfC));
   P.SetFlag(tfB);
   Assert(P.IsFlagClear(tfA));
   Assert(P.IsFlagSet(tfB));
   Assert(P.IsFlagClear(tfC));
   P.ClearFlag(tfB);
   Assert(P.IsFlagClear(tfA));
   Assert(P.IsFlagClear(tfB));
   Assert(P.IsFlagClear(tfC));
   P.SetFlag(tfA);
   Assert(P.IsFlagSet(tfA));
   Assert(P.IsFlagClear(tfB));
   Assert(P.IsFlagClear(tfC));
   P.ClearFlag(tfA);
   Assert(P.IsFlagClear(tfA));
   Assert(P.IsFlagClear(tfB));
   Assert(P.IsFlagClear(tfC));
   P.SetFlag(tfC);
   Assert(P.IsFlagClear(tfA));
   Assert(P.IsFlagClear(tfB));
   Assert(P.IsFlagSet(tfC));
   P.SetFlag(tfA);
   Assert(P.IsFlagSet(tfA));
   Assert(P.IsFlagClear(tfB));
   Assert(P.IsFlagSet(tfC));
   P.SetFlag(tfB);
   Assert(P.IsFlagSet(tfA));
   Assert(P.IsFlagSet(tfB));
   Assert(P.IsFlagSet(tfC));
   P.ClearFlag(tfB);
   Assert(P.IsFlagSet(tfA));
   Assert(P.IsFlagClear(tfB));
   Assert(P.IsFlagSet(tfC));
   P.Unwrap().Free();
   P.Clear();
   Assert(not P.Assigned);
end;
{$ENDIF}

initialization
   {$IFDEF TESTS} Test(); {$ENDIF}
end.
