{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit providers;

interface

uses
   systems;

type
   IHillDiameterProvider = interface ['IHillDiameterProvider']
      // Child is the body (e.g. star, planet, moon) whose hill diameter we want.
      // It must be a child of the receiver.
      // Usually this will be an Orbit asset, actually, whose primary is the "real" node (body) we care about.
      // ChildMass is the mass of that orbit asset's primary body, i.e. not including any satellites.
      function GetHillDiameter(Child: TAssetNode; ChildPrimaryMass: Double): Double;
   end;

   IAssetNameProvider = interface ['IAssetNameProvider']
      function GetAssetName(): UTF8String;
   end;

implementation

end.