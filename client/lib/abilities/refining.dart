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
    required this.sourceLimiting,
    required this.targetLimiting,
  });

  final int material;
  final double currentRate;
  final double maxRate;
  final DisabledReason disabledReason;
  final bool sourceLimiting;
  final bool targetLimiting;

  @override
  RendererType get rendererType => RendererType.none;

  @override
  String get status {
    if (!disabledReason.enabled) {
      return disabledReason.description;
    }
    if (sourceLimiting) {
      if (currentRate > 0.0) {
        return 'Shortage of ore to refine. Refining throttled to ${prettyFraction(currentRate / maxRate)}.';
      }
      return 'Shortage of ore to refine. Add more holes to restart refining.';
    }
    if (targetLimiting) {
      if (currentRate > 0.0) {
        return 'Storage full. Refining throttled to ${prettyFraction(currentRate / maxRate)}.';
      }
      return 'Storage full. Add more piles to restart refining.';
    }
    assert(currentRate == maxRate);
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
              Text('Current refining rate: ${prettyMass(currentRate * 1000.0 * 60.0 * 60.0)} per hour.'),
              Text('Maximum refining rate: ${prettyMass(maxRate * 1000.0 * 60.0 * 60.0)} per hour.'),
            ],
          ),
        ),
      ],
    );
  }
}
