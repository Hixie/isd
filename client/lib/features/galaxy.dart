import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../dynasty.dart';
import '../renderers.dart';
import '../widgets.dart';
import '../world.dart';
import '../zoom.dart';

// Parsed version of the stars data.
// Does not handle anything other than stars.
class Galaxy {
  Galaxy._(this.stars, this.diameter);

  final List<Float32List> stars; // Star positions in meters
  final double diameter; // in meters

  static const double _maxCoordinate = 4294967295; // Galaxy diameter in DWord Units

  static int encodeStarId(int category, int index) => (category << 20) | index; // max 1,048,575 stars per category
  static (int, int) decodeStarId(int id) => (id >> 20, id & 0x000fffff);
  
  factory Galaxy.from(Uint8List rawdata, double diameter) {
    final Uint32List data = rawdata.buffer.asUint32List();
    assert(data[0] == 1, 'galaxy raw data first dword is ${data[0]}');
    final int categoryCount = data[1];
    final categories = <Float32List>[];
    int indexSource = 2 + categoryCount;
    for (var category = 0; category < categoryCount; category += 1) {
      final target = Float32List(data[2 + category] * 2);
      var indexTarget = 0;
      while (indexTarget < target.length) {
        target[indexTarget] = data[indexSource] * diameter / _maxCoordinate;
        indexTarget += 1;
        indexSource += 1;
      }
      categories.add(target);
    }
    return Galaxy._(categories, diameter);
  }

  // returns first entry to be greater than or equal to target
  int _binarySearchY(Float32List list, double target, [ int min = 0, int? maxLimit ]) {
    int max = maxLimit ?? list.length ~/ 2;
    while (min < max) {
      final int mid = min + ((max - min) >> 1);
      final double element = list[mid * 2 + 1];
      final int comp = (element - target).sign.toInt();
      if (comp == 0) {
        return mid;
      }
      if (comp < 0) {
        min = mid + 1;
      } else {
        max = mid;
      }
    }
    return min;
  }

  List<int> hitTest(Offset target, double threshold) {
    // in meters
    final result = <int>[];
    for (var category = 0; category < stars.length; category += 1) {
      final int firstCandidate = _binarySearchY(stars[category], target.dy - threshold);
      final int lastCandidate = _binarySearchY(stars[category], target.dy + threshold, firstCandidate);
      for (int index = firstCandidate; index < lastCandidate; index += 1) {
        final double x = stars[category][index * 2];
        if (target.dx - threshold < x && x < target.dx + threshold) {
          result.add(encodeStarId(category, index));
        }
      }
    }
    return result;
  }

  int hitTestNearest(Offset target) {
    // in meters
    double currentDistance = double.infinity;
    int result = -1;
    bool test(int category, int index) {
      final double y = stars[category][index * 2 + 1];
      if ((target.dy - y).abs() > currentDistance) 
        return true;
      final double x = stars[category][index * 2];
      final double distance = (target - Offset(x, y)).distance;
      if (distance < currentDistance) {
        result = encodeStarId(category, index);
        currentDistance = distance;
      }
      return false;
    }
    for (var category = 0; category < stars.length; category += 1) {
      final int index = _binarySearchY(stars[category], target.dy);
      var subindex = 1;
      while ((index - subindex) >= 0) {
        if (test(category, index - subindex)) {
          break;
        }
        subindex += 1;
      }
      subindex = 0;
      while ((index + subindex) < stars[category].length ~/ 2) {
        if (test(category, index + subindex)) {
          break;
        }
        subindex += 1;
      }
    }
    return result;
  }
}

class GalaxyNode extends WorldNode {
  GalaxyNode();

  Galaxy? get galaxy => _galaxy;
  Galaxy? _galaxy;
  set galaxy(Galaxy? value) {
    if (_galaxy != value) {
      _galaxy = value;
      notifyListeners();
    }
  }
  
  final Set<SystemNode> systems = <SystemNode>{};

  List<Widget>? _children;
  
  void addSystem(SystemNode system) {
    if (systems.add(system)) {
      _children = null;
      notifyListeners();
    }
  }
  
  void removeSystem(SystemNode system) {
    if (systems.remove(system)) {
      _children = null;
      notifyListeners();
    }
  }

  void clearSystems() {
    if (systems.isNotEmpty) {
      systems.clear();
      _children = null;
      notifyListeners();
    }
  }

  final Map<int, Dynasty> _dynasties = <int, Dynasty>{};
  Dynasty getDynasty(int id) {
    return _dynasties.putIfAbsent(id, () => Dynasty(id));
  }

