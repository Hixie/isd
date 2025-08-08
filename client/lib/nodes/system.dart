import 'dart:async';
import 'dart:math' show min;
import 'dart:ui';

import 'package:flutter/rendering.dart' hide Gradient;
import 'package:flutter/widgets.dart' hide Gradient;

import '../assetclasses.dart';
import '../assets.dart';
import '../layout.dart';
import '../materials.dart';
import '../prettifiers.dart';
import '../root.dart';
import '../spacetime.dart';
import '../stringstream.dart';
import '../widgets.dart';
import '../world.dart';

class _HighlightDetails {
  const _HighlightDetails(this.asset, this.offset, this.diameter);

  final AssetNode asset;

  final Offset offset;

  final double diameter;

  @override
  String toString() => '$asset : $offset @ $diameter';
}

typedef SendCallback = Future<StreamReader> Function(List<Object> messageParts);

class SystemNode extends WorldNode {
  SystemNode({
    super.parent,
    required this.id,
    required this.sendCallback,
    required this.spaceTime,
  });

  final int id;
  final SendCallback sendCallback;
  final SpaceTime spaceTime;

  String get label => _label;
  String _label = '';

  void _updateLabel() {
    assert(_root != null);
    if (_root!.name != _label) {
      _label = _root!.name;
      notifyListeners();
    }
  }

  AssetNode get root => _root!;
  AssetNode? _root;
  set root(AssetNode value) {
    if (_root != value) {
      _root?.removeListener(_updateLabel);
      _root = value;
      _label = _root!.name;
      notifyListeners();
      _root!.addListener(_updateLabel);
    }
  }

  Offset get offset => _offset!;
  Offset? _offset;
  set offset(Offset value) {
    if (_offset != value) {
      _offset = value;
      notifyListeners();
    }
  }

  @override
  double get diameter => root.diameter;

  // Tracks all asset classes ever seen during this session in this system.
  final Map<int, AssetClass> _assetClasses = <int, AssetClass>{};

  void registerAssetClass(AssetClass assetClass) {
    // TODO: when we deduplicate asset classes in the protocol:
    // assert(!_assetClasses.containsKey(assetClass.id));
    _assetClasses[assetClass.id] = assetClass;
  }

  AssetClass assetClass(int id) => _assetClasses[id]!;

  // Tracks all materials ever seen during this session in this system.
  final Map<int, Material> _materials = <int, Material>{};

  void registerMaterial(Material material) {
    // TODO: when we deduplicate materials in the protocol:
    // assert(!_materials.containsKey(material.id));
    _materials[material.id] = material;
  }

  Material material(int id) => _materials[id]!;

  // called when any assets in the system change
  void markAsUpdated() {
    notifyListeners();
  }

  @override
  Offset findLocationForChild(WorldNode child, List<VoidCallback> callbacks) {
    return Offset.zero;
  }

  Offset locate(AssetNode asset) {
    Offset result = Offset.zero;
    WorldNode node = asset;
    while (node != this) {
      result += node.parent!.findLocationForChild(node, <VoidCallback>[notifyListeners]);
      node = node.parent!;
    }
    return result;
  }

  @override
  Widget buildRenderer(BuildContext context, Widget? nil) {
    final Set<_HighlightDetails> labels = <_HighlightDetails>{};
    root.walk((AssetNode asset) {
      if (asset.ownerDynasty != null) {
        labels.add(_HighlightDetails(asset, locate(asset), asset.diameter));
        return false;
      }
      return true;
    });
    return TickerProviderBuilder(
      builder: (BuildContext context, TickerProvider vsync) {
        void zoom(WorldNode node) {
          ZoomProvider.centerOn(context, node);
        }
        return SystemWidget(
          node: this,
          vsync: vsync,
          spaceTime: spaceTime,
          diameter: diameter,
          labels: labels,
          child: root.build(context),
          onZoomRequest: zoom,
        );
      },
    );
  }

  Future<StreamReader> play(List<Object> messageParts) {
    return sendCallback(<Object>['play', id, ...messageParts]);
  }

  static SystemNode of(WorldNode node) {
    while (node is! SystemNode) {
      assert(node.parent != null);
      node = node.parent!;
    }
    return node;
  }
}

typedef ZoomCallback = void Function(WorldNode node);

