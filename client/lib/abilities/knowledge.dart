import 'package:flutter/material.dart' hide Material;

import '../assetclasses.dart';
import '../assets.dart';
import '../materials.dart';
import '../widgets.dart';

class KnowledgeFeature extends AbilityFeature {
  KnowledgeFeature({
    required this.assetClasses,
    required this.materials,
  });

  final Map<int, AssetClass> assetClasses;
  final Map<int, Material> materials;

  @override
  RendererType get rendererType => RendererType.ui;

  @override
  Widget buildRenderer(BuildContext context) {
    // TODO: this should be left-aligned until it runs out of room, then stack
    if (assetClasses.isNotEmpty || materials.isNotEmpty) {
      final List<Widget> children = <Widget>[
        for (AssetClass assetClass in assetClasses.values)
          assetClass.asKnowledgeIcon(context),
        for (Material material in materials.values)
          material.asKnowledgeIcon(context),
      ];
      if (children.length == 1)
        return Center(child: children.single);
      int index = 0;
      return Stack(
        alignment: Alignment.topLeft,
        fit: StackFit.passthrough,
        children: <Widget>[
          for (Widget child in children)
            Align(
              alignment: Alignment(2.0 * (index++ / (children.length - 1)) - 1.0, 0.0),
              child: child,
            ),
        ],
      );
    }
    return const SizedBox.shrink();
  }

  @override
  Widget? buildDialog(BuildContext context) {
    if (assetClasses.isEmpty && materials.isEmpty)
      return null;
    return ListBody(
      children: <Widget>[
        const Text('Knowledge', style: bold),
        Padding(
          padding: featurePadding,
          child: KnowledgeDish(
            assetClasses: assetClasses.values.toList(),
            materials: materials.values.toList(),
          ),
        ),
      ],
    );
  }
}
