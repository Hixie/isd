{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit harness;

interface

uses
   sysutils;

type
   TIsdTest = class abstract
      procedure RunTest(const BaseDirectory, TestDirectory: UTF8String); virtual; abstract;
   end;

const
   TestTimeout = 5000; // 5 seconds

procedure RegisterTest(Test: TIsdTest);
procedure RunTests(BaseDirectory: UTF8String);

procedure Verify(Condition: Boolean);

implementation

uses
   plasticarrays, genericutils, fileutils;

var
   Tests: specialize PlasticArray<TIsdTest, PointerUtils>;

procedure RegisterTest(Test: TIsdTest);
begin
   Tests.Push(Test);
end;

procedure RunTests(BaseDirectory: UTF8String);
var
   Test: TIsdTest;
   TestDirectory: UTF8String;
begin
   if ((not DirectoryExists(BaseDirectory + 'defaults')) or
       (not DirectoryExists(BaseDirectory + 'runtime'))) then
      raise Exception.Create('Specified directory is not fully configured for tests.');
   for Test in Tests do
   begin
      TestDirectory := GetTempFileName(BaseDirectory + 'runtime', 'isd' + '-' + Test.UnitName + '-') + '/';
      CreateDir(TestDirectory);
      try
         Test.RunTest(BaseDirectory, TestDirectory);
      finally
         DeleteDirectoryRecursively(TestDirectory);
      end;
   end;
end;

procedure Verify(Condition: Boolean);
begin
   if (not Condition) then
      raise Exception.Create('test failure');
end;

var
   Test: TIsdTest;
finalization
   for Test in Tests do
      Test.Free();
end.