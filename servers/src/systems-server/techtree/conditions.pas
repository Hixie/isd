{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit conditions;

interface

//{$DEFINE VERBOSE}

uses
   sysutils, internals, plasticarrays, genericutils, hashtable, stringutils;

type
   TRootConditionAST = class(TConditionAST)
      FA: TConditionAST;
      constructor Create(A: TConditionAST);
      procedure Compile(var Target: TCompiledConditionTarget); override;
      function GetOperandDescription(): Word; override;
      destructor Destroy(); override;
      procedure CollectResearches(var Collection: TResearchHashSet; const Negated: Boolean = False); override;
      function ConstantValue(): TConditionConstant; override;
   end;

   TAndConditionAST = class(TConditionAST)
      FA, FB: TConditionAST;
      constructor Create(A, B: TConditionAST);
      procedure Compile(var Target: TCompiledConditionTarget); override;
      function GetOperandDescription(): Word; override;
      destructor Destroy(); override;
      procedure CollectResearches(var Collection: TResearchHashSet; const Negated: Boolean = False); override;
      function ConstantValue(): TConditionConstant; override;
   end;
   
   TOrConditionAST = class(TConditionAST)
      FA, FB: TConditionAST;
      constructor Create(A, B: TConditionAST);
      procedure Compile(var Target: TCompiledConditionTarget); override;
      function GetOperandDescription(): Word; override;
      destructor Destroy(); override;
      procedure CollectResearches(var Collection: TResearchHashSet; const Negated: Boolean = False); override;
      function ConstantValue(): TConditionConstant; override;
   end;
   
   TNotConditionAST = class(TConditionAST)
      FA: TConditionAST;
      constructor Create(A: TConditionAST);
      procedure Compile(var Target: TCompiledConditionTarget); override;
      function GetOperandDescription(): Word; override;
      destructor Destroy(); override;
      procedure CollectResearches(var Collection: TResearchHashSet; const Negated: Boolean = False); override;
      function ConstantValue(): TConditionConstant; override;
   end;
   
   TGroupConditionAST = class(TConditionAST)
      FA: TConditionAST;
      constructor Create(A: TConditionAST);
      procedure Compile(var Target: TCompiledConditionTarget); override;
      function GetOperandDescription(): Word; override;
      destructor Destroy(); override;
      procedure CollectResearches(var Collection: TResearchHashSet; const Negated: Boolean = False); override;
      function ConstantValue(): TConditionConstant; override;
   end;

   PResearchList = ^TResearchList;
   TResearchList = specialize PlasticArray<TResearchIndex, specialize IncomparableUtils<TResearchIndex>>;

   TResearchListHashTable = class(specialize THashTable<UTF8String, TResearchList, UTF8StringUtils>)
      constructor Create();
   end;
   
   TResearchListConditionAST = class(TConditionAST) // used for storybeats, materials, assets
      FA: PResearchList;
      constructor Create(A: PResearchList);
      procedure Compile(var Target: TCompiledConditionTarget); override;
      function GetOperandDescription(): Word; override;
      procedure CollectResearches(var Collection: TResearchHashSet; const Negated: Boolean = False); override;
      function ConstantValue(): TConditionConstant; override;
   end;
   
   TNothingConditionAST = class(TConditionAST)
      procedure Compile(var Target: TCompiledConditionTarget); override;
      function GetOperandDescription(): Word; override;
      procedure CollectResearches(var Collection: TResearchHashSet; const Negated: Boolean = False); override;
      function ConstantValue(): TConditionConstant; override;
   end;

   TSituationConditionAST = class(TConditionAST)
      FA: TSituation;
      constructor Create(A: TSituation);
      procedure Compile(var Target: TCompiledConditionTarget); override;
      function GetOperandDescription(): Word; override;
      procedure CollectResearches(var Collection: TResearchHashSet; const Negated: Boolean = False); override;
      function ConstantValue(): TConditionConstant; override;
   end;
   
   TTopicConditionAST = class(TConditionAST)
      FA: TTopic.TIndex;
      constructor Create(A: TTopic.TIndex);
      procedure Compile(var Target: TCompiledConditionTarget); override;
      function GetOperandDescription(): Word; override;
      procedure CollectResearches(var Collection: TResearchHashSet; const Negated: Boolean = False); override;
      function ConstantValue(): TConditionConstant; override;
   end;
   
   TPackageConditionAST = class(TConditionAST)
      procedure Compile(var Target: TCompiledConditionTarget); override;
      function GetOperandDescription(): Word; override;
      procedure CollectResearches(var Collection: TResearchHashSet; const Negated: Boolean = False); override;
      function ConstantValue(): TConditionConstant; override;
   end;

function EvaluateCondition(const Condition: PWord; const EvaluationContext: PResearchConditionEvaluationContext): Boolean;

{ Bitwise layout of operator words:

      Space reserved for
        pointer metadata ----------------+
               Operand 1 -------------+  |
               Operand 2 -----------+ |  |
      Operand 3 (unused) ---------+ | |  |
      Operand 4 (unused) -------+ | | |  |
                 End bit ------+| | | |  |
 Operator (and, or, etc) ----+ || | | |  |
  Operator bit indicator --+ | || | | |  |
                           | | || | | |  |
                          %1XXXEDDCCBBAAPPP

}
   
const
   OperatorBit          = %1000000000000000;

   OperatorMask         = %1111000000000000;
   OperatorSkip         = %1000000000000000;
   OperatorFalse        = %1001000000000000;
   OperatorTrue         = %1010000000000000;
   OperatorIdentity     = %1011000000000000;
   OperatorNot          = %1100000000000000;
   OperatorOr           = %1101000000000000;
   OperatorAnd          = %1110000000000000;

   OperatorEnd          = %0000100000000000;

   OperandMask          = %11;
   OperandResearch      = %00;
   OperandSituation     = %01;
   OperandTopic         = %10;

   OffsetOperand1       = 3;
   OffsetOperand2       = 5;

   OperandTrue          = $0000; // zero index is the root research, so we know it's always around
   OperandFalse         = $FFFE; // marked used for empty cells in the hash table, so guaranteed to not be present
   
implementation

uses
   exceptions, hashfunctions;

type
   EConditionEvaluator = class(Exception) end;


constructor TRootConditionAST.Create(A: TConditionAST);
begin
   FA := A;
end;

procedure TRootConditionAST.Compile(var Target: TCompiledConditionTarget);
begin
   case (FA.ConstantValue) of
      ccTrue: Target.Push(Word(OperatorTrue) or Word(OperatorEnd));
      ccFalse: Target.Push(Word(OperatorFalse) or Word(OperatorEnd));
      ccNotConstant:
         begin
            FA.Compile(Target);
            if ((FA.GetOperandDescription() <> OperandResearch) or ((Target.Last and OperatorBit) = 0)) then
            begin
               Target.Push(Word(OperatorIdentity) or Word(FA.GetOperandDescription() << OffsetOperand1) or Word(OperatorEnd));
            end
            else
            begin
               Target.Last := Target.Last or Word(OperatorEnd);
            end;
         end;
   end;
end;

function TRootConditionAST.GetOperandDescription(): Word;
begin
   Result := OperandResearch;
end;

destructor TRootConditionAST.Destroy();
begin
   FreeAndNil(FA);
   inherited;
end;

procedure TRootConditionAST.CollectResearches(var Collection: TResearchHashSet; const Negated: Boolean = False);
begin
   FA.CollectResearches(Collection, Negated);
end;

function TRootConditionAST.ConstantValue(): TConditionConstant;
begin
   Result := FA.ConstantValue();
end;


constructor TAndConditionAST.Create(A, B: TConditionAST);
begin
   FA := A;
   FB := B;
end;

procedure TAndConditionAST.Compile(var Target: TCompiledConditionTarget);
var
   A, B: TConditionConstant;
begin
   Assert(ConstantValue = ccNotConstant); // otherwise parent should handle us
   A := FA.ConstantValue();
   B := FB.ConstantValue();
   if ((A = ccNotConstant) and (B = ccNotConstant)) then
   begin
      FA.Compile(Target);
      FB.Compile(Target);
      Target.Push(Word(OperatorAnd) or Word(FA.GetOperandDescription() << OffsetOperand2) or Word(FB.GetOperandDescription() << OffsetOperand1));
   end
   else
   if (A = ccNotConstant) then
   begin
      Assert(B = ccTrue);
      FA.Compile(Target);
   end
   else
   begin
      Assert(B = ccNotConstant);
      Assert(A = ccTrue);
      FB.Compile(Target);
   end;
end;

function TAndConditionAST.GetOperandDescription(): Word;
var
   A, B: TConditionConstant;
begin
   A := FA.ConstantValue();
   B := FB.ConstantValue();
   if ((A = ccNotConstant) and (B = ccNotConstant)) then
   begin
      Result := OperandResearch;
   end
   else
   if (A = ccNotConstant) then
   begin
      Assert(B = ccTrue);
      Result := FA.GetOperandDescription();
   end
   else
   begin
      Assert(B = ccNotConstant);
      Assert(A = ccTrue);
      Result := FB.GetOperandDescription();
   end;
end;

destructor TAndConditionAST.Destroy();
begin
   FreeAndNil(FA);
   FreeAndNil(FB);
   inherited;
end;

procedure TAndConditionAST.CollectResearches(var Collection: TResearchHashSet; const Negated: Boolean = False);
begin
   FA.CollectResearches(Collection, Negated);
   FB.CollectResearches(Collection, Negated);
end;

function TAndConditionAST.ConstantValue(): TConditionConstant;
var
   A, B: TConditionConstant;
begin
   A := FA.ConstantValue();
   B := FB.ConstantValue();
   if ((A = ccNotConstant) or (B = ccNotConstant)) then
   begin
      Result := ccNotConstant;
   end
   else
   if ((A = ccFalse) or (B = ccFalse)) then
   begin
      Result := ccFalse;
   end
   else
   begin
      Assert(A = ccTrue);
      Assert(B = ccTrue);
      Result := ccTrue;
   end;
end;


constructor TOrConditionAST.Create(A, B: TConditionAST);
begin
   FA := A;
   FB := B;
end;

procedure TOrConditionAST.Compile(var Target: TCompiledConditionTarget);
var
   A, B: TConditionConstant;
begin
   Assert(ConstantValue = ccNotConstant); // otherwise parent should handle us
   A := FA.ConstantValue();
   B := FB.ConstantValue();
   if ((A = ccNotConstant) and (B = ccNotConstant)) then
   begin
      FA.Compile(Target);
      FB.Compile(Target);
      Target.Push(Word(OperatorOr) or Word(FA.GetOperandDescription() << OffsetOperand2) or Word(FB.GetOperandDescription() << OffsetOperand1));
   end
   else
   if (A = ccNotConstant) then
   begin
      Assert(B = ccFalse);
      FA.Compile(Target);
   end
   else
   begin
      Assert(B = ccNotConstant);
      Assert(A = ccFalse);
      FB.Compile(Target);
   end;
end;

function TOrConditionAST.GetOperandDescription(): Word;
var
   A, B: TConditionConstant;
begin
   A := FA.ConstantValue();
   B := FB.ConstantValue();
   if ((A = ccNotConstant) and (B = ccNotConstant)) then
   begin
      Result := OperandResearch;
   end
   else
   if (A = ccNotConstant) then
   begin
      Assert(B = ccFalse);
      Result := FA.GetOperandDescription();
   end
   else
   begin
      Assert(B = ccNotConstant);
      Assert(A = ccFalse);
      Result := FB.GetOperandDescription();
   end;
end;

destructor TOrConditionAST.Destroy();
begin
   FreeAndNil(FA);
   FreeAndNil(FB);
   inherited;
end;

procedure TOrConditionAST.CollectResearches(var Collection: TResearchHashSet; const Negated: Boolean = False);
begin
   FA.CollectResearches(Collection, Negated);
   FB.CollectResearches(Collection, Negated);
end;

function TOrConditionAST.ConstantValue(): TConditionConstant;
var
   A, B: TConditionConstant;
begin
   A := FA.ConstantValue();
   B := FB.ConstantValue();
   if ((A = ccNotConstant) or (B = ccNotConstant)) then
   begin
      Result := ccNotConstant;
   end
   else
   if ((A = ccTrue) or (B = ccTrue)) then
   begin
      Result := ccTrue;
   end
   else
   begin
      Assert((A = ccFalse) or (B = ccFalse));
      Result := ccFalse;
   end;
end;


constructor TNotConditionAST.Create(A: TConditionAST);
begin
   FA := A;
end;

procedure TNotConditionAST.Compile(var Target: TCompiledConditionTarget);
begin
   Assert(ConstantValue = ccNotConstant); // otherwise parent should handle us
   Assert(FA.ConstantValue = ccNotConstant); // otherwise we'd be constant
   FA.Compile(Target);
   Target.Push(Word(OperatorNot) or Word(FA.GetOperandDescription() << OffsetOperand1));
end;

function TNotConditionAST.GetOperandDescription(): Word;
begin
   Result := OperandResearch;
end;

destructor TNotConditionAST.Destroy();
begin
   FreeAndNil(FA);
   inherited;
end;

procedure TNotConditionAST.CollectResearches(var Collection: TResearchHashSet; const Negated: Boolean = False);
begin
   FA.CollectResearches(Collection, not Negated);
end;

function TNotConditionAST.ConstantValue(): TConditionConstant;
begin
   Result := FA.ConstantValue();
   if (Result = ccTrue) then
      Result := ccFalse
   else
   if (Result = ccFalse) then
      Result := ccTrue
   else
      Assert(Result = ccNotConstant);
end;


constructor TGroupConditionAST.Create(A: TConditionAST);
begin
   FA := A;
end;

procedure TGroupConditionAST.Compile(var Target: TCompiledConditionTarget);
begin
   Assert(ConstantValue = ccNotConstant); // otherwise parent should handle us
   Assert(FA.ConstantValue = ccNotConstant); // otherwise we'd be constant
   FA.Compile(Target);
end;

function TGroupConditionAST.GetOperandDescription(): Word;
begin
   Result := FA.GetOperandDescription();
end;

destructor TGroupConditionAST.Destroy();
begin
   FreeAndNil(FA);
   inherited;
end;

procedure TGroupConditionAST.CollectResearches(var Collection: TResearchHashSet; const Negated: Boolean = False);
begin
   FA.CollectResearches(Collection, Negated);
end;

function TGroupConditionAST.ConstantValue(): TConditionConstant;
begin
   Result := FA.ConstantValue();
end;


constructor TResearchListHashTable.Create();
begin
   inherited Create(@UTF8StringHash32);
end;


constructor TResearchListConditionAST.Create(A: PResearchList);
begin
   FA := A;
end;

procedure TResearchListConditionAST.Compile(var Target: TCompiledConditionTarget);
var
   Count, Index: Cardinal;
begin
   Assert(ConstantValue = ccNotConstant); // otherwise parent should handle us
   Count := FA^.Length;
   if (Count = 0) then
   begin
      Assert(False, 'not reachable'); // because otherwise we'd be constant
      Target.Push(OperandFalse);
   end
   else
   begin
      Target.Push(FA^[0]);
      if (Count >= 2) then
      begin
         Assert(OperandResearch = 0); // otherwise we need to adjust bits of OperatorOr below
         for Index := 1 to Count - 1 do // $R-
         begin
            Target.Push(FA^[Index]);
            Target.Push(OperatorOr);
         end;
      end;
   end;
end;

function TResearchListConditionAST.GetOperandDescription(): Word;
begin
   Result := OperandResearch;
end;

procedure TResearchListConditionAST.CollectResearches(var Collection: TResearchHashSet; const Negated: Boolean = False);
var
   Entry: TResearchIndex;
begin
   if (Negated) then
      exit;
   for Entry in FA^ do
      if (not Collection.Has(Entry)) then
         Collection.Add(Entry);
end;

function TResearchListConditionAST.ConstantValue(): TConditionConstant;
begin
   if (FA^.Length = 0) then
      Result := ccFalse
   else
      Result := ccNotConstant;
end;


procedure TNothingConditionAST.Compile(var Target: TCompiledConditionTarget);
begin
   Assert(False, 'not reachable'); // we are always constant so parent should always optimize us out
   Target.Push(OperandTrue);
end;

function TNothingConditionAST.GetOperandDescription(): Word;
begin
   Result := OperandResearch;
end;

procedure TNothingConditionAST.CollectResearches(var Collection: TResearchHashSet; const Negated: Boolean = False);
begin
   if (not Negated and not Collection.Has(0)) then
      Collection.Add(0);
end;

function TNothingConditionAST.ConstantValue(): TConditionConstant;
begin
   Result := ccTrue;
end;


constructor TSituationConditionAST.Create(A: TSituation);
begin
   FA := A;
end;

procedure TSituationConditionAST.Compile(var Target: TCompiledConditionTarget);
begin
   Assert(ConstantValue = ccNotConstant); // otherwise parent should handle us
   Target.Push(FA);
end;

function TSituationConditionAST.GetOperandDescription(): Word;
begin
   Result := OperandSituation;
end;

procedure TSituationConditionAST.CollectResearches(var Collection: TResearchHashSet; const Negated: Boolean = False);
begin
end;

function TSituationConditionAST.ConstantValue(): TConditionConstant;
begin
   Result := ccNotConstant;
end;


constructor TTopicConditionAST.Create(A: TTopic.TIndex);
begin
   FA := A;
end;

procedure TTopicConditionAST.Compile(var Target: TCompiledConditionTarget);
begin
   Assert(ConstantValue = ccNotConstant); // otherwise parent should handle us
   Target.Push(FA);
end;

function TTopicConditionAST.GetOperandDescription(): Word;
begin
   Result := OperandTopic;
end;

procedure TTopicConditionAST.CollectResearches(var Collection: TResearchHashSet; const Negated: Boolean = False);
begin
end;

function TTopicConditionAST.ConstantValue(): TConditionConstant;
begin
   Result := ccNotConstant;
end;


procedure TPackageConditionAST.Compile(var Target: TCompiledConditionTarget);
begin
   Assert(ConstantValue = ccNotConstant); // otherwise parent should handle us
   Target.Push(OperandFalse);
end;

function TPackageConditionAST.GetOperandDescription(): Word;
begin
   Result := OperandResearch;
end;

procedure TPackageConditionAST.CollectResearches(var Collection: TResearchHashSet; const Negated: Boolean = False);
begin
end;

function TPackageConditionAST.ConstantValue(): TConditionConstant;
begin
   Result := ccNotConstant;
end;


function EvaluateCondition(const Condition: PWord; const EvaluationContext: PResearchConditionEvaluationContext): Boolean;
const
   MaxStack = 7;
var
   Stack: array[0..MaxStack] of Word;
   Instruction: Word;
   ConditionIndex, StackIndex: Integer;
   Op1, Op2: Boolean;

   function Evaluate(OperandType: Word): Boolean;
   var
      Value: Word;
   begin
      Assert(StackIndex >= Low(Stack));
      Assert(StackIndex <= High(Stack));
      case (OperandType) of
         OperandResearch: begin
            Value := Stack[StackIndex];
            if (Value = OperandTrue) then
               Result := True
            else
            if (Value = OperandFalse) then
               Result := False
            else
               Result := EvaluationContext^.KnownResearches.Has(Value);
         end;
         OperandSituation: begin
            Result := EvaluationContext^.Situations.Has(Stack[StackIndex]);
         end;
         OperandTopic: begin
            Result := EvaluationContext^.SelectedTopic = Stack[StackIndex];
         end;
      else
         raise EConditionEvaluator.CreateFmt('unknown operand type: %s', [BinStr(OperandType, 2)]);
      end;
      {$IFDEF VERBOSE} Writeln('   READ => ', OperandType, ' ', BinStr(Stack[StackIndex], 16), ' ', Result); {$ENDIF}
   end;

var
   OperandResult, Done: Boolean;
begin
   Assert(Assigned(Condition));
   ConditionIndex := 0;
   StackIndex := -1;
   Done := False;
   {$IFDEF VERBOSE} Writeln('Evaluating condition at ', HexStr(Condition)); {$ENDIF}
   repeat
      Instruction := Condition[ConditionIndex];
      {$IFDEF VERBOSE} Writeln('  Instruction ', ConditionIndex, ': ', BinStr(Instruction, 16), '   Stack Index: ', StackIndex); {$ENDIF}
      Inc(ConditionIndex);
      if ((Instruction and OperatorBit) > 0) then
      begin
         case (Instruction and OperatorMask) of
            OperatorSkip: begin
               {$IFDEF VERBOSE} Writeln('    SKIP'); {$ENDIF}
               continue;
            end;
            OperatorFalse: begin
               {$IFDEF VERBOSE} Writeln('    PUSH FALSE'); {$ENDIF}
               Inc(StackIndex);
               OperandResult := False;
            end;
            OperatorTrue: begin
               {$IFDEF VERBOSE} Writeln('    PUSH TRUE'); {$ENDIF}
               Inc(StackIndex);
               OperandResult := True;
            end;
            OperatorIdentity: begin
               OperandResult := Evaluate(Word(Instruction >> OffsetOperand1) and Word(OperandMask));
               {$IFDEF VERBOSE} Writeln('    IDENTITY => ', OperandResult); {$ENDIF}
            end;
            OperatorNot: begin
               OperandResult := not Evaluate(Word(Instruction >> OffsetOperand1) and Word(OperandMask));
               {$IFDEF VERBOSE} Writeln('    NOT => ', OperandResult); {$ENDIF}
            end;
            OperatorAnd: begin
               Op1 := Evaluate(Word(Instruction >> OffsetOperand1) and Word(OperandMask));
               Dec(StackIndex);
               if (StackIndex < Low(Stack)) then
                  raise EConditionEvaluator.Create('stack underflow');
               Op2 := Evaluate(Word(Instruction >> OffsetOperand2) and Word(OperandMask));
               OperandResult := Op1 and Op2;
               {$IFDEF VERBOSE} Writeln('    POP'); {$ENDIF}
               {$IFDEF VERBOSE} Writeln('    AND => ', OperandResult); {$ENDIF}
            end;
            OperatorOr: begin
               Op1 := Evaluate(Word(Instruction >> OffsetOperand1) and Word(OperandMask));
               Dec(StackIndex);
               if (StackIndex < Low(Stack)) then
                  raise EConditionEvaluator.Create('stack underflow');
               Op2 := Evaluate(Word(Instruction >> OffsetOperand2) and Word(OperandMask));
               OperandResult := Op1 or Op2;
               {$IFDEF VERBOSE} Writeln('    POP'); {$ENDIF}
               {$IFDEF VERBOSE} Writeln('    OR => ', OperandResult); {$ENDIF}
            end;
         else
            raise EConditionEvaluator.CreateFmt('unknown operator: %s', [BinStr(Instruction and OperatorMask, 3)]);
         end;
         if (StackIndex < Low(Stack)) then
            raise EConditionEvaluator.Create('stack index inconsistent');
         if (OperandResult) then
            Stack[StackIndex] := OperandTrue
         else
            Stack[StackIndex] := OperandFalse;
         Done := (Instruction and OperatorEnd) > 0;
      end
      else
      begin
         Inc(StackIndex);
         if (StackIndex > High(Stack)) then
            raise EConditionEvaluator.Create('stack overflow');
         Stack[StackIndex] := Instruction;
         {$IFDEF VERBOSE} Writeln('    PUSH'); {$ENDIF}
      end;
   until Done;
   if (StackIndex <> Low(Stack)) then
      raise EConditionEvaluator.Create('invalid condition program, did not end with one value on the stack');
   Result := Evaluate(OperandResearch);
end;

end.