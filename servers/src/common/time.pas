{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit time;

interface

uses
   clock, masses, isdnumbers;

type
   TMillisecondsDuration = record // solar system milliseconds duration; supports Infinity and -Infinity
   private
      Value: Int64;
      function GetIsZero(): Boolean; inline;
      function GetIsNotZero(): Boolean; inline;
      function GetIsNegative(): Boolean; inline;
      function GetIsPositive(): Boolean; inline;
      function GetIsFinite(): Boolean; inline;
      function GetIsInfinite(): Boolean; inline;
      class function GetNegInfinity(): TMillisecondsDuration; inline; static;
      class function GetInfinity(): TMillisecondsDuration; inline; static;
      class function GetZero(): TMillisecondsDuration; inline; static;
   public
      constructor FromMilliseconds(A: Double); overload;
      constructor FromMilliseconds(A: Int64); overload;
      constructor FromWeeks(A: Int64);
      function ToString(): UTF8String;
      function ToSIUnits(): Double; // returns the value in seconds
      function Scale(Factor: Double): TMillisecondsDuration;
      property IsZero: Boolean read GetIsZero; // = 0
      property IsNotZero: Boolean read GetIsNotZero; // <> 0
      property IsNegative: Boolean read GetIsNegative; // < 0
      property IsPositive: Boolean read GetIsPositive; // > 0
      property IsFinite: Boolean read GetIsFinite;
      property IsInfinite: Boolean read GetIsInfinite;
      property AsInt64: Int64 read Value; // for storage, restore with FromMilliseconds(Int64)
      class property NegInfinity: TMillisecondsDuration read GetNegInfinity;
      class property Infinity: TMillisecondsDuration read GetInfinity;
      class property Zero: TMillisecondsDuration read GetZero;
   end;

   TTimeInMilliseconds = record // solar system absolute time (in milliseconds); supports Infinity and -Infinity
   private
      Value: Int64;
      function GetIsInfinite(): Boolean; inline;
      class function GetNegInfinity(): TTimeInMilliseconds; inline; static;
      class function GetInfinity(): TTimeInMilliseconds; inline; static;
      {$IFOPT C+} class function GetZero(): TTimeInMilliseconds; inline; static; {$ENDIF}
   public
      constructor FromMilliseconds(A: Double); overload;
      constructor FromMilliseconds(A: Int64); overload;
      constructor FromDurationSinceOrigin(A: TMillisecondsDuration); overload;
      function ToString(): UTF8String;
      property AsInt64: Int64 read Value; // for storage, restore with FromMilliseconds(Int64)
      property IsInfinite: Boolean read GetIsInfinite;
      class property NegInfinity: TTimeInMilliseconds read GetNegInfinity;
      class property Infinity: TTimeInMilliseconds read GetInfinity;
      {$IFOPT C+} class property Zero: TTimeInMilliseconds read GetZero; {$ENDIF} // there's really no need to specifically have the zero value in normal operation
   end;

   TWallMillisecondsDuration = record // wall-clock time duration in milliseconds (must be finite)
   private
      Value: Int64;
   public
      constructor FromMilliseconds(A: Double); overload;
      constructor FromMilliseconds(A: Int64); overload;
      constructor FromDateTimes(A, B: TDateTime); overload;
      function ToString(): UTF8String;
   end;

   TTimeFactor = record // wall clock time to solar system time
   private
      Value: Double;
   public
      constructor FromFactor(A: Double);
      property AsDouble: Double read Value; // for storage, restore with FromFactor(Double)
      function ToString(): UTF8String;
   end;
   
   TRate = record
   private
      Value: Double;
      function GetIsExactZero(): Boolean; inline;
      function GetIsNotExactZero(): Boolean; inline;
      {$IFOPT C+} function GetIsNearZero(): Boolean; inline; {$ENDIF}
      {$IFOPT C+} function GetIsNotNearZero(): Boolean; inline; {$ENDIF}
      function GetIsPositive(): Boolean; inline;
      function GetIsNegative(): Boolean; inline;
      function GetIsFinite(): Boolean; inline;
      function GetIsInfinite(): Boolean; inline;
   public
      constructor FromPerSecond(A: Double);
      constructor FromPerMillisecond(A: Double);
      procedure Reset(NewValue: Double = 0.0); // sets the value (useful when the precise type is not known, since TRate.Zero, TMassRate.MZero and TQuantityRate.QZero aren't type compatible)
      function ToString(NumeratorUnit: UTF8String): UTF8String;
      property IsExactZero: Boolean read GetIsExactZero;
      property IsNotExactZero: Boolean read GetIsNotExactZero;
      {$IFOPT C+} property IsNearZero: Boolean read GetIsNearZero; {$ENDIF}
      {$IFOPT C+} property IsNotNearZero: Boolean read GetIsNotNearZero; {$ENDIF}
      property IsPositive: Boolean read GetIsPositive; // >0
      property IsNegative: Boolean read GetIsNegative; // <0
      property IsFinite: Boolean read GetIsFinite;
      property IsInfinite: Boolean read GetIsInfinite;
      property AsDouble: Double read Value; // for storage, restore with FromPerMillisecond(Double)
   end;

   TMassRate = type TRate;
   TQuantityRate = type TRate;

   function ApplyIncrementally(Rate: TRate; Time: TMillisecondsDuration; var Fraction: Fraction32): Int64;
   function ApplyIncrementally(Rate: TQuantityRate; Time: TMillisecondsDuration; var Fraction: Fraction32): TQuantity64;
   function ApplyIncrementally(Rate: TMassRate; Time: TMillisecondsDuration; var Fraction: Fraction32): TMass;

type
   TRateConstants = record helper for TRate
   private
      class function GetInfinity(): TRate; inline; static;
      class function GetZero(): TRate; inline; static;
      class function GetMInfinity(): TMassRate; inline; static;
      class function GetMZero(): TMassRate; inline; static;
      class function GetQInfinity(): TQuantityRate; inline; static;
      class function GetQZero(): TQuantityRate; inline; static;
   public
      class property Zero: TRate read GetZero;
      class property Infinity: TRate read GetInfinity;
      class property MZero: TMassRate read GetMZero;
      class property MInfinity: TMassRate read GetMInfinity;
      class property QZero: TQuantityRate read GetQZero;
      class property QInfinity: TQuantityRate read GetQInfinity;
   end;

   TQuantityRateSum = record
   private
      Value: TSum;
      class operator Initialize(var Rec: TQuantityRateSum);
      function GetIsZero(): Boolean; inline;
      function GetIsNotZero(): Boolean; inline;
      function GetIsNegative(): Boolean; inline;
      function GetIsPositive(): Boolean; inline;
   public
      procedure Reset(); inline;
      procedure Inc(Delta: TQuantityRate); inline;
      procedure Dec(Delta: TQuantityRate); inline;
      procedure Inc(Delta: TQuantityRateSum); inline;
      procedure Dec(Delta: TQuantityRateSum); inline;
      class operator Copy(constref Source: TQuantityRateSum; var Destination: TQuantityRateSum);
      property IsZero: Boolean read GetIsZero;
      property IsNotZero: Boolean read GetIsNotZero;
      property IsNegative: Boolean read GetIsNegative;
      property IsPositive: Boolean read GetIsPositive;
      property AsSum: TSum read Value;
      function ToQuantityRate(): TQuantityRate; inline;
      function ToDouble(): Double; inline;
      function ToString(): UTF8String;
      class operator <(A, B: TQuantityRateSum): Boolean; inline;
      class operator <=(A, B: TQuantityRateSum): Boolean; inline;
      class operator >=(A, B: TQuantityRateSum): Boolean; inline;
      class operator >(A, B: TQuantityRateSum): Boolean; inline;
      class operator -(A, B: TQuantityRateSum): TQuantityRateSum;
   end;
   
   TGrowthRate = record // used for exponential growth with **
   private
      Value: Double;
   public
      constructor FromEachMillisecond(A: Double); // must be positive
      constructor FromEachWeek(A: Double); // must be positive
      constructor FromDoublingTimeInMilliseconds(A: Double); // must be positive
      constructor FromDoublingTimeInWeeks(A: Double); // must be positive
      property AsDouble: Double read Value; // for storage, restore with FromEachMilliseconds(Double)
   end;

   TFactor = record
      // all values must be positive
      // TGrowthRate ** TMillisecondsDuration => TFactor;
      // Double * TFactor => Double
      // Cardinal * TFactor => Cardinal (saturating)
   private
      Value: Double;
   end;

operator + (A: TMillisecondsDuration; B: TMillisecondsDuration): TMillisecondsDuration; inline;
operator - (A: TMillisecondsDuration; B: TMillisecondsDuration): TMillisecondsDuration; inline;
operator - (A: TMillisecondsDuration): TMillisecondsDuration; inline;
operator mod (A: TMillisecondsDuration; B: TMillisecondsDuration): TMillisecondsDuration; inline;
operator * (A: TMillisecondsDuration; B: Double): TMillisecondsDuration; inline;
operator / (A: TMillisecondsDuration; B: TMillisecondsDuration): Double; inline;
operator / (A: TMillisecondsDuration; B: Double): TMillisecondsDuration; inline;
operator = (A: TMillisecondsDuration; B: TMillisecondsDuration): Boolean; inline;
operator < (A: TMillisecondsDuration; B: TMillisecondsDuration): Boolean; inline;
operator <= (A: TMillisecondsDuration; B: TMillisecondsDuration): Boolean; inline;
operator > (A: TMillisecondsDuration; B: TMillisecondsDuration): Boolean; inline;
operator >= (A: TMillisecondsDuration; B: TMillisecondsDuration): Boolean; inline;

operator - (A: TTimeInMilliseconds; B: TTimeInMilliseconds): TMillisecondsDuration; inline;
operator = (A: TTimeInMilliseconds; B: TTimeInMilliseconds): Boolean; inline;
operator < (A: TTimeInMilliseconds; B: TTimeInMilliseconds): Boolean; inline;
operator <= (A: TTimeInMilliseconds; B: TTimeInMilliseconds): Boolean; inline;
operator > (A: TTimeInMilliseconds; B: TTimeInMilliseconds): Boolean; inline;
operator >= (A: TTimeInMilliseconds; B: TTimeInMilliseconds): Boolean; inline;
operator + (A: TTimeInMilliseconds; B: TMillisecondsDuration): TTimeInMilliseconds; inline;
operator - (A: TTimeInMilliseconds; B: TMillisecondsDuration): TTimeInMilliseconds; inline;
function Min(A: TTimeInMilliseconds; B: TTimeInMilliseconds): TTimeInMilliseconds; overload;
function Max(A: TTimeInMilliseconds; B: TTimeInMilliseconds): TTimeInMilliseconds; overload;

operator div (A: TMillisecondsDuration; B: TTimeFactor): TWallMillisecondsDuration; inline;

operator + (A: TDateTime; B: TWallMillisecondsDuration): TDateTime; inline;
operator * (A: TWallMillisecondsDuration; B: TTimeFactor): TMillisecondsDuration; inline;

operator + (A: TRate; B: TRate): TRate; inline;
operator - (A: TRate; B: TRate): TRate; inline;
operator - (A: TRate): TRate; inline;
operator * (A: TRate; B: Double): TRate; inline;
operator / (A: TRate; B: TRate): Double; inline;
operator / (A: TRate; B: Double): TRate; inline;
operator = (A: TRate; B: TRate): Boolean; inline;
operator < (A: TRate; B: TRate): Boolean; inline;
operator <= (A: TRate; B: TRate): Boolean; inline;
operator > (A: TRate; B: TRate): Boolean; inline;
operator >= (A: TRate; B: TRate): Boolean; inline;
function Min(A: TRate; B: TRate): TRate; overload;

operator + (A: TMassRate; B: TMassRate): TMassRate; inline;
operator - (A: TMassRate; B: TMassRate): TMassRate; inline;
operator - (A: TMassRate): TMassRate; inline;
operator * (A: TMassRate; B: Double): TMassRate; inline;
operator / (A: TMassRate; B: TMassRate): Double; inline;
operator / (A: TMassRate; B: Double): TMassRate; inline;
operator / (A: TMassRate; B: TMass): TRate; inline;
operator = (A: TMassRate; B: TMassRate): Boolean; inline;
operator < (A: TMassRate; B: TMassRate): Boolean; inline;
operator <= (A: TMassRate; B: TMassRate): Boolean; inline;
operator > (A: TMassRate; B: TMassRate): Boolean; inline;
operator >= (A: TMassRate; B: TMassRate): Boolean; inline;
function Min(A: TMassRate; B: TMassRate): TMassRate; overload;

operator + (A: TQuantityRate; B: TQuantityRate): TQuantityRate; inline;
operator - (A: TQuantityRate; B: TQuantityRate): TQuantityRate; inline;
operator - (A: TQuantityRate): TQuantityRate; inline;
operator * (A: TQuantityRate; B: Double): TQuantityRate; inline;
operator / (A: TQuantityRate; B: TQuantityRate): Double; inline;
operator / (A: TQuantityRate; B: Double): TQuantityRate; inline;
operator / (A: TQuantityRate; B: TQuantity64): TRate; inline;
operator / (A: TQuantityRate; B: TQuantity32): TRate; inline;
operator = (A: TQuantityRate; B: TQuantityRate): Boolean; inline;
operator < (A: TQuantityRate; B: TQuantityRate): Boolean; inline;
operator <= (A: TQuantityRate; B: TQuantityRate): Boolean; inline;
operator > (A: TQuantityRate; B: TQuantityRate): Boolean; inline;
operator >= (A: TQuantityRate; B: TQuantityRate): Boolean; inline;
function Min(A: TQuantityRate; B: TQuantityRate): TQuantityRate; overload;

operator * (A: TMillisecondsDuration; B: TRate): Double; inline;
operator * (A: TMillisecondsDuration; B: TMassRate): TMass; inline;
operator * (A: TMillisecondsDuration; B: TQuantityRate): TQuantity64; inline;

operator * (A: TQuantity64; B: TRate): TQuantityRate;
operator * (A: TQuantityRate; B: TMassPerUnit): TMassRate; inline;

operator / (A: Double; B: TRate): TMillisecondsDuration; inline;
operator / (A: TMassRate; B: TMassPerUnit): TQuantityRate; inline;
operator / (A: TQuantity64; B: TQuantityRate): TMillisecondsDuration; inline;
operator / (A: TQuantity32; B: TQuantityRate): TMillisecondsDuration; inline;

operator / (A: TMass; B: TMassRate): TMillisecondsDuration; inline;

operator / (A: Double; B: TMillisecondsDuration): TRate; inline;
operator / (A: TMass; B: TMillisecondsDuration): TMassRate; inline;
operator / (A: TQuantity64; B: TMillisecondsDuration): TQuantityRate; inline;
operator / (A: TQuantity32; B: TMillisecondsDuration): TQuantityRate; inline;

operator ** (A: TGrowthRate; B: TMillisecondsDuration): TFactor; inline;
operator * (A: Double; B: TFactor): Double; inline;
operator * (A: Cardinal; B: TFactor): Cardinal; inline;
function Min(A: TGrowthRate; B: TGrowthRate): TGrowthRate; overload;
function Max(A: TGrowthRate; B: TGrowthRate): TGrowthRate; overload;

type
   TMockClock = class(TRootClock)
   private
      FNow: TDateTime;
   public
      constructor Create(); override;
      procedure Advance(Duration: TMillisecondsDuration);
      function Now(): TDateTime; override;
   end;

implementation

uses
   dateutils, math, sysutils, exceptions, stringutils;

// inline functions should be first

constructor TMillisecondsDuration.FromMilliseconds(A: Double);
begin
   Assert(not IsNaN(A));
   if (A > High(Value)) then // including +Infinity
   begin
      Value := High(Value);
   end
   else
   if (A < Low(Value)) then // including -Infinity
   begin
      Value := Low(Value);
   end
   else
   begin
      Value := Round(A);
      // we want all values to be negatable, so one value on the negative side has to be considered taboo
      Assert(Value <> Low(Value) + 1); // won't happen, because Double can't represent this value
   end;
end;

constructor TMillisecondsDuration.FromMilliseconds(A: Int64);
begin
   if (A = Low(Value) + 1) then
      Value := Low(Value)
   else
      Value := A;
end;

constructor TMillisecondsDuration.FromWeeks(A: Int64);
begin
   Value := A * 7 * 24 * 60 * 60 * 1000; // $R-
end;

function TMillisecondsDuration.GetIsZero(): Boolean;
begin
   Result := Value = 0;
end;

function TMillisecondsDuration.GetIsNotZero(): Boolean;
begin
   Result := Value <> 0;
end;

function TMillisecondsDuration.GetIsNegative(): Boolean;
begin
   Result := Value < 0;
end;

function TMillisecondsDuration.GetIsPositive(): Boolean;
begin
   Result := Value > 0;
end;

function TMillisecondsDuration.GetIsFinite(): Boolean;
begin
   Result := (Value <> High(Value)) and (Value <> Low(Value));
end;

function TMillisecondsDuration.GetIsInfinite(): Boolean;
begin
   Result := (Value = High(Value)) or (Value = Low(Value));
end;

class function TMillisecondsDuration.GetNegInfinity(): TMillisecondsDuration;
begin
   Result := TMillisecondsDuration.FromMilliseconds(Low(Int64));
end;

class function TMillisecondsDuration.GetInfinity(): TMillisecondsDuration;
begin
   Result := TMillisecondsDuration.FromMilliseconds(High(Int64));
end;

class function TMillisecondsDuration.GetZero(): TMillisecondsDuration;
begin
   Result := TMillisecondsDuration.FromMilliseconds(0);
end;

function TMillisecondsDuration.ToString(): UTF8String;
var
   Scaled, Days: Double;
begin
   if (Value = Low(Value)) then
   begin
      Result := '-∞';
   end
   else
   if (Value = High(Value)) then
   begin
      Result := '∞';
   end
   else
   if (Value < 0) then
   begin
      Result := '-' + (-Self).ToString();
   end
   else
   if (Value = 0) then
   begin
      Result := '0';
   end
   else
   if (Value < 10000) then
   begin
      Result := IntToStr(Value) + 'ms';
   end
   else
   begin
      Scaled := Value / 1000;
      if (Scaled < 121) then
      begin
         Result := IntToStr(Round(Scaled)) + 's';
      end
      else
      begin
         Scaled := Scaled / 60;
         if (Scaled < 91) then
         begin
            Result := IntToStr(Round(Scaled)) + 'min';
         end
         else
         begin
            Scaled := Scaled / 60;
            if (Scaled < 25) then
            begin
               Result := IntToStr(Round(Scaled)) + 'h';
            end
            else
            begin
               Days := Scaled / 24;
               if (Days < 7) then
               begin
                  Result := IntToStr(Round(Days)) + 'd';
               end
               else
               begin
                  Scaled := Days / 7;
                  if (Scaled < 53) then
                  begin
                     Result := IntToStr(Round(Scaled)) + 'w';
                  end
                  else
                  begin
                     Scaled := Days / 365;
                     Result := IntToStr(Round(Scaled)) + 'y';
                  end;
               end;
            end;
         end;
      end;
   end;
end;

function TMillisecondsDuration.ToSIUnits(): Double;
begin
   if (Value = Low(Value)) then
   begin
      {$PUSH}
      {$IEEEERRORS OFF}
      Result := math.NegInfinity;
      {$POP}
   end
   else
   if (Value = High(Value)) then
   begin
      {$PUSH}
      {$IEEEERRORS OFF}
      Result := math.Infinity;
      {$POP}
   end
   else
   begin
      Result := Value / 1000.0;
   end;
end;

function TMillisecondsDuration.Scale(Factor: Double): TMillisecondsDuration;
var
   Temp: Double;
begin
   if (Factor = 0) then
   begin
      Result.Value := 0;
      exit;
   end;
   if (IsInfinite) then
   begin
      if (Factor > 0) then
      begin
         Result.Value := Value;
      end
      else // must negate result; can't just use `-` because -Low(Value) = Low(Value) and -High(Value) > Low(Value)
      if (Value = High(Value)) then
      begin
         Result.Value := Low(Value);
      end
      else
      begin
         Result.Value := High(Value);
      end;
      exit;
   end;
   Temp := Value * Factor;
   if (Temp <= Low(Result.Value)) then
   begin
      Result.Value := Low(Result.Value);
   end
   else
   if (Temp >= High(Result.Value)) then
   begin
      Result.Value := High(Result.Value);
   end
   else
   begin
      Result.Value := Round(Temp);
      Assert(Result.Value <> Low(Result.Value) + 1); // see constructor
   end;
end;

operator + (A: TMillisecondsDuration; B: TMillisecondsDuration): TMillisecondsDuration;
begin
   if (A.IsInfinite) then
   begin
      Result := A;
   end
   else
   if (B.IsInfinite) then
   begin
      Result := B;
   end
   else
   begin
      Result.Value := A.Value + B.Value;
      {$IFOPT Q+}
      if ((Result.Value <= Low(Result.Value) + 1) or
          (Result.Value >= High(Result.Value))) then
         raise EIntOverflow.Create('Overflow');
      {$ENDIF}
   end;
end;

operator - (A: TMillisecondsDuration; B: TMillisecondsDuration): TMillisecondsDuration;
begin
   if (A.IsInfinite) then
   begin
      Result := A;
   end
   else
   if (B.IsInfinite) then
   begin
      Result := B;
   end
   else
   begin
      Result.Value := A.Value - B.Value;
      {$IFOPT Q+}
      if ((Result.Value <= Low(Result.Value) + 1) or
          (Result.Value >= High(Result.Value))) then
         raise EIntOverflow.Create('Overflow');
      {$ENDIF}
   end;
end;

operator - (A: TMillisecondsDuration): TMillisecondsDuration;
begin
   if (A.Value = Low(A.Value)) then
   begin
      Result.Value := High(Result.Value);
   end
   else
   if (A.Value = High(A.Value)) then
   begin
      Result.Value := Low(Result.Value);
   end
   else
   begin
      Assert(A.Value <> Low(A.Value) + 1);
      Result.Value := -A.Value;
   end;
end;

operator mod (A: TMillisecondsDuration; B: TMillisecondsDuration): TMillisecondsDuration;
begin
   {$IFOPT Q+}
   if (A.IsInfinite or B.IsInfinite) then
      raise EIntOverflow.Create('Overflow');
   {$ENDIF}
   Result.Value := A.Value mod B.Value;
end;

operator * (A: TMillisecondsDuration; B: Double): TMillisecondsDuration;
begin
   if (A.IsInfinite) then
   begin
      if (B = 0.0) then
      begin
         Result.Value := 0
      end
      else
      if (B < 0.0) then
      begin
         Result.Value := -A.Value;
      end
      else
      begin
         Result.Value := A.Value;
      end;
   end
   else // TODO: what if B is infinite or NaN
      Result.Value := Round(A.Value * B);
end;

operator / (A: TMillisecondsDuration; B: TMillisecondsDuration): Double;
begin
   Assert(A.IsFinite);
   Assert(B.IsFinite);
   Result := A.Value / B.Value;
end;

operator / (A: TMillisecondsDuration; B: Double): TMillisecondsDuration;
begin
   Assert(A.IsFinite);
   Assert(B <> 0.0);
   // TODO: what if B is infinite or NaN
   Result.Value := Round(A.Value / B);
end;

operator = (A: TMillisecondsDuration; B: TMillisecondsDuration): Boolean;
begin
   Result := A.Value = B.Value;
end;

operator < (A: TMillisecondsDuration; B: TMillisecondsDuration): Boolean;
begin
   Result := A.Value < B.Value;
end;

operator <= (A: TMillisecondsDuration; B: TMillisecondsDuration): Boolean;
begin
   Result := A.Value <= B.Value;
end;

operator > (A: TMillisecondsDuration; B: TMillisecondsDuration): Boolean;
begin
   Result := A.Value > B.Value;
end;

operator >= (A: TMillisecondsDuration; B: TMillisecondsDuration): Boolean;
begin
   Result := A.Value >= B.Value;
end;


constructor TTimeInMilliseconds.FromMilliseconds(A: Double);
begin
   Assert(not IsNaN(A));
   if (A > High(Value)) then // including +Infinity
   begin
      Value := High(Value);
   end
   else
   if (A < Low(Value)) then // including -Infinity
   begin
      Value := Low(Value);
   end
   else
   begin
      Value := Round(A);
   end;
end;

constructor TTimeInMilliseconds.FromMilliseconds(A: Int64);
begin
   Value := A;
end;

constructor TTimeInMilliseconds.FromDurationSinceOrigin(A: TMillisecondsDuration);
begin
   Value := A.Value;
end;

function TTimeInMilliseconds.ToString(): UTF8String;
begin
   if (Value = Low(Value)) then
   begin
      Result := '-∞';
   end
   else
   if (Value = High(Value)) then
   begin
      Result := '∞';
   end
   else
   begin
      Result := 'T=' + IntToStr(Value) + 'ms';
   end;
end;

function TTimeInMilliseconds.GetIsInfinite(): Boolean;
begin
   Result := (Value = High(Value)) or (Value = Low(Value));
end;

class function TTimeInMilliseconds.GetNegInfinity(): TTimeInMilliseconds;
begin
   Result := TTimeInMilliseconds.FromMilliseconds(Low(Int64));
end;

class function TTimeInMilliseconds.GetInfinity(): TTimeInMilliseconds;
begin
   Result := TTimeInMilliseconds.FromMilliseconds(High(Int64));
end;

{$IFOPT C+}
class function TTimeInMilliseconds.GetZero(): TTimeInMilliseconds;
begin
   Result := TTimeInMilliseconds.FromMilliseconds(0);
end;
{$ENDIF}

operator - (A: TTimeInMilliseconds; B: TTimeInMilliseconds): TMillisecondsDuration;
begin
   Assert(not A.IsInfinite);
   Assert(not B.IsInfinite);
   Result.Value := A.Value - B.Value;
end;

operator = (A: TTimeInMilliseconds; B: TTimeInMilliseconds): Boolean;
begin
   Assert(not A.IsInfinite);
   Assert(not B.IsInfinite);
   Result := A.Value = B.Value;
end;

operator < (A: TTimeInMilliseconds; B: TTimeInMilliseconds): Boolean;
begin
   Result := A.Value < B.Value;
end;

operator <= (A: TTimeInMilliseconds; B: TTimeInMilliseconds): Boolean;
begin
   Result := A.Value <= B.Value;
end;

operator > (A: TTimeInMilliseconds; B: TTimeInMilliseconds): Boolean;
begin
   Result := A.Value > B.Value;
end;

operator >= (A: TTimeInMilliseconds; B: TTimeInMilliseconds): Boolean;
begin
   Result := A.Value >= B.Value;
end;

operator + (A: TTimeInMilliseconds; B: TMillisecondsDuration): TTimeInMilliseconds;
begin
   Assert(not A.IsInfinite);
   Assert(not B.IsInfinite);
   Result.Value := A.Value + B.Value;
end;

operator - (A: TTimeInMilliseconds; B: TMillisecondsDuration): TTimeInMilliseconds;
begin
   Assert(not A.IsInfinite);
   Assert(not B.IsInfinite);
   Result.Value := A.Value - B.Value;
end;

function Min(A: TTimeInMilliseconds; B: TTimeInMilliseconds): TTimeInMilliseconds;
begin
   if (A < B) then
   begin
      Result := A;
   end
   else
   begin
      Result := B;
   end;
end;

function Max(A: TTimeInMilliseconds; B: TTimeInMilliseconds): TTimeInMilliseconds;
begin
   if (A > B) then
   begin
      Result := A;
   end
   else
   begin
      Result := B;
   end;
end;


constructor TWallMillisecondsDuration.FromMilliseconds(A: Double);
begin
   Assert(not IsNaN(A));
   Assert(A <= High(Value));
   Assert(A >= Low(Value));
   Value := Round(A);
end;

constructor TWallMillisecondsDuration.FromDateTimes(A, B: TDateTime);
begin
   Value := MillisecondsBetween(A, B);
end;

function TWallMillisecondsDuration.ToString(): UTF8String;
begin
   Result := IntToStr(Value) + 'ms';
end;

constructor TWallMillisecondsDuration.FromMilliseconds(A: Int64);
begin
   Value := A;
end;


operator div (A: TMillisecondsDuration; B: TTimeFactor): TWallMillisecondsDuration;
begin
   Assert(not A.IsInfinite);
   Result.Value := Round(A.Value / B.Value);
end;


constructor TTimeFactor.FromFactor(A: Double);
begin
   Value := A;
end;

function TTimeFactor.ToString(): UTF8String;
begin
   Result := 'x' + FloatToStrF(Value, ffFixed, 0, 1, FloatFormat);
end;


operator + (A: TDateTime; B: TWallMillisecondsDuration): TDateTime;
begin
   Result := IncMillisecond(A, B.Value);
end;

operator * (A: TWallMillisecondsDuration; B: TTimeFactor): TMillisecondsDuration;
begin
   Result.Value := Round(A.Value * B.Value);
end;


constructor TRate.FromPerSecond(A: Double);
begin
   Value := A * 1000.0;
end;

constructor TRate.FromPerMillisecond(A: Double);
begin
   Value := A;
end;

procedure TRate.Reset(NewValue: Double);
begin
   Value := NewValue;
end;

function TRate.GetIsExactZero(): Boolean;
begin
   Result := Value = 0.0;
end;

{$IFOPT C+}
function TRate.GetIsNearZero(): Boolean;
begin
   Result := Abs(Value) < 0.00000001; // TODO: this is completely arbitrary
end;
{$ENDIF}

{$IFOPT C+}
function TRate.GetIsNotNearZero(): Boolean;
begin
   Result := Abs(Value) >= 0.00000001; // TODO: this is completely arbitrary
end;
{$ENDIF}

function TRate.GetIsNotExactZero(): Boolean;
begin
   Result := Value <> 0.0;
end;

function TRate.GetIsPositive(): Boolean;
begin
   Result := Value > 0.0;
end;

function TRate.GetIsNegative(): Boolean;
begin
   Result := Value < 0.0;
end;

function TRate.GetIsFinite(): Boolean;
begin
   Result := not math.IsInfinite(Value);
end;

function TRate.GetIsInfinite(): Boolean;
begin
   Result := math.IsInfinite(Value);
end;

function TRate.ToString(NumeratorUnit: UTF8String): UTF8String;
begin
   if (Value = 0.0) then
   begin
      Result := 'nil';
   end
   else
   begin
      if (Length(NumeratorUnit) > 2) then
         NumeratorUnit := ' ' + NumeratorUnit;
      if (Value < 0.0001 / (60.0 * 60.0 * 1000.0)) then
      begin
         Result := FloatToStrF(Value * 60.0 * 60.0 * 1000.0, ffFixed, 0, 15, FloatFormat) + NumeratorUnit + '/h';
      end
      else
      if (Value < 0.1 / (60.0 * 60.0 * 1000.0)) then
      begin
         Result := FloatToStrF(Value * 60.0 * 60.0 * 1000.0, ffFixed, 0, 55, FloatFormat) + NumeratorUnit + '/h';
      end
      else
      begin
         Result := FloatToStrF(Value * 60.0 * 60.0 * 1000.0, ffFixed, 0, 15, FloatFormat) + NumeratorUnit + '/h';
      end;
   end;
end;


function ApplyIncrementally(Rate: TRate; Time: TMillisecondsDuration; var Fraction: Fraction32): Int64;
var
   Amount: Double;
begin
   Amount := Rate.Value * Time.Value;
   Result := Trunc(Amount) + Round(Fraction.Increment(Frac(Amount))); // $R-
end;

function ApplyIncrementally(Rate: TQuantityRate; Time: TMillisecondsDuration; var Fraction: Fraction32): TQuantity64;
var
   Amount: Double;
begin
   Amount := Rate.Value * Time.Value;
   Result := TQuantity64.FromUnits(TruncUInt64(Amount) + Round(Fraction.Increment(Frac(Amount)))); // $R-
end;

function ApplyIncrementally(Rate: TMassRate; Time: TMillisecondsDuration; var Fraction: Fraction32): TMass;
var
   Amount: Double;
begin
   Amount := Rate.Value * Time.Value;
   Result := TMass.FromKg(Trunc(Amount) + Fraction.Increment(Frac(Amount))); // $R-
end;


class function TRateConstants.GetInfinity(): TRate;
begin
   {$PUSH}
   {$IEEEERRORS OFF}
   Result.Value := math.Infinity;
   {$POP}
end;

class function TRateConstants.GetZero(): TRate;
begin
   Result.Value := 0.0;
end;

operator + (A: TRate; B: TRate): TRate;
begin
   Result.Value := A.Value + B.Value;
end;

operator - (A: TRate; B: TRate): TRate;
begin
   Result.Value := A.Value - B.Value;
end;

operator - (A: TRate): TRate;
begin
   Result.Value := -A.Value;
end;

operator * (A: TRate; B: Double): TRate;
begin
   Result.Value := A.Value * B;
end;

operator / (A: TRate; B: TRate): Double;
begin
   Result := A.Value / B.Value;
end;

operator / (A: TRate; B: Double): TRate;
begin
   Result.Value := A.Value / B;
end;

operator = (A: TRate; B: TRate): Boolean;
begin
   Result := A.Value = B.Value;
end;

operator < (A: TRate; B: TRate): Boolean;
begin
   Result := A.Value < B.Value;
end;

operator <= (A: TRate; B: TRate): Boolean;
begin
   Result := A.Value <= B.Value;
end;

operator > (A: TRate; B: TRate): Boolean;
begin
   Result := A.Value > B.Value;
end;

operator >= (A: TRate; B: TRate): Boolean;
begin
   Result := A.Value >= B.Value;
end;

function Min(A: TRate; B: TRate): TRate;
begin
   if (A < B) then
   begin
      Result := A;
   end
   else
   begin
      Result := B;
   end;
end;


class function TRateConstants.GetMInfinity(): TMassRate;
begin
   {$PUSH}
   {$IEEEERRORS OFF}
   Result.Value := math.Infinity;
   {$POP}
end;

class function TRateConstants.GetMZero(): TMassRate;
begin
   Result.Value := 0.0;
end;

operator + (A: TMassRate; B: TMassRate): TMassRate;
begin
   Result.Value := A.Value + B.Value;
end;

operator - (A: TMassRate; B: TMassRate): TMassRate;
begin
   Result.Value := A.Value - B.Value;
end;

operator - (A: TMassRate): TMassRate;
begin
   Result.Value := -A.Value;
end;

operator * (A: TMassRate; B: Double): TMassRate;
begin
   Result.Value := A.Value * B;
end;

operator / (A: TMassRate; B: TMassRate): Double;
begin
   Result := A.Value / B.Value;
end;

operator / (A: TMassRate; B: Double): TMassRate;
begin
   Result.Value := A.Value / B;
end;

operator / (A: TMassRate; B: TMass): TRate;
begin
   Result.Value := A.Value / B.AsDouble;
end;

operator = (A: TMassRate; B: TMassRate): Boolean;
begin
   Result := A.Value = B.Value;
end;

operator < (A: TMassRate; B: TMassRate): Boolean;
begin
   Result := A.Value < B.Value;
end;

operator <= (A: TMassRate; B: TMassRate): Boolean;
begin
   Result := A.Value <= B.Value;
end;

operator > (A: TMassRate; B: TMassRate): Boolean;
begin
   Result := A.Value > B.Value;
end;

operator >= (A: TMassRate; B: TMassRate): Boolean;
begin
   Result := A.Value >= B.Value;
end;

function Min(A: TMassRate; B: TMassRate): TMassRate;
begin
   if (A < B) then
   begin
      Result := A;
   end
   else
   begin
      Result := B;
   end;
end;


class function TRateConstants.GetQInfinity(): TQuantityRate;
begin
   {$PUSH}
   {$IEEEERRORS OFF}
   Result.Value := math.Infinity;
   {$POP}
end;

class function TRateConstants.GetQZero(): TQuantityRate;
begin
   Result.Value := 0.0;
end;

operator + (A: TQuantityRate; B: TQuantityRate): TQuantityRate;
begin
   Result.Value := A.Value + B.Value;
end;

operator - (A: TQuantityRate; B: TQuantityRate): TQuantityRate;
begin
   Result.Value := A.Value - B.Value;
end;

operator - (A: TQuantityRate): TQuantityRate;
begin
   Result.Value := -A.Value;
end;

operator * (A: TQuantityRate; B: Double): TQuantityRate;
begin
   Result.Value := A.Value * B;
end;

operator / (A: TQuantityRate; B: TQuantityRate): Double;
begin
   Result := A.Value / B.Value;
end;

operator / (A: TQuantityRate; B: Double): TQuantityRate;
begin
   Result.Value := A.Value / B;
end;

operator / (A: TQuantityRate; B: TQuantity64): TRate;
begin
   Result.Value := A.Value / B.AsInt64;
end;

operator / (A: TQuantityRate; B: TQuantity32): TRate;
begin
   Result.Value := A.Value / B.AsCardinal;
end;

operator = (A: TQuantityRate; B: TQuantityRate): Boolean;
begin
   Result := A.Value = B.Value;
end;

operator < (A: TQuantityRate; B: TQuantityRate): Boolean;
begin
   Result := A.Value < B.Value;
end;

operator <= (A: TQuantityRate; B: TQuantityRate): Boolean;
begin
   Result := A.Value <= B.Value;
end;

operator > (A: TQuantityRate; B: TQuantityRate): Boolean;
begin
   Result := A.Value > B.Value;
end;

operator >= (A: TQuantityRate; B: TQuantityRate): Boolean;
begin
   Result := A.Value >= B.Value;
end;

function Min(A: TQuantityRate; B: TQuantityRate): TQuantityRate;
begin
   if (A < B) then
   begin
      Result := A;
   end
   else
   begin
      Result := B;
   end;
end;


operator * (A: TMillisecondsDuration; B: TRate): Double;
begin
   if (A.IsInfinite) then
   begin
      {$PUSH}
      {$IEEEERRORS OFF}
      if (B.IsExactZero) then
      begin
         Result := 0.0;
      end
      else
      if (A.IsPositive = B.IsPositive) then
      begin
         Result := Infinity;
      end
      else
      begin
         Result := NegInfinity;
      end;
      {$POP}
   end
   else
      Result := A.Value * B.Value;
end;

operator * (A: TMillisecondsDuration; B: TMassRate): TMass;
begin
   if (A.IsInfinite) then
   begin
      if (B.IsExactZero) then
      begin
         Result := TMass.Zero;
      end
      else
      if (A.IsPositive = B.IsPositive) then
      begin
         Result := TMass.Infinity;
      end
      else
      begin
         raise ERangeError.Create('Negative mass unsupported');
      end;
   end
   else
      Result := TMass.FromKg(A.Value * B.Value);
end;

operator * (A: TMillisecondsDuration; B: TQuantityRate): TQuantity64;
begin
   if (A.IsInfinite) then
   begin
      if (B.IsExactZero) then
      begin
         Result := TQuantity64.Zero;
      end
      else
      begin
         raise ERangeError.Create('Infinite quantities unsupported');
      end;
   end
   else
      Result := TQuantity64.FromUnits(Round(A.Value * B.Value));
end;


operator * (A: TQuantity64; B: TRate): TQuantityRate;
begin
   Result.Value := A.AsInt64 * B.Value;
end;
   
operator * (A: TQuantityRate; B: TMassPerUnit): TMassRate;
begin
   Result.Value := A.Value * B.AsDouble;
end;



operator / (A: Double; B: TRate): TMillisecondsDuration;
begin
   Result := TMillisecondsDuration.FromMilliseconds(A / B.Value);
end;

operator / (A: TMassRate; B: TMassPerUnit): TQuantityRate;
begin
   Result.Value := A.Value / B.AsDouble;
end;

operator / (A: TQuantity64; B: TQuantityRate): TMillisecondsDuration;
begin
   Result := TMillisecondsDuration.FromMilliseconds(A.AsInt64 / B.Value);
end;

operator / (A: TQuantity32; B: TQuantityRate): TMillisecondsDuration;
begin
   Result := TMillisecondsDuration.FromMilliseconds(A.AsCardinal / B.Value);
end;


operator / (A: TMass; B: TMassRate): TMillisecondsDuration;
begin
   Result := TMillisecondsDuration.FromMilliseconds(A.AsDouble / B.Value);
end;


operator / (A: Double; B: TMillisecondsDuration): TRate;
begin
   Result.Value := A / B.Value;
end;

operator / (A: TMass; B: TMillisecondsDuration): TMassRate;
begin
   Result.Value := A.ToSIUnits() / B.Value;
end;

operator / (A: TQuantity64; B: TMillisecondsDuration): TQuantityRate;
begin
   Result.Value := A.AsInt64 / B.Value;
end;

operator / (A: TQuantity32; B: TMillisecondsDuration): TQuantityRate;
begin
   Result.Value := A.AsCardinal / B.Value;
end;


class operator TQuantityRateSum.Initialize(var Rec: TQuantityRateSum);
begin
   Rec.Value.Reset();
end;

function TQuantityRateSum.ToQuantityRate(): TQuantityRate;
begin
   Result.Value := Value.ToDouble();
end;

function TQuantityRateSum.ToDouble(): Double;
begin
   Result := Value.ToDouble();
end;

procedure TQuantityRateSum.Reset();
begin
   Value.Reset();
end;

function TQuantityRateSum.GetIsZero(): Boolean;
begin
   Result := Value.IsZero;
end;

function TQuantityRateSum.GetIsNotZero(): Boolean;
begin
   Result := Value.IsNotZero;
end;

function TQuantityRateSum.GetIsNegative(): Boolean;
begin
   Result := Value.IsNegative;
end;

function TQuantityRateSum.GetIsPositive(): Boolean;
begin
   Result := Value.IsPositive;
end;

procedure TQuantityRateSum.Inc(Delta: TQuantityRate);
begin
   Value.Inc(Delta.AsDouble);
end;

procedure TQuantityRateSum.Dec(Delta: TQuantityRate);
begin
   Value.Dec(Delta.AsDouble);
end;

procedure TQuantityRateSum.Inc(Delta: TQuantityRateSum);
begin
   Value.Inc(Delta.Value);
end;

procedure TQuantityRateSum.Dec(Delta: TQuantityRateSum);
begin
   Value.Dec(Delta.Value);
end;

class operator TQuantityRateSum.Copy(constref Source: TQuantityRateSum; var Destination: TQuantityRateSum);
begin
   Destination.Value := Source.Value;
end;

function TQuantityRateSum.ToString(): UTF8String;
begin
   Result := ToQuantityRate.ToString('units');
end;

class operator TQuantityRateSum.< (A, B: TQuantityRateSum): Boolean;
begin
   Result := A.Value < B.Value;
end;

class operator TQuantityRateSum.> (A, B: TQuantityRateSum): Boolean;
begin
   Result := A.Value > B.Value;
end;

class operator TQuantityRateSum.<= (A, B: TQuantityRateSum): Boolean;
begin
   Result := A.Value <= B.Value;
end;

class operator TQuantityRateSum.>= (A, B: TQuantityRateSum): Boolean;
begin
   Result := A.Value >= B.Value;
end;

class operator TQuantityRateSum.- (A, B: TQuantityRateSum): TQuantityRateSum;
begin
   Result.Value.Reset();
   Result.Value.Inc(A.Value);
   Result.Value.Dec(B.Value);
end;

   
constructor TGrowthRate.FromEachMillisecond(A: Double);
begin
   Assert(A >= 0.0, 'Negative growth rate: ' + FloatToStr(A));
   Value := A;
   Assert(Value >= 0.0);
end;

constructor TGrowthRate.FromEachWeek(A: Double);
begin
   Assert(A >= 0.0);
   Value := Power(A, 1.0 / (7 * 24 * 60 * 60 * 1000)); // $R-
   Assert(Value >= 0.0);
end;

constructor TGrowthRate.FromDoublingTimeInMilliseconds(A: Double);
begin
   Assert(A >= 0.0);
   Value := Power(2, 1 / A); // $R-
   Assert(Value >= 0.0);
end;
   
constructor TGrowthRate.FromDoublingTimeInWeeks(A: Double);
begin
   Assert(A >= 0.0);
   Value := Power(2, 1 / (A * 7 * 24 * 60 * 60 * 1000)); // $R-
   Assert(Value >= 0.0);
end;
   
operator ** (A: TGrowthRate; B: TMillisecondsDuration): TFactor;
begin
   try
      Result.Value := Power(A.Value, Double(B.Value)); // $R-
   except
      Writeln('A: ', A.Value:0:15);
      Writeln('B: ', B.ToString());
      ReportCurrentException();
      Result.Value := 0.0;
   end;
   Assert(Result.Value >= 0.0);
end;

operator * (A: Double; B: TFactor): Double;
begin
   Result := A * B.Value;
end;

operator * (A: Cardinal; B: TFactor): Cardinal;
var
   Temp: Double;
begin
   Temp := Double(A) * B.Value;
   if (Temp > High(Result)) then
   begin
      Result := High(Result);
   end
   else
   begin
      Temp := Round(Result);
   end;
end;

function Min(A: TGrowthRate; B: TGrowthRate): TGrowthRate;
begin
   if (A.Value < B.Value) then
   begin
      Result.Value := A.Value;
   end
   else
   begin
      Result.Value := B.Value;
   end;
   Assert(Result.Value >= 0.0);
end;

function Max(A: TGrowthRate; B: TGrowthRate): TGrowthRate;
begin
   if (A.Value > B.Value) then
   begin
      Result.Value := A.Value;
   end
   else
   begin
      Result.Value := B.Value;
   end;
   Assert(Result.Value >= 0.0);
end;


constructor TMockClock.Create();
begin
   FNow := UnixToDateTime(0);
end;

procedure TMockClock.Advance(Duration: TMillisecondsDuration);
begin
   FNow := FNow + Duration.AsInt64 / MSecsPerDay;
end;

function TMockClock.Now(): TDateTime;
begin
   Result := FNow;
end;

end.