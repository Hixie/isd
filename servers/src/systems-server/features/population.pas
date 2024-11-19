{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit population;

interface

uses
   systems, systemdynasty, serverstream, materials;

type
   TPopulationFeatureClass = class(TFeatureClass)
   strict protected
      function GetFeatureNodeClass(): FeatureNodeReference; override;
   public
      function InitFeatureNode(): TFeatureNode; override;
   end;

   TPopulationFeatureNode = class(TFeatureNode)
   private
      FPopulation: Int64;
      FMeanHappiness: Double;
   protected
      function GetMass(): Double; override;
      function GetSize(): Double; override;
      function GetFeatureName(): UTF8String; override;
      procedure Walk(PreCallback: TPreWalkCallback; PostCallback: TPostWalkCallback); override;
      function HandleBusMessage(Message: TBusMessage): Boolean; override;
      procedure Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter; System: TSystem); override;
   public
      constructor CreatePopulated(APopulation: Int64; AMeanHappiness: Double); // only for use in plot-generated population centers
      procedure UpdateJournal(Journal: TJournalWriter); override;
      procedure ApplyJournal(Journal: TJournalReader; System: TSystem); override;
   end;

implementation

uses
   isdprotocol;

const
   MeanIndividualMass = 70; // kg // TODO: allow species to diverge and such, with different demographics, etc

function TPopulationFeatureClass.GetFeatureNodeClass(): FeatureNodeReference;
begin
   Result := TPopulationFeatureNode;
end;

function TPopulationFeatureClass.InitFeatureNode(): TFeatureNode;
begin
   Result := TPopulationFeatureNode.Create();
end;


constructor TPopulationFeatureNode.CreatePopulated(APopulation: Int64; AMeanHappiness: Double);
begin
   inherited Create();
   FPopulation := APopulation;
   FMeanHappiness := AMeanHappiness;
end;

function TPopulationFeatureNode.GetMass(): Double;
begin
   Result := MeanIndividualMass * FPopulation;
end;

function TPopulationFeatureNode.GetSize(): Double;
begin
   Result := 0.0;
end;

function TPopulationFeatureNode.GetFeatureName(): UTF8String;
begin
   Result := '';
end;

procedure TPopulationFeatureNode.Walk(PreCallback: TPreWalkCallback; PostCallback: TPostWalkCallback);
begin
end;

function TPopulationFeatureNode.HandleBusMessage(Message: TBusMessage): Boolean;
begin
   Result := False;
end;

procedure TPopulationFeatureNode.Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter; System: TSystem);
begin
   Writer.WriteCardinal(fcPopulation);
   Writer.WriteInt64(FPopulation);
   Writer.WriteDouble(FMeanHappiness);
end;

procedure TPopulationFeatureNode.UpdateJournal(Journal: TJournalWriter);
begin
   Journal.WriteInt64(FPopulation);
   Journal.WriteDouble(FMeanHappiness);
end;

procedure TPopulationFeatureNode.ApplyJournal(Journal: TJournalReader; System: TSystem);
begin
   FPopulation := Journal.ReadInt64();
   FMeanHappiness := Journal.ReadDouble();
end;

end.