  Dynasty? get currentDynasty => _currentDynasty;
  Dynasty? _currentDynasty;
  void setCurrentDynastyId(int? id) {
    if (id == null) {
      _currentDynasty = null;
    } else {
      _currentDynasty = getDynasty(id);
    }
  }
  
  @override
  Offset findLocationForChild(WorldNode child) {
    if (galaxy != null) {
      return (child as SystemNode).offset;
    }
    return Offset.zero;
  }

  @override
  double get diameter {
    if (galaxy != null) {
      return galaxy!.diameter;
    }
    return 1.0;
  }

  WorldNode? _lastZoomedChildNode;
  ZoomSpecifier? _lastZoomedChildZoom;
  
  @override
  Widget buildRenderer(BuildContext context, PanZoomSpecifier zoom, WorldNode? zoomedChildNode, ZoomSpecifier? zoomedChildZoom, double transitionLevel) {
    if (zoomedChildNode != _lastZoomedChildNode ||
        zoomedChildZoom != _lastZoomedChildZoom) {
      _children = null;
    }
    _lastZoomedChildNode = zoomedChildNode;
    _lastZoomedChildZoom = zoomedChildZoom;
    if (galaxy != null) {
      return GalaxyWidget(
        galaxy: galaxy!,
        diameter: galaxy!.diameter,
        zoom: zoom,
        transitionLevel: transitionLevel,
        children: _children ??= _rebuildChildren(context, zoom, zoomedChildNode, zoomedChildZoom),
      );
    }
    return WorldPlaceholder(
      diameter: diameter,
      zoom: zoom,
      transitionLevel: transitionLevel,
      color: const Color(0xFF999999),
    );
  }

  List<Widget> _rebuildChildren(BuildContext context, PanZoomSpecifier zoom, WorldNode? zoomedChildNode, ZoomSpecifier? zoomedChildZoom) {
    return systems.map((SystemNode childNode) {
      return ListenableBuilder(
        listenable: childNode,
        builder: (BuildContext context, Widget? child) {
          return GalaxyChildData(
            position: findLocationForChild(childNode),
            diameter: childNode.diameter,
            label: childNode.label,
            child: child!,
            onTap: () {
              ZoomProvider.zoom(context, childNode);
            },
          );
        },
        child: childNode.build(
          context,
          childNode == zoomedChildNode ? zoomedChildZoom! : PanZoomSpecifier.centered(childNode.diameter, 0.0),
        ),
      );
    }).toList();
  }
}

class GalaxyWidget extends MultiChildRenderObjectWidget {
  const GalaxyWidget({
    super.key,
    required this.galaxy,
    required this.diameter,
    required this.zoom,
    required this.transitionLevel,
    this.onTap,
    super.children,
  });

  final Galaxy galaxy;
  final double diameter;
  final PanZoomSpecifier zoom;
  final double transitionLevel;
  final GalaxyTapHandler? onTap;
  
  @override
  RenderGalaxy createRenderObject(BuildContext context) {
    return RenderGalaxy(
      galaxy: galaxy,
      diameter: diameter,
      zoom: zoom,
      transitionLevel: transitionLevel,
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderGalaxy renderObject) {
    renderObject
      ..galaxy = galaxy
      ..diameter = diameter
      ..zoom = zoom
      ..transitionLevel = transitionLevel;
  }
}

class GalaxyChildData extends StatefulWidget {
  const GalaxyChildData({
    super.key,
    required this.position,
    required this.diameter,
    required this.label,
    required this.onTap,
    required this.child,
  });

  final Offset position;
  final double diameter;
  final String label;
  final VoidCallback onTap;
  final Widget child;

  @override
  State<GalaxyChildData> createState() => _GalaxyChildDataState();
}

class _GalaxyChildDataState extends State<GalaxyChildData> with SingleTickerProviderStateMixin implements WorldTapTarget {
  late final AnimationController _controller;
  late final Animation<double> _animation;
  Timer? _cooldown;
  
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 250));
    _animation = _controller.drive(CurveTween(curve: Curves.ease));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
  
  @override
  void handleTapDown() {
    _cooldown?.cancel();
    _cooldown = null;
    _controller.forward();
  }

  @override
  void handleTapCancel() {
    _controller.reverse();
  }

  @override
  void handleTapUp() {
    assert(_cooldown == null);
    if (_controller.status == AnimationStatus.forward) {
      _cooldown = Timer(Duration(milliseconds: (75.0 + 250.0 * 1.0 - _controller.value).round()), () {
        _controller.reverse();
      });
    } else {
      _controller.reverse();
    }
    widget.onTap();
  }
  
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: _animation,
      builder: (BuildContext context, double value, Widget? child) => _GalaxyChildData(
        position: widget.position,
        diameter: widget.diameter,
        label: widget.label,
        active: value,
        tapTarget: this,
        child: widget.child,
      ),
    );
  }
}

