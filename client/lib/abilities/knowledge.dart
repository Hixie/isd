import 'package:flutter/material.dart' hide Material;

import '../assetclasses.dart';
import '../assets.dart';
import '../containers/messages.dart';
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
    if (assetClasses.isNotEmpty || materials.isNotEmpty) {
      final MessageBoardMode? mode = MessageBoardMode.of(context);
      if (mode?.showBody != false) {
        Widget result = Wrap(
          spacing: 12.0,
          runSpacing: 12.0,
          alignment: WrapAlignment.spaceEvenly,
          children: <Widget>[
            for (AssetClass assetClass in assetClasses.values)
              assetClass.asKnowledgeIcon(context),
            for (Material material in materials.values)
              material.asKnowledgeIcon(context),
          ],
        );
        if (mode == null) {
          result = NoZoom(
            child: Card(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(12.0),
                child: result,
              ),
            ),
          );
        } else {
          result = Padding(
            padding: const EdgeInsets.all(12.0),
            child: result,
          );
        }
        return result;
      }
    }
    return const SizedBox.shrink();
  }
  
  @override
  Widget buildDialog(BuildContext context) {
    return ListBody(
      children: <Widget>[
        const Text('Knowledge:', style: bold),
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
