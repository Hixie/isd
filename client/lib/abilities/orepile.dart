import 'package:flutter/material.dart';

import '../assets.dart';
import '../prettifiers.dart';
import '../spacetime.dart';

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
  RendererType get rendererType => RendererType.box;

  @override
  Widget buildRenderer(BuildContext context) {
    final double currentMass;
    if (pileMassFlowRate != 0.0) {
      final double elapsed = spaceTime.computeTime(<VoidCallback>[parent.notifyListeners]) * 1000.0 - timeOrigin; // ms
      currentMass = pileMass + pileMassFlowRate * elapsed;
    } else {
      currentMass = pileMass;
    }
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
            '${(100.0 * currentMass / capacity).toStringAsFixed(0)}% full\n${prettyMass(currentMass)}',
            textAlign: TextAlign.center,
          ),
        ),
      ),
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
