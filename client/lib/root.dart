import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'dynasty.dart';
import 'hud.dart';
import 'layout.dart';
import 'world.dart';

class ZoomCurve extends Curve {
  const ZoomCurve();

  static final double a = sqrt(2);
  static final double b = (1 - a * a ) / (2 * a);
  static final double c = -(b * b);

  @override
  double transformInternal(double t) {
    final double q = a * t + b;
    return q * q + c;
  }
}

class PanCurve extends Curve {
  const PanCurve();

  static const double b = -1;
  static const double a = 1 / (1 + 2 * b);
  static const double c = -a * b * b;

  @override
  double transformInternal(double t) {
    final double q = t + b;
    return a * q * q + c;
  }
}

class WorldRoot extends StatefulWidget {
  const WorldRoot({
    super.key,
    required this.rootNode,
    required this.recommendedFocus,
    required this.dynastyManager,
    this.hudKey,
  });

  final WorldNode rootNode;
  final ValueListenable<WorldNode?> recommendedFocus;
  final DynastyManager dynastyManager;
  final Key? hudKey;

  @override
  _WorldRootState createState() => _WorldRootState();
}

class _WorldRootState extends State<WorldRoot> with SingleTickerProviderStateMixin implements Listenable {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3000),
  );

  static const double _initialZoom = 4.0;
  static const Offset _initialPan = Offset(-3582946788187048960.0, -179685314906842080.0);

  final Tween<double> _zoomTween = Tween<double>(begin: _initialZoom, end: _initialZoom);
  late final Animation<double> _zoom = _controller.drive(CurveTween(curve: const ZoomCurve())).drive(_zoomTween);

  // pan, in meters
  final Tween<Offset> _panTween = Tween<Offset>(begin: _initialPan, end: _initialPan);
  late final Animation<Offset> _pan = _controller.drive(CurveTween(curve: const Interval(0.0, 0.5, curve: PanCurve()))).drive(_panTween);

  late WorldNode _centerNode;

  WorldTapTarget? _currentTarget;

  final GlobalKey _worldRootKey = GlobalKey();
  RenderBoxToRenderWorldAdapter get _worldRoot => _worldRootKey.currentContext!.findRenderObject()! as RenderBoxToRenderWorldAdapter;

  // a new instance of _precomputedPositions must be created each time it is changed, DO NOT MUTATE AN EXISTING COPY
  // (otherwise WorldConstraints will be unstable)
  Map<WorldNode, Offset> _precomputedPositions = <WorldNode, Offset>{};
  Offset _rootPosition = Offset.zero;

  // we would just mix in ChangeNotifier, but its dispose doesn't call super.dispose, which breaks State
  final ChangeNotifier _notifierImplementation = ChangeNotifier();
  @override
  void addListener(VoidCallback listener) => _notifierImplementation.addListener(listener);
  @override
  void removeListener(VoidCallback listener) => _notifierImplementation.removeListener(listener);

  @override
  void initState() {
    super.initState();
    _controller.addListener(_handlePositionChange);
    _centerNode = widget.rootNode;
    _handlePositionChange();
    widget.recommendedFocus.addListener(_handleRecommendedFocus);
  }

  @override
  void didUpdateWidget(WorldRoot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_centerNode == oldWidget.rootNode) {
      _centerNode = widget.rootNode;
      // not really any way to update pan, since we don't know how the two roots relate
    }
    if (widget.recommendedFocus != oldWidget.recommendedFocus) {
      oldWidget.recommendedFocus.removeListener(_handleRecommendedFocus);
      widget.recommendedFocus.addListener(_handleRecommendedFocus);
    }
  }

  void _handlePositionChange() {
    if (mounted) {
      setState(() {
        // TODO: when we're zoomed in enough that the things that changed position aren't visible, skip doing this
        _precomputedPositions = <WorldNode, Offset>{};
      });
      _notifierImplementation.notifyListeners(); // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
    }
  }

  void _updateSnap(double zoom, Offset pan) {
    _zoomTween.begin = zoom;
    _zoomTween.end = zoom;
    _panTween.begin = pan;
    _panTween.end = pan;
    _controller.reset();
    _handlePositionChange();
  }

  void _updatePan(Offset newPan, double scale, { double? zoom }) {
    final Size size = _worldRoot.size;
    _updateSnap(zoom ?? _zoom.value, Offset(
      _clampPan(newPan.dx, size.width / scale, widget.rootNode.diameter, _rootPosition.dx),
      _clampPan(newPan.dy, size.height / scale, widget.rootNode.diameter, _rootPosition.dy),
    ));
  }

  final List<WorldNode> _centerNodeChain = <WorldNode>[];

  void _centerNodeChainUpdate(WorldNode node) {
    _changeCenterNode(node.worldParent!);
  }
  
  void _changeCenterNode(WorldNode node) {
    if (node == _centerNode)
      return;

    for (WorldNode chain in _centerNodeChain) {
      chain.onDispose = null;
    }
    _centerNodeChain.clear();
      
    Offset oldPos = Offset.zero;
    WorldNode currentNode;
    currentNode = _centerNode;
    while (currentNode.parent != null) {
      if (_precomputedPositions.containsKey(currentNode)) {
        oldPos += _precomputedPositions[currentNode]!;
        break;
      } else {
        oldPos += currentNode.worldParent!.findLocationForChild(currentNode, <VoidCallback>[]);
        currentNode = currentNode.worldParent!;
      }
    }
    Offset newPos = Offset.zero;
    currentNode = node;
    while (currentNode.parent != null) {
      if (_precomputedPositions.containsKey(currentNode)) {
        newPos += _precomputedPositions[currentNode]!;
        break;
      } else {
        newPos += currentNode.worldParent!.findLocationForChild(currentNode, <VoidCallback>[]);
        currentNode = currentNode.worldParent!;
      }
    }
    final Offset delta = oldPos - newPos;
    _centerNode = node;

    WorldNode? chain = node;
    while (chain != null) {
      chain.onDispose = _centerNodeChainUpdate;
      chain = chain.worldParent;
    }
    
    _panTween.begin = _panTween.begin! - delta;
    _panTween.end = _panTween.end! - delta;
    _handlePositionChange();
  }

  void _centerOn(WorldNode node) {
    _changeCenterNode(node);
    final double zoom = log(widget.rootNode.diameter / _centerNode.diameter);
    _zoomTween.begin = _zoom.value;
    _zoomTween.end = zoom;
    _panTween.begin = _pan.value;
    _panTween.end = Offset.zero;
    _controller.forward(from: 0.0);
  }

  void _centerNear(WorldNode node, Offset offset, double diameter) {
    _changeCenterNode(node);
    final double zoom = log(widget.rootNode.diameter / diameter);
    _zoomTween.begin = _zoom.value;
    _zoomTween.end = zoom;
    _panTween.begin = _pan.value;
    _panTween.end = offset;
    _controller.forward(from: 0.0);
  }

  double? _lastScale; // tracks intra-frame scales in case scale events come in faster than the refresh rate (easy to do with a mousewheel)

  static double _clampPan(double x, double viewport, double diameter, double rootCenterOffset) {
    final double margin = diameter * 0.99 + (viewport - diameter) / 2.0;
    return x.clamp(rootCenterOffset - margin, rootCenterOffset + margin);
  }

  @override
  void dispose() {
    widget.recommendedFocus.removeListener(_handleRecommendedFocus);
    _controller.dispose();
    super.dispose();
  }

  bool _shouldAutofocus = true;

  void _handleRecommendedFocus() {
    if (widget.recommendedFocus.value == null) {
      _shouldAutofocus = true;
      _changeCenterNode(widget.rootNode);
      _zoomTween.end = _initialZoom;
      _panTween.end = _initialPan;
      _controller.forward(from: 0.0);
    } else if (_shouldAutofocus) {
      _shouldAutofocus = false;
      _centerOn(widget.recommendedFocus.value!);
    }
  }

  WorldNode? _badNode; // TODO: remove this

  @override
  Widget build(BuildContext context) {
    _lastScale = null;
    if (_precomputedPositions.isEmpty) {
      WorldNode? node = _centerNode;
      Offset offset = _pan.value;
      while (true) {
        _precomputedPositions[node!] = offset;
        if (node.parent != null) {
          offset -= node.worldParent!.findLocationForChild(node, <VoidCallback>[_handlePositionChange]);
          node = node.worldParent;
        } else {
          assert(node == widget.rootNode);
          // TODO: remove this, it should be obsolete debugging logic at this point
          if (node != widget.rootNode) {
            if (_centerNode != _badNode) {
              print('***** confused - center node ($_centerNode) is not in tree anymore *****');
              print('  root node is ${widget.rootNode}; ancestors of center node are:');
              WorldNode? node = _centerNode;
              while (node != null) {
                print('  - $node');
                node = node.worldParent;
              }
              print('');
              _badNode = _centerNode;
            }
          }
          // TODO: remove the above
          break;
        }
      }
      _rootPosition = _precomputedPositions[widget.rootNode]!;
    }
    return Listener(
      onPointerSignal: (PointerSignalEvent event) {
        GestureBinding.instance.pointerSignalResolver.register(event, (PointerSignalEvent event) {
          if (event is PointerScrollEvent && event.scrollDelta.dy != 0) {
            final RenderBoxToRenderWorldAdapter box = _worldRoot;
            final Size size = box.size;
            setState(() {
              final double deltaZoom = max(0.0 - _zoom.value, -event.scrollDelta.dy / 1000.0);
              // I don't understand why I need the negative sign below.
              // All the math I did suggests it should be positive, not negative.
              final Offset sigma = -Offset(event.localPosition.dx - size.width / 2.0, event.localPosition.dy - size.height / 2.0);
              _lastScale ??= box.layoutScale;
              final double newScale = max(box.minScale, _lastScale! * exp(deltaZoom));
              _updatePan(_pan.value + sigma / _lastScale! - sigma / newScale, newScale, zoom: _zoom.value + deltaZoom);
              _lastScale = newScale;
            });
          }
        });
      },
      child: ZoomProvider(
        state: this,
        child: DynastyProvider(
          dynastyManager: widget.dynastyManager,
          child: HudLayout(
            key: widget.hudKey,
            zoom: this,
            child: GestureDetector(
              trackpadScrollCausesScale: true,
              onScaleUpdate: (ScaleUpdateDetails details) {
                setState(() {
                  final RenderBoxToRenderWorldAdapter box = _worldRoot;
                  setState(() {
                    _lastScale ??= box.layoutScale;
                    final double newScale = max(box.minScale, _lastScale! * details.scale);
                    // TODO: check that this works when you pan AND zoom
                    _updatePan(_pan.value + details.focalPointDelta / _lastScale!, newScale, zoom: _zoom.value + log(details.scale));
                    _lastScale = newScale;
                  });
                });
              },
              onTapDown: (TapDownDetails details) {
                assert(_currentTarget == null);
                _currentTarget = _worldRoot.routeTap(details.localPosition);
                _currentTarget?.handleTapDown();
              },
              onTapCancel: () {
                _currentTarget?.handleTapCancel();
                _currentTarget = null;
              },
              onTapUp: (TapUpDetails details) {
                _currentTarget?.handleTapUp();
                _currentTarget = null;
              },
              child: ListenableBuilder(
                listenable: Listenable.merge(<Listenable?>[widget.rootNode, _controller]),
                builder: (BuildContext context, Widget? child) {
                  return BoxToWorldAdapter(
                    key: _worldRootKey,
                    diameter: widget.rootNode.diameter,
                    zoom: max(0.0, _zoom.value),
                    precomputedPositions: _precomputedPositions,
                    child: widget.rootNode.build(context),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ZoomProvider extends InheritedWidget {
  const ZoomProvider({ super.key, required this.state, required super.child });

  final _WorldRootState state;

  static void centerOn(BuildContext context, WorldNode target) {
    final ZoomProvider? provider = context.dependOnInheritedWidgetOfExactType<ZoomProvider>();
    assert(provider != null, 'No ZoomProvider found in context');
    provider!.state._centerOn(target);
  }

  static void centerNear(BuildContext context, WorldNode target, Offset offset, double diameter) {
    final ZoomProvider? provider = context.dependOnInheritedWidgetOfExactType<ZoomProvider>();
    assert(provider != null, 'No ZoomProvider found in context');
    provider!.state._centerNear(target, offset, diameter);
  }

  @override
  bool updateShouldNotify(ZoomProvider oldWidget) => state != oldWidget.state;
}

class BoxToWorldAdapter extends SingleChildRenderObjectWidget {
  const BoxToWorldAdapter({
    super.key,
    required this.diameter,
    required this.zoom,
    required this.precomputedPositions,
    super.child,
  });

  final double diameter;
  final double zoom;
  final Map<WorldNode, Offset> precomputedPositions;

  @override
  RenderBoxToRenderWorldAdapter createRenderObject(BuildContext context) {
    return RenderBoxToRenderWorldAdapter(
      diameter: diameter,
      zoom: zoom,
      precomputedPositions: precomputedPositions,
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderBoxToRenderWorldAdapter renderObject) {
    renderObject
      ..diameter = diameter
      ..zoom = zoom
      ..precomputedPositions = precomputedPositions;
  }
}

class RenderBoxToRenderWorldAdapter extends RenderBox with RenderObjectWithChildMixin<RenderWorld> {
  RenderBoxToRenderWorldAdapter({
    RenderWorld? child,
    required double diameter,
    required double zoom,
    required Map<WorldNode, Offset> precomputedPositions,
  }) : _diameter = diameter,
       _zoom = zoom,
       _precomputedPositions = precomputedPositions {
    this.child = child;
  }

  // size of play area (galaxy) in meters
  double get diameter => _diameter;
  double _diameter;
  set diameter (double value) {
    if (value != _diameter) {
      _diameter = value;
      markNeedsLayout();
    }
  }

  double get zoom => _zoom;
  double _zoom;
  set zoom (double value) {
    if (value != _zoom) {
      _zoom = value;
      markNeedsLayout();
    }
  }

  Map<WorldNode, Offset> get precomputedPositions => _precomputedPositions;
  Map<WorldNode, Offset> _precomputedPositions;
  set precomputedPositions (Map<WorldNode, Offset> value) {
    if (value != _precomputedPositions) {
      _precomputedPositions = value;
      markNeedsLayout();
    }
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

  double get minScale => _minScale;
  double _minScale = 0.0;

  double get layoutScale => _layoutScale; // pixels per meter
  double _layoutScale = 0.0;

  @override
  void performLayout() {
    size = constraints.constrain(Size.zero);
    if (child != null) {
      _minScale = size.shortestSide / diameter;
      _layoutScale = exp(zoom) * _minScale;
      child!.layout(WorldConstraints(
        viewportSize: size,
        zoom: zoom,
        scale: _layoutScale, // pixels per meter
        precomputedPositions: _precomputedPositions,
      ));
    }
  }

  final LayerHandle<TransformLayer> _universeLayer = LayerHandle<TransformLayer>();

  Offset _paintOffset = Offset.zero;

  @override
  void paint(PaintingContext context, Offset offset) {
    _paintOffset = size.center(offset);
    _universeLayer.layer = context.pushTransform(
      needsCompositing,
      Offset.zero,
      Matrix4.translationValues(_paintOffset.dx, _paintOffset.dy, 0.0),
      _paintChild,
      oldLayer: _universeLayer.layer,
    );
  }

  void _paintChild(PaintingContext context, Offset offset) {
    assert(offset == Offset.zero);
    if (child != null) {
      assert(_precomputedPositions.containsKey(child!.node)); // root must have precomputed position
      context.paintChild(child!, _precomputedPositions[child!.node]! * _layoutScale);
    }
  }

  @override
  void applyPaintTransform(covariant RenderObject child, Matrix4 transform) {
    // See also RenderWorld.applyPaintTransform in layout.dart and WorldToBox in widgets.dart.
    transform.translateByDouble(_paintOffset.dx, _paintOffset.dy, 0.0, 1.0);
  }

  @override
  bool hitTestSelf(Offset position) {
    return true;
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, { required Offset position }) {
    return result.addWithPaintOffset(offset: _paintOffset, position: position, hitTest: _hitTestChild);
  }

  bool _hitTestChild(BoxHitTestResult result, Offset offset) {
    return child?.hitTestChildren(result, position: offset) ?? false;
  }

  WorldTapTarget? routeTap(Offset offset) {
    if (child != null) {
      return child!.routeTap(Offset(offset.dx - size.width / 2.0, offset.dy - size.height / 2.0));
    }
    return null;
  }

  @override
  void dispose() {
    _universeLayer.layer = null;
    super.dispose();
  }
}
