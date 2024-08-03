import 'dart:math';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/rendering.dart';

import 'galaxy.dart';
import 'zoom.dart';

// CONSTRAINTS

class WorldConstraints extends Constraints {
  const WorldConstraints({
    required this.size,
    required this.full,
  });

  final Size size;
  final bool full;

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

abstract interface class WorldTapTarget {
  void handleTapDown();
  void handleTapCancel();
  void handleTapUp();
}

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


// RENDER GALAXY

class GalaxyParentData extends ParentData with ContainerParentDataMixin<RenderWorld> {
  Offset position = Offset.zero; // in meters
  double diameter = 0; // in meters
  String label = '';
  double active = 0.0; // how much to highlight the child's reticule (0..1)

  WorldTapTarget? tapTarget;
  
  TextPainter? _label;
  Rect? _labelRect;
  Offset? _reticuleCenter;
  double? _reticuleRadius;
}

class StarType {
  const StarType(this.color, this.magnitude, [this.blur]);
  final Color color;
  final double magnitude;
  final double? blur;

  double strokeWidth(PanZoomSpecifier zoom) => 8e8 * magnitude / (zoom.zoom * zoom.zoom * max(1, zoom.zoom - 8.0));
  double? blurWidth(double zoomFactor) => blur == null ? null : 8e8 * blur! / zoomFactor;
}

typedef GalaxyTapHandler = void Function(Offset offset, double zoomFactor);

class RenderGalaxy extends RenderWorld with ContainerRenderObjectMixin<RenderWorld, GalaxyParentData> {
  RenderGalaxy({
    required Galaxy galaxy,
    required double diameter,
    PanZoomSpecifier zoom = PanZoomSpecifier.none,
  }) : _galaxy = galaxy,
       _diameter = diameter,
       _zoom = zoom;

  Galaxy? get galaxy => _galaxy;
  Galaxy? _galaxy;
  set galaxy (Galaxy? value) {
    if (value != _galaxy) {
      _galaxy = value;
      markNeedsLayout();
    }
  }

  // In meters.
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

  @override
  void setupParentData(RenderObject child) {
    if (child.parentData is! GalaxyParentData) {
      child.parentData = GalaxyParentData();
    }
  }
  
  @override
  void adoptChild(RenderObject child) {
    super.adoptChild(child);
    final GalaxyParentData childParentData = child.parentData! as GalaxyParentData;
    assert(childParentData._label == null);
    childParentData._label = TextPainter(textDirection: TextDirection.ltr);
  }
  
  @override
  void dropChild(RenderObject child) {
    final GalaxyParentData childParentData = child.parentData! as GalaxyParentData;
    assert(childParentData._label != null);
    childParentData._label!.dispose();
    childParentData._label = null;
    super.dropChild(child);
  }

  @override
  void hitTestChildren(WorldHitTestResult result, { required Offset position }) {
    RenderWorld? child = firstChild;
    while (child != null) {
      final GalaxyParentData childParentData = child.parentData! as GalaxyParentData;
      if ((childParentData.position & child.constraints.size).contains(position) &&
          child.hitTest(result, position: position - childParentData.position)) {
        return;
      }
      child = childParentData.previousSibling;
    }
  }

  @override
  void visitChildren(RenderObjectVisitor visitor) {
    RenderWorld? child = firstChild;
    while (child != null) {
      visitor(child);
      final GalaxyParentData childParentData = child.parentData! as GalaxyParentData;
      child = childParentData.nextSibling;
    }
  }

  final TextPainter _legendLabel = TextPainter(textDirection: TextDirection.ltr);
  final TextStyle _legendStyle = const TextStyle(fontSize: 12.0);
  final Paint _legendPaint = Paint()
    ..color = const Color(0xFFFFFFFF);

  final TextStyle _hudStyle = const TextStyle(fontSize: 14.0, color: Color(0xFFFFFFFF));

  static const double lightYearInM = 9460730472580800.0;
  static const double auInM = 149597870700.0;

  static (double, String) _selectLegend(double length, double m) {
    assert(m > 0);
    double value;
    String units;
    final double ly = m / lightYearInM;
    if (ly > 0.9) {
      value = ly;
      units = 'ly';
    } else {
      final double au = m / auInM;
      if (au > 0.1) {
        value = au;
        units = 'AU';
      } else {
        final double km = m / 1000.0;
        if (km > 0.9) {
          value = km;
          units = 'km';
        } else {
          value = m;
          units = 'm';
        }
      }
    }
    const sigfig = 1;
    final double scale = pow(10, sigfig - (log(value) / ln10).ceil()).toDouble();
    final double roundValue = (value * scale).round() / scale;
    return (length * roundValue / value, '$roundValue $units');
  }
  
