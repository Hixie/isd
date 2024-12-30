{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit food;

interface

uses
   systems, systemdynasty, serverstream, materials, hashtable, genericutils;

type
   IFoodConsumer = interface ['IFoodConsumer']
      function GetOwner(): TDynasty;
      procedure SetFoodUsage(Quantity: Int64);
      property Owner: TDynasty read GetOwner;
   end;

   IFoodGenerator = interface ['IFoodGenerator']
      function GetOwner(): TDynasty;
      procedure SetFoodConsumption(Quantity: Int64);
      property Owner: TDynasty read GetOwner;
   end;

type
   TFoodBusFeatureNode = class;
   
   TInitFoodMessage = class(TPhysicalConnectionBusMessage)
   private
      type
         PGeneratorReport = ^TGeneratorReport;
         TGeneratorReport = record
            Quantity: Int64;
         end;
         PConsumerReport = ^TConsumerReport;
         TConsumerReport = record
            Quantity: Int64;
         end;
         TGenerators = specialize THashTable<IFoodGenerator, PGeneratorReport, PointerUtils>;
         TConsumers = specialize THashTable<IFoodConsumer, PConsumerReport, PointerUtils>;
         PFoodReport = ^TFoodReport;
         TFoodReport = record
            Generators: TGenerators;
            Consumers: TConsumers;
         end;
         TDynastyFoodReport = specialize THashTable<TDynasty, PFoodReport, TObjectUtils>;
      var
         FFoodReports: TDynastyFoodReport;
         FClaimed: Boolean;
      procedure Process();
      function ReportFor(Dynasty: TDynasty): PFoodReport;   
   public
      constructor Create();
      destructor Destroy(); override;
      procedure RequestFoodToEat(Target: IFoodConsumer; Quantity: Int64);
      procedure ReportFoodGenerationCapacity(Target: IFoodGenerator; Quantity: Int64);
   end;   
   
   TFoodBusFeatureClass = class(TFeatureClass)
   strict protected
      function GetFeatureNodeClass(): FeatureNodeReference; override;
   public
      function InitFeatureNode(): TFeatureNode; override;
   end;
   
   TFoodBusFeatureNode = class(TFeatureNode)
   protected
      function ManageBusMessage(Message: TBusMessage): Boolean; override;
      procedure HandleChanges(); override;
      procedure Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter; CachedSystem: TSystem); override;
   public
      destructor Destroy(); override;
      procedure UpdateJournal(Journal: TJournalWriter); override;
      procedure ApplyJournal(Journal: TJournalReader; CachedSystem: TSystem); override;
   end;

type
   TFoodGenerationFeatureClass = class(TFeatureClass)
   strict private
      FSize: Int64;
   strict protected
      function GetFeatureNodeClass(): FeatureNodeReference; override;
   public
      constructor Create(ASize: Int64);
      function InitFeatureNode(): TFeatureNode; override;
      property Size: Int64 read FSize;
   end;

   TFoodGenerationFeatureNode = class(TFeatureNode, IFoodGenerator)
   strict private
      FFeatureClass: TFoodGenerationFeatureClass;
      FFoodConsumption: Int64;
      function GetOwner(): TDynasty;
      procedure SetFoodConsumption(Quantity: Int64);
   protected
      constructor CreateFromJournal(Journal: TJournalReader; AFeatureClass: TFeatureClass; ASystem: TSystem); override;
      function HandleBusMessage(Message: TBusMessage): Boolean; override;
      procedure Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter; CachedSystem: TSystem); override;
   public
      constructor Create(AFeatureClass: TFoodGenerationFeatureClass);
      procedure UpdateJournal(Journal: TJournalWriter); override;
      procedure ApplyJournal(Journal: TJournalReader; CachedSystem: TSystem); override;
   end;

implementation

uses
   sysutils, hashfunctions, exceptions;

function IFoodGeneratorHash32(const Key: IFoodGenerator): DWord;
begin
   Result := PointerHash32(Key);
end;

function IFoodConsumerHash32(const Key: IFoodConsumer): DWord;
begin
   Result := PointerHash32(Key);
