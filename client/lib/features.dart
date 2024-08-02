import 'components.dart';
import 'world.dart';

class StarFeature extends Feature {
  const StarFeature(this.starId);
  final int starId;
}

typedef SpaceChild = ({ double r, double theta, AssetNode child });

class SpaceFeature extends Feature {
  const SpaceFeature(this.children);
  final Set<SpaceChild> children;
}

typedef Orbit = ({ double a, double e, double theta, double omega, AssetNode child });

class OrbitFeature extends Feature {
  const OrbitFeature(this.children);
  final Set<Orbit> children;
}

class StructureFeature extends Feature {
  const StructureFeature({
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

class SpaceSensorsFeature extends Feature {
  const SpaceSensorsFeature({
    required this.reach,
    required this.up,
    required this.down,
    required this.minSize,
    required this.nearestOrbit,
    required this.topOrbit,
    required this.detectedCount,
  });

  final int reach;
  final int up;
  final int down;
  final double minSize;
  final AssetNode? nearestOrbit;
  final AssetNode? topOrbit;
  final int? detectedCount;
}
