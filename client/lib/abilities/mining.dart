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
  });

  final double currentRate;
  final double maxRate;
  final DisabledReason disabledReason;

  @override
  RendererType get rendererType => RendererType.none;

  @override
  String get status {
    if (disabledReason.sourceLimited) {
      assert(currentRate == 0.0);
      return 'Region no longer has anything to mine.';
    }
    if (disabledReason.targetLimited) {
      if (currentRate > 0.0) {
        return 'Storage full. Refining waste is being returned to the ground.';
      }
      return 'Storage full. Add more piles to restart mining.';
    }
    if (!disabledReason.fullyActive)
      return disabledReason.describe(currentRate);
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
              Text('Current mining rate: ${prettyRate(currentRate, const Mass())}.'),
              Text('Maximum mining rate: ${prettyRate(maxRate, const Mass())}.'),
            ],
          ),
        ),
      ],
    );
  }
}
