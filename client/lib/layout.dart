import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

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
    return parentOffset + node.parent!.findLocationForChild(node, callbacks) * scale;
  }

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

  @override
  bool get sizedByParent => true;

  @override
  void performResize() { }

  @override
  void performLayout() {
    computeLayout(constraints);
  }

  void computeLayout(WorldConstraints constraints);

  Rect? _paintBounds;
  
  @override
  @nonVirtual
  void paint(PaintingContext context, Offset offset) {
    assert(offset.isFinite);
    _paintBounds = Rect.fromCircle(center: offset, radius: computePaint(context, offset) / 2.0);
  }

  // The offset parameter is the distance from the canvas origin to the asset origin, in pixels.
  // Canvas origin is the center of the viewport, whose size is constraints.viewportSize.
  // Returns the actual diameter in pixels.
  double computePaint(PaintingContext context, Offset offset);
  
  @override
  void applyPaintTransform(covariant RenderObject child, Matrix4 transform) {
    // This intentionally does nothing, because Flutter's applyPaintTransform logic
    // does not know how to handle our floating origin system.
    // See WorldToBox in widgets.dart.
  }
  
  static const double _minDiameter = 20.0;
  static const double _maxDiameterRatio = 0.1;

  static double get _minCartoonDiameter => log(10e6); // 10,000 km, a bit smaller than earth
  static double get _maxCartoonDiameter => log( 1e9); // 2 million km, a bit bigger than our sun

  // TODO: remove the duplication of diameter/maxDiameter in many of the
  // subclasses and rationalize how we do size-bumping (and how we don't --
  // consider a bumped planet and its not-bumped regions)
  double computePaintDiameter(double diameter, double parentDiameter) {
    final double cartoonScale = ((log(diameter) - _minCartoonDiameter) / (_maxCartoonDiameter - _minCartoonDiameter)).clamp(0.0, 1.0) * 2.5 + 1.0;
    assert(cartoonScale >= 1.0);
    assert(cartoonScale <= 3.5);
    return min(
      max(
        diameter * constraints.scale, // try to be your actual size, but
        _minDiameter * cartoonScale, // ...don't be smaller than something visible
      ),
      constraints.scale * max( // ...and...
        parentDiameter * _maxDiameterRatio, // ...definitely don't be bigger than one tenth your parent
        diameter, // ...unless you really are bigger than one tenth your parent
      ),
    );
  }

  @override
  Rect get paintBounds => _paintBounds!;

  @override
  Rect get semanticBounds => _paintBounds!; // TODO: actually implement semantics

  @override
  void debugAssertDoesMeetConstraints() { }

  bool hitTestChildren(BoxHitTestResult result, { required Offset position });

  WorldTapTarget? routeTap(Offset offset);
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
      hit = hit || child.hitTestChildren(result, position: position);
      child = childBefore(child);
    }
    return hit;
  }
}
