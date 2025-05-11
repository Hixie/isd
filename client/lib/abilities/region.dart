import '../assets.dart';

class RegionFeature extends AbilityFeature {
  RegionFeature({required this.minable});

  final bool minable;

  @override
  RendererType get rendererType => RendererType.none;
}
