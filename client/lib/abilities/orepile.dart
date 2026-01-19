import 'dart:math' as math;

import 'package:flutter/material.dart' hide Material;

import '../analysis.dart';
import '../assets.dart';
import '../icons.dart';
import '../nodes/system.dart';
import '../prettifiers.dart';
import '../spacetime.dart';
import '../widgets.dart';

// TODO: share code with nearly-identical MaterialPileFeature

class OrePileFeature extends AbilityFeature {
  OrePileFeature({
    required this.pileMass,
    required this.pileMassFlowRate,
    required this.timeOrigin,
    required this.spaceTime,
    required this.capacity,
    required this.materials,
  });

  final double pileMass;
  final double pileMassFlowRate; // kg/ms
  final int timeOrigin;
  final SpaceTime spaceTime;
  final double capacity;
  final Set<int> materials;

  @override
  RendererType get rendererType => RendererType.ui;

  // TODO: this is exactly the same logic as in materialpile.dart; we should refactor this to avoid code duplication

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
        Text('${prettyMass(mass)} out of ${prettyMass(capacity)}.'),
        if (mass == capacity)
          const Text('Storage is full.')
        else if (mass == 0.0)
          const Text('Storage is empty.')
        else if (pileMassFlowRate > 0.0)
          Text('Storage is filling at ${prettyRate(pileMassFlowRate, const Mass())}.')
        else if (pileMassFlowRate < 0.0)
          Text('Storage is draining at ${prettyRate(-pileMassFlowRate, const Mass())}.')
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
        const Text('Ore storage', style: bold),
        Padding(
          padding: featurePadding,
          child: result,
        ),
        const Padding(
          padding: featurePadding,
          child: Text('Known contents:'),
        ),
        Padding(
          padding: featurePadding,
          child: KnowledgeDish(
            materials: materials.map(system.material).toList(),
          ),
        ),
        Padding(
          padding: featurePadding,
          child: AnalysisUi.buildButton(context, parent),
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