end;


constructor TInitFoodMessage.Create();
begin
   inherited Create();
   FFoodReports := TDynastyFoodReport.Create(@DynastyHash32);
end;

destructor TInitFoodMessage.Destroy();
var
   FoodReport: PFoodReport;
   GeneratorReport: PGeneratorReport;
   ConsumerReport: PConsumerReport;
begin
   for FoodReport in FFoodReports.Values do
   begin
      for GeneratorReport in FoodReport^.Generators.Values do
         Dispose(GeneratorReport);
      FoodReport^.Generators.Free();
      for ConsumerReport in FoodReport^.Consumers.Values do
         Dispose(ConsumerReport);
      FoodReport^.Consumers.Free();
      Dispose(FoodReport);
   end;
   FFoodReports.Free();
   inherited;
end;

function TInitFoodMessage.ReportFor(Dynasty: TDynasty): PFoodReport;
begin
   Result := FFoodReports[Dynasty];
   if (not Assigned(Result)) then
   begin
      New(Result);
      Result^.Generators := TGenerators.Create(@IFoodGeneratorHash32);
      Result^.Consumers := TConsumers.Create(@IFoodConsumerHash32);
      FFoodReports[Dynasty] := Result;
   end;
end;

procedure TInitFoodMessage.RequestFoodToEat(Target: IFoodConsumer; Quantity: Int64);
var
   FoodReport: PFoodReport;
   ConsumerReport: PConsumerReport;
begin
   FoodReport := ReportFor(Target.Owner);
   New(ConsumerReport);
   ConsumerReport^.Quantity := Quantity;
   FoodReport^.Consumers[Target] := ConsumerReport;
end;

procedure TInitFoodMessage.ReportFoodGenerationCapacity(Target: IFoodGenerator; Quantity: Int64);
var
   FoodReport: PFoodReport;
   GeneratorReport: PGeneratorReport;
begin
   FoodReport := ReportFor(Target.Owner);
   New(GeneratorReport);
   GeneratorReport^.Quantity := Quantity;
   FoodReport^.Generators[Target] := GeneratorReport;
end;

procedure TInitFoodMessage.Process();
var
   Dynasty: TDynasty;
   FoodReport: PFoodReport;
   ConsumerReport: PConsumerReport;
   GeneratorReport: PGeneratorReport;
   TotalGeneration, TotalConsumption: Int64;
   GeneratorFactor, ConsumerFactor: Double;
   Generator: IFoodGenerator;
   Consumer: IFoodConsumer;
begin
   for Dynasty in FFoodReports do
   begin
      FoodReport := FFoodReports[Dynasty];
      TotalGeneration := 0;
      for GeneratorReport in FoodReport^.Generators.Values do
         Inc(TotalGeneration, GeneratorReport^.Quantity);
      TotalConsumption := 0;
      for ConsumerReport in FoodReport^.Consumers.Values do
         Inc(TotalConsumption, ConsumerReport^.Quantity);
      if (TotalGeneration > TotalConsumption) then
      begin
         GeneratorFactor := TotalConsumption / TotalGeneration;
         ConsumerFactor := 1.0;
      end
      else
      if (TotalGeneration < TotalConsumption) then
      begin
         GeneratorFactor := 1.0;
         ConsumerFactor := TotalGeneration / TotalConsumption;
      end
      else
      begin
         GeneratorFactor := 1.0;
         ConsumerFactor := 1.0;
      end;
      for Generator in FoodReport^.Generators do
      begin
         GeneratorReport := FoodReport^.Generators[Generator];
         Generator.SetFoodConsumption(Trunc(GeneratorReport^.Quantity * GeneratorFactor));
      end;
      for Consumer in FoodReport^.Consumers do
      begin
         ConsumerReport := FoodReport^.Consumers[Consumer];
         Consumer.SetFoodUsage(Trunc(ConsumerReport^.Quantity * ConsumerFactor));
      end;
   end;
end;


function TFoodBusFeatureClass.GetFeatureNodeClass(): FeatureNodeReference;
begin
   Result := TFoodBusFeatureNode;
