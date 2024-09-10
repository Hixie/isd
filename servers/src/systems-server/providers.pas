{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit providers;

interface

uses
   systems;

type
   IHillDiameterProvider = interface ['IHillDiameterProvider']
      function GetHillDiameter(Child: TAssetNode; ChildPrimaryMass: Double): Double;
   end;

   IAssetNameProvider = interface ['IAssetNameProvider']
      function GetAssetName(): UTF8String;
   end;

implementation

end.