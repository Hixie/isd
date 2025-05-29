{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit protoplanetary;

interface

uses
   materials, random, plasticarrays, systems;

type
   TBodyComposition = record
      Material: TMaterial;
      RelativeVolume: Double;
   end;

   PBodyArray = ^TBodyArray;

   TBody = record
   private
      Mass: Double; // approximation computed from Composition
      function GetAverageDistance(): Double;
   public
      Distance, Eccentricity: Double;
      Clockwise, Habitable: Boolean;
      Composition: array of TBodyComposition;
      Radius: Double; // also HP
      Temperature: Double;
      Moons: PBodyArray;
      property AverageOrbitalDistance: Double read GetAverageDistance;
      property ApproximateMass: Double read Mass;
   end;

   TBodyDistanceUtils = record
      class function Equals(const A, B: TBody): Boolean; static; inline;
      class function LessThan(const A, B: TBody): Boolean; static; inline;
      class function GreaterThan(const A, B: TBody): Boolean; static; inline;
   end;

   TBodyArray = specialize PlasticArray<TBody, TBodyDistanceUtils>;

// TODO: have different logic for home systems, support systems, and other random systems
function CondenseProtoplanetaryDisk(StarMass, StarRadius, HillRadius, StarTemperature: Double; Materials: TMaterialHashSet; System: TSystem): TBodyArray;

{$IFDEF DEBUG}
function WeighBody(const Body: TBody): Double;
{$ENDIF}

implementation

uses
   astronomy, math;

const
   MaxDistanceToFirstPlanet = 0.50 * AU;
   LowProbability = 0.50;
   HighProbability = 0.90;
   ProbabilityScale = 0.25;
   MinScale = 1.01;
   MaxScale = 1.3;
   DirectionSwitchProbability = 0.125;
   MoonDirectionSwitchProbability = 0.01;
   MeanProtoplanetaryDiscRadiusExtension = 50.0 * AU;
   MinProtoplanetaryDiscRadius = 10.0 * AU;
   TypicalProtoplanetaryDiscHeight = 0.07;
   ProtoplanetaryDiscHeightEdgeAdjustment = 0.0; // additional mass at edge of disc (at ProtoplanetaryDiscRadius) (can be negative to have smaller outer planets)
   ProtoplanetaryDiscHeightVariance = 0.1;
   MinPlanetCount = 10;
   TargetTerrestrialCount = 3;
   TerrestrialFractionThreshold = 0.01;
   MinimumTerrestrialRadius = 12756e3 / 4.0; // half Earth radius
   MinimumTerrestrialTemperature = 0; //225; // around -50 Celsius // TODO: guarantee to generate planets in the right temperature regime
   MaximumTerrestrialTemperature = 1000000; //350; // around +75 Celsius
   TypicalOuterPlanetDiameter = 2e6;
   MoonMassRatio = 0.5;
   CompositionPerturbationParameters: TPerturbationParameters = (
      ProbabilityZero: 0.01; // chance of a material just not being there
      ProbabilityRandomize: 0.01; // chance of ignoring normal density for a material
      RandomizeMin: 0.0;
      RandomizeMax: 5.0
   );
   ProtoplanetaryDiscRadiusPerturbationParameters: TPerturbationParameters = (
      ProbabilityZero: 0.0;
      ProbabilityRandomize: 0.0;
      RandomizeMin: 0.0;
      RandomizeMax: 0.0
   );
   InnerPlanetRadiusPerturbationParameters: TPerturbationParameters = (
      ProbabilityZero: 0.0;
      ProbabilityRandomize: 0.0;
      RandomizeMin: 0.0;
      RandomizeMax: 0.0
   );
   OuterPlanetRadiusPerturbationParameters: TPerturbationParameters = (
      ProbabilityZero: 0.0;
      ProbabilityRandomize: 0.01; // 1% chance of wacky outer planets
      RandomizeMin: 12756e3 / 4.0; // 0.5x Earth diameter
      RandomizeMax: 142984e3 // 2x Jupiter diameter
   );
   MoonSizePerturbationParameters: TPerturbationParameters = (
      ProbabilityZero: 0.0;
      ProbabilityRandomize: 0.0;
      RandomizeMin: 0.0;
      RandomizeMax: 0.0
   );
   MaxMoonSizeRatio = 0.25;
   MinMoonSize = 500e3; // 1000km diameter
   MoonSizeMinScale = 0.0;
   MoonSizeMaxScale = 0.99;
   DefaultEccentricity = 0.02;
   EccentricityPerturbationParameters: TPerturbationParameters = (
      ProbabilityZero: 0.0;
      ProbabilityRandomize: 0.05;
      RandomizeMin: 0.0;
      RandomizeMax: 0.5
   );

class function TBodyDistanceUtils.Equals(const A, B: TBody): Boolean;
begin
   Result := A.Distance = B.Distance;
end;

class function TBodyDistanceUtils.LessThan(const A, B: TBody): Boolean;
begin
   Result := A.Distance < B.Distance;
end;

class function TBodyDistanceUtils.GreaterThan(const A, B: TBody): Boolean;
begin
   Result := A.Distance > B.Distance;
end;

function TBody.GetAverageDistance(): Double;
begin
   // This must remain equivalent to the code in orbit.pas
   Result := Distance * (1 + Eccentricity * Eccentricity / 2.0);
end;
   
function WeighBody(const Body: TBody): Double;
var
   Index: Cardinal;
   BodyRadius, BodyVolume, MaterialMass: Double;
   TotalRelativeVolume: Double;
begin
   Result := 0.0;
   Assert(Length(Body.Composition) > 0);
   BodyRadius := Body.Radius;
   BodyVolume := BodyRadius * BodyRadius * BodyRadius * Pi * 4.0 / 3.0; // $R- // If it overflows, other things have gone very wrong already.
   TotalRelativeVolume := 0.0;
   for Index := 0 to Length(Body.Composition) - 1 do // $R-
   begin
      TotalRelativeVolume := TotalRelativeVolume + Body.Composition[Index].RelativeVolume;
   end;
   for Index := 0 to Length(Body.Composition) - 1 do // $R-
   begin
      if (Body.Composition[Index].RelativeVolume > 0.0) then
      begin
         MaterialMass := (Body.Composition[Index].RelativeVolume / TotalRelativeVolume) * BodyVolume * Body.Composition[Index].Material.Density;
         Result := Result + MaterialMass;
      end;
   end;
end;

function GetBondAlbedo(Body: TBody): Double;
// This function should remain equivalent to TPlanetaryBodyFeatureNode.GetBondAlbedo
var
   Index: Cardinal;
   Weight, Numerator, Denominator: Double;
   Material: TMaterial;
begin
   Numerator := 0.0;
   Denominator := 0.0;
   Assert(Length(Body.Composition) > 0);
   for Index := Low(Body.Composition) to High(Body.Composition) do // $R-
   begin
      Material := Body.Composition[Index].Material;
      if (not IsNaN(Material.BondAlbedo)) then
      begin
         Weight := Body.Composition[Index].RelativeVolume;
         Numerator := Numerator + Material.BondAlbedo * Weight;
         Denominator := Denominator + Weight;
      end;
   end;
   Result := Numerator / Denominator;
   if (IsNan(Result)) then
      Result := 1.0;
   Assert(Result >= 0.0);
   Assert(Result <= 1.0);
end;

procedure SetHabitability(var Planet: TBody);
var
   Index: Cardinal;
   TotalRelativeVolume: Double;
begin
   if (Planet.Radius > MinimumTerrestrialRadius) then
   begin
      if ((Planet.Temperature < MinimumTerrestrialTemperature) or
          (Planet.Temperature > MaximumTerrestrialTemperature)) then
      begin
         Planet.Habitable := False;
         exit;
      end;
      TotalRelativeVolume := 0.0;
      for Index := Low(Planet.Composition) to High(Planet.Composition) do // $R-
      begin
         TotalRelativeVolume := TotalRelativeVolume + Planet.Composition[Index].RelativeVolume;
      end;
      for Index := Low(Planet.Composition) to High(Planet.Composition) do // $R-
      begin
         if (mtTerrestrial in Planet.Composition[Index].Material.Tags) then
         begin
            if (Planet.Composition[Index].RelativeVolume < TotalRelativeVolume * TerrestrialFractionThreshold) then
            begin
               Planet.Habitable := False;
               exit;
            end;
         end;
      end;
      Planet.Habitable := True;
   end
   else
      Planet.Habitable := False;
end;

procedure SetTemperature(var Planet: TBody; SunTemperature, SunRadius, PlanetAverageOrbitalDistance: Double);
begin
   Planet.Temperature := SunTemperature * SqRt(SunRadius / (2.0 * PlanetAverageOrbitalDistance)) * Power(1 - GetBondAlbedo(Planet), 1.0 / 4.0); // $R-
end;

function NeedsMorePlanets(const Planets: TBodyArray): Boolean;

   procedure Consider(const Planet: TBody; var TerrestrialCount: Cardinal);
   begin
      if (Planet.Habitable) then
         Inc(TerrestrialCount);
   end;

var
   TerrestrialCount: Cardinal;
   Index, SubIndex: Cardinal;
   Planet: TBody;
begin
   TerrestrialCount := 0;
   if (Planets.Length < MinPlanetCount) then
   begin
      Result := True;
      exit;
   end;
   if (Planets.Length > 0) then
   begin
      for Index := 0 to Planets.Length - 1 do // $R-
      begin
         Planet := Planets[Index];
         Consider(Planet, TerrestrialCount);
         if (Assigned(Planet.Moons)) then
         begin
            Assert(Planet.Moons^.Length > 0);
            for SubIndex := 0 to Planet.Moons^.Length - 1 do // $R-
            begin
               Assert(not Assigned(Planet.Moons^[SubIndex].Moons));
               Consider(Planet.Moons^[SubIndex], TerrestrialCount);
            end;
         end;
      end;
   end;
   Result := TerrestrialCount < TargetTerrestrialCount;
end;

function AddMaterialsTo(var Planet: TBody; const D: Double; const Materials: TMaterialHashSet; const R: TRandomNumberGenerator): Boolean;
var
   Index, DistanceControlPointIndex: Cardinal;
   A, B: TMaterialAbundanceParameters;
   RelativeVolumeParameter, T, TotalRelativeVolume: Double;
   Material: TMaterial;
begin
   TotalRelativeVolume := 0.0;
   SetLength(Planet.Composition, Materials.Count);
   Index := 0;
   for Material in Materials do
   begin
      Assert(Length(Material.Abundance) > 0);
      Assert(Material.Abundance[0].Distance = 0.0); // so that we don't have to handle the left edge specially
      DistanceControlPointIndex := Low(Material.Abundance);
      while ((DistanceControlPointIndex <= High(Material.Abundance)) and (Material.Abundance[DistanceControlPointIndex].Distance < D)) do
         Inc(DistanceControlPointIndex);
      Assert(DistanceControlPointIndex > 0); // because the first point should be at D=0
      Assert((DistanceControlPointIndex = High(Material.Abundance) + 1) or (Material.Abundance[DistanceControlPointIndex].Distance >= D));
      if (DistanceControlPointIndex <= High(Material.Abundance)) then
      begin
         A := Material.Abundance[DistanceControlPointIndex - 1];
         Assert(A.Distance < D);
         B := Material.Abundance[DistanceControlPointIndex];
         Assert(B.Distance >= D);
         T := (D - A.Distance) / (B.Distance - A.Distance);
         RelativeVolumeParameter := A.RelativeVolume + (B.RelativeVolume - A.RelativeVolume) * T;
      end
      else
      begin
         RelativeVolumeParameter := Material.Abundance[DistanceControlPointIndex - 1].RelativeVolume;
      end;
      Planet.Composition[Index].Material := Material;
      Planet.Composition[Index].RelativeVolume := R.Perturb(RelativeVolumeParameter, CompositionPerturbationParameters);
      TotalRelativeVolume := TotalRelativeVolume + Planet.Composition[Index].RelativeVolume;
      Inc(Index);
   end;
   Result := TotalRelativeVolume > 0.0;
end;

function RocheLimit(const PrimaryMass, SecondaryMass, SecondaryRadius: Double): Double;
begin
   Assert(SecondaryRadius > 0);
   Assert(PrimaryMass > 0);
   Assert(SecondaryMass > 0);
   Result := SecondaryRadius * ((2.0 * PrimaryMass / SecondaryMass) ** (1.0 / 3.0)); // $R-
end;

function CondenseProtoplanetaryDisk(StarMass, StarRadius, HillRadius, StarTemperature: Double; Materials: TMaterialHashSet; System: TSystem): TBodyArray;
var
   Randomizer: TRandomNumberGenerator;
   Index, PlanetIndex, GenerationStart: Cardinal;
   Min, Max, Distance, MoonDistance, PreviousDistance, NextDistance, Alpha, Beta, PlanetDistance, Area,
   PlanetProbability, ProtoplanetaryDiscHeight, LocalProtoplanetaryDiscHeight, PlanetMass, ProtoplanetaryDiscRadius,
   MoonSize, PlanetHillRadius, CumulativeMoonMasses: Double;
   Clockwise, DidAddPlanet: Boolean;
   Planets: TBodyArray;
   Planet, Moon: TBody;
begin
   Randomizer := System.RandomNumberGenerator;
   // PLANETS
   Planets.Init(MinPlanetCount);
   Clockwise := True;
   GenerationStart := 0; // so we know which bodies need to be given mass from a protoplanetary disc
   while (NeedsMorePlanets(Planets)) do
   begin
      PlanetProbability := LowProbability;
      ProtoplanetaryDiscRadius := MinProtoplanetaryDiscRadius + Randomizer.Perturb(MeanProtoplanetaryDiscRadiusExtension, ProtoplanetaryDiscRadiusPerturbationParameters); // $R-
      ProtoplanetaryDiscHeight := TypicalProtoplanetaryDiscHeight * Randomizer.GetDouble(1.0 - ProtoplanetaryDiscHeightVariance, 1.0 + ProtoplanetaryDiscHeightVariance); // $R-
      Min := StarRadius;
      Max := MaxDistanceToFirstPlanet;
      if (Randomizer.GetBoolean(DirectionSwitchProbability)) then
         Clockwise := not Clockwise;
      Distance := Min + Randomizer.GetDouble(Min, Max);
      while (Distance < HillRadius) do
      begin
         DidAddPlanet := False;
         Planet := Default(TBody);
         Planet.Distance := Distance;
         Planet.Clockwise := Clockwise;
         if (AddMaterialsTo(Planet, Distance, Materials, Randomizer)) then
         begin
            Planet.Eccentricity := Randomizer.Perturb(DefaultEccentricity, EccentricityPerturbationParameters);
            SetTemperature(Planet, StarTemperature, StarRadius, Planet.AverageOrbitalDistance);
            SetHabitability(Planet);
            if (Planet.Habitable or Randomizer.GetBoolean(PlanetProbability)) then
            begin
               Planets.Push(Planet);
               DidAddPlanet := True;
            end;
         end;
         if (DidAddPlanet) then
         begin
            if (Distance < ProtoplanetaryDiscRadius) then
            begin
               PlanetProbability := HighProbability * (1 - Distance / ProtoplanetaryDiscRadius); // $R-
            end
            else
            begin
               PlanetProbability := LowProbability;
            end;
         end
         else
         begin
            PlanetProbability := ProbabilityScale + PlanetProbability - PlanetProbability * ProbabilityScale;
         end;
         Min *= MinScale; // $R-
         Max *= MaxScale; // $R-
         Distance := Distance + Randomizer.GetDouble(Min, Max);
      end;

      if (GenerationStart < Planets.Length) then
      begin
         if (GenerationStart < Planets.Length - 1) then
            Planets.SortSubrange(GenerationStart, Planets.Length - 1); // $R-
         PlanetDistance := 0.0;
         NextDistance := Planets[GenerationStart].Distance;
         PlanetIndex := GenerationStart;
         for Index := GenerationStart to Planets.Length - 1 do // $R-
         begin
            PreviousDistance := PlanetDistance;
            PlanetDistance := NextDistance;
            if (Index + 1 < Planets.Length) then
            begin
               NextDistance := Planets[Index + 1].Distance; // $R-
            end
            else
            begin
               NextDistance := HillRadius;
            end;
            Planet := Planets[Index];

            // Collect protoplanetary dust into planet
            if (PlanetDistance < MinProtoplanetaryDiscRadius + MeanProtoplanetaryDiscRadiusExtension) then
            begin
               Alpha := (PreviousDistance + PlanetDistance) / 2;
               Beta := (PlanetDistance + NextDistance) / 2;
               Area := Pi * (Beta * Beta - Alpha * Alpha); // $R-
               LocalProtoplanetaryDiscHeight := ProtoplanetaryDiscHeight + ProtoplanetaryDiscHeightEdgeAdjustment * (PlanetDistance / ProtoplanetaryDiscRadius); // $R-
               Planet.Radius := Randomizer.Perturb((Area * LocalProtoplanetaryDiscHeight * 3.0 / (4.0 * Pi)) ** (1.0 / 3.0), InnerPlanetRadiusPerturbationParameters); // $R-
               Assert(Planet.Radius > 0);
            end
            else
            begin
               Planet.Radius := Randomizer.Perturb(TypicalOuterPlanetDiameter / 2.0, OuterPlanetRadiusPerturbationParameters);
               Assert(Planet.Radius > 0);
            end;
            PlanetMass := WeighBody(Planet);
            Planet.Mass := PlanetMass;

            if (Distance < RocheLimit(StarMass, PlanetMass, Planet.Radius)) then
            begin
               PlanetDistance := PreviousDistance;
            end
            else
            begin
               // MOONS
               Assert(Length(Planet.Composition) > 0);
               Distance := Planet.Distance;
               PlanetHillRadius := Distance * (1 - Planet.Eccentricity) * Power((PlanetMass / (3 * (PlanetMass + StarMass))), 1/3); // $R-
               MoonSize := Randomizer.Perturb(Planet.Radius * MaxMoonSizeRatio, MoonSizePerturbationParameters);
               CumulativeMoonMasses := 0.0;
               while ((MoonSize > MinMoonSize) and (CumulativeMoonMasses < Planet.Mass * MoonMassRatio)) do
               begin
                  MoonDistance := Randomizer.GetDouble(0.0, PlanetHillRadius);
                  Moon := Default(TBody);
                  if (Randomizer.GetBoolean(MoonDirectionSwitchProbability)) then
                  begin
                     Moon.Clockwise := not Planet.Clockwise;
                  end
                  else
                  begin
                     Moon.Clockwise := Planet.Clockwise;
                  end;
                  Moon.Distance := MoonDistance;
                  Moon.Radius := MoonSize;
                  Assert(Moon.Radius > 0);
                  if (AddMaterialsTo(Moon, Distance, Materials, Randomizer)) then
                  begin
                     Moon.Mass := WeighBody(Moon);
                     if ((MoonDistance > RocheLimit(PlanetMass, Moon.Mass, MoonSize)) and (CumulativeMoonMasses + Moon.Mass < PlanetMass)) then
                     begin
                        if (not Assigned(Planet.Moons)) then
                        begin
                           Planet.Moons := New(PBodyArray);
                           Planet.Moons^.Init();
                        end;
                        CumulativeMoonMasses := CumulativeMoonMasses + Moon.Mass;
                        Moon.Eccentricity := Randomizer.Perturb(DefaultEccentricity, EccentricityPerturbationParameters);
                        SetTemperature(Moon, StarTemperature, StarRadius, Planet.AverageOrbitalDistance); // planet distance, not moon distance!
                        SetHabitability(Moon);
                        Planet.Moons^.Push(Moon);
                     end;
                  end;
                  Assert(MoonSizeMinScale < MoonSizeMaxScale);
                  Assert(MoonSizeMaxScale < 1.0); // otherwise this might not terminate
                  MoonSize := MoonSize * Randomizer.GetDouble(MoonSizeMinScale, MoonSizeMaxScale);
               end;
               if (Assigned(Planet.Moons)) then
                  Planet.Moons^.Sort();
               Planets[PlanetIndex] := Planet;
               Inc(PlanetIndex);
            end;
         end;
         if (GenerationStart + PlanetIndex < Planets.Length) then
         begin
            Planets.Length := GenerationStart + PlanetIndex; // $R-
         end;
      end;
      GenerationStart := Planets.Length;
   end;
   Planets.Sort();
   Result := Planets;
end;
   
end.