class _GalaxyChildData extends ParentDataWidget<GalaxyParentData> {
  const _GalaxyChildData({
    super.key, // ignore: unused_element
    required this.position,
    required this.diameter,
    required this.label,
    required this.active,
    required this.tapTarget,
    required super.child,
  });

  final Offset position;
  final double diameter;
  final String label;
  final double active;
  final WorldTapTarget? tapTarget;
  
  @override
  void applyParentData(RenderObject renderObject) {
    final GalaxyParentData parentData = renderObject.parentData! as GalaxyParentData;
    if (parentData.position != position ||
        parentData.diameter != diameter ||
        parentData.label != label ||
        parentData.active != active) {
      parentData.position = position;
      parentData.diameter = diameter;
      parentData.label = label;
      parentData.active = active;
      renderObject.parent!.markNeedsLayout();
    }
    parentData.tapTarget = tapTarget;
  }

  @override
  Type get debugTypicalAncestorWidgetClass => RenderGalaxy;
}

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

  double strokeWidth(PanZoomSpecifier zoom) => 8e8 * magnitude / ((zoom.zoom + 1) * (zoom.zoom + 1) * max(1, zoom.zoom - 7.0)); // the world is in a mess
  double? blurWidth(double zoomFactor) => blur == null ? null : 8e8 * blur! / zoomFactor;
}

typedef GalaxyTapHandler = void Function(Offset offset, double zoomFactor);

class RenderGalaxy extends RenderWorld with ContainerRenderObjectMixin<RenderWorld, GalaxyParentData> {
  RenderGalaxy({
    required Galaxy galaxy,
    required double diameter,
    required PanZoomSpecifier zoom,
    required double transitionLevel,
  }) : _galaxy = galaxy,
       _diameter = diameter,
       _zoom = zoom,
       _transitionLevel = transitionLevel;

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

