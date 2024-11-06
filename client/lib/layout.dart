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

@immutable
sealed class WorldShape {
  const WorldShape();

  Size get size;

  double get diameter => size.longestSide;

  bool contains(Offset center, Offset point);
}

class Square extends WorldShape {
  const Square(this.sideLength);

  final double sideLength;

  @override
  Size get size => Size.square(sideLength);

  @override
  bool contains(Offset center, Offset point) {
    return Rect.fromCenter(center: center, width: sideLength, height: sideLength).contains(point);
  }
}

class Circle extends WorldShape {
  const Circle(this.diameter);

  @override
  final double diameter;

  double get radius => diameter / 2.0;

  @override
  Size get size => Size.square(diameter);

  @override
  bool contains(Offset center, Offset point) {
    return (point - center).distance < radius;
  }
}

@immutable
class WorldGeometry {
  const WorldGeometry({
    required this.shape,
  });

  final WorldShape shape;

  static const double minSystemRenderDiameter = 4.0; // a system less than this size is not rendered at all, and fades in...
  static const double fullyVisibleRenderDiameter = 48.0; // ...up to the point where it's at least this size.

  bool contains(Offset center, Offset point) => shape.contains(center, point);
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

  WorldNode get node;
  
  @override
  WorldConstraints get constraints => super.constraints as WorldConstraints;

  @override
  bool get sizedByParent => true;

  @override
  void performResize() { }

  WorldGeometry get geometry => _geometry!;
  WorldGeometry? _geometry;

  @override
  void performLayout() {
    computeLayout(constraints);
  }

  void computeLayout(WorldConstraints constraints);

  @override
  @nonVirtual
  void paint(PaintingContext context, Offset offset) {
    assert(offset.isFinite);
    _geometry = computePaint(context, offset);
  }

  // The offset parameter is the distance from the canvas origin to the asset origin, in pixels.
  // Canvas origin is the center of the viewport, whose size is constraints.viewportSize.
  WorldGeometry computePaint(PaintingContext context, Offset offset);

  static const double _minDiameter = 20.0;
  static const double _maxDiameterRatio = 0.1;

  static double get _minCartoonDiameter => log(10e6); // 10,000 km, a bit smaller than earth
  static double get _maxCartoonDiameter => log( 1e9); // 2 million km, a bit bigger than our sun
  
  double computePaintDiameter(double diameter, double maxDiameter) {
    final double cartoonScale = ((log(diameter) - _minCartoonDiameter) / (_maxCartoonDiameter - _minCartoonDiameter)).clamp(0.0, 1.0) * 2.5 + 1.0;
    assert(cartoonScale >= 1.0);
    assert(cartoonScale <= 3.5);
    return min(
      max(
        _minDiameter * cartoonScale,
        diameter * constraints.scale,
      ),
      maxDiameter * _maxDiameterRatio * constraints.scale,
    );
  }
  
  @override
  Rect get paintBounds => Offset.zero & geometry.shape.size;

  @override
  Rect get semanticBounds => paintBounds;

  @override
  void debugAssertDoesMeetConstraints() { }

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
      markNeedsLayout();
    }
  }
}
