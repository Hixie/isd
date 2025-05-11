import '../assets.dart';

class SpaceSensorsFeature extends AbilityFeature {
  SpaceSensorsFeature({
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
