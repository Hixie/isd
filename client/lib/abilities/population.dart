import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../assets.dart';
import '../prettifiers.dart';
import '../spacetime.dart';
import '../types.dart';
import '../widgets.dart';

class Gossip {
  Gossip({
    required this.message,
    required this.source,
    required this.timestamp,
    required this.impact,
    required this.duration,
    required this.anchor,
    required this.people,
    required this.spreadRate,
  });

  final String message;
  final AssetNode? source;
  final int timestamp;
  final double impact;
  final int duration;
  final int anchor;
  final int people;
  final double spreadRate;

  double decay(double x) {
    return 1 - x * x * (3 - 2 * x);
  }

  double _actualImpact = 0.0;
  int _actualPeople = 0;
  double _totalImpact = 0.0;
  
  void _updateHappiness(int count, double now) {
    final double age = now - timestamp;
    _actualImpact = impact * decay((age / duration).clamp(0.0, 1.0));
    final double spreadTime = now - anchor;
    _actualPeople = math.min((people * math.pow(spreadRate, spreadTime)).round(), count);
    _totalImpact = _actualImpact * _actualPeople;
  }
  
  Widget build(BuildContext context) {
    return Text('${prettyHappiness(_totalImpact)}: $message (${prettyHappiness(_actualImpact)} for ${prettyQuantity(_actualPeople, zero: "nobody", singular: " person", plural: " people")})');
  }
}

class PopulationFeature extends AbilityFeature {
  PopulationFeature({
    required this.spaceTime,
    required this.disabledReason,
    required this.count,
    required this.max,
    required this.jobs,
    required this.gossips,
  });

  final SpaceTime spaceTime;
  final DisabledReason disabledReason;
  final int count;
  final int max;
  final int jobs;
  final List<Gossip> gossips;

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
    return ValueListenableBuilder<double>(
      valueListenable: spaceTime.asListenable(),
      builder: (BuildContext context, double time, Widget? widget) {
        double happiness = 0;
        for (Gossip gossip in gossips) {
          gossip._updateHappiness(count, time);
          happiness += gossip._totalImpact;
        }
        gossips.sort((Gossip a, Gossip b) => (b._totalImpact - a._totalImpact).round());
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
                  Text('Capacity: ${prettyQuantity(max, zero: "none", singular: " person", plural: " people")}'),
                  Text('Working population: ${prettyQuantity(jobs, zero: "none", singular: " worker", plural: " workers")}'),
                  Text('Total happiness: ${prettyHappiness(happiness)}'),
                  if (gossips.isNotEmpty)
                    const Text('Happiness:'),
                  if (gossips.isNotEmpty)
                    for (Gossip gossip in gossips)
                      Padding(
                        padding: const EdgeInsets.only(left: 8.0),
                        child: gossip.build(context),
                      ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
