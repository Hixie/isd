import '../assets.dart';

class SpaceSensorFeature extends AbilityFeature {
  SpaceSensorFeature({
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

  @override
  RendererType get rendererType => RendererType.none;
}

class GridSensorFeature extends AbilityFeature {
  GridSensorFeature({
    required this.grid,
    required this.detectedCount,
  });

  final AssetNode? grid;
  final int? detectedCount;

  @override
  RendererType get rendererType => RendererType.none;
}
