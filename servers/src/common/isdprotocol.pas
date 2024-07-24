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
   fcTerminator = $00000000;
   fcStar = $00000001;
   fcSpace = $00000002;
   fcOrbit = $00000003;
   fcStructure = $00000004;
   fcHighestKnownFeatureCode = fcStructure;
   
implementation

end.