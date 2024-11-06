import 'dart:math';

import 'package:flutter/rendering.dart' hide Gradient;
import 'package:flutter/widgets.dart' hide Gradient;

import '../assets.dart';
import '../layout.dart';
import '../world.dart';

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
      child.parent = parent;
    }
  }

  @override
  void detach() {
    for (AssetNode child in children.keys) {
      if (child.parent == parent) {
        child.parent = null;
        // if its parent is not the same as our parent,
        // then maybe it was already added to some other container
      }
    }
    super.detach();
  }

  @override
  Widget buildRenderer(BuildContext context, Widget? child) {
    return SpaceWidget(
      node: parent,
      diameter: parent.diameter,
      children: children.keys.map((AssetNode assetChild) => assetChild.build(context)).toList(),
    );
  }
}

class SpaceWidget extends MultiChildRenderObjectWidget {
  const SpaceWidget({
    super.key,
    required this.node,
    required this.diameter,
    super.children,
  });

  final WorldNode node;
  final double diameter;

  @override
  RenderSpace createRenderObject(BuildContext context) {
    return RenderSpace(
      node: node,
      diameter: diameter,
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderSpace renderObject) {
    renderObject
      ..node = node
      ..diameter = diameter;
  }
}

class SpaceParentData extends ParentData with ContainerParentDataMixin<RenderWorld> { }

class RenderSpace extends RenderWorldNode with ContainerRenderObjectMixin<RenderWorld, SpaceParentData> {
  RenderSpace({
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
  void setupParentData(RenderObject child) {
    if (child.parentData is! SpaceParentData) {
      child.parentData = SpaceParentData();
    }
  }

  @override
  void computeLayout(WorldConstraints constraints) {
    RenderWorld? child = firstChild;
    while (child != null) {
      final SpaceParentData childParentData = child.parentData! as SpaceParentData;
      child.layout(constraints);
      child = childParentData.nextSibling;
    }
  }

  @override
  WorldGeometry computePaint(PaintingContext context, Offset offset) {
    RenderWorld? child = firstChild;
    while (child != null) {
      final SpaceParentData childParentData = child.parentData! as SpaceParentData;
      context.paintChild(child, constraints.paintPositionFor(child.node, offset, <VoidCallback>[markNeedsPaint]));
      child = childParentData.nextSibling;
    }
    return WorldGeometry(shape: Circle(diameter));
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
