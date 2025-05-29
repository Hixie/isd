{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit time;

interface

type
   TMillisecondsDuration = record // solar system milliseconds duration; supports Infinity and -Infinity
   private
      Value: Int64;
      function GetIsZero(): Boolean; inline;
      function GetNegative(): Boolean; inline;
      function GetInfinite(): Boolean; inline;
      class function GetNegInfinity(): TMillisecondsDuration; inline; static;
      class function GetInfinity(): TMillisecondsDuration; inline; static;
   public
      constructor FromMilliseconds(A: Double); overload;
      constructor FromMilliseconds(A: Int64); overload;
      function ToString(): UTF8String;
      function ToSIUnits(): Double; // returns the value in seconds
      function Scale(Factor: Double): TMillisecondsDuration;
      property IsZero: Boolean read GetIsZero;
      property IsNegative: Boolean read GetNegative;
      property IsInfinite: Boolean read GetInfinite;
      property AsInt64: Int64 read Value; // for storage, restore with FromMilliseconds(Int64)
      class property NegInfinity: TMillisecondsDuration read GetNegInfinity;
      class property Infinity: TMillisecondsDuration read GetInfinity;
   end;

   TTimeInMilliseconds = record // solar system absolute time (in milliseconds); supports Infinity and -Infinity
   private
      Value: Int64;
      class function GetNegInfinity(): TTimeInMilliseconds; inline; static;
      class function GetInfinity(): TTimeInMilliseconds; inline; static;
      function GetInfinite(): Boolean; inline;
   public
      constructor FromMilliseconds(A: Double); overload;
      constructor FromMilliseconds(A: Int64); overload;
      function ToString(): UTF8String;
      property AsInt64: Int64 read Value; // for storage, restore with FromMilliseconds(Int64)
      property IsInfinite: Boolean read GetInfinite;
      class property NegInfinity: TTimeInMilliseconds read GetNegInfinity;
      class property Infinity: TTimeInMilliseconds read GetInfinity;
   end;

   TWallMillisecondsDuration = record // wall-clock time duration in milliseconds (must be finite)
   private
      Value: Int64;
   public
      constructor FromMilliseconds(A: Double); overload;
      constructor FromMilliseconds(A: Int64); overload;
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
   public
      constructor FromPerSecond(A: Double);
      constructor FromPerMillisecond(A: Double);
      function ToString(NumeratorUnit: UTF8String = ''): UTF8String;
      property IsZero: Boolean read GetIsZero;
      property AsDouble: Double read Value; // for storage, restore with FromMilliseconds(Double)
   end;

operator + (A: TMillisecondsDuration; B: TMillisecondsDuration): TMillisecondsDuration; inline;
operator - (A: TMillisecondsDuration; B: TMillisecondsDuration): TMillisecondsDuration; inline;
operator mod (A: TMillisecondsDuration; B: TMillisecondsDuration): TMillisecondsDuration; inline;
operator * (A: TMillisecondsDuration; B: TRate): Double; inline;
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

operator div (A: TMillisecondsDuration; B: TTimeFactor): TWallMillisecondsDuration; inline;

operator + (A: TDateTime; B: TWallMillisecondsDuration): TDateTime; inline;
operator * (A: TWallMillisecondsDuration; B: TTimeFactor): TMillisecondsDuration; inline;

operator + (A: TRate; B: TRate): TRate; inline;
operator - (A: TRate; B: TRate): TRate; inline;
operator * (A: TRate; B: Double): TRate; inline;
operator / (A: Double; B: TRate): TMillisecondsDuration; inline;
operator / (A: TRate; B: TRate): Double; inline;
operator = (A: TRate; B: TRate): Boolean; inline;
operator < (A: TRate; B: TRate): Boolean; inline;
operator <= (A: TRate; B: TRate): Boolean; inline;
operator > (A: TRate; B: TRate): Boolean; inline;
operator >= (A: TRate; B: TRate): Boolean; inline;

implementation

uses
   dateutils, math, sysutils;

const FloatFormat: TFormatSettings = (
   CurrencyFormat: 1;
   NegCurrFormat: 1;
   ThousandSeparator: ',';
   DecimalSeparator: '.';
   CurrencyDecimals: 2;
   DateSeparator: '-';
   TimeSeparator: ':';
   ListSeparator: ',';
   CurrencyString: '$';
   ShortDateFormat: 'yyyy-mm-dd';
   LongDateFormat: 'dd" "mmmm" "yyyy';
   TimeAMString: 'AM';
   TimePMString: 'PM';
   ShortTimeFormat: 'hh:nn';
   LongTimeFormat: 'hh:nn:ss';
   ShortMonthNames: ('Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec');
   LongMonthNames: ('January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December');
   ShortDayNames: ('Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat');
   LongDayNames: ('Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday');
   TwoDigitYearCenturyWindow: 50
);

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
   end;
end;

constructor TMillisecondsDuration.FromMilliseconds(A: Int64);
begin
   Value := A;
end;

function TMillisecondsDuration.GetIsZero(): Boolean;
begin
   Result := Value = 0;
end;

function TMillisecondsDuration.GetNegative(): Boolean;
begin
   Result := Value < 0;
end;

function TMillisecondsDuration.GetInfinite(): Boolean;
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
   end;
end;

operator + (A: TMillisecondsDuration; B: TMillisecondsDuration): TMillisecondsDuration;
begin
   Result.Value := A.Value + B.Value;
end;

operator - (A: TMillisecondsDuration; B: TMillisecondsDuration): TMillisecondsDuration;
begin
   Result.Value := A.Value - B.Value;
end;

operator mod (A: TMillisecondsDuration; B: TMillisecondsDuration): TMillisecondsDuration;
begin
   Result.Value := A.Value mod B.Value;
end;

operator * (A: TMillisecondsDuration; B: TRate): Double;
begin
   Result := A.Value * B.Value;
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

function TTimeInMilliseconds.GetInfinite(): Boolean;
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


constructor TWallMillisecondsDuration.FromMilliseconds(A: Double);
begin
   Assert(not IsNaN(A));
   Assert(A <= High(Value));
   Assert(A >= Low(Value));
   Value := Round(A);
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

function TRate.ToString(NumeratorUnit: UTF8String = ''): UTF8String;
begin
   Result := FloatToStrF(Value * 1000.0, ffFixed, 0, 1, FloatFormat) + NumeratorUnit + '/s';
end;

operator + (A: TRate; B: TRate): TRate;
begin
   Result.Value := A.Value + B.Value;
end;

operator - (A: TRate; B: TRate): TRate;
begin
   Result.Value := A.Value - B.Value;
end;

operator * (A: TRate; B: Double): TRate;
begin
   Result.Value := A.Value * B;
end;

operator / (A: Double; B: TRate): TMillisecondsDuration;
begin
   Result := TMillisecondsDuration.FromMilliseconds(A / B.Value); // TODO: should this use div?
end;

operator / (A: TRate; B: TRate): Double;
begin
   Result := A.Value / B.Value;
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

end.