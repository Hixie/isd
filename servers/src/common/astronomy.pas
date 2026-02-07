{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit astronomy;

interface

uses
   genericutils;

type
   TStarCategory = 0..31;
   TStarCategories = set of TStarCategory;
   TStarIndex = 0..$FFFFF; // 1048575

   TStarID = -1 .. $1FFFFFF;
   {$IF SizeOf(TStarID) <> SizeOf(Cardinal)}
      {$ERROR TStarID is not 32 bits}
   {$ENDIF}

   TStarIDUtils = specialize DefaultNumericUtils<TStarID>;

const
   CategoryShift = 20;
   StarIndexMask = $FFFFF;
   LY = 9460730472580800; // meters
   AU = 149597870700; // meters
   G = 6.67430E-11; // N.m^2.kg^-2

function EncodeStarID(Category: TStarCategory; Index: TStarIndex): TStarID;
function CategoryOf(ID: TStarID): TStarCategory;
function StarNameOf(StarID: TStarID): UTF8String;

function Modifier(Min, Max: Double; Seed: TStarID; Salt: Cardinal): Double;

implementation

uses
   sysutils;

function EncodeStarID(Category: TStarCategory; Index: TStarIndex): TStarID;
begin
   Result := (Category shl CategoryShift) or Index; // $R-
end;

function CategoryOf(ID: TStarID): TStarCategory;
begin
   Assert(ID >= 0);
   Result := ID shr CategoryShift; // $R-
end;

function StarNameOf(StarID: TStarID): UTF8String;
const
   Codes: array[0..$F] of UTF8String = ('Ada' {Palmer}, 'BEE' {WASP},
      'Cat', 'Carter' {SG1}, 'Dragonis', 'Epsilon', 'Eta', 'Geneva',
      'Hague' {B5}, 'Iota', 'Mc' {Mycroft}, 'Omicron', 'Picard' {TNG},
      '4K' {HD}, 'Smrt' {Simpsons, WISE}, 'Zeta');
   Symbols1: array[0..$1F] of UTF8String = ( 'A', 'B', 'D', 'E', 'G',
      'H', 'K', 'L', 'M', 'N', 'P', 'Q', 'R', 'X', 'Y', 'Z', '*', 'C',
      'F', 'J', 'S', 'T', 'V', 'W', 'u', 'α', 'β', 'ε', 'π', 'χ', '☉',
      '');
   Symbols2: array[0..$F] of UTF8String = ('Σ', 'Ω', 'α', 'β', 'γ',
      'δ', 'ε', 'θ', 'λ', 'μ', 'ξ', 'π', 'σ', 'φ', 'ψ', 'ω');
   Symbols3: array[0..$F] of UTF8String = ('1', '2', '3', '4', '5',
      '6', '7', '8', '9', '10', '11', '12', '13', '14', '15', '16');
   Symbols4: array[0..$7] of UTF8String = ('*', '¹', '²', '³', 'ⁱ', '⁽⁴⁾', 'ᵨ', 'ₘ');
   Symbols5: array[0..$7] of UTF8String = ('A', 'Aa', 'Majoris', '1', '2', 'b', 'c', 'έ');
   Symbols6: array[0..$1] of UTF8String = ('', 'Ж');
   Words1: array[0..$F] of UTF8String = ('Andromedae', 'Aquarii',
      'Arietis', 'Aurigae', 'Capricorni', 'Cassiopeiae', 'Hedralis',
      'Herculis', 'Lalande', 'Leporis', 'Pavonis', 'Pillaris',
      'Treeplatis', 'Ursae', 'Wolf', 'Zeta');
   Words2: array[0..$1F] of UTF8String = ('Galaxy', 'Galaxy Cluster',
      '', 'Prime', 'Xi', 'Gamma', 'Prior', 'Polaris', 'Carina',
      'Center', 'Red Giant', 'Nebula', 'Toobe', 'Mount', 'Flick',
      'Cluster', 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J',
      'K', 'L', 'M', 'N', 'O', 'P');

   function ComputeCode00(StarID: TStarID): UTF8String;
   var
      Code, Digits, X: Cardinal;
   begin
      //  TYPE 00: Codes[] + ' ' + Digits in decimal + Symbols6[X]
      //    _ _________ _________ __________
      //    x 0000 0000 0000 0000 00 0000 00
      //      ------------------+--- -+-- +-
      //                        |     |   |
      //                     Digits Code Type
      Code := (StarID shr 2) and $F; // $R-
      Digits := StarID shr 6 and $3FFFF; // $R-
      X := StarID shr 24; // $R-
      Result := Codes[Code] + ' ' + IntToStr(Digits) + Symbols6[X]; // $R-
   end;

   function ComputeCode01(StarID: TStarID): UTF8String;
   var
      Code1, Code2, Digits: Cardinal;
   begin
      //  TYPE 01: Symbols1[Code1] + Symbols1[Code2] + '-' + Digits in decimal
      //    _ __________ _________ ___________
      //    0 000 0 0000 0000 0000 00 00 00 01
      //    --+-- --+--- -----+------ --+-- -+
      //      |     '-Code2   |         |    |
      //      +-------------Digits    Code1 Type
      Code1 := (StarID shr 2) and $F; // $R-
      Code2 := (StarID shr 16) and $1F; // $R-
      Digits := ((StarID shr 6) and $3FF) or ((StarID shr 21) and $F); // $R-
      Result := Symbols1[Code1] + Symbols1[Code2] + '-' + IntToStr(Digits);
   end;

   function ComputeCode10(StarID: TStarID): UTF8String;
   var
      Left, Right: Cardinal;
   begin
      //  TYPE 10: Left in decimal + '+' + Right in decimal
      //    _ _________ __________ __________
      //    0 0000 0000 000 0 0000 0000 00 10
      //    -------+------- -------+------ -+
      //           |               |        |
      //          Left           Right     Type
      //    double then xor left and right with $555
      Left := ((StarID shr 13) and $07FF) xor $0555; // $R- // _000 0000 0000
      Right := ((StarID shr 1) and $0FFE) xor $0555; // $R- // 0000 0000 000_
      Result := IntToStr(Left) + '+' + IntToStr(Right);
   end;

   function ComputeCode11(StarID: TStarID): UTF8String;
   var
      A, B, C, D, E, F, G: Cardinal;
      Prefix, Suffix, Superscript, Space, Digits: UTF8String;
   begin
      //  TYPE 11: Prefix + Superscript + ' ' + Words1[C] + ' ' + Words2[E] + ' ' + D in decimal (treat 0 as '') + ' ' + Suffix
      //    G=0: Prefix = Symbols2[A]
      //    G=1: Prefix = Symbols3[A]
      //    F=0: Superscript = Symbols4[B]; Suffix = ''
      //    F=1: Superscript = ''; Suffix = Symbols5[B]
      //    _ _________ ___________ __________
      //    0 0000 0000 0 FG 0000 0 00 0000 11
      //    ---+-- ---+--    --+- --+- -+-- -+
      //       E      D        C    B   A    Type
      A := (StarID shr 2) and $F; // $R-
      B := (StarID shr 6) and $7; // $R-
      C := (StarID shr 9) and $F; // $R-
      D := (StarID shr 15) and $1F; // $R-
      E := (StarID shr 20) and $1F; // $R-
      F := (StarID shr 14) and $1; // $R-
      G := (StarID shr 13) and $1; // $R-
      if (G = 0) then
      begin
         Prefix := Symbols2[A];
      end
      else
      begin
         Prefix := Symbols3[A];
      end;
      if (F = 0) then
      begin
         Superscript := Symbols4[B];
         Suffix := '';
      end
      else
      begin
         Superscript := '';
         Suffix := ' ' + Symbols5[B];
      end;
      if (Words2[E] <> '') then
         Space := ' ';
      if (D > 0) then
         Digits := ' ' + IntToStr(D);
      Result := Prefix + Superscript + ' ' + Words1[C] + Space + Words2[E] + Digits + Suffix;
   end;

begin
   Assert(High(StarID) = $1FFFFFF);
   Assert(StarID >= 0);
   // 25 bits to generate the name from
   case StarID and $3 of
      $0: Result := ComputeCode00(StarID);
      $1: Result := ComputeCode01(StarID);
      $2: Result := ComputeCode10(StarID);
      $3: Result := ComputeCode11(StarID);
   end;
end;

function Modifier(Min, Max: Double; Seed: TStarID; Salt: Cardinal): Double;
var
   Value: Double;
begin
   Assert(Seed >= 0);
   RandSeed := Seed xor Salt; // $R-
   Value := Random(); // $R-
   Result := Min + Exp(Value * (Ln(Max) - Ln(Min))); // $R-
end;

end.
