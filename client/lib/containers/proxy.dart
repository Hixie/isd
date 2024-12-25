import 'package:flutter/rendering.dart' hide Gradient;
import 'package:flutter/widgets.dart' hide Gradient;

import '../assets.dart';
import '../layout.dart';
import '../world.dart';

class ProxyFeature extends ContainerFeature {
  ProxyFeature(this.child);

  final AssetNode? child;

  @override
  Offset findLocationForChild(AssetNode child, List<VoidCallback> callbacks) {
    assert(child == this.child);
    return Offset.zero;
  }

  @override
  void attach(AssetNode parent) {
    super.attach(parent);
    if (child != null)
      child!.attach(parent);
  }

  @override
  void detach() {
    if (child != null && child!.parent == parent) {
      child!.detach();
      // if its parent is not the same as our parent,
      // then maybe it was already added to some other container
    }
    super.detach();
  }

  @override
  void walk(WalkCallback callback) {
    if (child != null) {
      assert(child!.parent == parent);
      child!.walk(callback);
    }
  }

  @override
  Widget buildRenderer(BuildContext context, Widget? child) {
    return ProxyWidget(
      node: parent,
      diameter: parent.diameter,
      maxDiameter: parent.maxRenderDiameter,
      child: this.child?.build(context),
    );
  }
}

class ProxyWidget extends SingleChildRenderObjectWidget {
  const ProxyWidget({
    super.key,
    required this.node,
    required this.diameter,
    required this.maxDiameter,
    super.child,
  });

  final WorldNode node;
  final double diameter;
  final double maxDiameter;

  @override
  RenderProxy createRenderObject(BuildContext context) {
    return RenderProxy(
      node: node,
      diameter: diameter,
      maxDiameter: maxDiameter,
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderProxy renderObject) {
    renderObject
      ..node = node
      ..diameter = diameter
      ..maxDiameter = maxDiameter;
  }
}

class RenderProxy extends RenderWorldNode with RenderObjectWithChildMixin<RenderWorld> {
  RenderProxy({
    required super.node,
    required double diameter,
    required double maxDiameter,
  }) : _diameter = diameter,
       _maxDiameter = maxDiameter;

  double get diameter => _diameter;
  double _diameter;
  set diameter (double value) {
    if (value != _diameter) {
      _diameter = value;
      markNeedsPaint();
    }
  }

  double get maxDiameter => _maxDiameter;
  double _maxDiameter;
  set maxDiameter (double value) {
    if (value != _maxDiameter) {
      _maxDiameter = value;
      markNeedsPaint();
    }
  }

  double get radius => diameter / 2.0;

  @override
  void computeLayout(WorldConstraints constraints) {
    if (child != null) {
      child!.layout(constraints);
    }
  }

  @override
  WorldGeometry computePaint(PaintingContext context, Offset offset) {
    final double actualDiameter = computePaintDiameter(diameter, maxDiameter);
    if (child != null) {
      context.paintChild(child!, constraints.paintPositionFor(child!.node, offset, <VoidCallback>[markNeedsPaint]));
    }
    return WorldGeometry(shape: Circle(actualDiameter));
  }

  @override
  WorldTapTarget? routeTap(Offset offset) {
    if (child != null) {
      final WorldTapTarget? result = child!.routeTap(offset); // TODO: position...
      if (result != null)
        return result;
    }
    return null;
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, { required Offset position }) {
    bool hit = false;
    if (child != null) {
      hit = hit || child!.hitTestChildren(result, position: position);
    }
    return hit;
  }
}
