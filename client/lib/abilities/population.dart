import 'package:flutter/material.dart';

import '../assets.dart';
import '../prettifiers.dart';
import '../types.dart';
import '../widgets.dart';

class PopulationFeature extends AbilityFeature {
  PopulationFeature({
    required this.disabledReason,
    required this.count,
    required this.max,
    required this.jobs,
    required this.happiness,
  });

  final DisabledReason disabledReason;
  final int count;
  final int max;
  final int jobs;
  final double happiness;

  @override
  String get status {
    if (!disabledReason.enabled)
      return disabledReason.description;
    return 'Ready';
  }

  @override
  RendererType get rendererType => RendererType.none;

  @override
  Widget buildDialog(BuildContext context) {
    return ListBody(
      children: <Widget>[
        const Text('Population center', style: bold),
        Padding(
          padding: featurePadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('Status: $status'),
              Text('Total population: ${prettyQuantity(count, zero: "none", singular: " person", plural: " people")}'),
              Text('Capacity: ${prettyQuantity(count, zero: "none", singular: " person", plural: " people")}'),
              Text('Working population: ${prettyQuantity(jobs, zero: "none", singular: " worker", plural: " workers")}'),
              Text('Mean happiness: ${prettyHappiness(happiness)}'),
              Text('Total happiness: ${prettyHappiness(happiness * count)}'),
            ],
          ),
        ),
      ],
    );
  }
}
