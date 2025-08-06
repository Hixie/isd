import 'package:flutter/material.dart';

import '../assets.dart';
import '../prettifiers.dart';
import '../widgets.dart';

class PopulationFeature extends AbilityFeature {
  PopulationFeature({
    required this.count,
    required this.happiness,
  });

  final int count;
  final double happiness;

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
              Text('Total population: ${prettyQuantity(count, zero: "none", singular: " person", plural: " people")}'),
              Text('Mean happiness: ${prettyHappiness(happiness)}'),
              Text('Total happiness: ${prettyHappiness(happiness * count)}'),
            ],
          ),
        ),
      ],
    );
  }
}
