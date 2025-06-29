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
   fcStar = $01;
   fcSpace = $02;
   fcOrbit = $03;
   fcStructure = $04;
   fcSpaceSensor = $05;
   fcSpaceSensorStatus = $06;
   fcPlanetaryBody = $07;
   fcPlotControl = $08;
   fcSurface = $09;
   fcGrid = $0A;
   fcPopulation = $0B;
   fcMessageBoard = $0C;
   fcMessage = $0D;
   fcRubblePile = $0E;
   fcProxy = $0F;
   fcKnowledge = $10;
   fcResearch = $11;
   fcMining = $12;
   fcOrePile = $13;
   fcRegion = $14;
   fcRefining = $15;
   fcMaterialPile = $16;
   fcMaterialStack = $17;
   fcGridSensor = $18;
   fcGridSensorStatus = $19;
   fcHighestKnownFeatureCode = fcGridSensorStatus;
   
implementation

end.