{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit isdprotocol;

interface

const
   // Internal ISD Commands (server-to-server)
   icCreateAccount = 'create-account';
   icRegisterToken = 'register-token';
   icLogout = 'logout';
   icCreateSystem = 'create-system';
   icTriggerNewDynastyScenario = 'trigger-scenario-new-dynasty';
   icAddSystemServer = 'add-system-server';
   icRemoveSystemServer = 'remove-system-server';
   icAddScoreDatum = 'add-score';
   icUpdateScoreDatum = 'update-score';
   {$IFDEF TESTSUITE}
   icAdvanceClock = 'advance-clock';
   icAwaitScores = 'await-scores';
   icResetRNG = 'reset-rng';
   {$ENDIF}

const
   // ISD updates (server-to-client)
   iuSystemServers = 'system-servers';
   TokenSeparator = #$1F;

const
   // Client commands
   ccDismantle = 'dismantle';
   ccBuild = 'build';
   ccMarkRead = 'mark-read';
   ccMarkUnread = 'mark-unread';
   ccEnable = 'enable';
   ccDisable = 'disable';
   ccAnalyze = 'analyze';
   ccGetTopics = 'get-topics';
   ccSetTopic = 'set-topic';
   ccRate = 'set-rate';
   ccSampleOre = 'sample-ore';
   ccClearSamples = 'clear-sample';

const
   ieInvalidMessage = 'invalid message';
   ieUnrecognizedCredentials = 'unrecognized credentials';
   ieInadequateUsername = 'inadequate username';
   ieInadequatePassword = 'inadequate password';
   ieInternalError = 'internal error';
   ieUnknownFileCode = 'unknown file code';
   ieNotLoggedIn = 'not logged in';
   ieInvalidCommand = 'invalid command';
   ieUnknownDynasty = 'unknown dynasty';
   ieNoDestructors = 'no destructors';
   ieRangeError = 'range error';
   ieNotOwner = 'not owner';

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
   fcBuilder = $1A;
   fcInternalSensor = $1B;
   fcInternalSensorStatus = $1C;
   fcOnOff = $1D;
   fcStaffing = $1E;
   fcAssetPile = $1F;
   fcFactory = $20;
   fcSample = $21;
   fcHighestKnownFeatureCode = fcSample;

type
   TAssetClassID = LongInt; // signed because negative values are built-in, and positive values are in tech tree

const
   // built-in asset classes
   idSpace = -1;
   idOrbits = -2;
   idPlaceholderShip = -3;
   idMessage = -4;
   idCrater = -5;
   idRubblePile = -6;
   idStars = -100; // -100..-199
   idPlanetaryBody = -200;
   idRegion = -201;

const
   // built-in materials
   idDarkMatter = -1;

const
   // built-in research
   idPlaceholderShipInstructionManualResearch = -1;

type
   TIcon = String[32];

const
   UnknownIcon = 'unknown';

{$IFOPT C+}
// Stdout control codes for tests.
const
   ControlReady = #05; // Enquiry (network listeners are ready to accept connections)
   ControlEnd = #04; // End Of Transmission (server ended without any exceptions)
   ControlError = #21; // Negative Acknowledge (server caught a problem)
{$ENDIF}

implementation

end.