end;

function TFoodBusFeatureClass.InitFeatureNode(): TFeatureNode;
begin
   Result := TFoodBusFeatureNode.Create();
end;


destructor TFoodBusFeatureNode.Destroy();
begin
   inherited;
end;

function TFoodBusFeatureNode.ManageBusMessage(Message: TBusMessage): Boolean;
var
   FoodMessage: TInitFoodMessage;
begin
   if (Message is TInitFoodMessage) then
   begin
      FoodMessage := Message as TInitFoodMessage;
      Result := False;
      if (FoodMessage.FClaimed) then
      begin
         Result := True;
      end
      else
      begin
         FoodMessage.FClaimed := True;
         if (Assigned(Parent.Parent)) then
         begin
            Result := Parent.Parent.InjectBusMessage(FoodMessage);
         end;
         if (not Result) then
         begin
            Result := Parent.HandleBusMessage(FoodMessage);
            Assert(not Result, 'TInitFoodMessage should not be marked as handled');
            Result := True;
         end;
      end;
   end
   else
      Result := inherited;
end;

procedure TFoodBusFeatureNode.HandleChanges();
var
   InitFoodMessage: TInitFoodMessage;
   Injected: Boolean;
begin
   InitFoodMessage := TInitFoodMessage.Create();
   Injected := InjectBusMessage(InitFoodMessage);
   Assert(Injected);
   InitFoodMessage.Process();
   InitFoodMessage.Free();
   inherited;
end;

procedure TFoodBusFeatureNode.Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter; CachedSystem: TSystem);
begin
end;

procedure TFoodBusFeatureNode.UpdateJournal(Journal: TJournalWriter);
begin
end;

procedure TFoodBusFeatureNode.ApplyJournal(Journal: TJournalReader; CachedSystem: TSystem);
begin
end;


constructor TFoodGenerationFeatureClass.Create(ASize: Int64);
begin
   inherited Create();
   FSize := ASize;
end;

function TFoodGenerationFeatureClass.GetFeatureNodeClass(): FeatureNodeReference;
begin
   Result := TFoodGenerationFeatureNode;
end;

function TFoodGenerationFeatureClass.InitFeatureNode(): TFeatureNode;
begin
   Result := TFoodGenerationFeatureNode.Create(Self);
end;


constructor TFoodGenerationFeatureNode.Create(AFeatureClass: TFoodGenerationFeatureClass);
begin
   inherited Create();
   Assert(Assigned(AFeatureClass));
   FFeatureClass := AFeatureClass;
end;

constructor TFoodGenerationFeatureNode.CreateFromJournal(Journal: TJournalReader; AFeatureClass: TFeatureClass; ASystem: TSystem);
begin
   inherited CreateFromJournal(Journal, AFeatureClass, ASystem);
   Assert(Assigned(AFeatureClass));
   FFeatureClass := AFeatureClass as TFoodGenerationFeatureClass;
end;

function TFoodGenerationFeatureNode.HandleBusMessage(Message: TBusMessage): Boolean;
begin
   if (Message is TInitFoodMessage) then
   begin
      Assert(Assigned(FFeatureClass));
      (Message as TInitFoodMessage).ReportFoodGenerationCapacity(Self, FFeatureClass.Size);
   end;
   Result := False;
end;

procedure TFoodGenerationFeatureNode.Serialize(DynastyIndex: Cardinal; Writer: TServerStreamWriter; CachedSystem: TSystem);
begin
   //Writer.WriteCardinal(fcFoodGeneration);
end;

procedure TFoodGenerationFeatureNode.UpdateJournal(Journal: TJournalWriter);
begin
end;

procedure TFoodGenerationFeatureNode.ApplyJournal(Journal: TJournalReader; CachedSystem: TSystem);
begin
end;

function TFoodGenerationFeatureNode.GetOwner(): TDynasty;
begin
   Result := Parent.Owner;
end;

procedure TFoodGenerationFeatureNode.SetFoodConsumption(Quantity: Int64);
begin
   FFoodConsumption := Quantity;
end;

end.