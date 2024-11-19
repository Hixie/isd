{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit time;

interface

type
   TMillisecondsDuration = record // solar system milliseconds duration
   private
      Value: Int64;
   public
      function ToString(): UTF8String;
      function ToSIUnits(): Double; // returns the value in seconds
      function Scale(Factor: Double): TMillisecondsDuration;
   end;

   TTimeInMilliseconds = record // solar system absolute time (in milliseconds)
   private
      Value: Int64;
   public
      property AsInt64: Int64 read Value;
   end;

   TWallMillisecondsDuration = record // wall-clock time duration in milliseconds
   private
      Value: Int64;
   public
      function ToString(): UTF8String;
   end;

   TTimeFactor = record // wall clock time to solar system time
   private
      Value: Double;
   public
      property AsDouble: Double read Value;
   end;

operator explicit (A: Double): TMillisecondsDuration;
operator explicit (A: Int64): TMillisecondsDuration; inline;
operator + (A: TMillisecondsDuration; B: TMillisecondsDuration): TMillisecondsDuration; inline;
operator - (A: TMillisecondsDuration; B: TMillisecondsDuration): TMillisecondsDuration; inline;
operator mod (A: TMillisecondsDuration; B: TMillisecondsDuration): TMillisecondsDuration; inline;

operator explicit (A: Int64): TTimeInMilliseconds;
operator - (A: TTimeInMilliseconds; B: TTimeInMilliseconds): TMillisecondsDuration; inline;
operator < (A: TTimeInMilliseconds; B: TTimeInMilliseconds): Boolean; inline;
operator <= (A: TTimeInMilliseconds; B: TTimeInMilliseconds): Boolean; inline;
operator > (A: TTimeInMilliseconds; B: TTimeInMilliseconds): Boolean; inline;
operator >= (A: TTimeInMilliseconds; B: TTimeInMilliseconds): Boolean; inline;

operator + (A: TTimeInMilliseconds; B: TMillisecondsDuration): TTimeInMilliseconds; inline;
operator - (A: TTimeInMilliseconds; B: TMillisecondsDuration): TTimeInMilliseconds; inline;

operator div (A: TMillisecondsDuration; B: TTimeFactor): TWallMillisecondsDuration; inline;
operator explicit (A: Double): TTimeFactor; inline;

operator + (A: TDateTime; B: TWallMillisecondsDuration): TDateTime; inline;
operator * (A: TWallMillisecondsDuration; B: TTimeFactor): TMillisecondsDuration; inline;

implementation

uses
   dateutils, math, sysutils;

function TMillisecondsDuration.ToString(): UTF8String;
begin
   Result := IntToStr(Value) + 'ms';
end;

function TMillisecondsDuration.ToSIUnits(): Double;
begin
   Result := Value / 1000.0;
end;

function TMillisecondsDuration.Scale(Factor: Double): TMillisecondsDuration;
begin
   Result.Value := Round(Value * Factor);
end;

operator explicit (A: Double): TMillisecondsDuration;
begin
   Assert(not IsNaN(A));
   Result.Value := Round(A);
end;

operator explicit (A: Int64): TMillisecondsDuration;
begin
   Result.Value := A;
end;

operator + (A: TTimeInMilliseconds; B: TMillisecondsDuration): TTimeInMilliseconds;
begin
   Result.Value := A.Value + B.Value;
end;

operator - (A: TTimeInMilliseconds; B: TMillisecondsDuration): TTimeInMilliseconds;
begin
   Result.Value := A.Value - B.Value;
end;

operator mod (A: TMillisecondsDuration; B: TMillisecondsDuration): TMillisecondsDuration;
begin
   Result.Value := A.Value mod B.Value;
end;


operator explicit (A: Int64): TTimeInMilliseconds;
begin
   Result.Value := A;
end;

operator - (A: TTimeInMilliseconds; B: TTimeInMilliseconds): TMillisecondsDuration;
begin
   Result.Value := A.Value - B.Value;
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


function TWallMillisecondsDuration.ToString(): UTF8String;
begin
   Result := IntToStr(Value) + 'ms';
end;

operator + (A: TMillisecondsDuration; B: TMillisecondsDuration): TMillisecondsDuration;
begin
   Result.Value := A.Value + B.Value;
end;

operator - (A: TMillisecondsDuration; B: TMillisecondsDuration): TMillisecondsDuration;
begin
   Result.Value := A.Value - B.Value;
end;



operator div (A: TMillisecondsDuration; B: TTimeFactor): TWallMillisecondsDuration;
begin
   Result.Value := Round(A.Value / B.Value);
end;


operator explicit (A: Double): TTimeFactor;
begin
   Result.Value := A;
end;


operator + (A: TDateTime; B: TWallMillisecondsDuration): TDateTime;
begin
   Result := IncMillisecond(A, B.Value);
end;

operator * (A: TWallMillisecondsDuration; B: TTimeFactor): TMillisecondsDuration;
begin
   Result.Value := Round(A.Value * B.Value);
end;

end.