{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit masses;

interface

uses
   isdnumbers;

type
   TQuantity64 = record
   private
      Value: Int64;
      function GetIsZero(): Boolean; inline;
      function GetIsNotZero(): Boolean; inline;
      function GetIsPositive(): Boolean; inline;
      function GetIsNegative(): Boolean; inline;
      class function GetZero(): TQuantity64; inline; static;
      class function GetOne(): TQuantity64; inline; static;
      class function GetMax(): TQuantity64; inline; static;
   public
      constructor FromUnits(A: Int64);
      function TruncatedMultiply(B: Double): TQuantity64; inline;
      function ToString(): UTF8String;
      property IsZero: Boolean read GetIsZero; // > 0
      property IsNotZero: Boolean read GetIsNotZero; // > 0
      property IsPositive: Boolean read GetIsPositive; // > 0
      property IsNegative: Boolean read GetIsNegative; // < 0
      property AsInt64: Int64 read Value; // for storage, restore with FromUnits(Int64)
      class property Zero: TQuantity64 read GetZero;
      class property One: TQuantity64 read GetOne;
      class property Max: TQuantity64 read GetMax;
   end;

   TQuantity32 = record
   private
      Value: UInt32;
      function GetIsZero(): Boolean; inline;
      function GetIsNotZero(): Boolean; inline;
      function GetIsPositive(): Boolean; inline;
      //function GetIsNegative(): Boolean; inline;
      class function GetZero(): TQuantity32; inline; static;
      class function GetOne(): TQuantity32; inline; static;
      class function GetMax(): TQuantity32; inline; static;
   public
      constructor FromUnits(A: Cardinal);
      constructor FromQuantity64(A: TQuantity64);
      function ToString(): UTF8String;
      property IsZero: Boolean read GetIsZero; // > 0
      property IsNotZero: Boolean read GetIsNotZero; // > 0
      property IsPositive: Boolean read GetIsPositive; // > 0
      //property IsNegative: Boolean read GetIsNegative; // < 0
      property AsCardinal: Cardinal read Value; // for storage, restore with FromUnits(Cardinal)
      class property Zero: TQuantity32 read GetZero;
      class property One: TQuantity32 read GetOne;
      class property Max: TQuantity32 read GetMax;
   end;

   TMass = record
   private
      Value: Double;
      function GetIsZero(): Boolean; inline;
      function GetIsNotZero(): Boolean; inline;
      {$IFOPT C+} function GetIsNearZero(): Boolean; inline; {$ENDIF}
      {$IFOPT C+} function GetIsNotNearZero(): Boolean; inline; {$ENDIF}
      function GetIsNegative(): Boolean; inline;
      function GetIsPositive(): Boolean; inline;
      class function GetZero(): TMass; inline; static;
      class function GetInfinity(): TMass; inline; static;
   public
      constructor FromKg(A: Double); overload; // Kilograms
      constructor FromKg(A: Int256); overload; // Kilograms
      constructor FromG(A: Double); // Grams
      constructor FromMg(A: Double); // Milligrams
      function ToSIUnits(): Double; inline; // returns the value in kg
      function ToString(): UTF8String;
      property IsZero: Boolean read GetIsZero; // > 0
      property IsNotZero: Boolean read GetIsNotZero; // > 0
      {$IFOPT C+} property IsNearZero: Boolean read GetIsNearZero; {$ENDIF}
      {$IFOPT C+} property IsNotNearZero: Boolean read GetIsNotNearZero; {$ENDIF}
      property IsNegative: Boolean read GetIsNegative; // < 0
      property IsPositive: Boolean read GetIsPositive; // > 0
      property AsDouble: Double read Value; // for storage, restore with FromKg(Double)
      class property Zero: TMass read GetZero;
      class property Infinity: TMass read GetInfinity;
   end;

   TMassPerUnit = record
   private
      Value: Double;
      function GetIsZero(): Boolean; inline;
      function GetIsNotZero(): Boolean; inline;
      function GetIsPositive(): Boolean; inline;
      class function GetInfinity(): TMassPerUnit; inline; static;
   public
      constructor FromKgPerUnit(A: Double); // Kilograms
      constructor FromGPerUnit(A: Double); // Grams
      constructor FromMassPerUnit(A: TMass);
      function ToString(): UTF8String;
      property IsZero: Boolean read GetIsZero; // > 0
      property IsNotZero: Boolean read GetIsNotZero; // > 0
      property IsPositive: Boolean read GetIsPositive; // > 0
      property AsDouble: Double read Value; // for storage, restore with FromKgPerUnit(Double)
      class property Infinity: TMassPerUnit read GetInfinity;
   end;

operator + (A: TQuantity64; B: TQuantity64): TQuantity64; inline;
operator - (A: TQuantity64; B: TQuantity64): TQuantity64; inline;
operator - (A: TQuantity64; B: TQuantity32): TQuantity64; inline;
operator * (A: TQuantity64; B: Int64): TQuantity64; inline;
operator * (A: TQuantity64; B: Double): TQuantity64; inline;
operator / (A: TQuantity64; B: TQuantity64): Double; inline;
operator div (A: TQuantity64; B: TQuantity64): Int64; inline;
operator div (A: TQuantity64; B: Int64): TQuantity64; inline;
operator < (A: TQuantity64; B: TQuantity64): Boolean; inline;
operator <= (A: TQuantity64; B: TQuantity64): Boolean; inline;
operator = (A: TQuantity64; B: TQuantity64): Boolean; inline;
operator >= (A: TQuantity64; B: TQuantity64): Boolean; inline;
operator > (A: TQuantity64; B: TQuantity64): Boolean; inline;

operator + (A: TQuantity32; B: TQuantity32): TQuantity32; inline;
operator - (A: TQuantity32; B: TQuantity32): TQuantity32; inline;
operator * (A: TQuantity32; B: Cardinal): TQuantity32; inline;
operator * (A: TQuantity32; B: Double): TQuantity32; inline;
operator / (A: TQuantity32; B: TQuantity32): Double; inline;
operator div (A: TQuantity32; B: TQuantity32): Cardinal; inline;
operator div (A: TQuantity32; B: Cardinal): TQuantity32; inline;
operator < (A: TQuantity32; B: TQuantity32): Boolean; inline;
operator <= (A: TQuantity32; B: TQuantity32): Boolean; inline;
operator = (A: TQuantity32; B: TQuantity32): Boolean; inline;
operator >= (A: TQuantity32; B: TQuantity32): Boolean; inline;
operator > (A: TQuantity32; B: TQuantity32): Boolean; inline;

operator := (A: TQuantity32): TQuantity64; inline;

operator + (A: TMass; B: TMass): TMass; inline;
operator - (A: TMass; B: TMass): TMass; inline;
operator * (A: TMass; B: Double): TMass; inline;
operator * (A: TMass; B: Int64): TMass; inline;
operator * (A: Fraction32; B: TMass): TMass; inline;
operator / (A: TMass; B: TMass): Double; inline;
operator mod (A: TMass; B: TMass): TMass; inline;
operator < (A: TMass; B: TMass): Boolean; inline;
operator <= (A: TMass; B: TMass): Boolean; inline;
operator = (A: TMass; B: TMass): Boolean; inline;
operator >= (A: TMass; B: TMass): Boolean; inline;
operator > (A: TMass; B: TMass): Boolean; inline;

operator < (A: TMassPerUnit; B: TMassPerUnit): Boolean; inline;
operator <= (A: TMassPerUnit; B: TMassPerUnit): Boolean; inline;
operator = (A: TMassPerUnit; B: TMassPerUnit): Boolean; inline;
operator >= (A: TMassPerUnit; B: TMassPerUnit): Boolean; inline;
operator > (A: TMassPerUnit; B: TMassPerUnit): Boolean; inline;

operator / (A: TMass; B: TQuantity64): TMassPerUnit; inline;
operator / (A: TMass; B: TQuantity32): TMassPerUnit; inline;
operator * (A: TQuantity64; B: TMassPerUnit): TMass; inline;
operator * (A: TQuantity32; B: TMassPerUnit): TMass; inline;
operator / (A: TMass; B: TMassPerUnit): TQuantity64; inline;
operator / (A: TMass; B: TMassPerUnit): TQuantity32; inline;
operator div (A: TMass; B: TMassPerUnit): TQuantity64; inline;
operator div (A: TMass; B: TMassPerUnit): TQuantity32; inline;

implementation

uses
   sysutils, stringutils, math;

constructor TQuantity64.FromUnits(A: Int64);
begin
   Value := A;
end;

function TQuantity64.TruncatedMultiply(B: Double): TQuantity64;
begin
   Result.Value := Trunc(Value * B);
end;
      
function TQuantity64.ToString(): UTF8String;
begin
   Result := IntToStr(Value) + ' units';
end;

function TQuantity64.GetIsZero(): Boolean;
begin
   Result := Value = 0;
end;

function TQuantity64.GetIsNotZero(): Boolean;
begin
   Result := Value <> 0;
end;

function TQuantity64.GetIsPositive(): Boolean;
begin
   Result := Value > 0;
end;

function TQuantity64.GetIsNegative(): Boolean;
begin
   Result := Value < 0;
end;

class function TQuantity64.GetZero(): TQuantity64;
begin
   Result.Value := 0;
end;

class function TQuantity64.GetOne(): TQuantity64;
begin
   Result.Value := 1;
end;

class function TQuantity64.GetMax(): TQuantity64;
begin
   Result.Value := High(Result.Value);
end;



constructor TQuantity32.FromUnits(A: UInt32);
begin
   Value := A;
end;

constructor TQuantity32.FromQuantity64(A: TQuantity64);
begin
   Assert(A.Value <= High(Value));
   Value := A.Value; // $R-
end;

function TQuantity32.ToString(): UTF8String;
begin
   Result := IntToStr(Value) + ' units';
end;

function TQuantity32.GetIsZero(): Boolean;
begin
   Result := Value = 0;
end;

function TQuantity32.GetIsNotZero(): Boolean;
begin
   Result := Value <> 0;
end;

function TQuantity32.GetIsPositive(): Boolean;
begin
   Result := Value > 0;
end;

// function TQuantity32.GetIsNegative(): Boolean;
// begin
//    Result := Value < 0;
// end;

class function TQuantity32.GetZero(): TQuantity32;
begin
   Result.Value := 0;
end;

class function TQuantity32.GetOne(): TQuantity32;
begin
   Result.Value := 1;
end;

class function TQuantity32.GetMax(): TQuantity32;
begin
   Result.Value := High(Result.Value);
end;


constructor TMass.FromKg(A: Double);
begin
   Value := A;
end;

constructor TMass.FromKg(A: Int256);
begin
   Value := A.ToDouble();
end;

constructor TMass.FromG(A: Double);
begin
   Value := A / 1000;
end;

constructor TMass.FromMg(A: Double);
begin
   Value := A / 1000000;
end;

function TMass.ToSIUnits(): Double;
begin
   Result := Value;
end;

function TMass.ToString(): UTF8String;
begin
   Result := FloatToStrF(Value, ffFixed, 0, 1, FloatFormat) + 'kg';
end;

function TMass.GetIsZero(): Boolean;
begin
   Result := Value = 0;
end;

function TMass.GetIsNotZero(): Boolean;
begin
   Result := Value <> 0;
end;

{$IFOPT C+}
function TMass.GetIsNearZero(): Boolean;
begin
   Result := Abs(Value) < 0.00000001; // TODO: this is completely arbitrary
end;
{$ENDIF}

{$IFOPT C+}
function TMass.GetIsNotNearZero(): Boolean;
begin
   Result := Abs(Value) >= 0.00000001; // TODO: this is completely arbitrary
end;
{$ENDIF}

function TMass.GetIsPositive(): Boolean;
begin
   Result := Value > 0;
end;

function TMass.GetIsNegative(): Boolean;
begin
   Result := Value < 0;
end;

class function TMass.GetZero(): TMass;
begin
   Result.Value := 0.0;
end;

class function TMass.GetInfinity(): TMass;
begin
   {$PUSH}
   {$IEEEERRORS OFF}
   Result.Value := math.Infinity;
   {$POP}
end;


constructor TMassPerUnit.FromKgPerUnit(A: Double);
begin
   Assert(A > 0);
   Value := A;
end;

constructor TMassPerUnit.FromGPerUnit(A: Double);
begin
   Assert(A > 0);
   Value := A / 1000;
end;

constructor TMassPerUnit.FromMassPerUnit(A: TMass);
begin
   Assert(A.IsPositive);
   Value := A.Value;
end;

function TMassPerUnit.ToString(): UTF8String;
begin
   Result := FloatToStrF(Value, ffFixed, 0, 1, FloatFormat) + 'kg/units';
end;

function TMassPerUnit.GetIsZero(): Boolean;
begin
   Result := Value = 0;
end;

function TMassPerUnit.GetIsNotZero(): Boolean;
begin
   Result := Value <> 0;
end;

function TMassPerUnit.GetIsPositive(): Boolean;
begin
   Result := Value > 0;
end;

class function TMassPerUnit.GetInfinity(): TMassPerUnit;
begin
   {$PUSH}
   {$IEEEERRORS OFF}
   Result.Value := math.Infinity;
   {$POP}
end;


operator + (A: TQuantity64; B: TQuantity64): TQuantity64;
begin
   Result.Value := A.Value + B.Value;
end;

operator - (A: TQuantity64; B: TQuantity64): TQuantity64;
begin
   Assert(A >= B);
   Result.Value := A.Value - B.Value;
end;

operator - (A: TQuantity64; B: TQuantity32): TQuantity64;
begin
   Assert(A >= B);
   Result.Value := A.Value - B.Value;
end;

operator * (A: TQuantity64; B: Int64): TQuantity64;
begin
   Result.Value := A.Value * B;
end;

operator * (A: TQuantity64; B: Double): TQuantity64;
begin
   Result.Value := Round(A.Value * B);
end;

operator / (A: TQuantity64; B: TQuantity64): Double;
begin
   Result := A.Value / B.Value;
end;

operator div (A: TQuantity64; B: TQuantity64): Int64;
begin
   Result := A.Value div B.Value;
end;

operator div (A: TQuantity64; B: Int64): TQuantity64;
begin
   Result.Value := A.Value div B;
end;

operator < (A: TQuantity64; B: TQuantity64): Boolean;
begin
   Result := A.Value < B.Value;
end;

operator <= (A: TQuantity64; B: TQuantity64): Boolean;
begin
   Result := A.Value <= B.Value;
end;

operator = (A: TQuantity64; B: TQuantity64): Boolean;
begin
   Result := A.Value = B.Value;
end;

operator >= (A: TQuantity64; B: TQuantity64): Boolean;
begin
   Result := A.Value >= B.Value;
end;

operator > (A: TQuantity64; B: TQuantity64): Boolean;
begin
   Result := A.Value > B.Value;
end;


operator + (A: TQuantity32; B: TQuantity32): TQuantity32;
begin
   Result.Value := A.Value + B.Value; // $R-
end;

operator - (A: TQuantity32; B: TQuantity32): TQuantity32;
begin
   Assert(A >= B);
   Result.Value := A.Value - B.Value; // $R-
end;

operator * (A: TQuantity32; B: Cardinal): TQuantity32;
begin
   Result.Value := A.Value * B; // $R-
end;

operator * (A: TQuantity32; B: Double): TQuantity32;
begin
   Result.Value := Round(A.Value * B); // $R-
end;

operator / (A: TQuantity32; B: TQuantity32): Double;
begin
   Result := A.Value / B.Value;
end;

operator div (A: TQuantity32; B: TQuantity32): Cardinal;
begin
   Result := Cardinal(A.Value div B.Value);
end;

operator div (A: TQuantity32; B: Cardinal): TQuantity32;
begin
   Result.Value := Cardinal(A.Value div B);
end;

operator < (A: TQuantity32; B: TQuantity32): Boolean;
begin
   Result := A.Value < B.Value;
end;

operator <= (A: TQuantity32; B: TQuantity32): Boolean;
begin
   Result := A.Value <= B.Value;
end;

operator = (A: TQuantity32; B: TQuantity32): Boolean;
begin
   Result := A.Value = B.Value;
end;

operator >= (A: TQuantity32; B: TQuantity32): Boolean;
begin
   Result := A.Value >= B.Value;
end;

operator > (A: TQuantity32; B: TQuantity32): Boolean;
begin
   Result := A.Value > B.Value;
end;


operator := (A: TQuantity32): TQuantity64;
begin
   Result.Value := A.Value;
end;


operator + (A: TMass; B: TMass): TMass;
begin
   Result.Value := A.Value + B.Value;
end;

operator - (A: TMass; B: TMass): TMass;
begin
   Result.Value := A.Value - B.Value;
end;

operator * (A: TMass; B: Double): TMass;
begin
   Result.Value := A.Value * B;
end;

operator * (A: TMass; B: Int64): TMass;
begin
   Result.Value := A.Value * B;
end;

operator * (A: Fraction32; B: TMass): TMass;
begin
   Result.Value := A * B.Value;
end;

operator / (A: TMass; B: TMass): Double;
begin
   Result := A.Value / B.Value;
end;

operator mod (A: TMass; B: TMass): TMass;
begin
   Result.Value := A.Value mod B.Value; // $R-
end;

operator < (A: TMass; B: TMass): Boolean;
begin
   Result := A.Value < B.Value;
end;

operator <= (A: TMass; B: TMass): Boolean;
begin
   Result := A.Value <= B.Value;
end;

operator = (A: TMass; B: TMass): Boolean;
begin
   Result := A.Value = B.Value;
end;

operator >= (A: TMass; B: TMass): Boolean;
begin
   Result := A.Value >= B.Value;
end;

operator > (A: TMass; B: TMass): Boolean;
begin
   Result := A.Value > B.Value;
end;


operator < (A: TMassPerUnit; B: TMassPerUnit): Boolean;
begin
   Result := A.Value < B.Value;
end;

operator <= (A: TMassPerUnit; B: TMassPerUnit): Boolean;
begin
   Result := A.Value <= B.Value;
end;

operator = (A: TMassPerUnit; B: TMassPerUnit): Boolean;
begin
   Result := A.Value = B.Value;
end;

operator >= (A: TMassPerUnit; B: TMassPerUnit): Boolean;
begin
   Result := A.Value >= B.Value;
end;

operator > (A: TMassPerUnit; B: TMassPerUnit): Boolean;
begin
   Result := A.Value > B.Value;
end;


operator / (A: TMass; B: TQuantity64): TMassPerUnit;
begin
   Result.Value := A.Value / B.Value;
end;

operator / (A: TMass; B: TQuantity32): TMassPerUnit;
begin
   Result.Value := A.Value / B.Value;
end;

operator * (A: TQuantity64; B: TMassPerUnit): TMass;
begin
   Result.Value := A.Value * B.Value;
end;

operator * (A: TQuantity32; B: TMassPerUnit): TMass;
begin
   Result.Value := A.Value * B.Value;
end;

operator / (A: TMass; B: TMassPerUnit): TQuantity64;
begin
   Result.Value := Round(A.Value / B.Value);
end;

operator / (A: TMass; B: TMassPerUnit): TQuantity32;
begin
   Result.Value := Round(A.Value / B.Value); // $R-
end;

operator div (A: TMass; B: TMassPerUnit): TQuantity64;
begin
   Result.Value := Trunc(A.Value / B.Value);
end;

operator div (A: TMass; B: TMassPerUnit): TQuantity32;
begin
   Result.Value := Trunc(A.Value / B.Value); // $R-
end;

end.