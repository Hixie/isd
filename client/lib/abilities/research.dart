import '../assets.dart';

class ResearchFeature extends AbilityFeature {
  ResearchFeature({required this.current});

  final String current;

  @override
  RendererType get rendererType => RendererType.none;
}
