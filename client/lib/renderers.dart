import 'dart:math';
import 'dart:ui';

import 'package:flutter/rendering.dart';

import 'galaxy.dart';
import 'zoom.dart';

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

class WorldParentData extends ParentData {
  Offset position = Offset.zero;
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

abstract class RenderWorld extends RenderObject {
  @override
  WorldConstraints get constraints => super.constraints as WorldConstraints;

  @override
  void setupParentData(RenderObject child) {
    if (child.parentData is! WorldParentData) {
      child.parentData = WorldParentData();
    }
  }

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

  void hitTestChildren(WorldHitTestResult result, { required Offset position }) { }

  @override
  Rect get paintBounds => Offset.zero & constraints.size;

  @override
  Rect get semanticBounds => paintBounds;

  @override
  void debugAssertDoesMeetConstraints() { }

  Offset get panOffset; // rendering surface coordinates
  double get zoomFactor; // effective zoom (zoom.zoom but maybe affected by local shenanigans)
}

class WorldChildListParentData extends WorldParentData with ContainerParentDataMixin<RenderWorld> { }

abstract class RenderWorldWithChildren extends RenderWorld with ContainerRenderObjectMixin<RenderWorld, WorldChildListParentData> {
  RenderWorldWithChildren();

  @override
  void hitTestChildren(WorldHitTestResult result, { required Offset position }) {
    RenderWorld? child = firstChild;
    while (child != null) {
      final WorldChildListParentData childParentData = child.parentData! as WorldChildListParentData;
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
      final WorldChildListParentData childParentData = child.parentData! as WorldChildListParentData;
      child = childParentData.nextSibling;
    }
  }
}

class RenderGalaxy extends RenderWorldWithChildren {
  RenderGalaxy({
    required Galaxy? galaxy,
    required double diameter,
    PanZoomSpecifier zoom = PanZoomSpecifier.none,
  }) : _galaxy = galaxy,
       _diameter = diameter,
       _zoom = zoom;

  PanZoomSpecifier get zoom => _zoom;
  PanZoomSpecifier _zoom;
  set zoom (PanZoomSpecifier value) {
    if (value != _zoom) {
      _zoom = value;
      markNeedsLayout();
    }
  }

  Galaxy? get galaxy => _galaxy;
  Galaxy? _galaxy;
  set galaxy (Galaxy? value) {
    if (value != _galaxy) {
      _galaxy = value;
      markNeedsLayout();
    }
  }

  double get diameter => _diameter;
  double _diameter;
  set diameter (double value) {
    if (value != _diameter) {
      _diameter = value;
      markNeedsPaint();
    }
  }

  final TextPainter _legendLabel = TextPainter(textDirection: TextDirection.ltr);
  final TextStyle _legendStyle = const TextStyle(fontSize: 12.0);
  final Paint _legendPaint = Paint()
    ..color = const Color(0xFFFFFFFF);
  
  @override
  void dispose() {
    _legendLabel.dispose();
    super.dispose();
  }

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
    const int sigfig = 1;
    final double scale = pow(10, sigfig - (log(value) / ln10).ceil()).toDouble();
    final double roundValue = (value * scale).round() / scale;
    return (length * roundValue / value, '$roundValue $units');
  }
  
  double _zoomFactor = 1.0; // effective zoom (zoom.zoom but maybe affected by local shenanigans)
  double _legendLength = 0.0;
  double _scaleFactor = 1.0; // world coordinates to rendering surface coordinates, not counting zoom

  @override
  void performLayout() {
    _zoomFactor = exp(zoom.zoom - 1.0);
    RenderWorld? child = firstChild;
    while (child != null) {
      final WorldChildListParentData childParentData = child.parentData! as WorldChildListParentData;
      childParentData.position = Offset.zero; // XXX - don't yet have children
      child.layout(WorldConstraints(size: constraints.size, full: false)); // XXX - don't yet have children
      child = childParentData.nextSibling;
    }
    if (galaxy != null) {
      final Size renderSize = constraints.size;
      final double renderDiameter = renderSize.shortestSide;
      print(_zoomFactor);
      final (double legendLength, String legendText) = _selectLegend(renderDiameter * 0.2, diameter * 0.2 / _zoomFactor);
      _legendLength = legendLength;
      _legendLabel.text = TextSpan(text: legendText, style: _legendStyle);
      _legendLabel.layout();
    }
  }

