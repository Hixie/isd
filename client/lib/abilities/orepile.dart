import '../assets.dart';

class OrePileFeature extends AbilityFeature {
  OrePileFeature({
    required this.pileMass,
    required this.pileMassFlowRate,
    required this.capacity,
    required this.materials,
  });

  final double pileMass;
  final double pileMassFlowRate;
  final double capacity;
  final Set<int> materials;

  @override
  RendererType get rendererType => RendererType.none;
}
