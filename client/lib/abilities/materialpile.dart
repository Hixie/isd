import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../assets.dart';
import '../icons.dart';
import '../nodes/system.dart';
import '../prettifiers.dart';
import '../spacetime.dart';
import '../widgets.dart';

// TODO: share code with nearly-identical OrePileFeature, MaterialStackFeature

class MaterialPileFeature extends AbilityFeature {
  MaterialPileFeature({
    required this.pileMass,
    required this.pileMassFlowRate,
    required this.timeOrigin,
    required this.spaceTime,
    required this.capacity,
    required this.materialName,
    required this.material,
  });

  final double pileMass;
  final double pileMassFlowRate; // kg/ms
  final int timeOrigin;
  final SpaceTime spaceTime;
  final double capacity;
  final String materialName;
  final int material;

  @override
  RendererType get rendererType => RendererType.ui;

  Widget _buildForMass(BuildContext context, double currentMass) {
    return CustomPaint(
      painter: _Pile(
        pileMass: currentMass,
        capacity: capacity,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: 30.0,
        ),
        child: FittedBox(
          alignment: Alignment.bottomCenter,
          child: Text(
            currentMass == 0.0 ? 'empty' : '${(100.0 * currentMass / capacity).toStringAsFixed(0)}% full\n${prettyMass(currentMass)}',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }

  @override
  Widget buildRenderer(BuildContext context) {
    if (pileMassFlowRate == 0.0)
      return _buildForMass(context, pileMass);
    return ValueListenableBuilder<double>(
      valueListenable: spaceTime.asListenable(),
      builder: (BuildContext context, double time, Widget? widget) {
        final double elapsed = time - timeOrigin; // ms
        return _buildForMass(context, pileMass + pileMassFlowRate * elapsed);
      },
    );
  }

  Widget _buildDialogInternal(BuildContext context, IconsManager icons, double duration, { required double fontSize }) {
    final double mass = math.min(pileMass + duration * pileMassFlowRate, capacity);
    return ListBody(
      children: <Widget>[
        Text('${prettyMass(mass)} out of ${prettyMass(capacity)}'),
        if (mass == capacity)
          const Text('Storage is full.')
        else if (mass == 0.0)
          const Text('Storage is empty.')
        else if (pileMassFlowRate > 0.0)
          Text('Storage is filling at ${prettyMass(pileMassFlowRate * 1000.0 * 60.0 * 60.0)} per hour.')
        else if (pileMassFlowRate < 0.0)
          Text('Storage is draining at ${prettyMass(-pileMassFlowRate * 1000.0 * 60.0 * 60.0)} per hour.')
        else if (pileMassFlowRate < 0.0)
          const Text('Storage is not changing.'),
      ],
    );
  }

  @override
  Widget buildDialog(BuildContext context) {
    final double fontSize = DefaultTextStyle.of(context).style.fontSize!;
    final IconsManager icons = IconsManagerProvider.of(context);
    final SystemNode system = SystemNode.of(parent);
    Widget result;
    if (pileMassFlowRate == 0.0) {
      result = _buildDialogInternal(context, icons, 0.0, fontSize: fontSize);
    } else {
      result = ValueListenableBuilder<double>(
        valueListenable: spaceTime.asListenable(),
        builder: (BuildContext context, double time, Widget? widget) {
          final double elapsed = time - timeOrigin; // ms
          return _buildDialogInternal(context, icons, elapsed, fontSize: fontSize);
        },
      );
    }
    return ListBody(
      children: <Widget>[
        Text.rich(
          TextSpan(
            style: bold,
            children: <InlineSpan>[
              if (material != 0)
                system.material(material).describe(context, icons, iconSize: fontSize)
              else
                TextSpan(text: materialName),
              const TextSpan(text: ' storage:'),
            ],
          ),
        ),
        Padding(
          padding: featurePadding,
          child: result,
        ),
      ],
    );
  }
}

class _Pile extends CustomPainter {
  const _Pile({ required this.pileMass, required this.capacity });

  final double pileMass;
  final double capacity;

  static final Paint _innerPaint = Paint()
    ..color = const Color(0xFFFFFFFF);

  static final Paint _outerPaint = Paint()
    ..color = const Color(0xFF000000)
    ..strokeWidth = 12.0
    ..style = PaintingStyle.stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final Path path = Path()
      ..moveTo(0.0, size.height)
      ..arcToPoint(
        Offset(size.width, size.height),
        radius: Radius.elliptical(size.width / 2.0, size.height * pileMass / capacity),
        largeArc: true,
      );
    canvas.drawPath(path, _innerPaint);
    canvas.drawPath(path, _outerPaint);
  }

  @override
  bool shouldRepaint(_Pile oldDelegate) => oldDelegate.pileMass != pileMass ||
                                           oldDelegate.capacity != capacity;
}
