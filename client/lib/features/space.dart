import 'dart:math';
import 'dart:ui';

import 'package:flutter/rendering.dart' hide Gradient;
import 'package:flutter/widgets.dart' hide Gradient;

import '../assets.dart';
import '../layout.dart';

typedef SpaceChild = ({ double r, double theta });

class SpaceFeature extends ContainerFeature {
  SpaceFeature(this.children);

  // consider this read-only; the entire SpaceFeature gets replaced when the child list changes
  final Map<AssetNode, SpaceChild> children;

  @override
  Offset findLocationForChild(AssetNode child, List<VoidCallback> callbacks) {
    parent.addTransientListeners(callbacks);
    final SpaceChild childData = children[child]!;
    return Offset(
      childData.r * cos(childData.theta),
      childData.r * sin(childData.theta),
    );
  }

  @override
  void attach(WorldNode parent) {
    super.attach(parent);
    for (AssetNode child in children.keys) {
      assert(child.parent == null);
      child.parent = parent;
    }
  }

  @override
  void detach() {
    for (AssetNode child in children.keys) {
      assert(child.parent == parent);
      child.parent = null;
    }
    super.detach();
  }

  @override
  Widget buildRenderer(BuildContext context, Widget? child) {
    return SpaceWidget(
      diameter: parent.diameter,
      children: children.keys.map((AssetNode assetChild) {
        return SpaceChildData(
          position: findLocationForChild(assetChild, [parent.notifyListeners]),
          child: assetChild.build(context, ),
        );
      }).toList(),
    );
  }
}

class SpaceWidget extends MultiChildRenderObjectWidget {
  const SpaceWidget({
    super.key,
    required this.diameter,
    super.children,
  });

  final double diameter;

  @override
  RenderSpace createRenderObject(BuildContext context) {
    return RenderSpace(
      diameter: diameter,
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderSpace renderObject) {
    renderObject
      ..diameter = diameter;
  }
}

class SpaceChildData extends ParentDataWidget<SpaceParentData> {
  const SpaceChildData({
    super.key, // ignore: unused_element
    required this.position,
    required super.child,
  });

  final Offset position;

  @override
  void applyParentData(RenderObject renderObject) {
    final SpaceParentData parentData = renderObject.parentData! as SpaceParentData;
    if (parentData.position != position) {
      parentData.position = position;
      renderObject.parent!.markNeedsLayout();
    }
  }

  @override
  Type get debugTypicalAncestorWidgetClass => RenderSpace;
}

class SpaceParentData extends ParentData with ContainerParentDataMixin<RenderWorld> {
  Offset position = Offset.zero; // in meters
}

class RenderSpace extends RenderWorld with ContainerRenderObjectMixin<RenderWorld, SpaceParentData> {
  RenderSpace({
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
  void setupParentData(RenderObject child) {
    if (child.parentData is! SpaceParentData) {
      child.parentData = SpaceParentData();
    }
  }

  @override
  void hitTestChildren(WorldHitTestResult result, { required Offset position }) {
    RenderWorld? child = firstChild;
    while (child != null) {
      if (child.geometry.contains(position) &&
          child.hitTest(result, position: position)) {
        return;
      }
      child = childBefore(child);
    }
  }

  @override
  void visitChildren(RenderObjectVisitor visitor) {
    RenderWorld? child = firstChild;
    while (child != null) {
      visitor(child);
      final SpaceParentData childParentData = child.parentData! as SpaceParentData;
      child = childParentData.nextSibling;
    }
  }

  @override
  WorldGeometry computeLayout(WorldConstraints constraints) {
    RenderWorld? child = firstChild;
    while (child != null) {
      final SpaceParentData childParentData = child.parentData! as SpaceParentData;
      child.layout(constraints.forChild(childParentData.position));
      child = childParentData.nextSibling;
    }
    return WorldGeometry(shape: Circle(center: constraints.scaledPosition, diameter: diameter));
  }

  TransformLayer? _transformLayer;

  Paint _blackFadePaint(double fade, Offset offset, double radius) {
    final Color black = const Color(0xFF000000).withOpacity(fade);
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
  void paint(PaintingContext context, Offset offset) {
    final double visibleDiameter = diameter * constraints.scale;
    assert(visibleDiameter >= WorldGeometry.minSystemRenderDiameter);
    final double fade = ((visibleDiameter - WorldGeometry.minSystemRenderDiameter) / (WorldGeometry.fullyVisibleRenderDiameter - WorldGeometry.minSystemRenderDiameter)).clamp(0.0, 1.0);
    final double renderRadius = radius * constraints.scale;
    context.canvas.drawRect(Rect.fromCircle(center: offset, radius: renderRadius), _blackFadePaint(fade, offset, renderRadius));
    RenderWorld? child = firstChild;
    while (child != null) {
      final SpaceParentData childParentData = child.parentData! as SpaceParentData;
      context.paintChild(child, offset + childParentData.position * constraints.scale);
      child = childParentData.nextSibling;
    }
  }

  @override
  void applyPaintTransform(RenderWorld child, Matrix4 transform) {
    transform.multiply(_transformLayer!.transform!);
  }

  @override
  WorldTapTarget? routeTap(Offset offset) {
    RenderWorld? child = firstChild;
    while (child != null) {
      final SpaceParentData childParentData = child.parentData! as SpaceParentData;
      // TODO: something...
      child = childParentData.nextSibling;
    }
    return null;
  }
}
