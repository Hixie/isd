import 'package:flutter/material.dart' hide Material;

import '../analysis.dart';
import '../assets.dart';
import '../materials.dart';
import '../nodes/system.dart';
import '../widgets.dart';

class RubblePileFeature extends AbilityFeature {
  RubblePileFeature({ required this.manifest });

  final Map<int, int> manifest;

  @override
  RendererType get rendererType => RendererType.none;

  @override
  Widget buildDialog(BuildContext context) {
    final Map<Material, int> analysis = <Material, int>{};
    final List<Material> materials = <Material>[];
    final SystemNode system = SystemNode.of(parent);
    double total = 0;
    for (int materialID in manifest.keys) {
      final int quantity = manifest[materialID]!;
      if (materialID != 0) {
        final Material material = system.material(materialID);
        analysis[material] = quantity;
        materials.add(material);
      }
      total += quantity;
    }
    materials.sort((Material a, Material b) => analysis[b]! - analysis[a]!);
    return ListBody(
      children: <Widget>[
        const Text('Rubble', style: bold),
        const Padding(
          padding: featurePadding,
          child: Text('Known contents:'),
        ),
        Padding(
          padding: featurePadding,
          child: KnowledgeDish(
            materials: manifest.keys.where((int id) => id != 0).map(system.material).toList(),
          ),
        ),
        Padding(
          padding: featurePadding,
          child: PieChart(
            analysis: analysis,
            materials: materials,
            total: total,
          ),
        ),
      ],
    );
  }
}
