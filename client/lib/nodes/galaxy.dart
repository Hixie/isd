import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../layout.dart';
import '../prettifiers.dart';
import '../root.dart';
import '../widgets.dart';
import '../world.dart';

import 'system.dart';

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
    final Uint32List data = rawdata.buffer.asUint32List(rawdata.offsetInBytes, rawdata.lengthInBytes ~/ 4);
    assert(data[0] == 1, 'galaxy raw data first dword is ${data[0]}');
    final int categoryCount = data[1];
    final List<Float32List> categories = <Float32List>[];
    int indexSource = 2 + categoryCount;
    for (int category = 0; category < categoryCount; category += 1) {
      final Float32List target = Float32List(data[2 + category] * 2);
      int indexTarget = 0;
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
    final List<int> result = <int>[];
    for (int category = 0; category < stars.length; category += 1) {
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
    for (int category = 0; category < stars.length; category += 1) {
      final int index = _binarySearchY(stars[category], target.dy);
      int subindex = 1;
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

  void markChildrenDirty() {
    _children = null;
    notifyListeners();
  }

  void addSystem(SystemNode system) {
    if (systems.add(system)) {
      assert(system.parent == null);
      system.attach(this);
      markChildrenDirty();
    }
  }

  void removeSystem(SystemNode system) {
    if (systems.remove(system)) {
      assert(system.parent == this);
      system.detach();
      markChildrenDirty();
    }
  }

  void clearSystems() {
    if (systems.isNotEmpty) {
      for (SystemNode system in systems) {
        assert(system.parent == this);
        system.detach();
      }
      systems.clear();
      markChildrenDirty();
    }
  }

  @override
  Offset findLocationForChild(WorldNode child, List<VoidCallback> callbacks) {
    assert(child.parent == this);
    addTransientListeners(callbacks);
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

  double? _lastScale;

  @override
  Widget buildRenderer(BuildContext context, Widget? nil) {
    if (galaxy != null) {
      return WorldLayoutBuilder(
        builder: (BuildContext context, WorldConstraints constraints) {
          if (_lastScale != constraints.scale) {
            _children = null;
          }
          _lastScale = constraints.scale;
          return GalaxyWidget(
            node: this,
            galaxy: galaxy!,
            diameter: galaxy!.diameter,
            children: _children ??= _rebuildChildren(context, constraints.scale),
          );
        },
      );
    }
    return WorldNull(node: this);
  }

  List<Widget> _rebuildChildren(BuildContext context, double scale) {
    return systems.map((SystemNode childNode) {
      return ListenableBuilder(
        listenable: childNode,
        builder: (BuildContext context, Widget? child) {
          assert(child != null);
          final bool visible = childNode.diameter * scale >= WorldGeometry.minSystemRenderDiameter;
          return GalaxyChildData(
            position: findLocationForChild(childNode, <VoidCallback>[markChildrenDirty]),
            label: childNode.label,
            child: visible ? child! : WorldNull(node: childNode),
            onTap: () {
              ZoomProvider.centerOn(context, childNode);
            },
          );
        },
        child: childNode.build(context),
      );
    }).toList();
  }
}

class GalaxyWidget extends MultiChildRenderObjectWidget {
  const GalaxyWidget({
    super.key,
    required this.node,
    required this.galaxy,
    required this.diameter,
    this.onTap,
    super.children,
  });

  final WorldNode node;
  final Galaxy galaxy;
  final double diameter;
  final GalaxyTapHandler? onTap;

  @override
  RenderGalaxy createRenderObject(BuildContext context) {
    return RenderGalaxy(
      node: node,
      galaxy: galaxy,
      diameter: diameter,
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderGalaxy renderObject) {
    renderObject
      ..node = node
      ..galaxy = galaxy
      ..diameter = diameter;
  }
}

class GalaxyChildData extends StatefulWidget {
  const GalaxyChildData({
    super.key,
    required this.position,
    required this.label,
    required this.onTap,
    required this.child,
  });

  final Offset position;
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
    _controller = AnimationController(vsync: this, duration: hudAnimationDuration);
    _animation = _controller.drive(hudTween);
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
      _cooldown = Timer(Duration(milliseconds: (hudAnimationPauseLength + _controller.duration!.inMilliseconds * (1.0 - _controller.value)).round()), () {
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
    super.key, // ignore: unused_element_parameter
    required this.position,
    required this.label,
    required this.active,
    required this.tapTarget,
    required super.child,
  });

  final Offset position;
  final String label;
  final double active;
  final WorldTapTarget? tapTarget;

  @override
  void applyParentData(RenderObject renderObject) {
    final GalaxyParentData parentData = renderObject.parentData! as GalaxyParentData;
    if (parentData.position != position ||
        parentData.label != label ||
        parentData.active != active) {
      parentData.position = position;
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
  String label = '';
  double active = 0.0; // how much to highlight the child's reticule (0..1)

  WorldTapTarget? tapTarget;

  TextPainter? _label;
  Rect? _labelRect;
  Offset? _reticuleCenter;
  double? _reticuleRadius;

  Offset? _computedPosition; // in pixels
}

class StarType {
  const StarType(this.color, this.magnitude, [this.blur]);
  final Color color;
  final double magnitude;
  final double? blur;

  double strokeWidth(double zoom) {
    // TODO: shouldn't ever render bigger than the actual star, when there is one
    return 8e8 * magnitude / ((zoom + 1) * (zoom + 1) * max(1, zoom - 7.0));
  }
  double? blurWidth(double zoomFactor) => blur == null ? null : 8e8 * blur! / zoomFactor;
}

typedef GalaxyTapHandler = void Function(Offset offset, double zoomFactor);

class RenderGalaxy extends RenderWorldWithChildren<GalaxyParentData> {
  RenderGalaxy({
    required super.node,
    required Galaxy galaxy,
    required double diameter,
  }) : _galaxy = galaxy,
       _diameter = diameter;

  Galaxy? get galaxy => _galaxy;
  Galaxy? _galaxy;
  set galaxy (Galaxy? value) {
    if (value != _galaxy) {
      _galaxy = value;
      _preparedStarsRect = null;
      markNeedsPaint();
    }
  }

  // In meters.
  double get diameter => _diameter;
  double _diameter;
  set diameter (double value) {
    if (value != _diameter) {
      _diameter = value;
      markNeedsLayout();
    }
  }

  double get radius => diameter / 2.0;

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
  void visitChildren(RenderObjectVisitor visitor) {
    RenderWorld? child = firstChild;
    while (child != null) {
      visitor(child);
      final GalaxyParentData childParentData = child.parentData! as GalaxyParentData;
      child = childParentData.nextSibling;
    }
  }

  final TextPainter _legendLabel = TextPainter(textDirection: TextDirection.ltr);
  static final Paint _legendPaint = Paint()
    ..color = const Color(0xFFFFFFFF)
    ..blendMode = BlendMode.difference;
  static final TextStyle _legendStyle = TextStyle(fontSize: 12.0, foreground: _legendPaint);

  final TextStyle _hudStyle = const TextStyle(fontSize: 14.0, color: Color(0xFFFFFFFF));

  static const double minReticuleZoom = 8.0;
  static const double reticuleFadeZoom = 5.0;
  static const double lineFadeZoom = 7.5;
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

  double _legendLength = 0.0;

  @override
  void computeLayout(WorldConstraints constraints) {
    RenderWorld? child = firstChild;
    while (child != null) {
      final GalaxyParentData childParentData = child.parentData! as GalaxyParentData;
      child.layout(constraints);
      if (constraints.zoom < minReticuleZoom) {
        final TextPainter painter = childParentData._label!;
        painter.text = TextSpan(text: childParentData.label, style: _hudStyle);
        painter.layout();
      }
      child = childParentData.nextSibling;
    }
    _layoutLegend(constraints);
  }

  final LayerHandle<TransformLayer> _starsLayer = LayerHandle<TransformLayer>();

  Rect? _preparedStarsRect;
  double? _preparedStarsScale;
  final List<Float32List> _starPoints = <Float32List>[];
  final List<Vertices?> _starVertices = <Vertices?>[];
  final List<Color> _adjustedStarTypeColors = <Color>[];

  static bool isWithin(double a, double b, double max) {
    final double ratio = a / b;
    return (ratio < max) || (ratio > 1 / max);
  }

  @override
  double computePaint(PaintingContext context, Offset offset) {
    if (galaxy != null) {
      _drawGalaxyHalo(context, offset);
      final Rect wholeGalaxy = Rect.fromCircle(center: Offset.zero, radius: diameter / 2.0);
      final Rect viewport = Rect.fromCenter(center: -offset / constraints.scale, width: constraints.viewportSize.width / constraints.scale, height: constraints.viewportSize.height / constraints.scale);
      final Rect visibleGalaxy = wholeGalaxy.intersect(viewport);
      if (_preparedStarsRect == null ||
          _preparedStarsScale == null ||
          !isWithin(_preparedStarsScale!, constraints.scale, 0.0001) ||
          (!_preparedStarsRect!.contains(visibleGalaxy.topLeft)) ||
          (!_preparedStarsRect!.contains(visibleGalaxy.bottomRight))) {
        visibleGalaxy.inflate(1.0 * lightYearInM);
        _prepareStars(visibleGalaxy);
        _preparedStarsRect = visibleGalaxy;
        _preparedStarsScale = constraints.scale;
      }
      final Matrix4 transform = Matrix4.identity()
        ..translateByDouble(offset.dx, offset.dy, 0.0, 1.0)
        ..scaleByDouble(constraints.scale, constraints.scale, constraints.scale, 1.0);
      _starsLayer.layer = context.pushTransform(
        needsCompositing,
        Offset.zero,
        transform,
        _drawStars,
        oldLayer: _starsLayer.layer,
      );
    } else {
      _starsLayer.layer = null;
    }
    _drawChildren(context, offset);
    if (galaxy != null) {
      _drawLegend(context);
      _drawHud(context, offset);
    }
    return diameter * constraints.scale;
  }

  void _drawGalaxyHalo(PaintingContext context, Offset offset) {
    final Color galaxyGlowColor = const Color(0xFF66BBFF).withValues(alpha: (0x33/0xFF) * (1.0 / constraints.zoom).clamp(0.0, 1.0));
    if (galaxyGlowColor.a > 0) {
      context.canvas.drawOval(
        Rect.fromCircle(
          center: offset,
          radius: diameter * constraints.scale / 2.0,
        ),
        Paint()
          ..color = galaxyGlowColor
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 500.0),
      );
    }
  }

  void _prepareStars(Rect visibleRect) { // arguments are in meters
    assert(galaxy != null);
    final double dx = -radius;
    final double dy = -radius;
    // filter galaxy to visible stars
    _starPoints.clear();
    for (int categoryIndex = 0; categoryIndex < galaxy!.stars.length; categoryIndex += 1) {
      final StarType starType = _starTypes[categoryIndex];
      final Float32List allStars = galaxy!.stars[categoryIndex];
      final double maxStarDiameter = max(starType.strokeWidth(constraints.zoom), starType.blurWidth(constraints.zoomFactor) ?? 0.0);
      final double xMin = visibleRect.left + radius - maxStarDiameter;
      final double xMax = visibleRect.right + radius + maxStarDiameter;
      final double yMin = visibleRect.top + radius - maxStarDiameter;
      final double yMax = visibleRect.bottom + radius + maxStarDiameter;
      final Float32List visibleStars = Float32List(allStars.length);
      int count = 0;
      for (int starIndex = 0; starIndex < allStars.length; starIndex += 2) {
        if (allStars[starIndex] >= xMin && allStars[starIndex] < xMax &&
            allStars[starIndex + 1] >= yMin && allStars[starIndex + 1] < yMax) {
          visibleStars[count] = allStars[starIndex] + dx;
          visibleStars[count + 1] = allStars[starIndex + 1] + dy;
          count += 2;
        }
      }
      _starPoints.add(Float32List.sublistView(visibleStars, 0, count));
    }
    // prepare vertices for tiny stars
    _starVertices.clear();
    _adjustedStarTypeColors.clear();
    for (int categoryIndex = 0; categoryIndex < galaxy!.stars.length; categoryIndex += 1) {
      final StarType starType = _starTypes[categoryIndex];
      final double starDiameter = starType.strokeWidth(constraints.zoom);
      const double pixelTriangleRadius = 1.0;
      if (starType.blur == null && (starDiameter * constraints.scale < pixelTriangleRadius * 2.0)) {
        final double triangleRadius = pixelTriangleRadius / constraints.scale;
        assert((triangleRadius * 2) > starDiameter, '$triangleRadius vs $starDiameter');
        final Float32List points = _starPoints[categoryIndex];
        final int count = points.length ~/ 2;
        final Float32List vertices = Float32List(count * 12);
        for (int starIndex = 0; starIndex < count; starIndex += 1) {
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
        _adjustedStarTypeColors.add(starType.color.withValues(alpha: starType.color.a * min(starDiameter / (triangleRadius * 2.0), 1.0)));
        _starVertices.add(Vertices.raw(VertexMode.triangles, vertices));
      } else {
        _adjustedStarTypeColors.add(starType.color.withValues(alpha: starType.color.a));
        _starVertices.add(null);
      }
    }
  }

  // TODO: paint the category 0 and 1 stars in a parallax layer, spread across
  // the entire viewport, rather than pinned to the galaxy plane

  void _drawStars(PaintingContext context, Offset offset) {
    assert(offset == Offset.zero);
    for (int index = 0; index < _starPoints.length; index += 1) {
      if (_starPoints[index].isNotEmpty) {
        final StarType starType = _starTypes[index];
        final Paint paint = Paint()
          ..color = _adjustedStarTypeColors[index];
        if (_starVertices[index] != null) {
          context.canvas.drawVertices(_starVertices[index]!, BlendMode.src, paint);
        } else {
          paint
            ..strokeCap = StrokeCap.round
            ..strokeWidth = starType.strokeWidth(constraints.zoom);
          if (starType.blur != null) {
            paint.maskFilter = MaskFilter.blur(BlurStyle.normal, starType.blurWidth(constraints.zoomFactor)!);
          }
          context.canvas.drawRawPoints(PointMode.points, _starPoints[index], paint);
        }
      }
    }
  }

  void _drawChildren(PaintingContext context, Offset offset) {
    RenderWorld? child = firstChild;
    while (child != null) {
      final GalaxyParentData childParentData = child.parentData! as GalaxyParentData;
      childParentData._computedPosition = constraints.paintPositionFor(child.node, offset, <VoidCallback>[markNeedsPaint]);
      context.paintChild(child, childParentData._computedPosition!);
      child = childParentData.nextSibling;
    }
  }

  static (double, String) _selectLegend(double length, double scaleFactor) {
    final double m = length / scaleFactor;
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
          if (m > 0.9) {
            value = m;
            units = 'm';
          } else {
            final double cm = m / 10.0;
            if (cm > 0.9) {
              value = cm;
              units = 'cm';
            } else {
              final double mm = m * 1000.0;
              if (mm > 0.9) {
                value = mm;
                units = 'mm';
              } else {
                final double um = m * 1e6;
                if (um > 0.9) {
                  value = um;
                  units = 'μm';
                } else {
                  final double nm = m * 1e9;
                  if (nm > 0.9) {
                    value = nm;
                    units = 'nm';
                  } else {
                    final double A = m * 1e10;
                    if (A > 0.1) {
                      value = A;
                      units = 'Å';
                    } else {
                      final double fm = m * 1e15;
                      if (fm > 0.9) {
                        value = fm;
                        units = 'fm';
                      } else {
                        final double am = m * 1e18;
                        if (am > 0.9) {
                          value = am;
                          units = 'am';
                        } else {
                          final double zm = m * 1e21;
                          if (zm > 0.9) {
                            value = zm;
                            units = 'zm';
                          } else {
                            final double ym = m * 1e24;
                            if (ym > 0.9) {
                              value = ym;
                              units = 'ym';
                            } else {
                              final double rm = m * 1e27;
                              if (rm > 0.9) {
                                value = rm;
                                units = 'rm';
                              } else {
                                final double rm = m * 1e30;
                                if (rm > 0.1) {
                                  value = rm;
                                  units = 'qm';
                                } else {
                                  final double lp = m / 1.616255e-35;
                                  if (lp > 0.9) {
                                    value = lp;
                                    units = 'ℓₚ';
                                  } else {
                                    return (length, 'uncertain');
                                  }
                                }
                              }
                            }
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
    const int sigfig = 1;
    final double scale = pow(10, sigfig - (log(value) / ln10).ceil()).toDouble();
    final double roundValue = (value * scale).round() / scale;
    return (length * roundValue / value, '${roundValue.toStringAsFixed(1)} $units');
  }

  void _layoutLegend(WorldConstraints constraints) {
    final (double legendLength, String legendText) = _selectLegend(constraints.viewportSize.width * 0.2, constraints.scale);
    _legendLength = legendLength;
    final TextStyle style = _legendStyle;
    _legendLabel.text = TextSpan(text: legendText, style: style);
    _legendLabel.layout();
  }

  void _drawLegend(PaintingContext context) {
    final double d = _legendStyle.fontSize!;
    final double length = _legendLength;
    final Paint paint = _legendPaint;
    context.canvas.drawPoints(PointMode.polygon, <Offset>[
      Offset(d - constraints.viewportSize.width / 2.0, constraints.viewportSize.height / 2.0 - d * 2.0),
      Offset(d - constraints.viewportSize.width / 2.0, constraints.viewportSize.height / 2.0 - d),
      Offset(d + length - constraints.viewportSize.width / 2.0, constraints.viewportSize.height / 2.0 - d),
      Offset(d + length - constraints.viewportSize.width / 2.0, constraints.viewportSize.height / 2.0 - d * 2.0),
    ], paint);
    _legendLabel.paint(context.canvas, Offset(d + length - _legendLabel.width / 2.0 - constraints.viewportSize.width / 2.0, constraints.viewportSize.height / 2.0 - d * 3.0));
  }

  bool _hasOverlap(Iterable<Rect> rects, Rect candidate) {
    for (Rect rect in rects) {
      if (rect.overlaps(candidate)) {
        return true;
      }
    }
    return false;
  }

  void _drawHud(PaintingContext context, Offset offset) {
    if (constraints.zoom < minReticuleZoom) {
      final double reticuleOpacity = constraints.zoom < reticuleFadeZoom ? 1.0 : lerpDouble(1.0, 0.0, (constraints.zoom - reticuleFadeZoom) / (minReticuleZoom - reticuleFadeZoom))!;
      final double lineOpacity = constraints.zoom < lineFadeZoom ? 1.0 : lerpDouble(1.0, 0.0, (constraints.zoom - lineFadeZoom) / (minReticuleZoom - lineFadeZoom))!;

      final Paint hudReticulePaint = Paint()
        ..color = const Color(0xFFFFFFFF).withValues(alpha: reticuleOpacity)
        ..strokeWidth = hudReticuleStrokeWidth
        ..style = PaintingStyle.stroke;

      final Paint hudLinePaint = Paint()
        ..color = const Color(0xFFFFFF00).withValues(alpha: lineOpacity)
        ..strokeWidth = 0.0
        ..style = PaintingStyle.stroke;

      RenderWorld? child;
      final List<Rect> avoidanceRects = <Rect>[];

      // compute reticule centers and draw reticule circles on bottom layer
      child = firstChild;
      while (child != null) {
        final GalaxyParentData childParentData = child.parentData! as GalaxyParentData;
        final Offset center = childParentData._computedPosition!; // offset + childParentData.position * constraints.scale;
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
          context.canvas.drawPoints(PointMode.lines, <Offset>[
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
        int attempt = 0;
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
        final List<Offset> line = <Offset>[];
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
          painter.text = TextSpan(text: childParentData.label, style: _hudStyle.copyWith(color: _hudStyle.color!.withValues(alpha: lineOpacity)));
          painter.layout();
        }
        painter.paint(context.canvas, childParentData._labelRect!.topLeft);
        child = childParentData.nextSibling;
      }

      if (debugPaintSizeEnabled) {
        final Paint debugPaintSizePaint = Paint()
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
  void reassemble() {
    super.reassemble();
    _preparedStarsRect = null;
  }

  @override
  WorldTapTarget? routeTap(Offset offset) {
    if (constraints.zoom < minReticuleZoom) {
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
    RenderWorld? child = lastChild;
    while (child != null) {
      final GalaxyParentData childParentData = child.parentData! as GalaxyParentData;
      final WorldTapTarget? result = child.routeTap(offset);
      if (result != null)
        return result;
      child = childParentData.previousSibling;
    }
    return null;
  }

  @override
  void dispose() {
    _legendLabel.dispose();
    for (Vertices? vertices in _starVertices) {
      vertices?.dispose();
    }
    _starsLayer.layer = null;
    super.dispose();
  }
}
