import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../layout.dart';
import '../world.dart';

class WorldPlaceholder extends LeafRenderObjectWidget {
  const WorldPlaceholder({
    super.key,
    required this.node,
    required this.color,
  });

  final WorldNode node;
  final Color color;

  @override
  RenderWorldPlaceholder createRenderObject(BuildContext context) {
    return RenderWorldPlaceholder(
      node: node,
      color: color,
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderWorldPlaceholder renderObject) {
    renderObject
      ..node = node
      ..color = color;
  }
}

class RenderWorldPlaceholder extends RenderWorldNode {
  RenderWorldPlaceholder({
    required super.node,
    Color color = const Color(0xFFFFFFFF),
  }) : _color = color;

  Color get color => _color;
  Color _color;
  set color (Color value) {
    if (value != _color) {
      _color = value;
      markNeedsPaint();
    }
  }

  @override
  void computeLayout(WorldConstraints constraints, double actualDiameter) { }

  Paint get _paint => Paint()
    ..color = color
    ..strokeWidth = 2.0
    ..style = PaintingStyle.stroke;

  @override
  void computePaint(PaintingContext context, Offset offset, double actualDiameter) {
    final double radius = actualDiameter / 2.0;
    context.canvas.drawCircle(offset, radius, _paint);
    context.canvas.drawLine(offset - Offset(radius, 0.0), offset + Offset(radius, 0.0), _paint);
    context.canvas.drawLine(offset - Offset(0.0, radius), offset + Offset(0.0, radius), _paint);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, { required Offset position }) {
    return false;
  }

  @override
  WorldTapTarget? computeTap(Offset offset) {
    return null;
  }
}
