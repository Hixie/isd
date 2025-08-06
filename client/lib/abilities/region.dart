import 'package:flutter/widgets.dart';

import '../assets.dart';
import '../widgets.dart';

class RegionFeature extends AbilityFeature {
  RegionFeature({required this.minable});

  final bool minable;

  @override
  RendererType get rendererType => RendererType.none;

  @override
  Widget buildDialog(BuildContext context) {
    return ListBody(
      children: <Widget>[
        const Text('Region', style: bold),
        Padding(
          padding: featurePadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(minable ? 'This region can be mined.' : 'This region has been stripped bare, there is no longer anything to mine here.'),
            ],
          ),
        ),
      ],
    );
  }
}
