{$MODE OBJFPC} { -*- delphi -*- }
{$INCLUDE settings.inc}
unit providers;

interface

uses
   systems, masses;

type
   IHillDiameterProvider = interface ['IHillDiameterProvider']
      // Child is the body (e.g. star, planet, moon) whose hill diameter we want.
      // It must be a child of the receiver.
      // Usually this will be an Orbit asset, actually, whose primary is the "real" node (body) we care about.
      // ChildMass is the mass of that orbit asset's primary body, i.e. not including any satellites.
      function GetHillDiameter(Child: TAssetNode; ChildPrimaryMass: TMass): Double;
   end;

   IAssetNameProvider = interface ['IAssetNameProvider']
      function GetAssetName(): UTF8String;
   end;

   // TODO: asset description provider? e.g. surface should describe a planet


   // This is used as follows:
   //
   // type
   //   TRegisterMinerBusMessage = specialize TRegisterProviderBusMessage<TPhysicalConnectionBusMessage, IMiner>;
   //
   generic TRegisterProviderBusMessage<TSuperclass: TBusMessage; IProvider> = class(TSuperclass)
   private
      FProvider: IProvider;
   public
      constructor Create(AProvider: IProvider);
      property Provider: IProvider read FProvider;
   end;

implementation

constructor TRegisterProviderBusMessage.Create(AProvider: IProvider);
begin
   inherited Create();
   FProvider := AProvider;
end;

end.