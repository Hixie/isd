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
            tkIdentifier, tkString, tkNumber,
            tkOpenBrace, tkCloseBrace, tkOpenParenthesis, tkCloseParenthesis,
            tkComma, tkColon, tkSemicolon, tkPercentage, tkAsterisk, tkSlash,
            tkEOF
         );
      var
         FBuffer: PByte;
         FSize: QWord;
         FPosition: QWord;
         FLine, FColumn: Cardinal;
         FCurrentKind: TTokenKind;
         FNumericValue: Int64;
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
      function ReadString(): UTF8String;
      function ReadNumber(): Int64;
      procedure ReadOpenBrace();
      procedure ReadCloseBrace();
      procedure ReadOpenParenthesis();
      procedure ReadCloseParenthesis();
      procedure ReadComma();
      procedure ReadColon();
      procedure ReadSemicolon();
      procedure ReadPercentage();
      procedure ReadAsterisk();
      procedure ReadSlash();
      function IsIdentifier(): Boolean;
      function IsIdentifier(Keyword: UTF8String): Boolean;
      function IsString(): Boolean;
      function IsCloseBrace(): Boolean;
      function IsOpenParenthesis(): Boolean;
      function IsCloseParenthesis(): Boolean;
      function IsComma(): Boolean;
      function IsSemicolon(): Boolean;
      function IsEOF(): Boolean;
      procedure Error(const AMessage: UTF8String; const Arguments: array of const);
   end;

implementation

uses
   {$IFDEF VERBOSE} unicode, {$ENDIF}
   typedump, exceptions, rtlutils, plasticarrays, genericutils;

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
         if (Segment.Size > High(Integer)) then
            Error('Overlong string segment in string ending', []);
         Inc(Size, Segment.Size); // $R-
      end;
      SetLength(FStringValue, Size - 1);
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
   TTokenMode = (tmTop, tmIdentifier, tmNumber, tmString,
                 tmMultilineStringStart, tmMultilineStringFirstLinePrefix, tmMultilineStringPrefix, tmMultilineStringBodyStart, tmMultilineStringBody,
                 tmSlash, tmLineComment, tmBlockComment, tmBlockCommentEnd);
var
   Mode: TTokenMode;
   Current, ExpectedIndent, CurrentIndent: Cardinal;
   Negative: Boolean;
   Number: UInt64;
   SegmentStart: QWord;
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
                  $22:
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
                        Number := 0;
                        Mode := tmNumber;
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
                  $41..$5A, $61..$7A: // A-Z, a-z
                     begin
                        SegmentStart := FPosition;
                        Mode := tmIdentifier;
                        continue;
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
                  $2E:
                     begin
                        Error('Numeric literals do not yet support fractions; unexpected fraction', []);
                        //Advance();
                        //Mode := tmNumberFraction;
                     end;
                  $30..$39:
                     begin
                        {$PUSH}
                        {$OVERFLOWCHECKS-}
                        {$RANGECHECKS-}
                        Number := Number * 10 + Current - $30;
                        {$POP}
                        if (Negative and (Number > High(Int64) + 1)) then
                        begin
                           Error('Numeric literal out of range (valid range is %d..%d)', [Low(Number), High(Number)]);
                        end;
                        if (not Negative and (Number > High(Int64))) then
                        begin
                           Error('Numeric literal out of range (valid range is %d..%d)', [Low(Number), High(Number)]);
                        end;
                        Advance();
                     end;
               else
                  FCurrentKind := tkNumber;
                  if (Negative) then
                  begin
                     FNumericValue := -Number; // $R-
                  end
                  else
                  begin
                     FNumericValue := Number; // $R-
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
                  StringSegments.Init(4);
                  SegmentStart := FPosition;
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
                  $0A: // newline
                     begin
                        if (SegmentStart < FPosition) then
                           StringSegments.Push(TSegment.From(FBuffer + SegmentStart, FBuffer + FPosition));
                        StringSegments.Push(TSegment.From(kSpace));
                        AdvanceLine();
                        Mode := tmMultilineStringPrefix;
                        CurrentIndent := 0;
                     end;
               else
                  Advance();
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

function TTokenizer.ReadString(): UTF8String;
begin
   EnsureToken();
   ExpectToken(tkString);
   {$IFOPT C+}
   // This makes the leak tracking have a more convenient stack trace.
   Result := Copy(FStringValue, 1, Length(FStringValue));
   {$ELSE}
   Result := FStringValue;
   {$ENDIF}
   FCurrentKind := tkPending;
end;

function TTokenizer.ReadNumber(): Int64;
begin
   EnsureToken();
   ExpectToken(tkNumber);
   Result := FNumericValue;
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