import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'world.dart';

// CONSTRAINTS

class WorldConstraints extends Constraints {
  const WorldConstraints({
    required this.viewportSize,
    required this.zoom,
    required this.scale,
    required Map<WorldNode, Offset> precomputedPositions,
  }) : _precomputedPositions = precomputedPositions;

  final Size viewportSize; // size of visible area in pixels; by definition, center of viewport is at Offset.zero in the coordinate space that the paint method's offset is in
  final double zoom; // logarithmic scale (0..)
  final double scale; // pixels per meter with zoom applied
  final Map<WorldNode, Offset> _precomputedPositions; // offsets from viewport center in meters; see paintPositionFor below

  double get zoomFactor => exp(zoom);

  @override
  bool get isTight => true;

  @override
  bool get isNormalized => true;

  @override
  bool debugAssertIsValid({
    bool isAppliedConstraint = false,
    InformationCollector? informationCollector,
  }) {
    return true;
  }

  // Offset to pass to paint method for render objects of specific nodes, giving
  // the pixel offset from the canvas center to the node center.
  // For some nodes, this is precomputed. For others, it's a delta from the parent's offset.

  // This includes the pan (because that's baked into the parent offset).
  Offset paintPositionFor(WorldNode node, Offset parentOffset, List<VoidCallback> callbacks) {
    if (_precomputedPositions.containsKey(node)) {
      return _precomputedPositions[node]! * scale;
    }
    assert(node.parent != null); // root should always be precomputed
    return parentOffset + node.worldParent!.findLocationForChild(node, callbacks) * scale;
  }

  @override
  bool operator ==(Object other) {
    if (other.runtimeType != runtimeType) {
      return false;
    }
    return other is WorldConstraints
        && other.viewportSize == viewportSize
        && other.zoom == zoom
        && other.scale == scale
        && other._precomputedPositions == _precomputedPositions;
  }

  @override
  int get hashCode => Object.hash(viewportSize, zoom, scale, _precomputedPositions);

  @override
  String toString() => 'WorldConstraints(x$zoom, scale=${scale}px/m, viewport=${viewportSize}px)';
}

sealed class WorldGeometry {
  static const double minSystemRenderDiameter = 4.0; // a system less than this size is not rendered at all, and fades in...
  static const double fullyVisibleRenderDiameter = 48.0; // ...up to the point where it's at least this size.
}

// HIT TEST

abstract interface class WorldTapTarget {
  void handleTapDown();
  void handleTapCancel();
  void handleTapUp();
}


// ABSTRACT RENDER OBJECTS

abstract class RenderWorld extends RenderObject {
  RenderWorld();

  // this is used just to figure out the position of a child
  // (the child's node is the first argument passed to constraints.paintPositionFor)
  WorldNode get node;

  @override
  WorldConstraints get constraints => super.constraints as WorldConstraints;

  static const double _minDiameter = 20.0;
  static const double _maxDiameterRatio = 0.1;

  static double get _minCartoonDiameter => log(10e6); // 10,000 km, a bit smaller than earth
  static double get _maxCartoonDiameter => log( 1e9); // 2 million km, a bit bigger than our sun

  static double _computePaintDiameter(double diameter, double parentDiameter, double scale) {
    final double cartoonScale = ((log(diameter) - _minCartoonDiameter) / (_maxCartoonDiameter - _minCartoonDiameter)).clamp(0.0, 1.0) * 2.5 + 1.0;
    assert(cartoonScale >= 1.0);
    assert(cartoonScale <= 3.5);
    return min(
      max(
        diameter * scale, // try to be your actual size, but
        _minDiameter * cartoonScale, // ...don't be smaller than something visible
      ),
      scale * max( // ...and...
        parentDiameter * _maxDiameterRatio, // ...definitely don't be bigger than one tenth your parent
        diameter, // ...unless you really are bigger than one tenth your parent
      ),
    );
  }

  static const double _paintThreshold = 1.0;

  Offset get paintCenter => _paintCenter!;
  Offset? _paintCenter;
  double get paintDiameter => _paintDiameter!;
  double? _paintDiameter;

  double computePaintDiameter() => _computePaintDiameter(node.diameter, node.maxRenderDiameter, constraints.scale);

  @override
  bool get sizedByParent => true;

  @override
  void performResize() { }

  @override
  void performLayout() {
    _paintDiameter = computePaintDiameter();
    if (_paintDiameter! >= _paintThreshold) {
      computeLayout(constraints, _paintDiameter!);
    }
  }

  void computeLayout(WorldConstraints constraints, double actualDiameter);

  @override
  @nonVirtual
  void paint(PaintingContext context, Offset offset) {
    assert(offset.isFinite);
    _paintCenter = offset;
    if (_paintDiameter! >= _paintThreshold) {
      computePaint(context, offset, _paintDiameter!);
    }
  }

