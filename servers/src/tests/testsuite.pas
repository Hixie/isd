{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
program testsuite;

uses
   {$INCLUDE tests.inc}
   harness;

begin
   Writeln('Running tests...');
   RunTests('src/tests/data/');
   Writeln('Tests passed.');
   {$IFOPT C+}
   GlobalSkipIfNoLeaks := True;
   {$ENDIF}
end.