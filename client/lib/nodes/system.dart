import 'dart:ui';

import 'package:flutter/rendering.dart' hide Gradient;
import 'package:flutter/widgets.dart' hide Gradient;

import '../assets.dart';
import '../layout.dart';
import '../world.dart';

class SystemNode extends WorldNode {
  SystemNode({ super.parent, required this.id });

  final int id;

  String get label => _label;
  String _label = '';

  void _updateLabel() {
    assert(_root != null);
    if (_root!.name != _label) {
      _label = _root!.name;
      notifyListeners();
    }
  }

  AssetNode get root => _root!;
  AssetNode? _root;
  set root(AssetNode value) {
    if (_root != value) {
      _root?.removeListener(_updateLabel);
      _root = value;
      _label = _root!.name;
      notifyListeners();
      _root!.addListener(_updateLabel);
    }
  }

  Offset get offset => _offset!;
  Offset? _offset;
  set offset(Offset value) {
    if (_offset != value) {
      _offset = value;
      notifyListeners();
    }
  }

  @override
  double get diameter => root.diameter;

  @override
  Offset findLocationForChild(WorldNode child, List<VoidCallback> callbacks) {
    return Offset.zero;
  }

  @override
  Widget buildRenderer(BuildContext context, Widget? nil) {
    return SystemWidget(
      node: this,
      diameter: diameter,
      child: root.build(context),
    );
  }
}

class SystemWidget extends SingleChildRenderObjectWidget {
  const SystemWidget({
    super.key,
    required this.node,
    required this.diameter,
    super.child,
  });

  final WorldNode node;
  final double diameter;

  @override
  RenderSystem createRenderObject(BuildContext context) {
    return RenderSystem(
      node: node,
      diameter: diameter,
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderSystem renderObject) {
    renderObject
      ..node = node
      ..diameter = diameter;
  }
}

class RenderSystem extends RenderWorldNode with RenderObjectWithChildMixin<RenderWorld> {
  RenderSystem({
    required super.node,
    required double diameter,
  }) : _diameter = diameter;

  double get diameter => _diameter;
  double _diameter;
  set diameter (double value) {
    if (value != _diameter) {
      _diameter = value;
      markNeedsLayout();
    }
  }

  double get radius => diameter / 2.0;

  @override
  void computeLayout(WorldConstraints constraints) {
    if (child != null)
      child!.layout(constraints);
  }

  Paint _blackFadePaint(double fade, Offset offset, double radius) {
    final Color black = const Color(0xFF000000).withValues(alpha: fade);
    return Paint()
      ..shader = Gradient.radial(
        offset,
        radius,
        <Color>[ black, black, const Color(0x00000000) ],
        <double>[ 0.0, 0.8, 1.0 ],
        TileMode.decal,
      );
  }

  @override
  WorldGeometry computePaint(PaintingContext context, Offset offset) {
    if (child != null) {
      final double visibleDiameter = diameter * constraints.scale;
      assert(visibleDiameter >= WorldGeometry.minSystemRenderDiameter);
      final double fade = ((visibleDiameter - WorldGeometry.minSystemRenderDiameter) / (WorldGeometry.fullyVisibleRenderDiameter - WorldGeometry.minSystemRenderDiameter)).clamp(0.0, 1.0);
      final double renderRadius = radius * constraints.scale;
      context.canvas.drawRect(Rect.fromCircle(center: offset, radius: renderRadius), _blackFadePaint(fade, offset, renderRadius));
      context.paintChild(child!, constraints.paintPositionFor(child!.node, offset, <VoidCallback>[markNeedsPaint]));
    }
    return WorldGeometry(shape: Circle(diameter));
  }

  @override
  WorldTapTarget? routeTap(Offset offset) {
    if (child != null)
      return child!.routeTap(offset);
    return null;
  }
}
