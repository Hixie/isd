import '../assets.dart';
import '../components.dart';

class StructureFeature extends AbilityFeature {
  StructureFeature({
    required this.structuralComponents,
    required this.current,
    required this.min,
    required this.max,
  });

  final List<StructuralComponent> structuralComponents;

  // structural integrity
  final int current;
  final int? min;
  final int? max;
}
