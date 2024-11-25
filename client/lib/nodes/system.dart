import 'dart:async';
import 'dart:math' show max, min;
import 'dart:ui';

import 'package:flutter/rendering.dart' hide Gradient;
import 'package:flutter/widgets.dart' hide Gradient;

import '../assets.dart';
import '../layout.dart';
import '../root.dart';
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

class SystemNode extends WorldNode {
  SystemNode({ super.parent, required this.id });

  final int id;

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
      builder: (BuildContext context, TickerProvider vsync) => SystemWidget(
        node: this,
        vsync: vsync,
        diameter: diameter,
        labels: labels,
        child: root.build(context),
        onZoomRequest: (WorldNode node, Offset offset, double diameter) {
          ZoomProvider.centerNear(context, node, offset, diameter);
        },
      ),
    );
  }
}

typedef ZoomCallback = void Function(WorldNode node, Offset offset, double diameter);

class SystemWidget extends SingleChildRenderObjectWidget {
  const SystemWidget({
    super.key,
    required this.node,
    required this.vsync,
    required this.diameter,
    required this.labels,
    required this.onZoomRequest,
    super.child,
  });

  final WorldNode node;
  final TickerProvider vsync;
  final double diameter;
  final Set<_HighlightDetails> labels;
  final ZoomCallback onZoomRequest;

  @override
  RenderSystem createRenderObject(BuildContext context) {
    return RenderSystem(
      node: node,
      vsync: vsync,
      diameter: diameter,
      labels: labels,
      onZoomRequest: onZoomRequest,
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderSystem renderObject) {
    renderObject
      ..node = node
      ..vsync = vsync
      ..diameter = diameter
      ..labels = labels
      ..onZoomRequest = onZoomRequest;
  }
}

class RenderSystem extends RenderWorldNode with RenderObjectWithChildMixin<RenderWorld> {
  RenderSystem({
    required super.node,
    required TickerProvider vsync,
    required double diameter,
    required Set<_HighlightDetails> labels,
    required this.onZoomRequest,
  }) : _vsync = vsync,
       _diameter = diameter,
       _labels = labels;

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

  final Map<AssetNode, _HudStatus> _hudStatus = <AssetNode, _HudStatus>{};

  @override
  void dispose() {
    for (_HudStatus status in _hudStatus.values) {
      status.dispose();
    }
    super.dispose();
  }

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

  @override
  WorldGeometry computePaint(PaintingContext context, Offset offset) {
    if (child != null) {
      final double visibleDiameter = diameter * constraints.scale;
      assert(visibleDiameter >= WorldGeometry.minSystemRenderDiameter);
      final double fade = ((visibleDiameter - WorldGeometry.minSystemRenderDiameter) / (WorldGeometry.fullyVisibleRenderDiameter - WorldGeometry.minSystemRenderDiameter)).clamp(0.0, 1.0);
      final double renderRadius = radius * constraints.scale;
      context.canvas.drawRect(Rect.fromCircle(center: offset, radius: renderRadius), _blackFadePaint(fade, offset, renderRadius));
      context.paintChild(child!, constraints.paintPositionFor(child!.node, offset, <VoidCallback>[markNeedsPaint]));
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
    return WorldGeometry(shape: Circle(diameter));
  }

  @override
  WorldTapTarget? routeTap(Offset offset) {
    if (_visibleHudElements.isNotEmpty) {
      Rect? target;
      final List<AssetNode> assets = <AssetNode>[];
      _HighlightDetails? biggest;
      for (_HighlightDetails label in _visibleHudElements) {
        final Offset center = label.offset * constraints.scale;
        const double marginSquared = -_reticuleOuterRadius * -_reticuleOuterRadius;
        if ((center - offset).distanceSquared < marginSquared) {
          assets.add(label.asset);
          final Rect hitArea = Rect.fromCenter(center: center, width: label.diameter, height: label.diameter);
          if (target == null) {
            print('center=$center diameter=${label.diameter}');
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
          target!; biggest!;
          onZoomRequest(biggest.asset, target.center / constraints.scale - biggest.offset, max(target.width, target.height));
        });
      }
    }
    if (child != null)
      return child!.routeTap(offset);
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
