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
    required this.scaledPan,
    required this.scaledViewport,
  });

  final Rect viewport; // visible area relative to canvas origin, in pixels
  final double zoom; // logarithmic scale (0..)
  final double scale; // pixels per meter with zoom applied
  final Offset pan; // center of root node relative to canvas origin, in pixels
  final Offset scaledPan; // center of root node relative to canvas origin, in meters
  final Rect scaledViewport; // visible area relative to center of root node, in meters

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

  @override
  String toString() => 'WorldConstraints(x$zoom, scale=${scale}px/m, pan=${scaledPan}m viewport=${viewport}px or ${scaledViewport}m)';
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

  static const double minSystemRenderDiameter = 24.0; // a system less than this size is not rendered at all, and fades in...
  static const double fullyVisibleRenderDiameter = 96.0; // ...up to the point where it's at least this size.

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

  // offset is the distance from the canvas origin to the asset origin, in pixels
  WorldGeometry computePaint(PaintingContext context, Offset offset);

  static const double _minDiameter = 20.0;
  static const double _maxDiameterRatio = 0.1;

  static double get _minCartoonDiameter => log(10e6); // 10,000 km, a bit smaller than earth
  static double get _maxCartoonDiameter => log( 1e9); // 2 million km, a bit bigger than our sun
  
  double computePaintDiameter(double diameter, double maxDiameter) {
    double cartoonScale = ((log(diameter) - _minCartoonDiameter) / (_maxCartoonDiameter - _minCartoonDiameter)).clamp(0.0, 1.0) * 2.5 + 1.0;
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