class SystemWidget extends SingleChildRenderObjectWidget {
  const SystemWidget({
    super.key,
    required this.node,
    required this.vsync,
    required this.diameter,
    required this.labels,
    required this.onZoomRequest,
    required this.spaceTime,
    super.child,
  });

  final WorldNode node;
  final TickerProvider vsync;
  final double diameter;
  final Set<_HighlightDetails> labels;
  final ZoomCallback onZoomRequest;
  final SpaceTime spaceTime;

  @override
  RenderSystem createRenderObject(BuildContext context) {
    return RenderSystem(
      node: node,
      vsync: vsync,
      diameter: diameter,
      labels: labels,
      onZoomRequest: onZoomRequest,
      spaceTime: spaceTime,
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderSystem renderObject) {
    renderObject
      ..node = node
      ..vsync = vsync
      ..diameter = diameter
      ..labels = labels
      ..onZoomRequest = onZoomRequest
      ..spaceTime = spaceTime;
  }
}

class RenderSystem extends RenderWorldNode with RenderObjectWithChildMixin<RenderWorld> {
  RenderSystem({
    required super.node,
    required TickerProvider vsync,
    required double diameter,
    required Set<_HighlightDetails> labels,
    required this.onZoomRequest,
    required SpaceTime spaceTime,
  }) : _vsync = vsync,
       _diameter = diameter,
       _labels = labels,
       _spaceTime = spaceTime;

