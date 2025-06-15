import 'package:flutter/material.dart' hide Material;

import '../assets.dart';
import '../containers/messages.dart';
import '../icons.dart';
import '../materials.dart';
import '../widgets.dart';

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

  Widget build(BuildContext context) {
    return IconsManager.icon(context, icon, '$name\n$description');
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
  RendererType get rendererType => RendererType.box;

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
            // TODO: make this clickable (show a HUD with more information)
            for (AssetClass assetClass in assetClasses.values)
              assetClass.build(context),
            for (Material material in materials.values)
              material.build(context),
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

  // TODO: display the known asset classes and materials
}
