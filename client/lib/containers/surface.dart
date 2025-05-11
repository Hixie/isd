import 'package:flutter/rendering.dart' hide Gradient;
import 'package:flutter/widgets.dart' hide Gradient;

import '../assets.dart';
import '../layout.dart';
import '../world.dart';

typedef SurfaceParameters = ({ Offset position });

class SurfaceFeature extends ContainerFeature {
  SurfaceFeature(this.children);

  // consider this read-only; the entire SurfaceFeature gets replaced when the child list changes
  final Map<AssetNode, SurfaceParameters> children;

  @override
  Offset findLocationForChild(AssetNode child, List<VoidCallback> callbacks) {
    return children[child]!.position;
  }

  @override
  void attach(AssetNode parent) {
    super.attach(parent);
    for (AssetNode child in children.keys) {
      child.attach(parent);
    }
  }

  @override
  void detach() {
    for (AssetNode child in children.keys) {
      if (child.parent == parent) {
        child.detach();
        // if its parent is not the same as our parent,
        // then maybe it was already added to some other container
      }
    }
    super.detach();
  }

  @override
  void walk(WalkCallback callback) {
    for (AssetNode child in children.keys) {
      assert(child.parent == parent);
      child.walk(callback);
    }
  }

  @override
  Widget buildRenderer(BuildContext context) {
    return SurfaceWidget(
      node: parent,
      diameter: parent.diameter,
      maxDiameter: parent.maxRenderDiameter,
      children: children.keys.map((AssetNode assetChild) => assetChild.build(context)).toList(),
    );
  }
}

class SurfaceWidget extends MultiChildRenderObjectWidget {
  const SurfaceWidget({
    super.key,
    required this.node,
    required this.diameter,
    required this.maxDiameter,
    super.children,
  });

  final WorldNode node;
  final double diameter;
  final double maxDiameter;

  @override
  RenderSurface createRenderObject(BuildContext context) {
    return RenderSurface(
      node: node,
      diameter: diameter,
      maxDiameter: maxDiameter,
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderSurface renderObject) {
    renderObject
      ..node = node
      ..diameter = diameter
      ..maxDiameter = maxDiameter;
  }
}

class SurfaceParentData extends ParentData with ContainerParentDataMixin<RenderWorld> {
  Offset? _computedPosition;
}

class RenderSurface extends RenderWorldWithChildren<SurfaceParentData> {
  RenderSurface({
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
  void setupParentData(RenderObject child) {
    if (child.parentData is! SurfaceParentData) {
      child.parentData = SurfaceParentData();
    }
  }

  @override
  void computeLayout(WorldConstraints constraints) {
    RenderWorld? child = firstChild;
    while (child != null) {
      final SurfaceParentData childParentData = child.parentData! as SurfaceParentData;
      child.layout(constraints);
      child = childParentData.nextSibling;
    }
  }

  @override
  double computePaint(PaintingContext context, Offset offset) {
    RenderWorld? child = firstChild;
    final double actualDiameter = computePaintDiameter(diameter, maxDiameter);
    while (child != null) {
      final SurfaceParentData childParentData = child.parentData! as SurfaceParentData;
      childParentData._computedPosition = constraints.paintPositionFor(child.node, offset, <VoidCallback>[markNeedsPaint]);
      context.paintChild(child, childParentData._computedPosition!);
      child = childParentData.nextSibling;
    }
    return actualDiameter;
  }

  @override
  WorldTapTarget? routeTap(Offset offset) {
    RenderWorld? child = lastChild;
    while (child != null) {
      final SurfaceParentData childParentData = child.parentData! as SurfaceParentData;
      final WorldTapTarget? result = child.routeTap(offset); // TODO: position...
      if (result != null)
        return result;
      child = childParentData.previousSibling;
    }
    return null;
  }
}
