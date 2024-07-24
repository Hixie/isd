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
      function GetCardinal(Index: Cardinal): Cardinal; inline;
   public
      Buffer: Pointer; // includes leading file identifier
      Length: Cardinal;
      procedure Init(Filename: UTF8String);
      procedure Free();
      property Cardinals[Index: Cardinal]: Cardinal read GetCardinal;
   end;

implementation

uses
   sysutils, exceptions;

procedure TBinaryFile.Init(Filename: UTF8String);
var
   Error: cint;
   BufferAsError: PtrInt;
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
   BufferAsError := PtrInt(Buffer); // {BOGUS Hint: Conversion between ordinals and pointers is not portable}
   if (BufferAsError < 0) then
   begin
      if ((BufferAsError < Low(Error)) or (BufferAsError > High(Error))) then
      begin
         raise EKernelError.Create(ESysEOverflow);
      end;
      raise EKernelError.Create(BufferAsError); // $R-
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

function TBinaryFile.GetCardinal(Index: Cardinal): Cardinal; inline;
type
   PCardinalArray = ^TCardinalArray;
   TCardinalArray = array[0..High(Integer)] of Cardinal;
begin
   Assert(Index < Length div SizeOf(Cardinal));
   Result := PCardinalArray(Buffer)^[Index];
end;

end.
