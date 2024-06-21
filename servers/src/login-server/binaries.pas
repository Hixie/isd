{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit binaries;

interface

uses
   baseunix;

type
   TBinaryFile = record
   private
      fd: cint;
   public
      Buffer: Pointer; // includes leading file identifier
      Length: Cardinal;
      procedure Init(Filename: UTF8String);
      procedure Free();
   end;

implementation

uses
   sysutils, exceptions;

procedure TBinaryFile.Init(Filename: UTF8String);
var
   Error: cint;
   Info: Stat;
begin
   fd := fpOpen(Filename, O_RDONLY);
   if (fd < 0) then
   begin
      raise EFileNotFoundException.Create('Could not find ' + Filename);
   end;
   Error := fpFstat(fd, Info); // $DFA- for Info
   if (Error <> 0) then
   begin
      raise EKernelError.Create(Error);
   end;
   if (Info.st_size > High(Length)) then
   begin
      raise Exception('Unexpectedly large binary file: ' + Filename + ' has ' + IntToStr(Info.st_size) + ' bytes.');
   end;
   Length := Info.st_size; // $R-
   Buffer := fpMmap(nil, Length, PROT_READ, MAP_SHARED, fd, 0);
   if (PtrInt(Buffer) < 0) then // {BOGUS Hint: Conversion between ordinals and pointers is not portable}
   begin
      raise EKernelError.Create(PtrInt(Buffer)); // {BOGUS Hint: Conversion between ordinals and pointers is not portable}
   end;
end;

procedure TBinaryFile.Free();
var
   Error: cint;
begin
   fpClose(fd);
   Error := fpMunmap(Buffer, Length);
   if (Error <> 0) then
   begin
      raise EKernelError.Create(Error);
   end;
end;

end.
