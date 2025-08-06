import 'package:flutter/widgets.dart';

import '../assets.dart';
import '../icons.dart';
import '../prettifiers.dart';
import '../widgets.dart';

class BuilderFeature extends AbilityFeature {
  BuilderFeature({
    required this.capacity,
    required this.buildRate,
    required this.assignedStructures, 
 });

  final int capacity;
  final double buildRate;
  final List<AssetNode> assignedStructures;

  @override
  RendererType get rendererType => RendererType.none;

  @override
  Widget buildDialog(BuildContext context) {
    final double fontSize = DefaultTextStyle.of(context).style.fontSize!;
    final IconsManager icons = IconsManagerProvider.of(context);
    return ListBody(
      children: <Widget>[
        const Text('Building:', style: bold),
        Padding(
          padding: featurePadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('Projects: ${assignedStructures.length} out of $capacity'),
              for (int index = 0; index < capacity; index += 1)
                Text.rich(
                  TextSpan(
                    children: <InlineSpan>[
                      TextSpan(text: '  ${index + 1}: '),
                      index < assignedStructures.length
                        ? assignedStructures[index].describe(context, icons, iconSize: fontSize)
                        : const TextSpan(text: 'unassigned', style: italic)
                    ],
                  ),
                ),
              Text('Maximum build rate: ${prettyHp(buildRate* 1000 * 60 * 60)} hp per hour'),
            ],
          ),
        ),
      ],
    );
  }
}
