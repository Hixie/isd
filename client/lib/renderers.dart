import 'dart:math';

import 'package:flutter/rendering.dart';

import 'zoom.dart' show PanZoomSpecifier;

// CONSTRAINTS

class WorldConstraints extends Constraints {
  const WorldConstraints({
    required this.size,
    required this.currentScale,
  });

  final Size size;
  final double currentScale;

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

  @override
  void performLayout();

  @override
  void paint(PaintingContext context, Offset offset) {
  }
  
  bool hitTest(WorldHitTestResult result, { required Offset position }) {
    hitTestChildren(result, position: position);
    result.add(WorldHitTestEntry(this, position: position));
    return true;
  }

  void hitTestChildren(WorldHitTestResult result, { required Offset position }) {
    // hit test actual children
  }

  @override
  Rect get paintBounds => Offset.zero & constraints.size;

  @override
  Rect get semanticBounds => paintBounds;

  @override
  void debugAssertDoesMeetConstraints() { }

  WorldTapTarget? routeTap(Offset offset);

  Offset get panOffset; // rendering surface coordinates
  double get zoomFactor; // effective zoom (zoom.zoom but maybe affected by local shenanigans)
}


// INFRASTRUCTURE RENDER OBJECTS

class RenderBoxToRenderWorldAdapter extends RenderBox with RenderObjectWithChildMixin<RenderWorld> {
  RenderBoxToRenderWorldAdapter({ RenderWorld? child }) {
    this.child = child;
  }

  @override
  double computeMinIntrinsicWidth(double height) {
    if (height.isFinite)
      return height;
    return 0.0;
  }

  @override
  double computeMaxIntrinsicWidth(double height) {
    if (height.isFinite)
      return height;
    return 0.0;
  }

  @override
  double computeMinIntrinsicHeight(double width) {
    if (width.isFinite)
      return width;
    return 0.0;
  }

  @override
  double computeMaxIntrinsicHeight(double width) {
    if (width.isFinite)
      return width;
    return 0.0;
  }

  @override
  void performLayout() {
    size = constraints.constrain(Size.zero);
    child?.layout(WorldConstraints(size: size, currentScale: 1.0));
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child != null) {
      context.paintChild(child!, offset);
    }
  }

  @override
  bool hitTest(BoxHitTestResult result, { required Offset position }) {
    if (child == null) {
      return false;
    }
    child!.hitTest(WorldHitTestResult.wrap(result), position: position);
    result.add(BoxHitTestEntry(this, position));
    return true;
  }

  WorldTapTarget? routeTap(Offset offset) {
    if (child != null) {
      return child!.routeTap(offset);
    }
    return null;
  }
  
  Offset get panOffset => child != null ? child!.panOffset : Offset.zero;
  double get zoomFactor => child != null ? child!.zoomFactor : 1.0;
}

class RenderWorldPlaceholder extends RenderWorld {
  RenderWorldPlaceholder({
    required double diameter,
    required PanZoomSpecifier zoom,
    required double transitionLevel,
    Color color = const Color(0xFFFFFFFF),
  }) : _diameter = diameter,
       _zoom = zoom,
       _transitionLevel = transitionLevel,
       _color = color;

  double get diameter => _diameter;
  double _diameter;
  set diameter (double value) {
    if (value != _diameter) {
      _diameter = value;
      markNeedsPaint();
    }
  }

  PanZoomSpecifier get zoom => _zoom;
  PanZoomSpecifier _zoom;
  set zoom (PanZoomSpecifier value) {
    if (value != _zoom) {
      _zoom = value;
      markNeedsLayout();
    }
  }

  double get transitionLevel => _transitionLevel;
  double _transitionLevel;
  set transitionLevel (double value) {
    if (value != _transitionLevel) {
      _transitionLevel = value;
      markNeedsLayout();
    }
  }

  Color get color => _color;
  Color _color;
  set color (Color value) {
    if (value != _color) {
      _color = value;
      markNeedsPaint();
    }
  }

  late Matrix4 _matrix;
  
  @override
  void performLayout() {
    _matrix = Matrix4.identity()
      ..scale(exp(zoom.zoom));
  }

  Paint get _paint => Paint()
    ..color = color
    ..strokeWidth = diameter / 128.0
    ..style = PaintingStyle.stroke;
  
  @override
  void paint(PaintingContext context, Offset offset) {
    context.canvas.drawCircle(offset, constraints.size.shortestSide / 2.0, _paint);
    context.canvas.save();
    context.canvas.transform(_matrix.storage);
    context.canvas.drawCircle(offset / (zoom.zoom + 1.0), diameter / 2.0, _paint);
    context.canvas.restore();
  }

  @override
  WorldTapTarget? routeTap(Offset offset) {
    return null;
  }
  
  @override
  Offset get panOffset => Offset.zero;

  @override
  double get zoomFactor => 1.0;
}