  static const List<StarType> _starTypes = <StarType>[
    StarType(Color(0x7FFFFFFF), 4.0e9, 2.0e9),
    StarType(Color(0xCFCCBBAA), 2.5e9),
    StarType(Color(0xDFFF0000), 0.5e9),
    StarType(Color(0xCFFF9900), 0.7e9),
    StarType(Color(0xBFFFFFFF), 0.5e9),
    StarType(Color(0xAFFFFFFF), 1.2e9),
    StarType(Color(0x2F0099FF), 1.0e9),
    StarType(Color(0x2F0000FF), 0.5e9),
    StarType(Color(0x4FFF9900), 0.5e9),
    StarType(Color(0x2FFFFFFF), 0.5e9),
    StarType(Color(0x5FFF2200), 20.0e9, 8.0e9),
  ];
  
  double _zoomFactor = 1.0; // effective zoom (zoom.zoom but maybe affected by local shenanigans)
  double _legendLength = 0.0;
  double _scaleFactor = 0.0; // meters to pixels (includes _zoomFactor)
  Offset _panOffset = Offset.zero; // in pixels

  final List<Float32List> _starPoints = [];
  final List<Vertices?> _starVertices = [];
  final List<Color> _adjustedStarTypeColors = [];

  @override
  void performLayout() {
    final Size renderSize = constraints.size; // pixels
    final double renderDiameter = renderSize.shortestSide;
    _zoomFactor = exp(zoom.zoom - 1.0);
    _scaleFactor = (renderDiameter / diameter) * _zoomFactor;
    _panOffset = Offset(
      zoom.destinationFocalPointFraction.dx * renderSize.width,
      zoom.destinationFocalPointFraction.dy * renderSize.height
    ) - zoom.sourceFocalPointFraction * diameter * _scaleFactor;
    if (galaxy != null) {
      // filter galaxy to visible stars
      _starPoints.clear();
      for (var categoryIndex = 0; categoryIndex < galaxy!.stars.length; categoryIndex += 1) {
        final StarType starType = _starTypes[categoryIndex];
        final Float32List allStars = galaxy!.stars[categoryIndex];
        final double maxStarDiameter = max(starType.strokeWidth(zoom), starType.blurWidth(_zoomFactor) ?? 0.0);
        final xMin = (0.0 - _panOffset.dx) / _scaleFactor - maxStarDiameter;
        final xMax = (renderSize.width - _panOffset.dx) / _scaleFactor + maxStarDiameter;
        final yMin = (0.0 - _panOffset.dy) / _scaleFactor - maxStarDiameter;
        final yMax = (renderSize.height - _panOffset.dy) / _scaleFactor + maxStarDiameter;
        if (xMin > 0 || xMax < diameter ||
            yMin > 0 || yMax < diameter) {
          final visibleStars = Float32List(allStars.length);
          var count = 0;
          for (var starIndex = 0; starIndex < allStars.length; starIndex += 2) {
            if (allStars[starIndex] >= xMin && allStars[starIndex] < xMax &&
                allStars[starIndex + 1] >= yMin && allStars[starIndex + 1] < yMax) {
              visibleStars[count] = allStars[starIndex];
              visibleStars[count + 1] = allStars[starIndex + 1];
              count += 2;
            }
          }
          _starPoints.add(Float32List.sublistView(visibleStars, 0, count));
        } else {
          _starPoints.add(allStars);
        }
      }
      // prepare vertices for tiny stars
      _starVertices.clear();
      _adjustedStarTypeColors.clear();
      for (var categoryIndex = 0; categoryIndex < galaxy!.stars.length; categoryIndex += 1) {
        final StarType starType = _starTypes[categoryIndex];
        final double starDiameter = starType.strokeWidth(zoom);
        const pixelTriangleRadius = 1.0;
        if (starType.blur == null && (starDiameter * _scaleFactor < pixelTriangleRadius * 2.0)) {
          final double triangleRadius = pixelTriangleRadius / _scaleFactor;
          assert((triangleRadius * 2) > starDiameter, '$triangleRadius vs $starDiameter');
          final Float32List points = _starPoints[categoryIndex];
          final int count = points.length ~/ 2;
          final vertices = Float32List(count * 12);
          for (var starIndex = 0; starIndex < count; starIndex += 1) {
            vertices[starIndex * 12 + 0] = points[starIndex * 2 + 0];
            vertices[starIndex * 12 + 1] = points[starIndex * 2 + 1] - triangleRadius;
            vertices[starIndex * 12 + 2] = points[starIndex * 2 + 0] - triangleRadius;
            vertices[starIndex * 12 + 3] = points[starIndex * 2 + 1];
            vertices[starIndex * 12 + 4] = points[starIndex * 2 + 0] + triangleRadius;
            vertices[starIndex * 12 + 5] = points[starIndex * 2 + 1];
            vertices[starIndex * 12 + 6] = points[starIndex * 2 + 0];
            vertices[starIndex * 12 + 7] = points[starIndex * 2 + 1] + triangleRadius;
            vertices[starIndex * 12 + 8] = points[starIndex * 2 + 0] - triangleRadius;
            vertices[starIndex * 12 + 9] = points[starIndex * 2 + 1];
            vertices[starIndex * 12 + 10] = points[starIndex * 2 + 0] + triangleRadius;
            vertices[starIndex * 12 + 11] = points[starIndex * 2 + 1];
          }
          _adjustedStarTypeColors.add(starType.color.withOpacity(starType.color.opacity * min(starDiameter / (triangleRadius * 2.0), 1.0)));
          _starVertices.add(Vertices.raw(VertexMode.triangles, vertices));
        } else {
          _adjustedStarTypeColors.add(starType.color);
          _starVertices.add(null);
        }
      }
    }
    RenderWorld? child = firstChild;
    while (child != null) {
      final GalaxyParentData childParentData = child.parentData! as GalaxyParentData;
      assert(childParentData.diameter > 0);
      child.layout(WorldConstraints(
        size: Size.square(childParentData.diameter), // in meters
        full: false,
      ));
      final TextPainter painter = childParentData._label!;
      painter.text = TextSpan(text: childParentData.label, style: _hudStyle);
      painter.layout();
      child = childParentData.nextSibling;
    }
    final (double legendLength, String legendText) = _selectLegend(renderDiameter * 0.2, diameter * 0.2 / _zoomFactor);
    _legendLength = legendLength;
    _legendLabel.text = TextSpan(text: legendText, style: _legendStyle);
    _legendLabel.layout();
  }