  TransformLayer? _transformLayer;

  Offset _panOffset = Offset.zero; // rendering surface coordinates
  
  @override
  void paint(PaintingContext context, Offset offset) {
    final Size renderSize = constraints.size;
    final double renderDiameter = renderSize.shortestSide;
    final double galaxyDiameter = Galaxy.maxCoordinate.toDouble();
    _scaleFactor = renderDiameter / galaxyDiameter;
    _panOffset = Offset(
      zoom.destinationFocalPointFraction.dx * renderSize.width,
      zoom.destinationFocalPointFraction.dy * renderSize.height
    ) - zoom.sourceFocalPointFraction * galaxyDiameter * _scaleFactor * _zoomFactor;
    if (galaxy != null) {
      final Matrix4 transform = Matrix4.identity()
        ..translate(_panOffset.dx, _panOffset.dy)
        ..scale(_scaleFactor * _zoomFactor);
      _transformLayer = context.pushTransform(
        needsCompositing,
        offset,
        transform,
        _paintChildren,
        oldLayer: _transformLayer,
      );
      final double d = _legendStyle.fontSize!;
      final double length = _legendLength;
      context.canvas.drawPoints(PointMode.polygon, <Offset>[
        Offset(d, renderSize.height - d * 2.0),
        Offset(d, renderSize.height - d),
        Offset(d + length, renderSize.height - d),
        Offset(d + length, renderSize.height - d * 2.0),
      ], _legendPaint);
      _legendLabel.paint(context.canvas, Offset(d + length - _legendLabel.width / 2.0, renderSize.height - d * 3.0));
    }
  }

  static const List<StarType> _starTypes = <StarType>[
    StarType(Color(0x7FFFFFFF), 4.0, 2.0),
    StarType(Color(0xCFCCBBAA), 2.5),
    StarType(Color(0xDFFF0000), 0.5),
    StarType(Color(0xCFFF9900), 0.7),
    StarType(Color(0xBFFFFFFF), 0.5),
    StarType(Color(0xAFFFFFFF), 1.2),
    StarType(Color(0x2F0099FF), 1.0),
    StarType(Color(0x2F0000FF), 0.5),
    StarType(Color(0x4FFF9900), 0.5),
    StarType(Color(0x2FFFFFFF), 0.5),
    StarType(Color(0x5FFF2200), 20.0, 8.0),
  ];
  
  void _paintChildren(PaintingContext context, Offset offset) {
    assert(galaxy != null);
    context.canvas.drawOval(
      Rect.fromCircle(
        center: const Offset(Galaxy.maxCoordinate / 2.0, Galaxy.maxCoordinate / 2.0),
        radius: Galaxy.maxCoordinate / 2.0,
      ),
      Paint()
        ..color = const Color(0xFF66BBFF).withOpacity(0x33/0xFF * exp(-(zoom.zoom - 1.0)).clamp(0.0, 1.0))
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 500.0 / _scaleFactor),
    );
    for (int index = 0; index < galaxy!.stars.length; index += 1) {
      final StarType starType = _starTypes[index];
      final Paint paint = Paint()
        ..strokeCap = StrokeCap.round
        ..color = starType.color
        ..strokeWidth = starType.magnitude / (_scaleFactor * zoom.zoom * zoom.zoom);
      if (starType.blur != null) {
        paint.maskFilter = MaskFilter.blur(BlurStyle.normal, starType.blur! / (_scaleFactor * _zoomFactor));
      }
      context.canvas.drawRawPoints(PointMode.points, galaxy!.stars[index], paint);
    }
  }

  @override
  Offset get panOffset => _panOffset; // TODO: defer to child if fully zoomed

  @override
  double get zoomFactor => _zoomFactor; // TODO: defer to child if fully zoomed
}

class StarType {
  const StarType(this.color, this.magnitude, [this.blur]);
  final Color color;
  final double magnitude;
  final double? blur;
}


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

  Offset get panOffset => child != null ? child!.panOffset : Offset.zero;
  double get zoomFactor => child != null ? child!.zoomFactor : 1.0;
}