  TickerProvider get vsync => _vsync;
  TickerProvider _vsync;
  set vsync(TickerProvider value) {
    if (value == _vsync) {
      return;
    }
    _vsync = value;
    for (_HudStatus status in _hudStatus.values) {
      status.resync(vsync);
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

  double get radius => diameter / 2.0;

  Set<_HighlightDetails> get labels => _labels;
  Set<_HighlightDetails> _labels;
  set labels (Set<_HighlightDetails> value) {
    if (value != _labels) {
      _labels = value;
      markNeedsPaint();
    }
  }

  ZoomCallback onZoomRequest;

  SpaceTime get spaceTime => _spaceTime;
  SpaceTime _spaceTime;
  set spaceTime (SpaceTime value) {
    if (value != _spaceTime) {
      _spaceTime = value;
      markNeedsPaint();
    }
  }

  final Map<AssetNode, _HudStatus> _hudStatus = <AssetNode, _HudStatus>{};

  @override
  void dispose() {
    for (_HudStatus status in _hudStatus.values) {
      status.dispose();
    }
    _clockLabel.dispose();
    super.dispose();
  }

  final TextPainter _clockLabel = TextPainter(textDirection: TextDirection.ltr, textAlign: TextAlign.right);
  static final Paint _clockPaint = Paint()
    ..color = const Color(0xFFFFFFFF)
    ..blendMode = BlendMode.difference;
  static final TextStyle _clockStyle = TextStyle(fontSize: 12.0, foreground: _clockPaint);

  @override
  void computeLayout(WorldConstraints constraints) {
    if (child != null)
      child!.layout(constraints);
  }

  Paint _blackFadePaint(double fade, Offset offset, double radius) {
    final Color black = const Color(0xFF000000).withValues(alpha: fade);
    return Paint()
      ..shader = Gradient.radial(
        offset,
        radius,
        <Color>[ black, black, const Color(0x00000000) ],
        <double>[ 0.0, 0.8, 1.0 ],
        TileMode.decal,
      );
  }

  Paint _greenHudPaint(double fade) => Paint()
    ..color = const Color(0xFF00FF66).withValues(alpha: fade)
    ..strokeWidth = 2.0
    ..style = PaintingStyle.stroke;

  static const double _reticuleInnerPadding = 5.0;
  static const double _reticuleInnerRadius = 20.0;
  static const double _reticuleInnerChamfer = 10.0;
  static const double _reticuleOuterPadding = 5.0;
  static const double _reticuleOuterRadius = _reticuleInnerRadius + _reticuleOuterPadding;
  static const double _reticuleOuterChamfer = _reticuleInnerChamfer * (1 + _reticuleOuterPadding / _reticuleInnerRadius);
  static const double _fadeFactorStart = 0.2;
  static const double _fadeFactorEnd = 0.5;
  static const double _minVisibleForInteraction = 0.1;

  Path _reticulePath(double t) {
    final double crossExtension = _reticuleInnerPadding * (1 + t);
    final double outerExtension = _reticuleOuterRadius * t;
    return Path()
      // inner top left
      ..moveTo(-_reticuleInnerRadius + crossExtension, 0.0)
      ..lineTo(-_reticuleInnerRadius, 0.0)
      ..lineTo(-_reticuleInnerRadius, -_reticuleInnerChamfer)
      ..lineTo(-_reticuleInnerChamfer, -_reticuleInnerRadius)
      ..lineTo(0.0, -_reticuleInnerRadius)
      ..lineTo(0.0, -_reticuleInnerRadius + crossExtension)
      // inner bottom left
      ..moveTo(_reticuleInnerRadius - crossExtension, 0.0)
      ..lineTo(_reticuleInnerRadius, 0.0)
      ..lineTo(_reticuleInnerRadius, _reticuleInnerChamfer)
      ..lineTo(_reticuleInnerChamfer, _reticuleInnerRadius)
      ..lineTo(0.0, _reticuleInnerRadius)
      ..lineTo(0.0, _reticuleInnerRadius - crossExtension)
      // outer top left
      ..moveTo(-_reticuleOuterRadius, outerExtension)
      ..lineTo(-_reticuleOuterRadius, -_reticuleOuterChamfer)
      ..lineTo(-_reticuleOuterChamfer, -_reticuleOuterRadius)
      ..lineTo(outerExtension, -_reticuleOuterRadius)
      // outer bottom left
      ..moveTo(_reticuleOuterRadius, -outerExtension)
      ..lineTo(_reticuleOuterRadius, _reticuleOuterChamfer)
      ..lineTo(_reticuleOuterChamfer, _reticuleOuterRadius)
      ..lineTo(-outerExtension, _reticuleOuterRadius);
  }

  final List<_HighlightDetails> _visibleHudElements = <_HighlightDetails>[];

  Offset? _childPosition;

  @override
  double computePaint(PaintingContext context, Offset offset) {
    final double visibleDiameter = diameter * constraints.scale;
    if (child != null) {
      assert(visibleDiameter >= WorldGeometry.minSystemRenderDiameter);
      final double fade = ((visibleDiameter - WorldGeometry.minSystemRenderDiameter) / (WorldGeometry.fullyVisibleRenderDiameter - WorldGeometry.minSystemRenderDiameter)).clamp(0.0, 1.0);
      final double renderRadius = radius * constraints.scale;
      context.canvas.drawRect(Rect.fromCircle(center: offset, radius: renderRadius), _blackFadePaint(fade, offset, renderRadius));
      _childPosition = constraints.paintPositionFor(child!.node, offset, <VoidCallback>[markNeedsPaint]);
      context.paintChild(child!, _childPosition!);
    }
    _visibleHudElements.clear();
    if (_labels.isNotEmpty) {
      final double side = constraints.viewportSize.shortestSide;
      final double outerFade = ((diameter * constraints.scale / side) - 0.5).clamp(0.0, 1.0);
      if (outerFade > 0.0) {
        for (_HighlightDetails label in _labels) {
          assert(_fadeFactorStart < _fadeFactorEnd);
          const double diameterWhenFullyVisible = (_reticuleOuterRadius * 2.0) * _fadeFactorStart;
          const double diameterWhenInvisible = (_reticuleOuterRadius * 2.0) * _fadeFactorEnd;
          final double innerFade = ((label.diameter * constraints.scale - diameterWhenInvisible) / (diameterWhenFullyVisible - diameterWhenInvisible)).clamp(0.0, 1.0);
          if (innerFade > 0.0) {
            final double fade = min(outerFade, innerFade);
            final Paint hudPaint = _greenHudPaint(fade);
            context.canvas.drawPath(_reticulePath(_hudStatus[label.asset]?.value ?? 0.0).shift(offset + label.offset * constraints.scale), hudPaint);
            if (fade > _minVisibleForInteraction)
              _visibleHudElements.add(label);
          }
        }
      }
    }
    final Rect viewportRect = Rect.fromCenter(center: Offset.zero, width: constraints.viewportSize.width, height: constraints.viewportSize.height);
    final Rect systemRect = Rect.fromCircle(center: offset, radius: visibleDiameter / 2.0);
    if (systemRect.contains(viewportRect.topLeft) && systemRect.contains(viewportRect.bottomRight))
      _paintClock(context);
    return visibleDiameter;
  }

  void _paintClock(PaintingContext context) {
    _clockLabel.text = TextSpan(text: prettyTime(spaceTime.computeTime(<VoidCallback>[markNeedsPaint]).round(), precise: false), style: _clockStyle);
    _clockLabel.layout();
    final double d = _clockStyle.fontSize!;
    _clockLabel.paint(context.canvas, Offset(constraints.viewportSize.width / 2.0 - _clockLabel.width - d, constraints.viewportSize.height / 2.0 - d - _clockLabel.height));
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, { required Offset position }) {
    return child?.hitTestChildren(result, position: position) ?? false;
  }

  @override
  WorldTapTarget? routeTap(Offset offset) {
    final Offset offsetInSystem = offset - _childPosition!; // pixels relative to system center
    if (!isInsideCircle(offset))
      return null;
    if (_visibleHudElements.isNotEmpty) {
      Rect? target;
      final List<AssetNode> assets = <AssetNode>[];
      _HighlightDetails? biggest;
      for (_HighlightDetails label in _visibleHudElements) {
        final Offset labelCenter = label.offset * constraints.scale; // pixels relative to system center
        const double marginSquared = -_reticuleOuterRadius * -_reticuleOuterRadius;
        if ((labelCenter - offsetInSystem).distanceSquared < marginSquared) {
          assets.add(label.asset);
          final Rect hitArea = Rect.fromCenter(center: labelCenter, width: label.diameter, height: label.diameter);
          if (target == null) {
            target = hitArea;
            biggest = label;
          } else {
            target = target.expandToInclude(hitArea);
            if (label.diameter > biggest!.diameter)
              biggest = label;
          }
        }
      }
      if (assets.isNotEmpty) {
        return _SystemTapHandler(this, assets, () {
          onZoomRequest(biggest!.asset);
        });
      }
    }
    if (child != null) {
      return child!.routeTap(offset);
    }
    return null;
  }
}

class _HudStatus {
  factory _HudStatus(AssetNode asset, RenderSystem system) {
    final AnimationController controller = AnimationController(vsync: system.vsync, duration: hudAnimationDuration);
    return _HudStatus._(
      asset,
      system,
      controller,
      controller.drive(hudTween),
    );
  }

  _HudStatus._(this.asset, this.system, this._controller, this._active) {
    _controller.addListener(system.markNeedsPaint);
    _controller.addStatusListener(_handleStatus);
  }

  final AssetNode asset;
  final RenderSystem system;
  final AnimationController _controller;
  final Animation<double> _active;
  Timer? _cooldown;

  double get value => _active.value;

  void handleTapDown() {
    _cooldown?.cancel();
    _cooldown = null;
    _controller.forward();
  }

  void handleTapCancel() {
    _controller.reverse();
  }

  void handleTapUp() {
    assert(_cooldown == null);
    if (_controller.status == AnimationStatus.forward) {
      _cooldown = Timer(Duration(milliseconds: (hudAnimationPauseLength + _controller.duration!.inMilliseconds * (1.0 - _controller.value)).round()), () {
        _cooldown = null;
        _controller.reverse();
      });
    } else {
      _controller.reverse();
    }
  }

  void _handleStatus(AnimationStatus status) {
    if (status == AnimationStatus.dismissed) {
      dispose();
      system._hudStatus.remove(asset);
    }
  }

  void resync(TickerProvider vsync) {
    _controller.resync(vsync);
  }

  void dispose() {
    _cooldown?.cancel();
    _controller.dispose();
  }
}

class _SystemTapHandler implements WorldTapTarget {
  _SystemTapHandler(this.system, this.assets, this.onTap) {
    for (AssetNode asset in assets) {
      system._hudStatus.putIfAbsent(asset, () => _HudStatus(asset, system));
    }
  }

  final RenderSystem system;
  final List<AssetNode> assets;
  final VoidCallback onTap;

  @override
  void handleTapDown() {
    for (AssetNode asset in assets)
      system._hudStatus[asset]!.handleTapDown();
  }

  @override
  void handleTapCancel() {
    for (AssetNode asset in assets)
      system._hudStatus[asset]!.handleTapCancel();
  }

  @override
  void handleTapUp() {
    for (AssetNode asset in assets)
      system._hudStatus[asset]!.handleTapUp();
    onTap();
  }
}
