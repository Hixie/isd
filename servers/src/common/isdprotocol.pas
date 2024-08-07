{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit isdprotocol;

interface

const
   // ISD Commands (client-to-server or server-to-server)
   icCreateAccount = 'create-account';
   icRegisterToken = 'register-token';
   icLogout = 'logout';
   icCreateSystem = 'create-system'; // internal
   icTriggerNewDynastyScenario = 'trigger-scenario-new-dynasty'; // internal
   icAddSystemServer = 'add-system-server'; // internal
   icRemoveSystemServer = 'remove-system-server'; // internal
   // ISD Updates (server-to-client)
   iuSystemServers = 'system-servers';
   TokenSeparator = #$1F;

const
   // These must increment monotonically and their values must never change
   // during the history of the project.
   fcTerminator = 0;
   fcStar = 1;
   fcSpace = 2;
   fcOrbit = 3;
   fcStructure = 4;
   fcSpaceSensor = 5;
   fcSpaceSensorStatus = 6;
   fcHighestKnownFeatureCode = fcSpaceSensorStatus;
   
implementation

end.