  // The offset parameter is the distance from the canvas origin to the asset origin, in pixels.
  // Canvas origin is the center of the viewport, whose size is constraints.viewportSize.
  void computePaint(PaintingContext context, Offset offset, double actualDiameter);

  @override
  void applyPaintTransform(covariant RenderObject child, Matrix4 transform) {
    // This intentionally does nothing, because Flutter's applyPaintTransform logic
    // does not know how to handle our floating origin system.
    // See WorldToBox in widgets.dart.
  }

  @override
  Rect get paintBounds => Rect.fromCircle(center: _paintCenter!, radius: _paintDiameter! / 2.0);

  @override
  Rect get semanticBounds => paintBounds; // TODO: actually implement semantics

  bool isInsideCircle(Offset offset) {
    final double r = _paintDiameter! / 2.0;
    return (_paintDiameter! >= _paintThreshold) && (offset - _paintCenter!).distanceSquared <= r * r;
  }

  bool isInsideSquare(Offset offset) {
    final double r = _paintDiameter! / 2.0;
    final Offset distance = offset - _paintCenter!;
    return (_paintDiameter! >= _paintThreshold) && (distance.dx.abs() <= r) && (distance.dy.abs() <= r);
  }

  @override
  void debugAssertDoesMeetConstraints() { }

  bool hitTest(BoxHitTestResult result, { required Offset position }) {
    return (_paintDiameter! >= _paintThreshold) && hitTestChildren(result, position: position);
  }

  @protected
  bool hitTestChildren(BoxHitTestResult result, { required Offset position });

  // Offset is the offset from the center of the screen at which the tap happened.
  // Subtracting the offset given to [computePaint] gives you the distance from
  // the center of the asset to the tap.
  @nonVirtual
  WorldTapTarget? routeTap(Offset offset) {
    if (_paintDiameter! >= _paintThreshold) {
      return computeTap(offset);
    } else {
      return null;
    }
  }

  WorldTapTarget? computeTap(Offset offset);
}

abstract class RenderWorldNode extends RenderWorld {
  RenderWorldNode({ required WorldNode node }) : _node = node;

  @override
  WorldNode get node => _node;
  WorldNode _node;
  set node (WorldNode value) {
    if (value != _node) {
      _node = value;
      markNeedsPaint();
    }
  }
}

abstract class RenderWorldWithChildren<ParentDataType extends ContainerParentDataMixin<RenderWorld>>
       extends RenderWorldNode
          with ContainerRenderObjectMixin<RenderWorld, ParentDataType> {
  RenderWorldWithChildren({ required super.node });

  @override
  bool hitTestChildren(BoxHitTestResult result, { required Offset position }) {
    bool hit = false;
    RenderWorld? child = lastChild;
    while (child != null) {
      hit = hit || child.hitTest(result, position: position);
      child = childBefore(child);
    }
    return hit;
  }
}

typedef TapDetectorCallback = void Function (BuildContext context);

class WorldTapDetector extends LeafRenderObjectWidget {
  const WorldTapDetector({
    super.key,
    required this.node,
    required this.shape,
    this.onTap,
  });

  final WorldNode node;
  final BoxShape shape;
  final TapDetectorCallback? onTap;

  @override
  RenderWorldTapDetector createRenderObject(BuildContext context) {
    return RenderWorldTapDetector(
      node: node,
      shape: shape,
      onTap: onTap == null ? null : () => onTap!(context),
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderWorldTapDetector renderObject) {
    renderObject
      ..node = node
      ..shape = shape
      ..onTap = onTap == null ? null : () => onTap!(context);
    }
}

class RenderWorldTapDetector extends RenderWorldNode {
  RenderWorldTapDetector({
    required super.node,
    this.shape,
    this.onTap,
  });

  BoxShape? shape;
  VoidCallback? onTap;

  @override
  void computeLayout(WorldConstraints constraints, double actualDiameter) { }

  @override
  void computePaint(PaintingContext context, Offset offset, double actualDiameter) { }

  @override
  bool hitTestChildren(BoxHitTestResult result, { required Offset position }) {
    return false;
  }

  @override
  WorldTapTarget? computeTap(Offset offset) {
    if (onTap != null) {
      if (switch (shape!) {
        BoxShape.rectangle => isInsideSquare(offset),
        BoxShape.circle => isInsideCircle(offset),
      }) {
        return _TapDetectorTarget(onTap!);
      }
    }
    return null;
  }
}

class _TapDetectorTarget implements WorldTapTarget {
  _TapDetectorTarget(this.onTap);

  final VoidCallback onTap;

  @override
  void handleTapDown() {}

  @override
  void handleTapCancel() {}

  @override
  void handleTapUp() {
    onTap();
  }
}
