{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit commonbuses;

interface

uses
   systems;

type
   TDisabledReason = (
      drManuallyDisabled, // Manually disabled.
      drStructuralIntegrity, // Structural integrity has not yet reached minimum functional threshold.
      drNoBus // not usually used with TCheckDisabledBusMessage, but indicates no appropriate bus could be reached (e.g. TRegionFeatureNode for mining/refining, or TBuilderBusFeatureNode for builders).
   );
   TDisabledReasons = set of TDisabledReason;
   
   TCheckDisabledBusMessage = class(TBusMessage)
   strict private
      FReasons: TDisabledReasons;
   public
      procedure AddReason(Reason: TDisabledReason);
      property Reasons: TDisabledReasons read FReasons;
   end; // should be injected using Parent.HandleBusMessage
   
function CheckDisabled(Asset: TAssetNode): TDisabledReasons;

implementation

uses
   sysutils;

procedure TCheckDisabledBusMessage.AddReason(Reason: TDisabledReason);
begin
   Include(FReasons, Reason);
end;

function CheckDisabled(Asset: TAssetNode): TDisabledReasons;
var
   OnOffMessage: TCheckDisabledBusMessage;
begin
   OnOffMessage := TCheckDisabledBusMessage.Create();
   Asset.HandleBusMessage(OnOffMessage);
   Result := OnOffMessage.Reasons;
   FreeAndNil(OnOffMessage);
end;

end.