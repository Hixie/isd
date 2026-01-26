import 'package:flutter/material.dart' hide Material;

import '../assets.dart';
import '../dialogs.dart';
import '../game.dart';
import '../icons.dart';
import '../nodes/system.dart';
import '../prettifiers.dart';
import '../stringstream.dart';
import '../widgets.dart';

class SampleMaterialFeature extends AbilityFeature {
  SampleMaterialFeature({
    required this.size,
    required this.mass,
    required this.material,
    required this.isOre,
  });

  final double size;
  final double mass;
  final int material;
  final bool isOre;

  @override
  RendererType get rendererType => RendererType.ui;

  Widget _buildButton(BuildContext context) {
    if (mass == 0.0) {
      return OutlinedButton(
        child: const Text('Sample ore piles'),
        onPressed: () async {
          final Game game = GameProvider.of(context);
          final SystemNode system = SystemNode.of(parent);
          final StreamReader result = await system.play(<Object>[parent.id, 'sample-ore']);
          if (!result.readBool()) {
            game.reportError('Unable to fill sample container.');
          }
        },
      );
    }
    return OutlinedButton(
      child: const Text('Empty sample container'),
      onPressed: () async {
        final Game game = GameProvider.of(context);
        final SystemNode system = SystemNode.of(parent);
        final StreamReader result = await system.play(<Object>[parent.id, 'clear-sample']);
        if (!result.readBool()) {
          game.reportError('Unable to empty sample container.');
        }
      },
    );
  }
  
  @override
  Widget buildRenderer(BuildContext context) {
    final IconsManager icons = IconsManagerProvider.of(context);
    final SystemNode system = SystemNode.of(parent);
    Widget result;
    if (mass == 0.0) {
      result = const Center(child: Text(
        'Sample container empty.',
        textAlign: TextAlign.center,
      ));
    } else if (material == 0) {
      result = Center(child: Text(
        'Sample container contains ${prettyMass(mass)} of unknown ${isOre ? "ore" : "material"}.',
        textAlign: TextAlign.center,
      ));
    } else {
      result = FittedBox(child: system.material(material).asIcon(context, size: 20.0, icons: icons));
    }
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: const Color(0x10000000),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20.0),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          children: <Widget>[
            Expanded(
              child: result,
            ),
            _buildButton(context),
          ],
        ),
      ),
    );
  }

  @override
  Widget buildDialog(BuildContext context) {
    final double fontSize = DefaultTextStyle.of(context).style.fontSize!;
    final IconsManager icons = IconsManagerProvider.of(context);
    final SystemNode system = SystemNode.of(parent);
    return ListBody(
      children: <Widget>[
        const Text('Sample container', style: bold),
        Padding(
          padding: featurePadding,
          child: mass == 0.0
               ? const Text('empty')
               : material == 0
               ? Text('${prettyMass(mass)} of unknown ${ isOre ? "ore" : "material" }')
               : Text.rich(
                   TextSpan(
                     children: <InlineSpan>[
                       TextSpan(text: '${prettyMass(mass)} of '),
                       system.material(material).describe(context, icons, iconSize: fontSize),
                     ],
                   ),
                 ),
        ),
        Padding(
          padding: featurePadding,
          child: _buildButton(context),
        ),
      ],
    );
  }
}
