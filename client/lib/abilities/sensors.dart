import 'package:flutter/material.dart' hide Material;

import '../assets.dart';
import '../icons.dart';
import '../prettifiers.dart';
import '../widgets.dart';

class SpaceSensorFeature extends AbilityFeature {
  SpaceSensorFeature({
    required this.reach,
    required this.up,
    required this.down,
    required this.minSize,
    required this.nearestOrbit,
    required this.topOrbit,
    required this.detectedCount,
  });

  final int reach;
  final int up;
  final int down;
  final double minSize;
  final AssetNode? nearestOrbit;
  final AssetNode? topOrbit;
  final int? detectedCount;

  @override
  RendererType get rendererType => RendererType.none;

  @override
  Widget buildDialog(BuildContext context) {
    final double fontSize = DefaultTextStyle.of(context).style.fontSize!;
    final IconsManager icons = IconsManagerProvider.of(context);
    return ListBody(
      children: <Widget>[
        const Text('Space sensor', style: bold),
        Padding(
          padding: featurePadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('Resolution: ${prettyLength(minSize)}'),
              Text('Penetration: ${prettyQuantity(reach, zero: "none", singular: " level", plural: " levels")}'),
              Text('Range: ${prettyQuantity(up, zero: "zero orbits", singular: " orbit", plural: " orbits")}'),
              Text('Detail: ${prettyQuantity(up, zero: "zero orbits", singular: " orbit", plural: " orbits")}'),
              if (topOrbit != null)
                Text.rich(
                  TextSpan(
                    children: <InlineSpan>[
                      const TextSpan(text: 'Top of scan range: '),
                      topOrbit!.describe(context, icons, iconSize: fontSize),
                    ],
                  ),
                ),
              if (nearestOrbit != null)
                Text.rich(
                  TextSpan(
                    children: <InlineSpan>[
                      const TextSpan(text: 'Bottom of scan range: '),
                      nearestOrbit!.describe(context, icons, iconSize: fontSize),
                    ],
                  ),
                ),
              if (detectedCount != null)
                Text('Detected ${prettyQuantity(detectedCount!, zero: "nothing", singular: " object", plural: " objects")}.'),
            ],
          ),
        ),
      ],
    );
  }
}

class GridSensorFeature extends AbilityFeature {
  GridSensorFeature({
    required this.grid,
    required this.detectedCount,
  });

  final AssetNode? grid;
  final int? detectedCount;

  @override
  RendererType get rendererType => RendererType.none;

  @override
  Widget buildDialog(BuildContext context) {
    final double fontSize = DefaultTextStyle.of(context).style.fontSize!;
    final IconsManager icons = IconsManagerProvider.of(context);
    return ListBody(
      children: <Widget>[
        const Text('Grid sensor', style: bold),
        Padding(
          padding: featurePadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (grid != null)
                Text.rich(
                  TextSpan(
                    children: <InlineSpan>[
                      const TextSpan(text: 'Scanning grid: '),
                      grid!.describe(context, icons, iconSize: fontSize),
                    ],
                  ),
                ),
              if (detectedCount != null)
                Text('Detected ${prettyQuantity(detectedCount!, zero: "nothing", singular: " object", plural: " objects")}.'),
            ],
          ),
        ),
      ],
    );
  }
}