  TransformLayer? _transformLayer;
  
  @override
  void paint(PaintingContext context, Offset offset) {
    final transform = Matrix4.identity()
      ..translate(_panOffset.dx, _panOffset.dy)
      ..scale(_scaleFactor);
    _transformLayer = context.pushTransform(
      needsCompositing,
      offset,
      transform,
      _paintChildren,
      oldLayer: _transformLayer,
    );
    if (galaxy != null) {
      drawLegend(context, offset);
      drawHud(context, offset);
    }
  }
  
  void _paintChildren(PaintingContext context, Offset offset) {
    context.canvas.drawOval(
      Rect.fromCircle(
        center: Offset(diameter / 2.0, diameter / 2.0),
        radius: diameter / 2.0,
      ),
      Paint()
        ..color = const Color(0xFF66BBFF).withOpacity(0x33/0xFF * exp(-(zoom.zoom - 1.0)).clamp(0.0, 1.0))
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 500.0 / _scaleFactor),
    );
    for (var index = 0; index < _starPoints.length; index += 1) {
      final StarType starType = _starTypes[index];
      final paint = Paint()
        ..color = _adjustedStarTypeColors[index];
      if (_starVertices[index] != null) {
        context.canvas.drawVertices(_starVertices[index]!, BlendMode.src, paint);
      } else {
        paint
          ..strokeCap = StrokeCap.round
          ..strokeWidth = starType.strokeWidth(zoom);
        if (starType.blur != null) {
          paint.maskFilter = MaskFilter.blur(BlurStyle.normal, starType.blurWidth(_zoomFactor)!);
          print(paint.maskFilter);
        }
        context.canvas.drawRawPoints(PointMode.points, _starPoints[index], paint);
      }
    }
    RenderWorld? child = firstChild;
    while (child != null) {
      final GalaxyParentData childParentData = child.parentData! as GalaxyParentData;
      child.paint(context, offset + childParentData.position);
      child = childParentData.nextSibling;
    }
  }

  void drawLegend(PaintingContext context, Offset offset) {
    final Size renderSize = constraints.size;
    final double d = _legendStyle.fontSize!;
    final double length = _legendLength;
    context.canvas.drawPoints(PointMode.polygon, <Offset>[
      offset + Offset(d, renderSize.height - d * 2.0),
      offset + Offset(d, renderSize.height - d),
      offset + Offset(d + length, renderSize.height - d),
      offset + Offset(d + length, renderSize.height - d * 2.0),
    ], _legendPaint);
    _legendLabel.paint(context.canvas, offset + Offset(d + length - _legendLabel.width / 2.0, renderSize.height - d * 3.0));
  }

