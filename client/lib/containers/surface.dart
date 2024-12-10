import 'package:flutter/rendering.dart' hide Gradient;
import 'package:flutter/widgets.dart' hide Gradient;

import '../assets.dart';
import '../layout.dart';
import '../world.dart';

typedef SurfaceParameters = ();

class SurfaceFeature extends ContainerFeature {
  SurfaceFeature(this.children);

  // consider this read-only; the entire SurfaceFeature gets replaced when the child list changes
  final Map<AssetNode, SurfaceParameters> children;

  @override
  Offset findLocationForChild(AssetNode child, List<VoidCallback> callbacks) {
    // final SurfaceParameters childData = children[child]!;
    // TODO: positioned regions
    return Offset.zero;
  }

  @override
  void attach(AssetNode parent) {
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
  void walk(WalkCallback callback) {
    for (AssetNode child in children.keys) {
      child.walk(callback);
    }
  }

  @override
  Widget buildRenderer(BuildContext context, Widget? child) {
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

class SurfaceParentData extends ParentData with ContainerParentDataMixin<RenderWorld> { }

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

  Paint get _planetPaint => Paint()
    ..color = const Color(0xFFFFFFFF);

  @override
  WorldGeometry computePaint(PaintingContext context, Offset offset) {
    RenderWorld? child = firstChild;
    final double actualDiameter = computePaintDiameter(diameter, maxDiameter);
    context.canvas.drawCircle(offset, actualDiameter / 2.0, _planetPaint); // TODO: pretty planet surfaces
    while (child != null) {
      final SurfaceParentData childParentData = child.parentData! as SurfaceParentData;
      context.paintChild(child, constraints.paintPositionFor(child.node, offset, <VoidCallback>[markNeedsPaint]));
      child = childParentData.nextSibling;
    }
    return WorldGeometry(shape: Circle(actualDiameter));
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
