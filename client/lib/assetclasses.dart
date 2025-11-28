import 'package:flutter/material.dart' hide Material;

import 'icons.dart';

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

  String get tooltip {
    return '$name\n$description';
  }

  Widget asKnowledgeIcon(BuildContext context) {
    return IconsManager.knowledgeIcon(context, icon, tooltip);
  }

  Widget asIcon(BuildContext context, { required double size, IconsManager? icons, String? tooltip }) {
    return IconsManager.icon(context, icon, size: size, tooltip: tooltip ?? this.tooltip, icons: icons);
  }
}
