{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit time;

interface

uses
   clock;

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
      function GetIsZero(): Boolean; inline;
      {$IFOPT C+} function GetIsNearZero(): Boolean; inline; {$ENDIF}
      function GetIsNotZero(): Boolean; inline;
      function GetIsPositive(): Boolean; inline;
      function GetIsFinite(): Boolean; inline;
      function GetIsInfinite(): Boolean; inline;
      class function GetInfinity(): TRate; inline; static;
      class function GetZero(): TRate; inline; static;
   public
      constructor FromPerSecond(A: Double);
      constructor FromPerMillisecond(A: Double);
      function ToString(NumeratorUnit: UTF8String = ''): UTF8String;
      property IsZero: Boolean read GetIsZero;
      {$IFOPT C+} property IsNearZero: Boolean read GetIsNearZero; {$ENDIF}
      property IsNotZero: Boolean read GetIsNotZero;
      property IsPositive: Boolean read GetIsPositive; // >0
      property IsFinite: Boolean read GetIsFinite;
      property IsInfinite: Boolean read GetIsInfinite;
      property AsDouble: Double read Value; // for storage, restore with FromMilliseconds(Double)
      class property Zero: TRate read GetZero;
      class property Infinity: TRate read GetInfinity;
   end;

   TGrowthRate = record // used for exponential growth with **
   private
      Value: Double;
   public
      constructor FromEachMillisecond(A: Double); // must be positive
      constructor FromEachWeek(A: Double); // must be positive
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
operator * (A: TMillisecondsDuration; B: TRate): Double; inline;
operator / (A: TMillisecondsDuration; B: TMillisecondsDuration): Double; inline;
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
operator / (A: Double; B: TRate): TMillisecondsDuration; inline;
operator / (A: TRate; B: TRate): Double; inline;
operator / (A: TRate; B: Double): TRate; inline;
operator = (A: TRate; B: TRate): Boolean; inline;
operator < (A: TRate; B: TRate): Boolean; inline;
operator <= (A: TRate; B: TRate): Boolean; inline;
operator > (A: TRate; B: TRate): Boolean; inline;
operator >= (A: TRate; B: TRate): Boolean; inline;
function Min(A: TRate; B: TRate): TRate; overload;

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
   Scaled: Double;
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
               Scaled := Scaled / 24;
               if (Scaled < 7) then
               begin
                  Result := IntToStr(Round(Scaled)) + 'd';
               end
               else
               begin
                  Scaled := Scaled / 7;
                  if (Scaled < 53) then
                  begin
                     Result := IntToStr(Round(Scaled)) + 'w';
                  end
                  else
                  begin
                     Scaled := Scaled / 365.25;
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

operator * (A: TMillisecondsDuration; B: TRate): Double;
begin
   if (A.IsInfinite) then
   begin
      {$PUSH}
      {$IEEEERRORS OFF}
      if (A.Value > 0) then
         Result := Infinity
      else
         Result := NegInfinity;
      {$POP}
   end
   else
      Result := A.Value * B.Value;
end;

operator / (A: TMillisecondsDuration; B: TMillisecondsDuration): Double;
begin
   Assert(A.IsFinite);
   Assert(B.IsFinite);
   Result := A.Value / B.Value;
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

function TRate.GetIsZero(): Boolean;
begin
   Result := Value = 0.0;
end;

{$IFOPT C+}
function TRate.GetIsNearZero(): Boolean;
begin
   Result := Abs(Value) < 0.00000001; // TODO: this is completely arbitrary
end;
{$ENDIF}

function TRate.GetIsNotZero(): Boolean;
begin
   Result := Value <> 0.0;
end;

function TRate.GetIsPositive(): Boolean;
begin
   Result := Value > 0.0;
end;

function TRate.GetIsFinite(): Boolean;
begin
   Result := not math.IsInfinite(Value);
end;

function TRate.GetIsInfinite(): Boolean;
begin
   Result := math.IsInfinite(Value);
end;

function TRate.ToString(NumeratorUnit: UTF8String = ''): UTF8String;
begin
   if (Value = 0.0) then
   begin
      Result := 'nil';
   end
   else
   begin
      if (Value < 0.1 / (60.0 * 60.0 * 1000.0)) then
      begin
         Result := FloatToStrF(Value * 60.0 * 60.0 * 1000.0, ffFixed, 0, 5, FloatFormat) + NumeratorUnit + '/h';
      end
      else
      begin
         Result := FloatToStrF(Value * 60.0 * 60.0 * 1000.0, ffFixed, 0, 1, FloatFormat) + NumeratorUnit + '/h';
      end;
   end;
end;

class function TRate.GetInfinity(): TRate;
begin
   {$PUSH}
   {$IEEEERRORS OFF}
   Result.Value := math.Infinity;
   {$POP}
end;

class function TRate.GetZero(): TRate;
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

operator / (A: Double; B: TRate): TMillisecondsDuration;
begin
   Result := TMillisecondsDuration.FromMilliseconds(A / B.Value);
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


constructor TGrowthRate.FromEachMillisecond(A: Double);
begin
   Assert(A >= 0.0);
   Value := A;
end;

constructor TGrowthRate.FromEachWeek(A: Double);
begin
   Assert(A >= 0.0);
   Value := Power(A, 1.0 / (7 * 24 * 60 * 60 * 1000)); // $R-
end;

operator ** (A: TGrowthRate; B: TMillisecondsDuration): TFactor;
begin
   Result.Value := Power(A.Value, Double(B.Value)); // $R-
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