  static const double minZoom = 10000.0;
  static const double reticuleFadeZoom = 5000.0;
  static const double lineFadeZoom = 8000.0;
  static const double hudOuterRadius = 36.0;
  static const double hudInnerRadius = 30.0;
  static const double hudReticuleLineLength = 15.0;
  static const double hudLineExtension = 20.0;
  static const double hudReticuleStrokeWidth = 4.0;
  static const double hudAvoidanceRadius = hudOuterRadius + hudReticuleStrokeWidth / 2.0 + 8.0;
  static const int hudRadials = 16;
  static const int maxHudLineExtensions = 3;
  static const EdgeInsets hudTextMargin = EdgeInsets.symmetric(horizontal: 8.0);
  static const Offset hudLineMargin = Offset(2.0, 0.0);

  bool _hasOverlap(Iterable<Rect> rects, Rect candidate) {
    for (Rect rect in rects) {
      if (rect.overlaps(candidate)) {
        return true;
      }
    }
    return false;
  }
  
  void drawHud(PaintingContext context, Offset offset) {
    if (_zoomFactor < minZoom) {
      final double unzoom = 1.0 / _scaleFactor;
      final double reticuleOpacity = _zoomFactor < reticuleFadeZoom ? 1.0 : lerpDouble(1.0, 0.0, (_zoomFactor - reticuleFadeZoom) / (minZoom - reticuleFadeZoom))!;
      final double lineOpacity = _zoomFactor < lineFadeZoom ? 1.0 : lerpDouble(1.0, 0.0, (_zoomFactor - lineFadeZoom) / (minZoom - lineFadeZoom))!;

      final hudReticulePaint = Paint()
        ..color = const Color(0xFFFFFFFF).withOpacity(reticuleOpacity)
        ..strokeWidth = hudReticuleStrokeWidth
        ..style = PaintingStyle.stroke;

      final hudLinePaint = Paint()
        ..color = const Color(0xFFFFFF00).withOpacity(lineOpacity)
        ..strokeWidth = 0.0
        ..style = PaintingStyle.stroke;

      RenderWorld? child;
      final List<Rect> avoidanceRects = [];

      // compute reticule centers and draw reticule circles on bottom layer
      child = firstChild;
      while (child != null) {
        final GalaxyParentData childParentData = child.parentData! as GalaxyParentData;
        final Offset center = _panOffset + offset + childParentData.position / unzoom;
        childParentData._reticuleCenter = center;
        childParentData._reticuleRadius = hudAvoidanceRadius;
        context.canvas.drawCircle(center, hudOuterRadius, hudReticulePaint);
        context.canvas.drawCircle(center, hudInnerRadius, hudReticulePaint);
        if (childParentData.active > 0.0) {
          const double hudCenterRadius = (hudOuterRadius + hudInnerRadius) / 2.0;
          final double length = hudReticuleLineLength * childParentData.active;
          context.canvas.save();
          context.canvas.translate(center.dx, center.dy);
          context.canvas.rotate(childParentData.active * pi / 2);
          context.canvas.drawPoints(PointMode.lines, [
            Offset(0.0, hudCenterRadius - length), Offset(0.0, hudCenterRadius + length), 
            Offset(0.0, -hudCenterRadius + length), Offset(0.0, -hudCenterRadius - length), 
            Offset(hudCenterRadius - length, 0.0), Offset(hudCenterRadius + length, 0.0), 
            Offset(-hudCenterRadius + length, 0.0), Offset(-hudCenterRadius - length, 0.0), 
          ], hudReticulePaint);
          context.canvas.restore();
        }
        avoidanceRects.add(Rect.fromCircle(center: center, radius: hudAvoidanceRadius));
        child = childParentData.nextSibling;
      }

      // find positions for text labels
      child = firstChild;
      while (child != null) {
        final GalaxyParentData childParentData = child.parentData! as GalaxyParentData;
        final Offset center = childParentData._reticuleCenter!;
        final TextPainter label = childParentData._label!;
        final Size labelSize = label.size;
        Offset target;
        Rect candidateRect;
        var attempt = 0;
        do {
          final double r = hudOuterRadius + hudLineExtension * (attempt ~/ hudRadials);
          final double theta = -pi / 4.0 + (attempt % hudRadials) * pi / (hudRadials / 2.0);
          double dx = r * cos(theta);
          double dy = r * sin(theta);
          if (dy < 0) {
            dy -= labelSize.height;
          }
          if (dx < 0) {
            dx -= labelSize.width;
          }
          target = center + Offset(dx, dy);
          attempt += 1;
          candidateRect = hudTextMargin.inflateRect(target & labelSize);
        } while (_hasOverlap(avoidanceRects, candidateRect) && (attempt < hudRadials * maxHudLineExtensions));
        childParentData._labelRect = target & labelSize;
        avoidanceRects.add(candidateRect);
        child = childParentData.nextSibling;
      }

      // draw lines for reticule labels
      child = firstChild;
      while (child != null) {
        final GalaxyParentData childParentData = child.parentData! as GalaxyParentData;
        final Offset center = childParentData._reticuleCenter!;
        final Rect rect = childParentData._labelRect!;
        final List<Offset> line = [];
        if ((rect.bottom > center.dy) &&
            (rect.left < center.dx) &&
            (rect.right > center.dx)) {
          // can't get to a bottom corner. Use the top-left corner instead and draw a line along the left edge.
          line.add(rect.bottomRight);
          line.add(rect.bottomLeft - hudLineMargin);
          line.add(rect.topLeft - hudLineMargin);
        } else if ((rect.left >= center.dx) ||
                   (rect.bottom < center.dy)) {
          line.add(rect.bottomRight);
          line.add(rect.bottomLeft - hudLineMargin);
        } else {
          line.add(rect.bottomLeft);
          line.add(rect.bottomRight + hudLineMargin);
        }
        final Offset offset = line.last - center;
        final double theta = atan2(offset.dx, offset.dy);
        line.add(center + Offset(hudOuterRadius * sin(theta), hudOuterRadius * cos(theta)));
        context.canvas.drawPoints(PointMode.polygon, line, hudLinePaint);
        child = childParentData.nextSibling;
      }

      // draw labels
      child = firstChild;
      while (child != null) {
        final GalaxyParentData childParentData = child.parentData! as GalaxyParentData;
        final TextPainter painter = childParentData._label!;
        if (lineOpacity < 1.0) {
          painter.text = TextSpan(text: childParentData.label, style: _hudStyle.copyWith(color: _hudStyle.color!.withOpacity(lineOpacity)));
          painter.layout();
        }
        painter.paint(context.canvas, childParentData._labelRect!.topLeft);
        child = childParentData.nextSibling;
      }

      if (debugPaintSizeEnabled) {
        final debugPaintSizePaint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0
          ..color = const Color(0xFF00FFFF);
        for (Rect rect in avoidanceRects) {
          context.canvas.drawRect(rect.deflate(0.5), debugPaintSizePaint);
        }
      }
    }
  }

