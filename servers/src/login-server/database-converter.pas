{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
program converter;
uses sysutils;

type
   TOldDynastyRecord = record
   public
      const
         MaxUsernameLength = 127; // plus one byte for the length
         SaltLength = 8;
         SHA256Length = 32;
         DynastyServerLength = 255;
      var
         Username: String[MaxUsernameLength];
         Salt: array[0..SaltLength-1] of Byte;
         PasswordHash: array[0..SHA256Length-1] of Byte; // SHA256
         DynastyServer: String[DynastyServerLength];
   end;

   TNewDynastyRecord = record
   public
      const
         MaxUsernameLength = 127; // plus one byte for the length
         SaltLength = 8;
         SHA256Length = 32;
      var
         Username: String[MaxUsernameLength];
         Salt: array[0..SaltLength-1] of Byte;
         PasswordHash: array[0..SHA256Length-1] of Byte; // SHA256
         DynastyServer: Cardinal;
   end;

var
   InputFile: File of TOldDynastyRecord;
   OutputFile: File of TNewDynastyRecord;
   Filename: UTF8String;
   InputRecord: TOldDynastyRecord;
   OutputRecord: TNewDynastyRecord;
   Count: Integer;
begin
   if (ParamCount() <> 2) then
   begin
      Writeln('usage: database-converter <input> <output>');
      exit;
   end;
   Filename := ParamStr(1);
   if (not FileExists(Filename)) then
   begin
      Writeln('Input file does not exist: ', Filename);
      exit;
   end;
   Assign(InputFile, Filename);
   Reset(InputFile);
   Filename := ParamStr(2);
   if (FileExists(Filename)) then
   begin
      Writeln('Output file already exists: ', Filename);
      exit;
   end;
   Assign(OutputFile, Filename);
   Rewrite(OutputFile);
   while (not Eof(InputFile)) do
   begin
      BlockRead(InputFile, InputRecord, 1, Count);
      if (Count <> 1) then
      begin
         Writeln('Failed to read record.');
         exit;
      end;
      FillChar(OutputRecord, SizeOf(OutputRecord), 0);
      OutputRecord.Username := InputRecord.Username;
      Move(InputRecord.Salt[0], OutputRecord.Salt[0], Length(OutputRecord.Salt));
      Move(InputRecord.PasswordHash[0], OutputRecord.PasswordHash[0], Length(OutputRecord.PasswordHash));
      OutputRecord.DynastyServer := 0;
      BlockWrite(OutputFile, OutputRecord, 1, Count);
      if (Count <> 1) then
      begin
         Writeln('Failed to write record.');
         exit;
      end;
   end;
   Close(InputFile);
   Close(OutputFile);
end.