import 'package:flutter/material.dart';

import '../assets.dart';
import '../prettifiers.dart';
import '../spacetime.dart';

class MaterialStackFeature extends AbilityFeature {
  MaterialStackFeature({
    required this.pileQuantity,
    required this.pileQuantityFlowRate,
    required this.timeOrigin,
    required this.spaceTime,
    required this.capacity,
    required this.materialName,
    required this.material,
  });

  final int pileQuantity;
  final double pileQuantityFlowRate; // kg/ms
  final int timeOrigin;
  final SpaceTime spaceTime;
  final int capacity;
  final String materialName;
  final int material;

  @override
  RendererType get rendererType => RendererType.box;

  @override
  Widget buildRenderer(BuildContext context) {
    final double currentQuantity;
    if (pileQuantityFlowRate != 0.0) {
      final double elapsed = spaceTime.computeTime(<VoidCallback>[parent.notifyListeners]) * 1000.0 - timeOrigin; // ms
      currentQuantity = pileQuantity + pileQuantityFlowRate * elapsed;
    } else {
      currentQuantity = pileQuantity.toDouble();
    }
    return CustomPaint(
      painter: _Stack(
        pileQuantity: currentQuantity,
        capacity: capacity.toDouble(),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: 30.0,
        ),
        child: FittedBox(
          alignment: Alignment.bottomCenter,
          child: Text(
            '${(100.0 * currentQuantity / capacity).toStringAsFixed(0)}% full\n${prettyQuantity(currentQuantity)}',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}

class _Stack extends CustomPainter {
  const _Stack({ required this.pileQuantity, required this.capacity });

  final double pileQuantity;
  final double capacity;

  static final Paint _innerPaint = Paint()
    ..color = const Color(0xFFFFFFFF);

  static final Paint _outerPaint = Paint()
    ..color = const Color(0xFF000000)
    ..strokeWidth = 12.0
    ..style = PaintingStyle.stroke;
  
  @override
  void paint(Canvas canvas, Size size) {
    final double top = size.height * (1.0 - pileQuantity / capacity);
    final Path path = Path()
      ..moveTo(0.0, size.height)
      ..lineTo(0.0, top)
      ..lineTo(size.width, top)
      ..lineTo(size.width, size.height);
    canvas.drawPath(path, _innerPaint);
    canvas.drawPath(path, _outerPaint);
  }

  @override
  bool shouldRepaint(_Stack oldDelegate) => oldDelegate.pileQuantity != pileQuantity ||
                                            oldDelegate.capacity != capacity;
}
