import 'package:flutter/material.dart';

import '../assets.dart';
import '../prettifiers.dart';
import '../types.dart';
import '../widgets.dart';

class MiningFeature extends AbilityFeature {
  MiningFeature({
    required this.currentRate,
    required this.maxRate,
    required this.disabledReason,
    required this.sourceLimiting,
    required this.targetLimiting,
  });

  final double currentRate;
  final double maxRate;
  final DisabledReason disabledReason;
  final bool sourceLimiting;
  final bool targetLimiting;

  @override
  RendererType get rendererType => RendererType.none;

  @override
  String get status {
    if (!disabledReason.enabled)
      return disabledReason.description;
    if (sourceLimiting) {
      assert(currentRate == 0.0);
      return 'Region no longer has anything to mine.';
    }
    if (targetLimiting) {
      if (currentRate > 0.0) {
        return 'Storage full. Refining waste is being returned to the ground.';
      }
      return 'Storage full. Add more piles to restart mining.';
    }
    assert(currentRate == maxRate);
    return 'Mining at full rate.';
  }

  @override
  Widget buildDialog(BuildContext context) {
    return ListBody(
      children: <Widget>[
        const Text('Mining ore', style: bold),
        Padding(
          padding: featurePadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('Status: $status'),
              Text('Current mining rate: ${prettyMass(currentRate * 1000.0 * 60.0 * 60.0)} per hour.'),
              Text('Maximum mining rate: ${prettyMass(maxRate * 1000.0 * 60.0 * 60.0)} per hour.'),
            ],
          ),
        ),
      ],
    );
  }
}
