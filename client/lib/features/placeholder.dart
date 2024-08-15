import 'dart:math';

import 'package:flutter/widgets.dart';

import '../layout.dart';

class WorldPlaceholder extends LeafRenderObjectWidget {
  const WorldPlaceholder({
    super.key,
    required this.diameter,
    required this.color,
  });

  final double diameter;
  final Color color;

  @override
  RenderWorldPlaceholder createRenderObject(BuildContext context) {
    return RenderWorldPlaceholder(
      diameter: diameter,
      color: color,
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderWorldPlaceholder renderObject) {
    renderObject
      ..diameter = diameter
      ..color = color;
  }
}

class RenderWorldPlaceholder extends RenderWorld {
  RenderWorldPlaceholder({
    required double diameter,
    Color color = const Color(0xFFFFFFFF),
  }) : _diameter = diameter,
       _color = color;

  double get diameter => _diameter;
  double _diameter;
  set diameter (double value) {
    if (value != _diameter) {
      _diameter = value;
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
  WorldGeometry computeLayout(WorldConstraints constraints) {
    return WorldGeometry(shape: Circle(center: constraints.scaledPosition, diameter: diameter));
  }

  Paint get _paint => Paint()
    ..color = color
    ..strokeWidth = 2.0
    ..style = PaintingStyle.stroke;

  static const double _minRadius = 20.0;
  static const double _maxDiameterRatio = 0.1;

  @override
  void paint(PaintingContext context, Offset offset) {
    double actualRadius = max(_minRadius, radius * constraints.scale);
    if (parent is RenderWorld) {
      actualRadius = min(actualRadius, (parent! as RenderWorld).geometry.shape.diameter * _maxDiameterRatio * constraints.scale / 2.0);
    }
    context.canvas.drawCircle(offset, actualRadius, _paint);
  }

  @override
  WorldTapTarget? routeTap(Offset offset) {
    return null;
  }
}
