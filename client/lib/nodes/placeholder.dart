import 'package:flutter/widgets.dart';

import '../layout.dart';

class WorldPlaceholder extends LeafRenderObjectWidget {
  const WorldPlaceholder({
    super.key,
    required this.diameter,
    required this.maxDiameter,
    required this.color,
  }) : assert(maxDiameter > 0.0);

  final double diameter;
  final double maxDiameter;
  final Color color;

  @override
  RenderWorldPlaceholder createRenderObject(BuildContext context) {
    return RenderWorldPlaceholder(
      diameter: diameter,
      maxDiameter: maxDiameter,
      color: color,
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderWorldPlaceholder renderObject) {
    renderObject
      ..diameter = diameter
      ..maxDiameter = maxDiameter
      ..color = color;
  }
}

class RenderWorldPlaceholder extends RenderWorld {
  RenderWorldPlaceholder({
    required double diameter,
    required double maxDiameter,
    Color color = const Color(0xFFFFFFFF),
  }) : _diameter = diameter,
       _maxDiameter = maxDiameter,
       _color = color;

  double get diameter => _diameter;
  double _diameter;
  set diameter (double value) {
    if (value != _diameter) {
      _diameter = value;
      markNeedsLayout();
    }
  }

  double get maxRadius => maxDiameter / 2.0;

  double get maxDiameter => _maxDiameter;
  double _maxDiameter;
  set maxDiameter (double value) {
    if (value != _maxDiameter) {
      _maxDiameter = value;
      markNeedsLayout();
    }
  }

  double get radius => diameter / 2.0;

  Color get color => _color;
  Color _color;
  set color (Color value) {
    if (value != _color) {
      _color = value;
      markNeedsPaint();
    }
  }

  @override
  void computeLayout(WorldConstraints constraints) { }

  Paint get _paint => Paint()
    ..color = color
    ..strokeWidth = 2.0
    ..style = PaintingStyle.stroke;

  @override
  WorldGeometry computePaint(PaintingContext context, Offset offset) {
    final double radius = computePaintDiameter(diameter, maxDiameter) / 2.0;
    context.canvas.drawCircle(offset, radius, _paint);
    context.canvas.drawLine(offset - Offset(radius, 0.0), offset + Offset(radius, 0.0), _paint);
    context.canvas.drawLine(offset - Offset(0.0, radius), offset + Offset(0.0, radius), _paint);
    return WorldGeometry(shape: Circle(diameter));
  }

  @override
  WorldTapTarget? routeTap(Offset offset) {
    return null;
  }
}
