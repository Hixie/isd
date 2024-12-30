{$IFNDEF INCLUDING} { -*- delphi -*- }
{$DEFINE INCLUDING}
{$MODE OBJFPC}
{$INCLUDE settings.inc}
unit authnetwork;

interface

uses
   sysutils, passwords, basenetwork, basedynasty;

type
   TAuthenticatableBaseIncomingConnection = class(TBaseIncomingCapableConnection)
   protected
      function GetDynasty(DynastyID: Cardinal): TBaseDynasty; virtual; abstract;
      function VerifyLogin(var Message: TMessage): Integer;
   end;

   TAuthenticatableBaseIncomingInternalCapableConnection = class(TBaseIncomingInternalCapableConnection)
   protected
      function GetDynasty(DynastyID: Cardinal): TBaseDynasty; virtual; abstract;
      function VerifyLogin(var Message: TMessage): Integer;
   end;
   
implementation

uses
   isdprotocol, isderrors, intutils;

function TAuthenticatableBaseIncomingConnection.VerifyLogin(var Message: TMessage): Integer;
{$I *}

function TAuthenticatableBaseIncomingInternalCapableConnection.VerifyLogin(var Message: TMessage): Integer;
{$I *}

end.
{$ELSE}

// VerifyLogin body (identical in both implementations)
var
   Token: UTF8String;
   SeparatorIndex: Cardinal;
   Dynasty: TBaseDynasty;
begin
   Dynasty := nil;
   Result := -1;
   Token := Message.Input.ReadString(MaxTokenLength); // arbitrary length limit
   SeparatorIndex := Pos(TokenSeparator, Token); // $R-
   if ((SeparatorIndex < 2) or (Length(Token) - SeparatorIndex <= 0)) then
   begin
      Message.Error(ieUnrecognizedCredentials);
      exit;
   end;     
   Result := ParseInt32(Copy(Token, 1, SeparatorIndex - 1), -1);
   if (Result < 0) then
   begin
      Message.Error(ieUnrecognizedCredentials);
      exit;
   end;
   Dynasty := GetDynasty(Result); // $R-
   if ((not Assigned(Dynasty)) or (not Dynasty.VerifyToken(Copy(Token, SeparatorIndex + 1, Length(Token) - SeparatorIndex)))) then
   begin
      Message.Error(ieUnrecognizedCredentials);
      Result := -1;
      exit;
   end;
   if (not Message.CloseInput()) then
   begin
      Result := -1;
      exit;
   end;
end;
{$ENDIF}