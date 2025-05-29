import 'package:flutter/foundation.dart';

import '../assets.dart';
import '../materials.dart';

@immutable
class AssetClass {
  const AssetClass({
    required this.id,
    required this.icon,
    required this.name,
    required this.description,
  });

  final int id;
  final String icon;
  final String name;
  final String description;

  static int alphabeticalSort(AssetClass a, AssetClass b) {
    return a.name.compareTo(b.name);
  }
}

class KnowledgeFeature extends AbilityFeature {
  KnowledgeFeature({
    required this.assetClasses,
    required this.materials,
  });

  final Map<int, AssetClass> assetClasses;
  final Map<int, Material> materials;

  @override
  RendererType get rendererType => RendererType.none;

  // TODO: display the known asset classes and materials
}