  double get transitionLevel => _transitionLevel;
  double _transitionLevel;
  set transitionLevel (double value) {
    if (value != _transitionLevel) {
      _transitionLevel = value;
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
  final TextStyle _legendStyle = const TextStyle(fontSize: 12.0, color: Color(0xFFFFFFFF));
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

  static const double minReticuleZoom = 10000.0;
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
  Offset _scaledPanOffset = Offset.zero; // in meters
  double _transitionOpacity = 1.0; // 1 - transitionLevel

  final List<Float32List> _starPoints = [];
  final List<Vertices?> _starVertices = [];
  final List<Color> _adjustedStarTypeColors = [];

  @override
  void performLayout() {
    final Size renderSize = constraints.size; // pixels
    final double renderDiameter = renderSize.shortestSide;
    _zoomFactor = exp(zoom.zoom);
    assert(_zoomFactor.isFinite, 'exp(${zoom.zoom}) was infinite');
    _scaleFactor = (renderDiameter / diameter) * _zoomFactor;
    // TODO: clamp the pan to prevent showing the nothingness on the edges
    _panOffset = Offset(
      zoom.destinationFocalPointFraction.dx * renderSize.width,
      zoom.destinationFocalPointFraction.dy * renderSize.height
    ) - zoom.sourceFocalPoint * _scaleFactor;
    _scaledPanOffset = _panOffset / _scaleFactor;
    _transitionOpacity = 1.0 - transitionLevel;
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
            yMin > 0 || yMax < diameter ||
            _panOffset != Offset.zero) {
          final visibleStars = Float32List(allStars.length);
          var count = 0;
          for (var starIndex = 0; starIndex < allStars.length; starIndex += 2) {
            if (allStars[starIndex] >= xMin && allStars[starIndex] < xMax &&
                allStars[starIndex + 1] >= yMin && allStars[starIndex + 1] < yMax) {
              visibleStars[count] = allStars[starIndex] + _scaledPanOffset.dx;
              visibleStars[count + 1] = allStars[starIndex + 1] + _scaledPanOffset.dy;
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
          _adjustedStarTypeColors.add(starType.color.withOpacity(_transitionOpacity * starType.color.opacity * min(starDiameter / (triangleRadius * 2.0), 1.0)));
          _starVertices.add(Vertices.raw(VertexMode.triangles, vertices));
        } else {
          _adjustedStarTypeColors.add(starType.color.withOpacity(_transitionOpacity * starType.color.opacity));
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
        currentScale: constraints.currentScale * _scaleFactor,
      ));
      if (_zoomFactor < minReticuleZoom) {
        final TextPainter painter = childParentData._label!;
        painter.text = TextSpan(text: childParentData.label, style: _hudStyle);
        painter.layout();
      }
      child = childParentData.nextSibling;
    }
    if (_transitionOpacity > 0.0) {
      final (double legendLength, String legendText) = _selectLegend(renderDiameter * 0.2, diameter * 0.2 / _zoomFactor);
      _legendLength = legendLength;
      final TextStyle style = _transitionOpacity == 1.0 ? _legendStyle : _legendStyle.copyWith(color: _legendStyle.color!.withOpacity(_transitionOpacity));
      _legendLabel.text = TextSpan(text: legendText, style: style);
      _legendLabel.layout();
    }
  }

  TransformLayer? _transformLayer;
  
  @override
  void paint(PaintingContext context, Offset offset) {
    final transform = Matrix4.identity()
      ..scale(_scaleFactor);
    _transformLayer = context.pushTransform(
      needsCompositing,
      offset,
      transform,
      _paintChildren,
      oldLayer: _transformLayer,
    );
    if (galaxy != null && _transitionOpacity > 0.0) {
      drawLegend(context, offset);
      drawHud(context, offset);
    }
  }
  
  void _paintChildren(PaintingContext context, Offset offset) {
    final Color galaxyGlowColor = const Color(0xFF66BBFF).withOpacity((0x33/0xFF) * exp(-zoom.zoom).clamp(0.0, 1.0));
    if (galaxyGlowColor.alpha > 0) {
      context.canvas.drawOval(
        Rect.fromCircle(
          center: Offset(diameter / 2.0, diameter / 2.0) + _scaledPanOffset,
          radius: diameter / 2.0,
        ),
        Paint()
          ..color = galaxyGlowColor
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 500.0 / _scaleFactor),
      );
    }
    for (var index = 0; index < _starPoints.length; index += 1) {
      if (_starPoints[index].isNotEmpty) {
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
          }
          context.canvas.drawRawPoints(PointMode.points, _starPoints[index], paint);
        }
      }
    }
    RenderWorld? child = firstChild;
    while (child != null) {
      final GalaxyParentData childParentData = child.parentData! as GalaxyParentData;
      context.paintChild(child, offset + (childParentData.position + _scaledPanOffset));
      child = childParentData.nextSibling;
    }
  }

  void drawLegend(PaintingContext context, Offset offset) {
    final Size renderSize = constraints.size;
    final double d = _legendStyle.fontSize!;
    final double length = _legendLength;
    final Paint paint = transitionLevel == 1.0 ? _legendPaint : Paint.from(_legendPaint)..color = _legendPaint.color.withOpacity(_transitionOpacity);
    context.canvas.drawPoints(PointMode.polygon, <Offset>[
      offset + Offset(d, renderSize.height - d * 2.0),
      offset + Offset(d, renderSize.height - d),
      offset + Offset(d + length, renderSize.height - d),
      offset + Offset(d + length, renderSize.height - d * 2.0),
    ], paint);
    _legendLabel.paint(context.canvas, offset + Offset(d + length - _legendLabel.width / 2.0, renderSize.height - d * 3.0));
  }

  bool _hasOverlap(Iterable<Rect> rects, Rect candidate) {
    for (Rect rect in rects) {
      if (rect.overlaps(candidate)) {
        return true;
      }
    }
    return false;
  }
  
  void drawHud(PaintingContext context, Offset offset) {
    if (_zoomFactor < minReticuleZoom) {
      final double unzoom = 1.0 / _scaleFactor;
      final double reticuleOpacity = _zoomFactor < reticuleFadeZoom ? 1.0 : lerpDouble(1.0, 0.0, (_zoomFactor - reticuleFadeZoom) / (minReticuleZoom - reticuleFadeZoom))!;
      final double lineOpacity = _zoomFactor < lineFadeZoom ? 1.0 : lerpDouble(1.0, 0.0, (_zoomFactor - lineFadeZoom) / (minReticuleZoom - lineFadeZoom))!;

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
    if (transitionLevel < 1.0) {
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
    }
    return null;
  }

  @override
  Offset get panOffset => _panOffset; // TODO: defer to child if fully zoomed

  @override
  double get zoomFactor => _scaleFactor; // TODO: defer to child if fully zoomed

  @override
  void dispose() {
    _legendLabel.dispose();
    for (Vertices? vertices in _starVertices) {
      vertices?.dispose();
    }
    super.dispose();
  }
}
