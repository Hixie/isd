import '../assets.dart';

enum MiningMode {
  mining,
  pilesFull,
  regionEmpty,
  noRegion,
  disabled,
}

class MiningFeature extends AbilityFeature {
  MiningFeature({required this.rate, required this.mode});

  final double rate;
  final MiningMode mode;

  @override
  RendererType get rendererType => RendererType.none;
}
