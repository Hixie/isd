import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

// CONSTRAINTS

class WorldConstraints extends Constraints {
  const WorldConstraints({
    required this.viewport,
    required this.zoom,
    required this.scale,
    required this.pan,
    required this.scaledPosition,
    required this.scaledPan,
    required this.scaledViewport,
  });

  final Rect viewport; // visible area relative to canvas origin, in pixels
  final double zoom; // logarithmic scale (0..)
  final double scale; // pixels per meter with zoom applied
  final Offset pan; // center of root node relative to canvas origin, in pixels
  final Offset scaledPosition; // child origin relative to center of root node, in meters
  final Offset scaledPan; // center of root node relative to canvas origin, in meters
  final Rect scaledViewport; // visible area relative to center of root node, in meters

  double get zoomFactor => exp(zoom);

  // childOffset is in meters
  WorldConstraints forChild(Offset childOffset) {
    return WorldConstraints(
      viewport: viewport,
      zoom: zoom, // the world is in a mess!
      scale: scale,
      pan: pan,
      scaledPosition: scaledPosition + childOffset,
      scaledPan: scaledPan,
      scaledViewport: scaledViewport,
    );
  }

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

  @override
  String toString() => 'WorldConstraints(x$zoom, scale=${scale}px/m, position=${scaledPosition}m, pan=${scaledPan}m viewport=${viewport}px or ${scaledViewport}m)';
}

@immutable
sealed class WorldShape {
  const WorldShape(this.center);

  final Offset center;

  Size get size;

  double get diameter => size.longestSide;

  bool contains(Offset point);
}

class Square extends WorldShape {
  const Square(super.center, this.sideLength);

  final double sideLength;

  @override
  Size get size => Size.square(sideLength);

  @override
  bool contains(Offset point) {
    return Rect.fromCenter(center: center, width: sideLength, height: sideLength).contains(point);
  }
}

class Circle extends WorldShape {
  const Circle({required Offset center, required this.diameter}) : super(center);

  @override
  final double diameter;

  double get radius => diameter / 2.0;

  @override
  Size get size => Size.square(diameter);

  @override
  bool contains(Offset point) {
    return (point - center).distance < radius;
  }
}

@immutable
class WorldGeometry {
  const WorldGeometry({
    required this.shape,
  });

  final WorldShape shape;

  static const double minSystemRenderDiameter = 24.0; // a system less than this size is not rendered at all, and fades in...
  static const double fullyVisibleRenderDiameter = 96.0; // ...up to the point where it's at least this size.

  bool contains(Offset point) => shape.contains(point);
}


// HIT TEST

abstract interface class WorldTapTarget {
  void handleTapDown();
  void handleTapCancel();
  void handleTapUp();
}

class WorldHitTestResult extends HitTestResult {
  WorldHitTestResult();

  WorldHitTestResult.wrap(super.result) : super.wrap();
}

class WorldHitTestEntry extends HitTestEntry {
  WorldHitTestEntry(RenderWorld super.target, { required this.position });

  @override
  RenderWorld get target => super.target as RenderWorld;

  final Offset position;
}


// ABSTRACT RENDER OBJECTS

abstract class RenderWorld extends RenderObject {
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
    _geometry = computeLayout(constraints);
  }

  WorldGeometry computeLayout(WorldConstraints constraints);

  @override
  void paint(PaintingContext context, Offset offset) { }

  bool hitTest(WorldHitTestResult result, { required Offset position }) {
    hitTestChildren(result, position: position);
    result.add(WorldHitTestEntry(this, position: position));
    return true;
  }

  void hitTestChildren(WorldHitTestResult result, { required Offset position }) {
    // hit test actual children
  }

  @override
  Rect get paintBounds => Offset.zero & geometry.shape.size;

  @override
  Rect get semanticBounds => paintBounds;

  @override
  void debugAssertDoesMeetConstraints() { }

  WorldTapTarget? routeTap(Offset offset);
}
