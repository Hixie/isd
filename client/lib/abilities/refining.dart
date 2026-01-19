import 'package:flutter/material.dart';

import '../assets.dart';
import '../icons.dart';
import '../nodes/system.dart';
import '../prettifiers.dart';
import '../types.dart';
import '../widgets.dart';

class RefiningFeature extends AbilityFeature {
  RefiningFeature({
    required this.material,
    required this.currentRate,
    required this.maxRate,
    required this.disabledReason,
  });

  final int material;
  final double currentRate;
  final double maxRate;
  final DisabledReason disabledReason;

  @override
  RendererType get rendererType => RendererType.none;

  @override
  String get status {
    if (currentRate > 0.0) {
      if (disabledReason.sourceLimited) {
        return 'Shortage of ore to refine. Refining throttled to ${prettyFraction(currentRate / maxRate)}.';
      }
      if (disabledReason.targetLimited) {
        return 'Storage full. Refining throttled to ${prettyFraction(currentRate / maxRate)}.';
      }
    }
    if (disabledReason.targetLimited) {
      return 'Storage full. Add more piles to restart refining.';
    }
    if (disabledReason.sourceLimited) {
      return 'Shortage of ore to refine. Add more holes to restart refining.';
    }
    if (!disabledReason.fullyActive) {
      return disabledReason.describe(currentRate);
    }
    assert(currentRate == maxRate, 'currentRate = $currentRate, maxRate = $maxRate');
    return 'Refining at full rate.';
  }

  @override
  Widget buildDialog(BuildContext context) {
    final double fontSize = DefaultTextStyle.of(context).style.fontSize!;
    final IconsManager icons = IconsManagerProvider.of(context);
    final SystemNode system = SystemNode.of(parent);
    return ListBody(
      children: <Widget>[
        Text.rich(
          TextSpan(
            text: 'Refining',
            style: bold,
            children: <InlineSpan>[
              if (material != 0)
                const TextSpan(text: ' '),
              if (material != 0)
                system.material(material).describe(context, icons, iconSize: fontSize),
              const TextSpan(text: ':'),
            ],
          ),
        ),
        Padding(
          padding: featurePadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('Status: $status'),
              Text('Current refining rate: ${prettyRate(currentRate, const Mass())}'),
              Text('Maximum refining rate: ${prettyRate(maxRate, const Mass())}'),
            ],
          ),
        ),
      ],
    );
  }
}
