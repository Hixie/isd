{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit isdnumbers;

interface

uses
   sysutils, random;

type
   PInt256 = ^Int256;
   Int256 = record
   public
      type
         TQuadIndex = 1..4;
   private
      procedure AssignQuad1(Value: QWord); inline;
      function GetQuad(Index: TQuadIndex): QWord; inline;
      procedure SetQuad(Index: TQuadIndex; Value: QWord); inline;
      procedure BitFlip(); inline;
      procedure Increment(); inline;
      procedure Decrement(); inline;
      function GetIsZero(): Boolean; inline;
      function GetIsNotZero(): Boolean; inline;
      function GetIsNegative(): Boolean; inline;
      function GetIsPositive(): Boolean; inline;
      class function GetZero(): Int256; inline; static;
   public
      constructor FromDouble(Value: Double; FixedPointBias: Cardinal = 0); // multiplies by 2^FixedPointBias, then drops remaining fractional component (rounding away from zero)
      constructor FromInt64(Value: Int64);
      constructor FromInt256(const Value: Int256);
      procedure ResetToZero(); inline;
      procedure ShiftLeft(Operand: Byte);
      procedure Add(Value: Int256); inline;
      procedure Subtract(Value: Int256); inline;
      procedure Negate(); inline;
      function ToString(): UTF8String; // as hex, for debugging
      function ToDouble(FixedPointBias: Cardinal = 0): Double;
      property IsZero: Boolean read GetIsZero;
      property IsNotZero: Boolean read GetIsNotZero;
      property IsNegative: Boolean read GetIsNegative; // < 0
      property IsPositive: Boolean read GetIsPositive; // >= 0 (includes zero!)
      property AsQWords[Index: TQuadIndex]: QWord read GetQuad write SetQuad; // for storage only; note the indicies are backwards from normal
      class property Zero: Int256 read GetZero;
      class operator < (A, B: Int256): Boolean;
      class operator <= (A, B: Int256): Boolean;
      class operator >= (A, B: Int256): Boolean;
      class operator > (A, B: Int256): Boolean;
   private
      // 256 bit two's complement integer
      case Integer of
         0: (FBits: bitpacked array[0..255] of Boolean);
         1: (FQuad4, FQuad3, FQuad2, FQuad1: QWord);
         2: (FQuads: array[TQuadIndex] of QWord); // beware, indicies are backwards from FQuad1..FQuad4
   end;
   {$IF SIZEOF(Int256) <> 256} {FATAL} {$ENDIF}

   PFraction32 = ^Fraction32;

   // unsigned 31(ish) bit integer numerator of a fraction whose denominator is 2^31
   Fraction32 = record
   private
      const
         FDenominator: Cardinal = $80000000;
      var
         FNumerator: Cardinal;
      function GetIsZero(): Boolean; inline;
      function GetIsNotZero(): Boolean; inline;
      class function GetZero(): Fraction32; inline; static;
   public
      constructor FromDouble(Value: Double);
      constructor FromCardinal(Value: Cardinal);
      procedure ResetToZero(); inline;
      procedure Add(Value: Double);
      procedure Subtract(Value: Double);
      function Increment(Delta: Double): Double; // 0 <= Value < 1, 0 <= Delta < 1.0
      function ToDouble(): Double;
      function ToString(): UTF8String;
      class operator + (A: Fraction32; B: Fraction32): Fraction32; inline;
      class operator * (Multiplicand: Fraction32; Multiplier: Double): Double; inline;
      class operator * (Multiplicand: Fraction32; Multiplier: Int64): Double; inline;
      class operator / (Dividend: Fraction32; Divisor: Double): Double; inline;
      class operator / (Dividend: Fraction32; Divisor: Fraction32): Fraction32; inline;
      property IsZero: Boolean read GetIsZero;
      property IsNotZero: Boolean read GetIsNotZero;
      property AsCardinal: Cardinal read FNumerator write FNumerator; // for storage or aggregate math
      class procedure NormalizeArray(Target: PFraction32; Count: SizeInt); static; // Target must have at least one value greater than 0
      class procedure InitArray(Target: PFraction32; Count: SizeInt; Value: Cardinal = 0); static;
      class function ChooseFrom(Target: PFraction32; Count: SizeInt; RandomSource: TRandomNumberGenerator): SizeInt; static;
      class property Zero: Fraction32 read GetZero;
   end;

   ENumberError = class(Exception)
   end;

   TSum = record // fixed point with format Q127.128
   private
      const
         Scale = 128;
   private
      Value: Int256;
      function GetIsZero(): Boolean; inline;
      function GetIsNotZero(): Boolean; inline;
      function GetIsNegative(): Boolean; inline;
      function GetIsPositive(): Boolean; inline;
   public
      procedure Reset(); inline;
      class operator Copy (constref Source: TSum; var Destination: TSum); inline;
      procedure Inc(Addend: Double); inline;
      procedure Dec(Subtrahend: Double); inline;
      procedure Inc(Addend: TSum); inline;
      procedure Dec(Subtrahend: TSum); inline;
      procedure Negate(); inline;
      property IsZero: Boolean read GetIsZero;
      property IsNotZero: Boolean read GetIsNotZero;
      property IsNegative: Boolean read GetIsNegative; // < 0
      property IsPositive: Boolean read GetIsPositive; // > 0 (excludes zero!)
      function ToString(): UTF8String; // as hex, for debugging
      function ToDouble(): Double; inline;
      class operator < (A, B: TSum): Boolean;
      class operator <= (A, B: TSum): Boolean;
      class operator >= (A, B: TSum): Boolean;
      class operator > (A, B: TSum): Boolean;
   end;
   

function RoundUInt64(Value: Double): UInt64;
function TruncUInt64(Value: Double): UInt64;
function CeilUInt64(Value: Double): UInt64;

implementation

uses
   exceptions, stringutils {$IFDEF TESTS}, math{$ENDIF};

// IEEE binary64 format
const
   kQuadWidth     = 64;
   kFractionWidth = 52;
   kSign          = $8000000000000000;
   kExponent      = $7FF0000000000000;
   kFraction      = $000FFFFFFFFFFFFF;
   kHiddenBit     = $0010000000000000;

// Int256 inline functions.
// (Inline functions must be first or they won't get inlined.)

procedure Int256.AssignQuad1(Value: QWord);
begin
   FQuad4 := 0;
   FQuad3 := 0;
   FQuad2 := 0;
   FQuad1 := Value;
end;

function Int256.GetQuad(Index: TQuadIndex): QWord;
begin
   Result := FQuads[Index];
end;

procedure Int256.SetQuad(Index: TQuadIndex; Value: QWord);
begin
   FQuads[Index] := Value;
end;

procedure Int256.BitFlip();
begin
   FQuad1 := not FQuad1;
   FQuad2 := not FQuad2;
   FQuad3 := not FQuad3;
   FQuad4 := not FQuad4;
end;

procedure Int256.Increment(); assembler;
asm
   add Self.FQuad1, 1;
   adc Self.FQuad2, 0;
   adc Self.FQuad3, 0;
   adc Self.FQuad4, 0;
end;

procedure Int256.Decrement(); assembler;
asm
   sub Self.FQuad1, 1;
   sbb Self.FQuad2, 0;
   sbb Self.FQuad3, 0;
   sbb Self.FQuad4, 0;
end;

function Int256.GetIsZero(): Boolean;
begin
   Result := (FQuad1 = 0) and (FQuad2 = 0) and (FQuad3 = 0) and (FQuad4 = 0);
end;

function Int256.GetIsNotZero(): Boolean;
begin
   Result := (FQuad1 <> 0) or (FQuad2 <> 0) or (FQuad3 <> 0) or (FQuad4 <> 0);
end;

function Int256.GetIsNegative(): Boolean;
begin
   Result := Int64(FQuad4) < 0;
end;

function Int256.GetIsPositive(): Boolean;
begin
   Result := Int64(FQuad4) >= 0;
end;

class function Int256.GetZero(): Int256;
begin
   Result.FQuad1 := 0;
   Result.FQuad2 := 0;
   Result.FQuad3 := 0;
   Result.FQuad4 := 0;
end;

class operator Int256.< (A, B: Int256): Boolean;
begin
   if (A.FQuad4 = B.FQuad4) then
   begin
      if (A.FQuad3 = B.FQuad3) then
      begin
         if (A.FQuad2 = B.FQuad2) then
         begin
            if (Int64(A.FQuad1) < Int64(B.FQuad1)) then
            begin
               Result := True;
            end
            else
            begin
               Result := False;
            end;
         end
         else
         if (Int64(A.FQuad2) < Int64(B.FQuad2)) then
         begin
            Result := True;
         end
         else
         begin
            Result := False;
         end;
      end
      else
      if (Int64(A.FQuad3) < Int64(B.FQuad3)) then
      begin
         Result := True;
      end
      else
      begin
         Result := False;
      end;
   end
   else
   if (Int64(A.FQuad4) < Int64(B.FQuad4)) then
   begin
      Result := True;
   end
   else
   begin
      Result := False;
   end;
end;

class operator Int256.<= (A, B: Int256): Boolean;
begin
   if (A.FQuad4 = B.FQuad4) then
   begin
      if (A.FQuad3 = B.FQuad3) then
      begin
         if (A.FQuad2 = B.FQuad2) then
         begin
            if (Int64(A.FQuad1) <= Int64(B.FQuad1)) then
            begin
               Result := True;
            end
            else
            begin
               Result := False;
            end;
         end
         else
         if (Int64(A.FQuad2) <= Int64(B.FQuad2)) then
         begin
            Result := True;
         end
         else
         begin
            Result := False;
         end;
      end
      else
      if (Int64(A.FQuad3) <= Int64(B.FQuad3)) then
      begin
         Result := True;
      end
      else
      begin
         Result := False;
      end;
   end
   else
   if (Int64(A.FQuad4) <= Int64(B.FQuad4)) then
   begin
      Result := True;
   end
   else
   begin
      Result := False;
   end;
end;

class operator Int256.>= (A, B: Int256): Boolean;
begin
   if (A.FQuad4 = B.FQuad4) then
   begin
      if (A.FQuad3 = B.FQuad3) then
      begin
         if (A.FQuad2 = B.FQuad2) then
         begin
            if (Int64(A.FQuad1) >= Int64(B.FQuad1)) then
            begin
               Result := True;
            end
            else
            begin
               Result := False;
            end;
         end
         else
         if (Int64(A.FQuad2) >= Int64(B.FQuad2)) then
         begin
            Result := True;
         end
         else
         begin
            Result := False;
         end;
      end
      else
      if (Int64(A.FQuad3) >= Int64(B.FQuad3)) then
      begin
         Result := True;
      end
      else
      begin
         Result := False;
      end;
   end
   else
   if (Int64(A.FQuad4) >= Int64(B.FQuad4)) then
   begin
      Result := True;
   end
   else
   begin
      Result := False;
   end;
end;

class operator Int256.> (A, B: Int256): Boolean;
begin
   if (A.FQuad4 = B.FQuad4) then
   begin
      if (A.FQuad3 = B.FQuad3) then
      begin
         if (A.FQuad2 = B.FQuad2) then
         begin
            if (Int64(A.FQuad1) > Int64(B.FQuad1)) then
            begin
               Result := True;
            end
            else
            begin
               Result := False;
            end;
         end
         else
         if (Int64(A.FQuad2) > Int64(B.FQuad2)) then
         begin
            Result := True;
         end
         else
         begin
            Result := False;
         end;
      end
      else
      if (Int64(A.FQuad3) > Int64(B.FQuad3)) then
      begin
         Result := True;
      end
      else
      begin
         Result := False;
      end;
   end
   else
   if (Int64(A.FQuad4) > Int64(B.FQuad4)) then
   begin
      Result := True;
   end
   else
   begin
      Result := False;
   end;
end;

procedure Int256.ResetToZero();
begin
   FQuad4 := 0;
   FQuad3 := 0;
   FQuad2 := 0;
   FQuad1 := 0;
end;

procedure Int256.Add(Value: Int256); assembler;
asm
   mov r11, Value.FQuad1
   add Self.FQuad1, r11
   mov r11, Value.FQuad2
   adc Self.FQuad2, r11
   mov r11, Value.FQuad3
   adc Self.FQuad3, r11
   mov r11, Value.FQuad4
   adc Self.FQuad4, r11
end;

procedure Int256.Subtract(Value: Int256); assembler;
asm
   mov r11, Value.FQuad1
   sub Self.FQuad1, r11
   mov r11, Value.FQuad2
   sbb Self.FQuad2, r11
   mov r11, Value.FQuad3
   sbb Self.FQuad3, r11
   mov r11, Value.FQuad4
   sbb Self.FQuad4, r11
end;

procedure Int256.Negate();
begin
   BitFlip();
   Increment();
end;


// Remainder of API.

constructor Int256.FromDouble(Value: Double; FixedPointBias: Cardinal = 0);
var
   Sign: Boolean;
   Exponent: Integer;
   Fraction: QWord;
   Bits: QWord absolute Value;
begin
   Assert(SizeOf(QWord) = SizeOf(Double));
   Sign := (Bits and kSign) > 0;
   Exponent := ((Bits and kExponent) >> kFractionWidth); // $R-
   Fraction := Bits and kFraction; // $R-
   case Exponent of
      0: begin
         // zero or subnormal number
         if (Fraction = 0) then
         begin
            FillQWord(FBits, SizeOf(FBits) div SizeOf(QWord), 0); {BOGUS Hint: Function result variable does not seem to be initialized}
            exit;
         end;
         Exponent := 1; // subnormal number
         // If FixedPointBias = 0, we could just treat it as zero and short-circuit all this, it's guaranteed that a subnormal number can't be above 1.0.
         // But in case FixedPointBias > 0, and since this is a rare case where performance isn't as important, we do it the long way.
      end;
      $7FF: begin
         // infinity or NaN
         // not supported
         raise ENumberError.Create('Cannot represent infinity or NaN in Int256.');
      end;
   else
      // normal number, add in the "hidden bit"
      Fraction := Fraction + kHiddenBit; // $R-
   end;
   Dec(Exponent, 1023 - FixedPointBias); // IEEE754 exponent bias, further biased by our own fixed point FixedPointBias
   Dec(Exponent, kFractionWidth); // convert exponent into bit shift to get an integer
   if (Exponent < 0) then
   begin
      // we are throwing away fractional bits
      // we must round up (increment by 1) if the most significant bit we are discarding is set
      if (($01 and (Fraction >> (-Exponent - 1)) > 0)) then
      begin
         Fraction := Fraction >> -Exponent;
         Inc(Fraction);
      end
      else
      begin
         Fraction := Fraction >> -Exponent;
      end;
      AssignQuad1(Fraction);
   end
   else
   begin
      // we are adding trailing zeros
      // the most we can do is add 255-kFractionWidth zeros
      // otherwise we'd overflow our Int256
      // (top bit is essentially the sign bit)
      if (Exponent >= (High(FBits) - kFractionWidth)) then
      begin
         raise ENumberError.CreateFmt('Integer overflow when converting Double (%f) to Int256.', [Value]);
      end;
      AssignQuad1(Fraction);
      Assert(Exponent >= Low(Byte));
      Assert(Exponent <= High(Byte));
      if (Exponent > 0) then
         ShiftLeft(Exponent); // $R-
   end;
   if (Sign) then
      Negate();
end;

constructor Int256.FromInt64(Value: Int64);
var
   ValueAsQWord: QWord absolute Value;
begin
   if (Value >= 0) then
   begin
      AssignQuad1(Value); // $R- // this also resets the other quads
   end
   else
   begin
      FQuad4 := QWord($FFFFFFFFFFFFFFFF);
      FQuad3 := QWord($FFFFFFFFFFFFFFFF);
      FQuad2 := QWord($FFFFFFFFFFFFFFFF);
      FQuad1 := ValueAsQWord;
   end;
end;

constructor Int256.FromInt256(const Value: Int256);
begin
   FQuad1 := Value.FQuad1;
   FQuad2 := Value.FQuad2;
   FQuad3 := Value.FQuad3;
   FQuad4 := Value.FQuad4;
end;

procedure Int256.ShiftLeft(Operand: Byte);
var
   ShiftedQuads, ShiftedBits, UnshiftedBits: Integer;

begin
   Assert(Operand > 0);
   ShiftedQuads := Operand div kQuadWidth; // $R-
   ShiftedBits := Operand mod kQuadWidth; // $R-
   UnshiftedBits := kQuadWidth - ShiftedBits; // $R-
   Assert(ShiftedQuads >= 0);
   Assert(ShiftedQuads < 4);
   if (ShiftedBits > 0) then
   begin
      case ShiftedQuads of
         0: begin
               FQuad4 := (FQuad4 << ShiftedBits) or (FQuad3 >> UnshiftedBits);
               FQuad3 := (FQuad3 << ShiftedBits) or (FQuad2 >> UnshiftedBits);
               FQuad2 := (FQuad2 << ShiftedBits) or (FQuad1 >> UnshiftedBits);
               FQuad1 := (FQuad1 << ShiftedBits);
            end;
         1: begin
               FQuad4 := (FQuad3 << ShiftedBits) or (FQuad2 >> UnshiftedBits);
               FQuad3 := (FQuad2 << ShiftedBits) or (FQuad1 >> UnshiftedBits);
               FQuad2 := (FQuad1 << ShiftedBits);
               FQuad1 := 0;
            end;
         2: begin
               FQuad4 := (FQuad2 << ShiftedBits) or (FQuad1 >> UnshiftedBits);
               FQuad3 := (FQuad1 << ShiftedBits);
               FQuad2 := 0;
               FQuad1 := 0;
            end;
         3: begin
               FQuad4 := (FQuad1 << ShiftedBits);
               FQuad3 := 0;
               FQuad2 := 0;
               FQuad1 := 0;
            end;
         else
            Assert(False);
      end;
   end
   else
   begin
      Assert(UnshiftedBits = 64);
      case ShiftedQuads of
         0: begin
               Assert(Operand = 0); // unreachable
            end;
         1: begin
               FQuad4 := FQuad3;
               FQuad3 := FQuad2;
               FQuad2 := FQuad1;
               FQuad1 := 0;
            end;
         2: begin
               FQuad4 := FQuad2;
               FQuad3 := FQuad1;
               FQuad2 := 0;
               FQuad1 := 0;
            end;
         3: begin
               FQuad4 := FQuad1;
               FQuad3 := 0;
               FQuad2 := 0;
               FQuad1 := 0;
            end;
         else
            Assert(False);
      end;
   end;
end;

function Int256.ToString(): UTF8String;
begin
   Result := HexStr(FQuad4, 16) + HexStr(FQuad3, 16) + HexStr(FQuad2, 16) + HexStr(FQuad1, 16);
end;

function Int256.ToDouble(FixedPointBias: Cardinal = 0): Double;
var
   FirstQuad: QWord absolute Result;
   SecondQuad, Bias: QWord;
   StartFraction: Integer;
   Positive: Int256;
begin
   Result := 0.0;
   if (FQuad4 = 0) then
   begin
      if (FQuad3 = 0) then
      begin
         if (FQuad2 = 0) then
         begin
            if (FQuad1 = 0) then
            begin
               exit;
            end
            else
            begin
               FirstQuad := FQuad1;
               SecondQuad := 0;
               Bias := kQuadWidth * 0;
            end;
         end
         else
         begin
            FirstQuad := FQuad2;
            SecondQuad := FQuad1;
            Bias := kQuadWidth * 1;
         end;
      end
      else
      begin
         FirstQuad := FQuad3;
         SecondQuad := FQuad2;
         Bias := kQuadWidth * 2;
      end;
   end
   else
   begin
      if ((FQuad4 and $8000000000000000) > 0) then
      begin
         // this is a negative number.
         // plan: convert it to a positive number, convert that to double, then negate the double
         Positive := Self;
         Positive.Negate();
         if ((Positive.FQuad4 and $8000000000000000) > 0) then
         begin
            // The number was $8000000000000000 $0 $0 $0, which just
            // negated back to itself, so we force the lowest bits to
            // be $00000001, which guarantees that it will in fact
            // negate. (Setting the last quad doesn't matter, those
            // bits are dropped in the conversion to double anyway.)
            // TODO: just hard-code what the right answer is here since we know all the bits precisely
            Positive.FQuad1 := 1;
            Positive.Negate();
         end;
         Result := -Positive.ToDouble(FixedPointBias);
         exit;
      end;
      FirstQuad := FQuad4;
      SecondQuad := FQuad3;
      Bias := kQuadWidth * 3;
   end;
   StartFraction := BsrQWord(FirstQuad); // $R- // index of leftmost set bit
   Assert(StartFraction >= 0);
   Assert(StartFraction < kQuadWidth);
   Inc(Bias, StartFraction);
   Inc(Bias, 1023 - FixedPointBias); // IEEE754 bias plus our own fixed point FixedPointBias
   // Move the first 64 bits of the number into FirstQuad (and drop the hidden bit).
   FirstQuad := FirstQuad << (kQuadWidth - StartFraction);
   FirstQuad := FirstQuad or (SecondQuad >> StartFraction);
   // Shift the bits so that the first 52 bits are at the end of FirstQuad.
   // First shift all but one bit.
   FirstQuad := FirstQuad >> (kQuadWidth - kFractionWidth - 1);
   // Then check the lsb, if it's set, we need to round up (increment by one).
   if (FirstQuad mod 2 = 1) then
   begin
      Inc(FirstQuad);
      StartFraction := BsfQWord(FirstQuad); // $R- // index of rightmost set bit
      if (StartFraction > kQuadWidth - kFractionWidth) then
      begin
         FirstQuad := 0; // all the bits got increased, and we overflowed into the exponent area; we want to clear that bit before we add the exponent
         Inc(Bias);
         if (Bias >= 2047) then
            raise ENumberError.CreateFmt('Integer overflow when converting Int256 (%s) to Double.', [ToString()]);
      end;
   end;
   // Finally, shift off that last bit, so we are ready to add the exponent.
   FirstQuad := FirstQuad >> 1;
   // Replace the first 12 bits with the exponent (Bias).
   FirstQuad := FirstQuad or (Bias << kFractionWidth);
   // Result and FirstQuad are aliased.
end;


// Inline functions for Fraction32.

function Fraction32.GetIsZero(): Boolean;
begin
   Result := FNumerator = 0;
end;

function Fraction32.GetIsNotZero(): Boolean;
begin
   Result := FNumerator > 0;
end;

class function Fraction32.GetZero(): Fraction32;
begin
   Result.FNumerator := 0;
end;

procedure Fraction32.ResetToZero();
begin
   FNumerator := 0;
end;

class function Fraction32GetZero(): Fraction32;
begin
   Result.FNumerator := 0;
end;

class operator Fraction32.+ (A: Fraction32; B: Fraction32): Fraction32;
begin
   Assert(A.FDenominator = B.FDenominator);
   Assert(High(Result.FNumerator) - A.FNumerator >= B.FNumerator);
   Result.FNumerator := A.FNumerator + B.FNumerator; // $R-
end;

class operator Fraction32.* (Multiplicand: Fraction32; Multiplier: Double): Double;
begin
   Result := (Multiplicand.FNumerator / Multiplicand.FDenominator) * Multiplier;
end;

class operator Fraction32.* (Multiplicand: Fraction32; Multiplier: Int64): Double;
begin
   Result := (Multiplicand.FNumerator / Multiplicand.FDenominator) * Multiplier;
end;

class operator Fraction32./ (Dividend: Fraction32; Divisor: Double): Double;
begin
   Result := (Dividend.FNumerator / Dividend.FDenominator) / Divisor;
end;

class operator Fraction32./ (Dividend: Fraction32; Divisor: Fraction32): Fraction32;
begin
   Assert(Dividend.FDenominator = FDenominator);
   Assert(Divisor.FDenominator = FDenominator);
   Assert(Dividend.FNumerator <= Divisor.FNumerator);
   Result.FNumerator := Round(FDenominator * Dividend.FNumerator / Divisor.FNumerator); // $R-
end;


// Remainder of API.

constructor Fraction32.FromDouble(Value: Double);
begin
   Assert(Value >= 0);
   Assert(Value <= 1.0);
   FNumerator := Round(Value * FDenominator); // $R-
end;

constructor Fraction32.FromCardinal(Value: Cardinal);
begin
   FNumerator := Value;
end;

procedure Fraction32.Add(Value: Double);
begin
   Assert(ToDouble() + Value <= 1.0);
   Assert(ToDouble() + Value >= 0.0);
   FNumerator := FNumerator + Round(Value * FDenominator); // $R-
end;

procedure Fraction32.Subtract(Value: Double);
begin
   Assert(ToDouble() - Value <= 1.0);
   Assert(ToDouble() - Value >= 0.0);
   FNumerator := FNumerator - Round(Value * FDenominator); // $R-
end;

function Fraction32.Increment(Delta: Double): Double;
var
   Work: Cardinal;
begin
   Assert((FDenominator - 1) + (FDenominator) <= High(Cardinal));
   Assert(FNumerator < FDenominator);
   Assert(Delta >= 0);
   Assert(Delta < 1.0);
   Work := FNumerator + Round(Delta * FDenominator); // $R-
   Result := Work div FDenominator;
   FNumerator := Work mod FDenominator; // $R-
end;

function Fraction32.ToDouble(): Double;
begin
   Result := FNumerator / FDenominator;
end;

function Fraction32.ToString(): UTF8String;
begin
   Result := FloatToStrF(FNumerator / FDenominator, ffFixed, 0, 15, FloatFormat);
end;

class procedure Fraction32.NormalizeArray(Target: PFraction32; Count: SizeInt);
var
   Index: Cardinal;
   Total, NewTotal: Int64;
begin
   Assert(Count > 0);
   Total := 0;
   {$PUSH}
   {$POINTERMATH ON}
   for Index := 0 to Count - 1 do // $R-
   begin
      Inc(Total, (Target + Index)^.FNumerator);
   end;
   Assert(Total > 0, 'Cannot normalize array with no values.');
   NewTotal := 0;
   if (Count > 1) then
      for Index := 0 to Count - 2 do // $R-
      begin
         (Target + Index)^.FNumerator := Trunc(((Target + Index)^.FNumerator * FDenominator) / Total); // $R-
         Inc(NewTotal, (Target + Index)^.FNumerator);
      end;
   Assert(NewTotal <= FDenominator, 'NewTotal='+IntToStr(NewTotal)+', FDenominator='+IntToStr(FDenominator));
   (Target + Count - 1)^.FNumerator := FDenominator - NewTotal; // $R-
   {$IFOPT C+} Inc(NewTotal, (Target + Count - 1)^.FNumerator); {$ENDIF}
   Assert(NewTotal = FDenominator);
   {$POP}
end;

class procedure Fraction32.InitArray(Target: PFraction32; Count: SizeInt; Value: Cardinal = 0);
begin
   Assert(SizeOf(Fraction32) = SizeOf(DWord));
   Assert(SizeOf(Value) = SizeOf(DWord));
   // we're just going to assume the array is tightly packed
   if (Value > 0) then
      Value := Round(Value * Count / FDenominator); // $R-
   FillDWord(Target^, Count, Value);
end;

class function Fraction32.ChooseFrom(Target: PFraction32; Count: SizeInt; RandomSource: TRandomNumberGenerator): SizeInt;
var
   Index: SizeInt;
   Threshold: Cardinal;
   {$IFOPT C+}
   Total: Cardinal;
   {$ENDIF}
begin
   {$PUSH}
   {$POINTERMATH ON}
   Assert(Count > 0);
   {$IFOPT C+}
   Total := 0;
   for Index := 0 to Count - 1 do
      Total := Total + (Target[Index].FNumerator); // $R-
   Assert(Total = FDenominator);
   {$ENDIF}
   Threshold := RandomSource.GetCardinal(0, FDenominator + 1); // $R-
   for Index := 0 to Count - 1 do
   begin
      if (Threshold < Target[Index].FNumerator) then
      begin
         Result := Index;
         exit;
      end;
      Dec(Threshold, Target[Index].FNumerator);
   end;
   Assert(False);
   {$POP}
end;


// Global functions.

function RoundUInt64(Value: Double): UInt64;
var
   Exponent: Integer;
   Fraction: QWord;
   Bits: QWord absolute Value;
begin
   Assert(SizeOf(QWord) = SizeOf(Double));
   if (Value < 0.0) then
      raise ENumberError.CreateFmt('Cannot represent negative number (%d) in UInt64.', [Value]);
   if (Value = Double(High(UInt64))) then // 18446744073709551616.0 (2^64)
   begin
      // This particular value (because of floating point lossiness) becomes a number
      // outside the range of UInt64 (by 1 bit). We hard-code this specific value
      // because otherwise we would overflow when we try to decode it, and it is a
      // very likely value to occur in this codebase.
      Value := High(UInt64);
      exit;
   end;
   if (Value < 0.5) then
   begin
      Result := 0;
      exit;
   end;
   Exponent := (Bits and kExponent) >> kFractionWidth; // $R-
   case Exponent of
      0: Assert(False); // subnormal
      1..1021: Assert(False); // less than 0.5
      1022: begin // 0.5 <= Value < 1.0
         Result := 1;
         exit;
      end;
      $7FF: begin
         // infinity or NaN
         // not supported
         raise ENumberError.Create('Cannot represent infinity or NaN in UInt64.');
      end;
   end;
   Fraction := Bits and kFraction; // $R-
   Fraction := Fraction + kHiddenBit; // $R-
   Dec(Exponent, 1023); // IEEE754 exponent bias
   Dec(Exponent, kFractionWidth); // convert exponent into bit shift to get an integer
   Result := Fraction;
   if (Exponent < 0) then
   begin
      // we are dropping trailing digits
      if ((Result shr -(Exponent+1)) mod 2 > 0) then
      begin
         Result := (Result shr -Exponent) + 1;
      end
      else
      begin
         Result := Result shr -Exponent;
      end;
   end
   else
   if (Exponent > 0) then
   begin
      // we are adding trailing zeros
      // the most we can do is add 63-kFractionWidth zeros
      // otherwise we'd overflow our UInt64
      if (Exponent >= 64 - kFractionWidth) then
      begin
         raise ENumberError.CreateFmt('Integer overflow when converting Double (%f) to UInt64.', [Value]);
      end;
      Result := Result shl Exponent;
   end;
end;

function TruncUInt64(Value: Double): UInt64;
var
   Exponent: Integer;
   Fraction: QWord;
   Bits: QWord absolute Value;
begin
   Assert(SizeOf(QWord) = SizeOf(Double));
   if (Value < 0.0) then
      raise ENumberError.CreateFmt('Cannot represent negative number (%f) in UInt64.', [Value]);
   if (Value = Double(High(UInt64))) then // 18446744073709551616.0 (2^64)
   begin
      // This particular value (because of floating point lossiness) becomes a number
      // outside the range of UInt64 (by 1 bit). We hard-code this specific value
      // because otherwise we would overflow when we try to decode it, and it is a
      // very likely value to occur in this codebase.
      Value := High(UInt64);
      exit;
   end;
   if (Value < 1.0) then
   begin
      Result := 0;
      exit;
   end;
   Exponent := (Bits and kExponent) >> kFractionWidth; // $R-
   case Exponent of
      0: Assert(False); // subnormal
      1..1021: Assert(False); // less than 0.5
      1022: Assert(False); // 0.5 <= Value < 1.0
      $7FF: begin
         // infinity or NaN
         // not supported
         raise ENumberError.Create('Cannot represent infinity or NaN in UInt64.');
      end;
   end;
   Fraction := Bits and kFraction; // $R-
   Fraction := Fraction + kHiddenBit; // $R-
   Dec(Exponent, 1023); // IEEE754 exponent bias
   Dec(Exponent, kFractionWidth); // convert exponent into bit shift to get an integer
   Result := Fraction;
   if (Exponent < 0) then
   begin
      // we are dropping trailing digits
      Result := Result shr -Exponent;
   end
   else
   if (Exponent > 0) then
   begin
      // we are adding trailing zeros
      // the most we can do is add 63-kFractionWidth zeros
      // otherwise we'd overflow our UInt64
      if (Exponent >= 64 - kFractionWidth) then
      begin
         raise ENumberError.CreateFmt('Integer overflow when converting Double (%f) to UInt64.', [Value]);
      end;
      Result := Result shl Exponent;
   end;
end;

function CeilUInt64(Value: Double): UInt64;
var
   Exponent: Integer;
   Fraction: QWord;
   Bits: QWord absolute Value;
begin
   Assert(SizeOf(QWord) = SizeOf(Double));
   if (Value < 0.0) then
      raise ENumberError.CreateFmt('Cannot represent negative number (%d) in UInt64.', [Value]);
   if (Value = Double(High(UInt64))) then // 18446744073709551616.0 (2^64)
   begin
      // This particular value (because of floating point lossiness) becomes a number
      // outside the range of UInt64 (by 1 bit). We hard-code this specific value
      // because otherwise we would overflow when we try to decode it, and it is a
      // very likely value to occur in this codebase.
      Value := High(UInt64);
      exit;
   end;
   if (Value = 0.0) then
   begin
      Result := 0;
      exit;
   end;
   if (Value <= 1.0) then
   begin
      Result := 1;
      exit;
   end;
   Exponent := (Bits and kExponent) >> kFractionWidth; // $R-
   case Exponent of
      0: Assert(False); // subnormal
      1..1022: Assert(False); // less than 1.0
      $7FF: begin
         // infinity or NaN
         // not supported
         raise ENumberError.Create('Cannot represent infinity or NaN in UInt64.');
      end;
   end;
   Fraction := Bits and kFraction; // $R-
   Fraction := Fraction + kHiddenBit; // $R-
   Dec(Exponent, 1023); // IEEE754 exponent bias
   Dec(Exponent, kFractionWidth); // convert exponent into bit shift to get an integer
   Result := Fraction;
   if (Exponent < 0) then
   begin
      if (((Result shr -Exponent) shl -Exponent) = Result) then
      begin
         // this is an integer
         Result := (Result shr -Exponent);
      end
      else
      begin
         // we are dropping trailing digits, round up
         Result := (Result shr -Exponent) + 1;
      end;
   end
   else
   if (Exponent > 0) then
   begin
      // we are adding trailing zeros, number is already an integer
      // the most we can do is add 63-kFractionWidth zeros
      // otherwise we'd overflow our UInt64
      if (Exponent >= 64 - kFractionWidth) then
      begin
         raise ENumberError.CreateFmt('Integer overflow when converting Double (%f) to UInt64.', [Value]);
      end;
      Result := Result shl Exponent;
   end;
end;


procedure TSum.Reset();
begin
   Value.ResetToZero();
end;

class operator TSum.Copy(constref Source: TSum; var Destination: TSum);
begin
   Destination.Value := Int256.FromInt256(Source.Value);
end;

function TSum.GetIsZero(): Boolean;
begin
   Result := Value.IsZero;
end;

function TSum.GetIsNotZero(): Boolean;
begin
   Result := Value.IsNotZero;
end;

function TSum.GetIsNegative(): Boolean;
begin
   Result := Value.IsNegative;
end;

function TSum.GetIsPositive(): Boolean;
begin
   Result := Value.IsPositive and Value.IsNotZero;
end;

procedure TSum.Inc(Addend: Double);
begin
   Value.Add(Int256.FromDouble(Addend, Scale));
end;

procedure TSum.Dec(Subtrahend: Double);
begin
   Value.Subtract(Int256.FromDouble(Subtrahend, Scale));
end;

procedure TSum.Inc(Addend: TSum);
begin
   Value.Add(Addend.Value);
end;

procedure TSum.Dec(Subtrahend: TSum);
begin
   Value.Subtract(Subtrahend.Value);
end;

procedure TSum.Negate();
begin
   Value.Negate();
end;

function TSum.ToString(): UTF8String;
begin
   Result := Value.ToString();
end;

function TSum.ToDouble(): Double;
begin
   Result := Value.ToDouble(Scale);
end;

class operator TSum.<(A, B: TSum): Boolean;
begin
   Result := A.Value < B.Value;
end;

class operator TSum.<=(A, B: TSum): Boolean;
begin
   Result := A.Value <= B.Value;
end;

class operator TSum.>=(A, B: TSum): Boolean;
begin
   Result := A.Value >= B.Value;
end;

class operator TSum.>(A, B: TSum): Boolean;
begin
   Result := A.Value > B.Value;
end;


{$IFDEF TESTS}
procedure Test();
var
   A, B: Int256;
   F: Fraction32;
   L: array of Fraction32;
   S: TSum;
begin
   Assert(SizeOf(Int256) = 256 / 8);
   Assert(SizeOf(Fraction32) = 32 / 8);

   Assert(Int256.Zero.ToDouble() = 0.0);
   A := Int256.Zero;
   A.Increment();
   Assert(A.ToDouble() = 1.0);
   Assert(Int256.Zero.ToDouble() = 0.0);

   A.AssignQuad1($01);
   A.ShiftLeft(9);
   Assert(A.ToString() = '0000000000000000000000000000000000000000000000000000000000000200');
   Assert(A.ToDouble() = 1 << 9);

   A.AssignQuad1($01);
   A.ShiftLeft(63);
   Assert(A.ToString() = '0000000000000000000000000000000000000000000000008000000000000000');
   Assert(A.ToDouble() = Double(Power(2, 63)));

   A.AssignQuad1($01);
   A.ShiftLeft(64);
   Assert(A.ToString() = '0000000000000000000000000000000000000000000000010000000000000000');
   Assert(A.ToDouble() = Double(Power(2, 64)));

   A.AssignQuad1($01);
   A.ShiftLeft(65);
   Assert(A.ToString() = '0000000000000000000000000000000000000000000000020000000000000000');
   Assert(A.ToDouble() = Double(Power(2, 65)));

   A.AssignQuad1($01);
   A.ShiftLeft(100);
   Assert(A.ToString() = '0000000000000000000000000000000000000010000000000000000000000000');
   Assert(A.ToDouble() = Double(1267650600228229400000000000000.0));

   A.AssignQuad1($01);
   A.ShiftLeft(150);
   Assert(A.ToString() = '0000000000000000000000000040000000000000000000000000000000000000');
   Assert(A.ToDouble() = Double(1427247692705959900000000000000000000000000000));

   A.AssignQuad1($01);
   A.ShiftLeft(200);
   Assert(A.ToString() = '0000000000000100000000000000000000000000000000000000000000000000');
   Assert(A.ToDouble() = Double(1606938044258990300000000000000000000000000000000000000000000));

   A := Int256.FromDouble(0.005);
   Assert(A.ToString() = '0000000000000000000000000000000000000000000000000000000000000000');
   Assert(A.ToDouble() = 0);

   A := Int256.FromDouble(0.05);
   Assert(A.ToString() = '0000000000000000000000000000000000000000000000000000000000000000');
   Assert(A.ToDouble() = 0);

   A := Int256.FromDouble(0.5);
   Assert(A.ToString() = '0000000000000000000000000000000000000000000000000000000000000001');
   Assert(A.ToDouble() = 1);

   A := Int256.FromDouble(1.0);
   Assert(A.ToString() = '0000000000000000000000000000000000000000000000000000000000000001');
   Assert(A.ToDouble() = 1);

   A := Int256.FromDouble(2.345e10);
   Assert(A.ToString() = '0000000000000000000000000000000000000000000000000000000575BA9A80');
   Assert(A.ToDouble() = 2.345e10);

   A.AsQWords[4] := (UInt64($FFFFFFFFFFFFFFFF));
   A.AsQWords[3] := (UInt64($FFFFFFFFFFFFFFFF));
   A.AsQWords[2] := (UInt64($FFFFFFFFFFFFFFFF));
   A.AsQWords[1] := (UInt64($7FFFFFFFFFFFFFFF));
   Assert(A.ToDouble() = Double(5.7896044618658098E+076));

   A := Int256.FromDouble(5.7896044618658091E+076);
   Assert(A.ToString() = '7FFFFFFFFFFFFC00000000000000000000000000000000000000000000000000');
   Assert(A.ToDouble() = Double(5.7896044618658091E+076));

   A := Int256.FromDouble(9223372036854775808.0);
   Assert(A.ToString() = '0000000000000000000000000000000000000000000000008000000000000000');
   Assert(A.ToDouble() = 9223372036854775808.0);

   A := Int256.FromDouble(-9223372036854775808.0);
   Assert(A.ToString() = 'FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF8000000000000000');
   Assert(A.ToDouble() = -9223372036854775808.0);

   A := Int256.FromInt64(-1);
   Assert(A.ToString() = 'FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF');
   Assert(A.ToDouble() = -1);

   A := Int256.FromInt64(128);
   Assert(A.ToString() = '0000000000000000000000000000000000000000000000000000000000000080');
   Assert(A.ToDouble() = 128);

   A := Int256.FromInt64(123456789);
   B := Int256.FromInt64(1);
   A.Subtract(B);
   Assert(A.ToDouble() = 123456788);
   A.Add(B);
   Assert(A.ToDouble() = 123456789);
   B := Int256.FromInt64(987654321);
   A.Subtract(B);
   Assert(A.ToDouble() = -864197532);
   A.Add(B);
   Assert(A.ToDouble() = 123456789);
   
   F := Fraction32.FromDouble(0.5);
   Assert(F * 1.0 = 0.5);
   Assert(F / 1.0 = 0.5);
   Assert(F * 2.0 = 1.0);
   Assert(F / 2.0 = 0.25);

   Assert(Int256.FromDouble(10) < Int256.FromDouble(1e10));
   Assert(not (Int256.FromDouble(1978365928375) < Int256.FromDouble(1.0)));
   Assert(not (Int256.FromDouble(10) < Int256.FromDouble(10)));

   SetLength(L, 5);
   L[0] := Fraction32.FromDouble(0.25);
   L[1] := Fraction32.FromDouble(0.25);
   L[2] := Fraction32.FromDouble(0.25);
   L[3] := Fraction32.FromDouble(0.25);
   L[4] := Fraction32.FromDouble(1.0);
   Fraction32.NormalizeArray(@L[0], Length(L));
   Assert(L[0] * 1.0 = 0.125);
   Assert(L[1] * 1.0 = 0.125);
   Assert(L[2] * 1.0 = 0.125);
   Assert(L[3] * 1.0 = 0.125);
   Assert(L[4] * 1.0 = 0.5);
   Fraction32.NormalizeArray(@L[0], Length(L) - 1);
   Assert(L[0] * 1.0 = 0.25);
   Assert(L[1] * 1.0 = 0.25);
   Assert(L[2] * 1.0 = 0.25);
   Assert(L[3] * 1.0 = 0.25);
   Fraction32.NormalizeArray(@L[0], Length(L) - 2);
   Assert(L[0] * 1.0 = L[1] * 1.0);
   Assert(L[0] * 1.0 + L[1] * 1.0 + L[2] * 1.0 = 1.0);

   Assert(TruncUInt64(1.5) = 1);
   Assert(TruncUInt64(2.5) = 2);
   Assert(TruncUInt64(3.5) = 3);
   Assert(TruncUInt64(4.5) = 4);
   Assert(TruncUInt64(5.5) = 5);
   Assert(TruncUInt64(6.5) = 6);
   Assert(Trunc(123.45) = TruncUInt64(123.45));
   Assert(TruncUInt64(18446744073709549568.0) = 18446744073709549568);
   Assert(TruncUInt64(1e3) = 1000);
   Assert(TruncUInt64(1e2) = 100);
   Assert(TruncUInt64(1e1) = 10);
   Assert(TruncUInt64(1e-15) = 0);
   Assert(TruncUInt64(1e-25) = 0);
   Assert(TruncUInt64(1e-30) = 0);
   Assert(TruncUInt64(1e-35) = 0);
   Assert(TruncUInt64(1e-40) = 0);
   Assert(TruncUInt64(1e-100) = 0);
   Assert(TruncUInt64(1e-200) = 0);
   Assert(TruncUInt64(1e-300) = 0);
   Assert(TruncUInt64(1e-305) = 0);
   Assert(TruncUInt64(1e-306) = 0);
   Assert(TruncUInt64(1e-307) = 0);
   Assert(TruncUInt64(1e-308) = 0);
   Assert(TruncUInt64(1e-309) = 0);

   Assert(RoundUInt64(1.4) = 1);
   Assert(RoundUInt64(2.4) = 2);
   Assert(RoundUInt64(3.4) = 3);
   Assert(RoundUInt64(4.4) = 4);
   Assert(RoundUInt64(5.4) = 5);
   Assert(RoundUInt64(6.4) = 6);
   Assert(RoundUInt64(1.5) = 2);
   Assert(RoundUInt64(2.5) = 3);
   Assert(RoundUInt64(3.5) = 4);
   Assert(RoundUInt64(4.5) = 5);
   Assert(RoundUInt64(5.5) = 6);
   Assert(RoundUInt64(6.5) = 7);
   Assert(RoundUInt64(1.6) = 2);
   Assert(RoundUInt64(2.6) = 3);
   Assert(RoundUInt64(3.6) = 4);
   Assert(RoundUInt64(4.6) = 5);
   Assert(RoundUInt64(5.6) = 6);
   Assert(RoundUInt64(6.6) = 7);
   Assert(Round(123.45) = RoundUInt64(123.45));
   Assert(RoundUInt64(18446744073709549568.0) = 18446744073709549568);
   Assert(RoundUInt64(1e3) = 1000);
   Assert(RoundUInt64(1e2) = 100);
   Assert(RoundUInt64(1e1) = 10);
   Assert(RoundUInt64(1e-15) = 0);
   Assert(RoundUInt64(1e-25) = 0);
   Assert(RoundUInt64(1e-30) = 0);
   Assert(RoundUInt64(1e-35) = 0);
   Assert(RoundUInt64(1e-40) = 0);
   Assert(RoundUInt64(1e-100) = 0);
   Assert(RoundUInt64(1e-200) = 0);
   Assert(RoundUInt64(1e-300) = 0);
   Assert(RoundUInt64(1e-305) = 0);
   Assert(RoundUInt64(1e-306) = 0);
   Assert(RoundUInt64(1e-307) = 0);
   Assert(RoundUInt64(1e-308) = 0);
   Assert(RoundUInt64(1e-309) = 0);

   Assert(CeilUInt64(0.0) = 0);
   Assert(CeilUInt64(0.05) = 1);
   Assert(CeilUInt64(0.5) = 1);
   Assert(CeilUInt64(0.95) = 1);
   Assert(CeilUInt64(1.5) = 2);
   Assert(CeilUInt64(2.5) = 3);
   Assert(CeilUInt64(3.5) = 4);
   Assert(CeilUInt64(4.5) = 5);
   Assert(CeilUInt64(5.5) = 6);
   Assert(CeilUInt64(6.5) = 7);
   Assert(CeilUInt64(120918240) = 120918240);
   Assert(CeilUInt64(120918240.0001) = 120918241);
   Assert(CeilUInt64(123.45) = 124);
   Assert(CeilUInt64(18446744073709549568.0) = 18446744073709549568);
   Assert(CeilUInt64(1e3) = 1000);
   Assert(CeilUInt64(1e2) = 100);
   Assert(CeilUInt64(1e1) = 10);
   Assert(CeilUInt64(1e-15) = 1);
   Assert(CeilUInt64(1e-25) = 1);
   Assert(CeilUInt64(1e-30) = 1);
   Assert(CeilUInt64(1e-35) = 1);
   Assert(CeilUInt64(1e-40) = 1);
   Assert(CeilUInt64(1e-100) = 1);
   Assert(CeilUInt64(1e-200) = 1);
   Assert(CeilUInt64(1e-300) = 1);
   Assert(CeilUInt64(1e-305) = 1);
   Assert(CeilUInt64(1e-306) = 1);
   Assert(CeilUInt64(1e-307) = 1);
   Assert(CeilUInt64(1e-308) = 1);
   Assert(CeilUInt64(1e-309) = 1);

   S.Reset();
   S.Inc(Double(1e20));
   S.Inc(Double(1e-10));
   Assert(S.ToDouble() = Double(1e20));
   S.Dec(1e20);
   Assert(S.ToDouble() = Double(1e-10));
   
   S.Reset();
   S.Inc(Double(1e30));
   Assert(S.ToDouble() = Double(1e30));
   S.Inc(Double(1e30));
   Assert(S.ToDouble() = Double(2e30));
   S.Dec(Double(1e-20));
   Assert(S.ToDouble() = Double(2e30));
   S.Dec(Double(1e30));
   Assert(S.ToDouble() = Double(1e30));
   S.Dec(Double(1e30));
   Assert(S.ToDouble() = -Double(1e-20));
   
   S.Reset();
   S.Inc(Double(1));
   Assert(S.ToDouble() = Double(1));
   S.Inc(Double(1e30));
   Assert(S.ToDouble() = Double(1e30));
   S.Inc(Double(1e30));
   Assert(S.ToDouble() = Double(2e30));
   S.Dec(Double(1e30));
   Assert(S.ToDouble() = Double(1e30));
   S.Dec(Double(1e30));
   Assert(S.ToDouble() = Double(1));

   S.Reset();
   S.Inc(1000 / (60 * 60 * 1000));
   Assert(S.ToDouble() = Double(1000 / (60 * 60 * 1000)));

   S.Reset();
   S.Inc(Double(1.000000005));
   Assert(S.ToDouble() = Double(1.000000005));
   S.Dec(Double(0.000000005));
   Assert(S.ToDouble() = Double(1.000000000));
end;
{$ENDIF}

initialization
   {$IFDEF TESTS}
   Test();
   {$ENDIF}
end.
