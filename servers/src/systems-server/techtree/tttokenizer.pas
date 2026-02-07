{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit tttokenizer;

//{$DEFINE VERBOSE}

interface

uses
   sysutils;

type
   EParseError = class(Exception)
   strict private
      FLine, FColumn: Cardinal;
   public
      constructor CreateFmt(const AMessage: UTF8String; const Arguments: array of const; ALine, AColumn: Cardinal);
      property Line: Cardinal read FLine;
      property Column: Cardinal read FColumn;
   end;

type
   TTokenizer = class
   strict private
      type
         TTokenKind = (
            tkPending,
            tkIdentifier, tkString, tkInteger, tkDouble, tkMultiplier,
            tkOpenBrace, tkCloseBrace, tkOpenParenthesis, tkCloseParenthesis,
            tkComma, tkColon, tkSemicolon, tkPercentage, tkAsterisk, tkSlash, tkAt,
            tkEOF
         );
      var
         FBuffer: PByte;
         FSize: QWord;
         FPosition: QWord;
         FLine, FColumn: Cardinal;
         FCurrentKind: TTokenKind;
         FNumericInteger: Int64;
         FNumericDouble: Double;
         FStringValue: UTF8String;
      procedure Tokenize();
      procedure EnsureToken(); inline;
      procedure ExpectToken(ExpectedKind: TTokenKind); inline;
   private
      property Line: Cardinal read FLine;
      property Column: Cardinal read FColumn;
   public
      constructor Create(Buffer: Pointer; Size: QWord);
      destructor Destroy(); override;
      function ReadIdentifier(): UTF8String;
      procedure ReadIdentifier(Keyword: UTF8String);
      function ReadString(const MaxLength: Int64 = High(SizeInt)): UTF8String;
      function ReadNumber(): Int64;
      function ReadDouble(): Double;
      function ReadMultiplier(): Double;
      procedure ReadOpenBrace();
      procedure ReadCloseBrace();
      procedure ReadOpenParenthesis();
      procedure ReadCloseParenthesis();
      procedure ReadComma(); // see also ReadComma in ttparser.pas
      procedure ReadColon();
      procedure ReadSemicolon();
      procedure ReadPercentage();
      procedure ReadAsterisk();
      procedure ReadSlash();
      procedure ReadAt();
      function IsIdentifier(): Boolean;
      function IsIdentifier(Keyword: UTF8String): Boolean;
      function IsString(): Boolean;
      function IsNumber(): Boolean; // integer only
      function IsDouble(): Boolean;
      function IsCloseBrace(): Boolean;
      function IsOpenParenthesis(): Boolean;
      function IsCloseParenthesis(): Boolean;
      function IsComma(): Boolean;
      function IsSemicolon(): Boolean;
      function IsAt(): Boolean;
      function IsEOF(): Boolean;
      procedure Error(const AMessage: UTF8String; const Arguments: array of const);
   end;

implementation

uses
   {$IFDEF VERBOSE} unicode, {$ENDIF}
   typedump, exceptions, rtlutils, plasticarrays, genericutils, math;

constructor EParseError.CreateFmt(const AMessage: UTF8String; const Arguments: array of const; ALine, AColumn: Cardinal);
begin
   inherited CreateFmt(AMessage, Arguments);
   FLine := ALine;
   FColumn := AColumn;
end;


type
   TSegment = record
      Start: Pointer;
      Size: QWord;
      class function From(AString: UTF8String): TSegment; inline; overload; static;
      class function From(AStart, AEnd: Pointer): TSegment; inline; overload; static;
   end;

class function TSegment.From(AString: UTF8String): TSegment;
begin
   {$IFOPT C+} AssertStringIsConstant(AString); {$ENDIF}
   Assert(AString <> '');
   Result.Start := @AString[1];
   Result.Size := Length(AString); // $R-
end;

class function TSegment.From(AStart, AEnd: Pointer): TSegment;
begin
   Assert(AEnd > AStart);
   Result.Start := AStart;
   Result.Size := AEnd - AStart; // $R-
end;


constructor TTokenizer.Create(Buffer: Pointer; Size: QWord);
begin
   inherited Create();
   FBuffer := Buffer;
   FSize := Size;
   FLine := 1;
   FColumn := 1;
   Assert(FPosition = 0);
   Assert(FCurrentKind = tkPending);
end;

destructor TTokenizer.Destroy();
begin
   inherited;
end;

procedure TTokenizer.Tokenize();

   procedure Advance(); inline;
   begin
      Inc(FPosition);
      Inc(FColumn);
   end;

   procedure AdvanceLine(); inline;
   begin
      Inc(FPosition);
      Inc(FLine);
      FColumn := 1;
   end;

   procedure FixStringSegment(StringStart, StringEnd: QWord);
   var
      StringLength: QWord;
   begin
      StringLength := StringEnd - StringStart;
      if (StringLength >= High(SizeInt)) then
      begin
         Error('String component is too big (%d bytes, maximum is %d bytes)', [StringLength, High(SizeInt)]);
      end;
      SetLength(FStringValue, StringLength);
      if (StringLength > 0) then
      begin
         Move((FBuffer + StringStart)^, FStringValue[1], StringLength); // $R-
      end;
   end;

var
   StringSegments: specialize PlasticArray<TSegment, specialize IncomparableUtils<TSegment>>;

   procedure FixSegments();
   var
      Segment: TSegment;
      Size: QWord;
      Destination: Pointer;
   begin
      Size := 0;
      for Segment in StringSegments do
      begin
         Assert(Segment.Size > 0);
         if (Segment.Size > High(Integer)) then
            Error('Overlong string segment in string ending', []);
         Inc(Size, Segment.Size); // $R-
      end;
      Assert(Size > 0);
      SetLength(FStringValue, Size - 1); // SetLength allocates an extra byte for a trailing null; it's safe to write to that byte
      if (Size > 1) then
      begin
         Destination := @FStringValue[1];
         for Segment in StringSegments do
         begin
            Move(Segment.Start^, Destination^, Segment.Size); // $R-
            Inc(Destination, Segment.Size); // $R-
         end;
      end;
      // This (intentionally) clobbers the trailing #$00 on the string with a #$20, so we have to restore it.
      Assert(Length(FStringValue) = Size-1);
      {$PUSH}
      {$RANGECHECKS-}
      Assert(FStringValue[Size] = #$20);
      FStringValue[Size] := #$00;
      {$POP}
   end;

const
   kEOF = High(Cardinal);
   kNewline = #$0A;
   kSpace = #$20;
type
   TTokenMode = (tmTop, tmIdentifier, tmX, tmNumber, tmNumberFraction, tmExponentStart, tmExponentStartDigit, tmExponent, tmString,
                 tmMultilineStringStart, tmMultilineStringFirstLinePrefix, tmMultilineStringPrefix, tmMultilineStringBodyStart, tmMultilineStringBody,
                 tmSlash, tmLineComment, tmBlockComment, tmBlockCommentEnd);
var
   Mode: TTokenMode;
   Current, ExpectedIndent, CurrentIndent, NumberLength, NumberDecimalPosition: Cardinal;
   Negative, ExponentNegative, HasXPrefix: Boolean;
   Number: UInt64;
   Exponent: Integer;
   SegmentStart, SegmentCheckpoint: QWord;
begin
   Mode := tmTop;
   repeat
      if (FPosition >= FSize) then
      begin
         Current := kEOF;
      end
      else
      begin
         Current := (FBuffer + FPosition)^;
      end;
      repeat
         {$IFDEF VERBOSE} Writeln('Tokenizer: ', FPosition:10, ' ', Line:5, ' ', Column:5, ' ', TUnicodeCodepoint(Current).GetDebugDescription(), ' ', specialize EnumToString<TTokenMode>(Mode)); {$ENDIF}
         case (Mode) of
            tmTop:
               case (Current) of
                  kEOF:
                     begin
                        FCurrentKind := tkEOF;
                     end;
                  $09, $0D, $20: // tab, CR, space
                     begin
                        Advance();
                     end;
                  $0A: // newline
                     begin
                        AdvanceLine();
                     end;
                  $22: // U+0022 QUOTATION MARK (")
                     begin
                        Advance();
                        SegmentStart := FPosition;
                        Mode := tmString;
                     end;
                  $25: // U+0025 PERCENT SIGN character (%)
                     begin
                        FCurrentKind := tkPercentage;
                        Advance();
                     end;
                  $28: // U+0028 LEFT PARENTHESIS character (()
                     begin
                        FCurrentKind := tkOpenParenthesis;
                        Advance();
                     end;
                  $29: // U+0029 RIGHT PARENTHESIS character ())
                     begin
                        FCurrentKind := tkCloseParenthesis;
                        Advance();
                     end;
                  $2A: // U+002A ASTERISK character (*)
                     begin
                        FCurrentKind := tkAsterisk;
                        Advance();
                     end;
                  $2B: // U+002B PLUS SIGN character (+)
                     begin
                        Negative := False;
                        HasXPrefix := False;
                        Number := 0;
                        Advance();
                        Mode := tmNumber;
                     end;
                  $2C: // U+002C COMMA character (,)
                     begin
                        FCurrentKind := tkComma;
                        Advance();
                     end;
                  $2D: // U+002D HYPHEN-MINUS character (-)
                     begin
                        Negative := True;
                        HasXPrefix := False;
                        Number := 0;
                        Advance();
                        Mode := tmNumber;
                     end;
                  $2F: // U+002F SOLIDUS character (/)
                     begin
                        Advance();
                        Mode := tmSlash;
                     end;
                  $30..$39: // digits 0..9
                     begin
                        Negative := False;
                        HasXPrefix := False;
                        Number := 0;
                        NumberLength := 0;
                        Mode := tmNumber;
                        // we do not advance, so digit is reinterpreted again in tmNumber immediately
                        continue; // reparse in new mode
                     end;
                  $3A: // U+003B COLON character (:)
                     begin
                        FCurrentKind := tkColon;
                        Advance();
                     end;
                  $3B: // U+003B SEMICOLON character (;)
                     begin
                        FCurrentKind := tkSemicolon;
                        Advance();
                     end;
                  $40: // U+0040 COMMERCIAL AT character (@)
                     begin
                        FCurrentKind := tkAt;
                        Advance();
                     end;
                  $78: // x
                     begin
                        SegmentStart := FPosition;
                        Advance();
                        Mode := tmX;
                     end;
                  $41..$5A, $61..$77, $79..$7A: // A-Z, a-w, y-z
                     begin
                        SegmentStart := FPosition;
                        Advance();
                        Mode := tmIdentifier;
                     end;
                  $5B: // LEFT SQUARE BRACKET character ([)
                     begin
                        Advance();
                        Mode := tmMultilineStringStart;
                     end;
                  $7B: // U+007B LEFT CURLY BRACKET character ({)
                     begin
                        FCurrentKind := tkOpenBrace;
                        Advance();
                     end;
                  $7D: // U+007D RIGHT CURLY BRACKET character (})
                     begin
                        FCurrentKind := tkCloseBrace;
                        Advance();
                     end;
               else
                  Error('Unexpected character 0x%2x (''%s'')', [Current, Chr(Current)]);
               end;
            tmX:
               case (Current) of
                  $30..$39: // 0-9
                     begin
                        Negative := False;
                        HasXPrefix := True;
                        Number := 0;
                        NumberLength := 0;
                        Mode := tmNumber;
                        continue;
                     end;
               else
                  Mode := tmIdentifier;
                  continue;
               end;
            tmIdentifier:
               case (Current) of
                  $2D, $30..$39, $41..$5A, $61..$7A:
                     begin
                        Advance();
                     end;
               else
                  FCurrentKind := tkIdentifier;
                  FixStringSegment(SegmentStart, FPosition);
               end;
            tmNumber:
               case (Current) of
                  $45, $65: // E, e
                     begin
                        if (NumberLength < 1) then
                        begin
                           Error('Exponent is only valid after a digit', []);
                        end;
                        Advance();
                        NumberDecimalPosition := NumberLength;
                        ExponentNegative := False;
                        Exponent := 0;
                        Mode := tmExponentStart;
                     end;
                  $2E: // .
                     begin
                        Advance();
                        NumberDecimalPosition := NumberLength;
                        Mode := tmNumberFraction;
                     end;
                  $30..$39:
                     begin
                        Inc(NumberLength);
                        {$PUSH}
                        {$OVERFLOWCHECKS-}
                        {$RANGECHECKS-}
                        Number := Number * 10 + Current - $30;
                        {$POP}
                        if ((Negative and (Number > High(Int64) + 1)) or (not Negative and (Number > High(Int64)))) then
                           Error('Numeric literal out of range (valid range is %d..%d)', [Low(Number), High(Number)]);
                        Advance();
                     end;
               else
                  if (HasXPrefix) then
                  begin
                     if (Negative) then
                        Error('Negative multiplier (%f)', [Number]);
                     FNumericDouble := Number;
                     FCurrentKind := tkMultiplier;
                  end
                  else
                  begin
                     if (Negative) then
                        FNumericInteger := -Number // $R-
                     else
                        FNumericInteger := Number; // $R-
                     FCurrentKind := tkInteger;
                  end;
               end;
            tmNumberFraction:
               case (Current) of
                  $45, $65: // E, e
                     begin
                        Advance();
                        ExponentNegative := False;
                        Exponent := 0;
                        Mode := tmExponentStart;
                     end;
                  $2E: // .
                     begin
                        Error('Unexpected decimal point in fraction', []);
                     end;
                  $30..$39:
                     begin
                        Inc(NumberLength);
                        if (NumberLength > 15) then
                           Error('Too many digits in number', []);
                        {$PUSH}
                        {$OVERFLOWCHECKS-}
                        {$RANGECHECKS-}
                        Number := Number * 10 + Current - $30;
                        {$POP}
                        Advance();
                     end;
               else
                  if (Negative) then
                  begin
                     FNumericDouble := -Number / Power(10, (NumberLength - NumberDecimalPosition)); // $R-
                  end
                  else
                  begin
                     FNumericDouble := Number / Power(10, (NumberLength - NumberDecimalPosition)); // $R-
                  end;
                  if (HasXPrefix) then
                  begin
                     if (Negative) then
                        Error('Negative multiplier (%f)', [Number]);
                     FCurrentKind := tkMultiplier;
                  end
                  else
                  begin
                     FCurrentKind := tkDouble;
                  end;
               end;
            tmExponentStart:
               case (Current) of
                  kEOF, $0A:
                     begin
                        Error('Unterminated exponent in numerical value', []);
                     end;
                  $2D: // -
                     begin
                        Advance();
                        ExponentNegative := True;
                        Mode := tmExponentStartDigit;
                     end;
                  $30..$39:
                     begin
                        Mode := tmExponentStartDigit;
                        continue;
                     end;
               else
                  Error('Unexpected character after exponent in numerical value', []);
               end;
            tmExponentStartDigit:
               case (Current) of
                  kEOF, $0A:
                     begin
                        Error('Unterminated exponent in numerical value', []);
                     end;
                  $30..$39:
                     begin
                        Mode := tmExponent;
                        continue;
                     end;
               else
                  Error('Unexpected character after exponent in numerical value', []);
               end;
            tmExponent:
               case (Current) of
                  $30..$39:
                     begin
                        {$PUSH}
                        {$OVERFLOWCHECKS-}
                        {$RANGECHECKS-}
                        Exponent := Exponent * 10 + Current - $30; // $R-
                        {$POP}
                        if ((ExponentNegative and (Exponent > 1022)) or (not ExponentNegative and (Exponent > 1023))) then
                           Error('Numeric literal out of range (valid range is %d..%d)', [-1022, 1023]);
                        Advance();
                     end;
               else
                  if (ExponentNegative) then
                     Exponent := -Exponent; // $R-
                  if (Negative) then
                  begin
                     FNumericDouble := -Number / Power(10, (NumberLength - NumberDecimalPosition)) * Power(10, Exponent); // $R-
                  end
                  else
                  begin
                     FNumericDouble := Number / Power(10, (NumberLength - NumberDecimalPosition)) * Power(10, Exponent); // $R-
                  end;
                  if (HasXPrefix) then
                  begin
                     if (Negative) then
                        Error('Negative multiplier (%f)', [Number]);
                     FCurrentKind := tkMultiplier;
                  end
                  else
                  begin
                     FCurrentKind := tkDouble;
                  end;
               end;
            tmString:
               case (Current) of
                  kEOF, $0A:
                     begin
                        Error('Unterminated string', []);
                     end;
                  $22:
                     begin
                        FCurrentKind := tkString;
                        FixStringSegment(SegmentStart, FPosition);
                        Advance();
                     end;
               else
                  Advance();
               end;
            tmMultilineStringStart:
               case (Current) of
                  kEOF:
                     begin
                        Error('Unterminated string', []);
                     end;
                  $0A: // newline
                     begin
                        AdvanceLine();
                        Mode := tmMultilineStringFirstLinePrefix;
                        ExpectedIndent := 0;
                     end;
                  $20: // U+0020 SPACE character
                     begin
                        Advance();
                     end;
                  $5D: // U+005D RIGHT SQUARE BRACKET character (])
                     begin
                        Advance();
                        FCurrentKind := tkString;
                        FStringValue := '';
                     end;
               else
                  Error('Expected line break in multiline string', []);
               end;
            tmMultilineStringFirstLinePrefix:
               case (Current) of
                  kEOF:
                     begin
                        Error('Unterminated string', []);
                     end;
                  $0A: // newline
                     begin
                        Error('Unexpected blank line at top of multiline string', []);
                     end;
                  $20: // U+0020 SPACE character
                     begin
                        Advance();
                        Inc(ExpectedIndent);
                     end;
                  $5D: // U+005D RIGHT SQUARE BRACKET character (])
                     begin
                        Advance();
                        FCurrentKind := tkString;
                        FStringValue := '';
                     end;
               else
                  if (ExpectedIndent = 0) then
                     Error('Missing indent in multiline string', []);
                  StringSegments.Prepare(4);
                  SegmentStart := FPosition;
                  SegmentCheckpoint := SegmentStart;
                  Mode := tmMultilineStringBody;
                  continue;
               end;
            tmMultilineStringPrefix:
               case (Current) of
                  kEOF:
                     begin
                        Error('Unterminated string', []);
                     end;
                  $0A: // newline
                     begin
                        AdvanceLine();
                        StringSegments.Last := TSegment.From(kNewline);
                        Mode := tmMultilineStringPrefix;
                        CurrentIndent := 0;
                     end;
                  $20: // U+0020 SPACE character
                     begin
                        Advance();
                        Inc(CurrentIndent);
                        if (CurrentIndent = ExpectedIndent) then
                        begin
                           SegmentStart := FPosition;
                           SegmentCheckpoint := SegmentStart;
                           Mode := tmMultilineStringBodyStart;
                        end;
                     end;
                  $5D: // U+005D RIGHT SQUARE BRACKET character (])
                     begin
                        Advance();
                        FCurrentKind := tkString;
                        FixSegments();
                        Mode := tmTop;
                     end;
               else
                  Error('Insufficient indent in multiline string', []);
               end;
            tmMultilineStringBodyStart:
               case (Current) of
                  kEOF:
                     begin
                        Error('Unterminated string', []);
                     end;
                  $0A: // newline
                     begin
                        AdvanceLine();
                        StringSegments.Last := TSegment.From(kNewline);
                        Mode := tmMultilineStringPrefix;
                        CurrentIndent := 0;
                     end;
               else
                  Mode := tmMultilineStringBody;
                  continue;
               end;
            tmMultilineStringBody:
               case (Current) of
                  kEOF:
                     begin
                        Error('Unterminated string', []);
                     end;
                  $20: // strip trailing spaces
                     begin
                        Advance();
                        // do not update SegmentCheckpoint
                     end;
                  $0A: // newline
                     begin
                        if (SegmentStart < SegmentCheckpoint) then
                           StringSegments.Push(TSegment.From(FBuffer + SegmentStart, FBuffer + SegmentCheckpoint));
                        StringSegments.Push(TSegment.From(kSpace));
                        AdvanceLine();
                        Mode := tmMultilineStringPrefix;
                        CurrentIndent := 0;
                     end;
               else
                  Advance();
                  SegmentCheckpoint := FPosition;
               end;
            tmSlash:
               case (Current) of
                  $2A: // U+002A ASTERISK character (*)
                     begin
                        Advance();
                        Mode := tmBlockComment;
                     end;
                  $2F: // U+002F SOLIDUS character (/)
                     begin
                        Advance();
                        Mode := tmLineComment;
                     end;
               else
                  FCurrentKind := tkSlash;
                  Mode := tmTop;
                  // do not advance, we need to reprocess this character
               end;
            tmLineComment:
               case (Current) of
                  kEOF:
                     begin
                        Mode := tmTop;
                        continue;
                     end;
                  $0A: // newline
                     begin
                        AdvanceLine();
                        Mode := tmTop;
                     end;
               else
                  Advance();
               end;
            tmBlockComment:
               case (Current) of
                  kEOF:
                     begin
                        Error('Unexpected end of file in comment', []);
                     end;
                  $0A: // newline
                     begin
                        AdvanceLine();
                     end;
                  $2A: // U+002A ASTERISK character (*)
                     begin
                        Advance();
                        Mode := tmBlockCommentEnd;
                     end;
               else
                  Advance();
               end;
            tmBlockCommentEnd:
               case (Current) of
                  kEOF:
                     begin
                        Error('Unexpected end of file in comment', []);
                     end;
                  $2F: // U+002F SOLIDUS character (/)
                     begin
                        Advance();
                        Mode := tmTop;
                     end;
               else
                  Mode := tmBlockComment;
                  continue;
               end;
         end;
      until True;
   until FCurrentKind <> tkPending;
   {$IFDEF VERBOSE} Writeln('Tokenizer: EMITTING ', specialize EnumToString<TTokenKind>(FCurrentKind)); {$ENDIF}
end;

procedure TTokenizer.EnsureToken();
begin
   if (FCurrentKind = tkPending) then
      Tokenize();
end;

procedure TTokenizer.ExpectToken(ExpectedKind: TTokenKind);
begin
   Assert(ExpectedKind <> tkPending);
   Assert(FCurrentKind <> tkPending);
   if (FCurrentKind <> ExpectedKind) then
      Error('Expected %s but got %s', [specialize EnumToString<TTokenKind>(ExpectedKind), specialize EnumToString<TTokenKind>(FCurrentKind)]);
end;

function TTokenizer.ReadIdentifier(): UTF8String;
begin
   EnsureToken();
   ExpectToken(tkIdentifier);
   Result := FStringValue;
   FCurrentKind := tkPending;
end;

procedure TTokenizer.ReadIdentifier(Keyword: UTF8String);
var
   Value: UTF8String;
begin
   Value := ReadIdentifier();
   if (Value <> Keyword) then
      Error('Expected %s but got %s', [Keyword, Value]);
end;

function TTokenizer.ReadString(const MaxLength: Int64 = High(SizeInt)): UTF8String;
begin
   EnsureToken();
   ExpectToken(tkString);
   {$IFOPT C+}
   // This makes the leak tracking have a more convenient stack trace.
   Result := Copy(FStringValue, 1, Length(FStringValue));
   {$ELSE}
   Result := FStringValue;
   {$ENDIF}
   if (Length(Result) > MaxLength) then
      Error('String is too long. Maximum length is %d. String length was %d', [MaxLength, Length(Result)]);
   FCurrentKind := tkPending;
end;

function TTokenizer.ReadNumber(): Int64;
begin
   EnsureToken();
   ExpectToken(tkInteger);
   Result := FNumericInteger;
   FCurrentKind := tkPending;
end;

function TTokenizer.ReadDouble(): Double;
begin
   EnsureToken();
   case (FCurrentKind) of
     tkInteger: Result := FNumericInteger;
     tkDouble: Result := FNumericDouble;
     else
       Error('Expected a numeric token but got %s', [specialize EnumToString<TTokenKind>(FCurrentKind)]);
   end;
   FCurrentKind := tkPending;
end;

function TTokenizer.ReadMultiplier(): Double;
begin
   EnsureToken();
   ExpectToken(tkMultiplier);
   Result := FNumericDouble;
   FCurrentKind := tkPending;
end;

procedure TTokenizer.ReadOpenBrace();
begin
   EnsureToken();
   ExpectToken(tkOpenBrace);
   FCurrentKind := tkPending;
end;

procedure TTokenizer.ReadCloseBrace();
begin
   EnsureToken();
   ExpectToken(tkCloseBrace);
   FCurrentKind := tkPending;
end;

procedure TTokenizer.ReadOpenParenthesis();
begin
   EnsureToken();
   ExpectToken(tkOpenParenthesis);
   FCurrentKind := tkPending;
end;

procedure TTokenizer.ReadCloseParenthesis();
begin
   EnsureToken();
   ExpectToken(tkCloseParenthesis);
   FCurrentKind := tkPending;
end;

procedure TTokenizer.ReadComma();
begin
   EnsureToken();
   ExpectToken(tkComma);
   FCurrentKind := tkPending;
end;

procedure TTokenizer.ReadColon();
begin
   EnsureToken();
   ExpectToken(tkColon);
   FCurrentKind := tkPending;
end;

procedure TTokenizer.ReadSemicolon();
begin
   EnsureToken();
   ExpectToken(tkSemicolon);
   FCurrentKind := tkPending;
end;

procedure TTokenizer.ReadPercentage();
begin
   EnsureToken();
   ExpectToken(tkPercentage);
   FCurrentKind := tkPending;
end;

procedure TTokenizer.ReadAsterisk();
begin
   EnsureToken();
   ExpectToken(tkAsterisk);
   FCurrentKind := tkPending;
end;

procedure TTokenizer.ReadSlash();
begin
   EnsureToken();
   ExpectToken(tkSlash);
   FCurrentKind := tkPending;
end;

procedure TTokenizer.ReadAt();
begin
   EnsureToken();
   ExpectToken(tkAt);
   FCurrentKind := tkPending;
end;

function TTokenizer.IsIdentifier(): Boolean;
begin
   EnsureToken();
   Result := FCurrentKind = tkIdentifier;
end;

function TTokenizer.IsIdentifier(Keyword: UTF8String): Boolean;
begin
   EnsureToken();
   Result := (FCurrentKind = tkIdentifier) and (FStringValue = Keyword);
end;

function TTokenizer.IsString(): Boolean;
begin
   EnsureToken();
   Result := FCurrentKind = tkString;
end;

function TTokenizer.IsNumber(): Boolean;
begin
   EnsureToken();
   Result := FCurrentKind = tkInteger;
end;

function TTokenizer.IsDouble(): Boolean;
begin
   EnsureToken();
   Result := FCurrentKind in [tkInteger, tkDouble];
end;

function TTokenizer.IsCloseBrace(): Boolean;
begin
   EnsureToken();
   Result := FCurrentKind = tkCloseBrace;
end;

function TTokenizer.IsOpenParenthesis(): Boolean;
begin
   EnsureToken();
   Result := FCurrentKind = tkOpenParenthesis;
end;

function TTokenizer.IsCloseParenthesis(): Boolean;
begin
   EnsureToken();
   Result := FCurrentKind = tkCloseParenthesis;
end;

function TTokenizer.IsComma(): Boolean;
begin
   EnsureToken();
   Result := FCurrentKind = tkComma;
end;

function TTokenizer.IsSemicolon(): Boolean;
begin
   EnsureToken();
   Result := FCurrentKind = tkSemicolon;
end;

function TTokenizer.IsAt(): Boolean;
begin
   EnsureToken();
   Result := FCurrentKind = tkAt;
end;

function TTokenizer.IsEOF(): Boolean;
begin
   EnsureToken();
   Result := FCurrentKind = tkEOF;
end;

procedure TTokenizer.Error(const AMessage: UTF8String; const Arguments: array of const);
begin
   raise EParseError.CreateFmt(AMessage, Arguments, Line, Column);
end;

end.