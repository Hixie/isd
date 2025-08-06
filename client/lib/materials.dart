import 'package:flutter/widgets.dart';

import 'icons.dart';
import 'prettifiers.dart';

enum MaterialKind { ore, component, fluid }

class Material {
  Material({
    required this.id,
    required this.icon,
    required this.name,
    required this.description,
    required this.massPerUnit,
    required this.density,
    required this.kind,
    required this.isPressurized,
  });

  final int id;
  final String icon;
  final String name;
  final String description;
  final double massPerUnit;
  final double density;
  final MaterialKind kind;
  final bool isPressurized;

  String get tooltip {
    return '$name\n$description';
  }

  Widget asKnowledgeIcon(BuildContext context) {
    // TODO: make this clickable (show a HUD with more information)
    return IconsManager.knowledgeIcon(context, icon, tooltip);
  }

  Widget asIcon(BuildContext context, { required double size, IconsManager? icons }) {
    return IconsManager.icon(context, icon, size: size, tooltip: tooltip, icons: icons);
  }

  InlineSpan describe(BuildContext context, IconsManager icons, { required double iconSize }) {
    final Widget icon = asIcon(context, size: iconSize, icons: icons);
    return TextSpan(
      children: <InlineSpan>[
        WidgetSpan(child: icon),
        TextSpan(text: ' $name'),
      ],
    );
  }

  InlineSpan describeQuantity(BuildContext context, IconsManager icons, int quantity, { required double iconSize }) {
    final String amount;
    switch (kind) {
      case MaterialKind.ore:
        amount = prettyMass(quantity * massPerUnit);
      case MaterialKind.component:
        amount = prettyQuantity(quantity);
      case MaterialKind.fluid:
        amount = prettyVolume(quantity * massPerUnit / density);
    }
    final Widget icon = asIcon(context, size: iconSize, icons: icons);
    return TextSpan(
      text: '$amount ',
      children: <InlineSpan>[
        WidgetSpan(child: icon),
        TextSpan(text: ' $name'),
      ],
    );
  }

  DecorationImage asDecorationImage(BuildContext context, IconsManager icons, { required double size }) {
    return DecorationImage(
      image: IconImageProvider(icon, icons),
      fit: BoxFit.contain,
      alignment: Alignment.bottomCenter,
    );
  }
}