  @override
  void applyPaintTransform(RenderWorld child, Matrix4 transform) {
    transform.multiply(_transformLayer!.transform!);
  }
  
  @override
  WorldTapTarget? routeTap(Offset offset) {
    RenderWorld? child = firstChild;
    while (child != null) {
      final GalaxyParentData childParentData = child.parentData! as GalaxyParentData;
      if (childParentData.tapTarget != null) {
        if (childParentData._labelRect!.contains(offset) ||
            (childParentData._reticuleCenter! - offset).distance < childParentData._reticuleRadius!) {
          return childParentData.tapTarget!;
        }
      }
      child = childParentData.nextSibling;
    }
    // target location in meters is (offset - _panOffset) / (_scaleFactor)
    return null;
  }

  @override
  Offset get panOffset => _panOffset; // TODO: defer to child if fully zoomed

  @override
  double get zoomFactor => _zoomFactor; // TODO: defer to child if fully zoomed

  @override
  void dispose() {
    _legendLabel.dispose();
    for (Vertices? vertices in _starVertices) {
      vertices?.dispose();
    }
    super.dispose();
  }
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
    child?.layout(WorldConstraints(size: size, full: true));
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
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
    PanZoomSpecifier zoom = PanZoomSpecifier.none,
    Color color = const Color(0xFFFFFFFF),
  }) : _diameter = diameter,
       _zoom = zoom,
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

  Color get color => _color;
  Color _color;
  set color (Color value) {
    if (value != _color) {
      _color = value;
      markNeedsPaint();
    }
  }

  @override
  void performLayout() { }

  Paint get _paint => Paint()
    ..color = color
    ..strokeWidth = diameter / 128.0
    ..style = PaintingStyle.stroke;
  
  @override
  void paint(PaintingContext context, Offset offset) {
    context.canvas.drawCircle(offset, diameter, _paint);
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
