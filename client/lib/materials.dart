import 'package:flutter/widgets.dart';

import 'icons.dart';

class Material {
  Material({
    required this.id,
    required this.icon,
    required this.name,
    required this.description,
    required this.flags,
    required this.massPerUnit,
    required this.density,
  });

  final int id;
  final String icon;
  final String name;
  final String description;
  final int flags; // TODO: use an enum or something
  final double massPerUnit;
  final double density;

  Widget build(BuildContext context) {
    return IconsManager.icon(context, icon, '$name\n$description');
  }
}

class StructuralComponent {
  StructuralComponent({
    required this.current,
    required this.max,
    required this.name,
    required this.materialID,
    required this.description,
  });

  final int current;
  final int? max;
  final String? name;
  final int materialID;
  final String description;
}
