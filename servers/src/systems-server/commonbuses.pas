{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit commonbuses;

interface

uses
   systems;

type
   TPriority = 0..2147483647;
   TManualPriority = 1..1073741823;
   TAutoPriority = 1073741824..2147483646;
   
const
   NoPriority = 2147483647; // used by some features to track that they couldn't find a bus, by others as a marker for deleted nodes; should never be exposed (even internally)

type
   TDisabledReason = (
      drManuallyDisabled, // Manually disabled.
      drStructuralIntegrity, // Structural integrity has not yet reached minimum functional threshold.
      drNoBus, // not usually used with TCheckDisabledBusMessage, but indicates no appropriate bus could be reached (e.g. TRegionFeatureNode for mining/refining, or TBuilderBusFeatureNode for builders).
      drUnderstaffed // Staffing levels are below required levels for funcionality.
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
   try
      Asset.HandleBusMessage(OnOffMessage);
      Result := OnOffMessage.Reasons;
   finally
      FreeAndNil(OnOffMessage);
   end;
end;

end.