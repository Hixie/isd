import 'package:flutter/material.dart' hide Material;

import '../analysis.dart';
import '../assets.dart';
import '../connection.dart' show NetworkError;
import '../dialogs.dart';
import '../game.dart';
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
        Padding(
          padding: featurePadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text('Known contents:'),
              KnowledgeDish(
                materials: manifest.keys.where((int id) => id != 0).map(system.material).toList(),
              ),
              PieChart(
                analysis: analysis,
                materials: materials,
                total: total,
              ),
              OutlinedButton(
                onPressed: () async {
                  final Game game = GameProvider.of(context);
                  try {
                    await system.play(<Object>[parent.id, 'dismantle']);
                  } on NetworkError catch (e) {
                    if (e.message == 'no destructors') {
                      game.reportError('Could not clean up ${parent.nameOrClassName}; no available cleanup teams');
                    } else {
                      rethrow;
                    }
                  }
                },
                child: Text('Clean up ${parent.nameOrClassName}'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
