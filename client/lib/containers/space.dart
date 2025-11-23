import 'dart:math';

import 'package:flutter/rendering.dart' hide Gradient;
import 'package:flutter/widgets.dart' hide Gradient;

import '../assets.dart';
import '../icons.dart';
import '../layout.dart';
import '../widgets.dart';
import '../world.dart';

typedef SpaceParameters = ({ double r, double theta });

class SpaceFeature extends ContainerFeature {
  SpaceFeature(this.children);

  // consider this read-only; the entire SpaceFeature gets replaced when the child list changes
  final Map<AssetNode, SpaceParameters> children;

  @override
  Offset findLocationForChild(AssetNode child, List<VoidCallback> callbacks) {
    parent.addTransientListeners(callbacks);
    final SpaceParameters childData = children[child]!;
    return Offset(
      childData.r * cos(childData.theta),
      childData.r * sin(childData.theta),
    );
  }

  @override
  void attach(Node parent) {
    super.attach(parent);
    for (AssetNode child in children.keys) {
      child.attach(this);
    }
  }

  @override
  void detach() {
    for (AssetNode child in children.keys) {
      if (child.parent == this)
        child.dispose();
    }
    super.detach();
  }

  @override
  void walk(WalkCallback callback) {
    for (AssetNode child in children.keys) {
      child.walk(callback);
    }
  }

  @override
  RendererType get rendererType => RendererType.circle;

  @override
  Widget buildRenderer(BuildContext context) {
    return SpaceWidget(
      node: parent,
      diameter: parent.diameter,
      children: children.keys.map((AssetNode assetChild) => assetChild.build(context)).toList(),
    );
  }

  @override
  Widget buildDialog(BuildContext context) {
    final double fontSize = DefaultTextStyle.of(context).style.fontSize!;
    final IconsManager icons = IconsManagerProvider.of(context);
    return ListBody(
      children: <Widget>[
        const Text('Astronomical objects', style: bold),
        Padding(
          padding: featurePadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (children.isEmpty)
                const Text('None detected', style: italic), // this should never happen; at a minimum, we should be able to detect ourselves otherwise we wouldn't know about this system
              for (AssetNode region in children.keys)
                Text.rich(
                  region.describe(context, icons, iconSize: fontSize),
                ),
            ],
          ),
        ),
      ],
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

class SpaceParentData extends ParentData with ContainerParentDataMixin<RenderWorld> {
  Offset? _computedPosition;
}

class RenderSpace extends RenderWorldWithChildren<SpaceParentData> {
  RenderSpace({
    required super.node,
    required double diameter,
  }) : _diameter = diameter;

  double get diameter => _diameter;
  double _diameter;
  set diameter (double value) {
    if (value != _diameter) {
      _diameter = value;
      markNeedsPaint();
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
  double computePaint(PaintingContext context, Offset offset) {
    RenderWorld? child = firstChild;
    while (child != null) {
      final SpaceParentData childParentData = child.parentData! as SpaceParentData;
      childParentData._computedPosition = constraints.paintPositionFor(child.node, offset, <VoidCallback>[markNeedsPaint]);
      context.paintChild(child, childParentData._computedPosition!);
      child = childParentData.nextSibling;
    }
    return diameter;
  }

  @override
  WorldTapTarget? routeTap(Offset offset) {
    RenderWorld? child = lastChild;
    while (child != null) {
      final SpaceParentData childParentData = child.parentData! as SpaceParentData;
      final WorldTapTarget? result = child.routeTap(offset);
      if (result != null)
        return result;
      child = childParentData.previousSibling;
    }
    return null;
  }
}
