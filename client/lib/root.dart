import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'assets.dart' show WorldNode;
import 'layout.dart';

class WorldRoot extends StatefulWidget {
  const WorldRoot({super.key, required this.rootNode, required this.recommendedFocus });

  final WorldNode rootNode;
  final ValueListenable<WorldNode?> recommendedFocus;

  @override
  _WorldRootState createState() => _WorldRootState();
}

class _WorldRootState extends State<WorldRoot> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2500),
  );

  static const double _initialZoom = 4.0;
  static const Offset _initialPan = Offset(-3582946788187048960.0, -179685314906842080.0);
  
  final Tween<double> _zoomTween = Tween<double>(begin: _initialZoom, end: _initialZoom);
  late final Animation<double> _zoom = _controller.drive(CurveTween(curve: Curves.easeInBack)).drive(_zoomTween);
  
  final Tween<Offset> _panTween = Tween<Offset>(begin: _initialPan, end: _initialPan);
  late final Animation<Offset> _pan = _controller.drive(CurveTween(curve: const Interval(0.0, 0.5, curve: Curves.easeOut))).drive(_panTween);

  WorldNode? _centerNode;

  WorldTapTarget? _currentTarget;

  final GlobalKey _worldRootKey = GlobalKey();
  RenderBoxToRenderWorldAdapter get _worldRoot => _worldRootKey.currentContext!.findRenderObject()! as RenderBoxToRenderWorldAdapter;

  void markNeedsBuild() {
    setState(() { });
  }

  @override
  void initState() {
    super.initState();
    widget.recommendedFocus.addListener(_handleRecommendedFocus);
  }

  @override
  void didUpdateWidget(WorldRoot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.recommendedFocus != oldWidget.recommendedFocus) {
      oldWidget.recommendedFocus.removeListener(_handleRecommendedFocus);
      widget.recommendedFocus.addListener(_handleRecommendedFocus);
    }
  }
  
  void _updateTo(double zoom, Offset pan) {
    _zoomTween.end = zoom;
    _panTween.end = pan;
  }

  void _updateSnap(double zoom, Offset pan) {
    _zoomTween.begin = zoom;
    _zoomTween.end = zoom;
    _centerNode = null;
    _panTween.begin = pan;
    _panTween.end = pan;
    _controller.reset();
  }

  void _updatePan(Offset newPan, double scale, { double? zoom }) {
    final Size size = _worldRoot.size;
    _updateSnap(zoom ?? _zoom.value, Offset(
      _clampPan(newPan.dx, size.width / scale, widget.rootNode.diameter, size.width < size.height),
      _clampPan(newPan.dy, size.height / scale, widget.rootNode.diameter, size.height < size.width),
    ));
  }

  void _centerOn(WorldNode node) {
    _centerNode = node;
    final double zoom = log(widget.rootNode.diameter / _centerNode!.diameter);
    final Offset pan = -_centerNode!.computePosition(<VoidCallback>[markNeedsBuild]);
    _zoomTween.begin = _zoom.value;
    _zoomTween.end = zoom;
    _panTween.begin = _pan.value;
    _panTween.end = pan;
    _controller.forward(from: 0.0);
  }

  double? _lastScale; // tracks into-frame scales in case scale events come in faster than the refresh rate (easy to do with a mousewheel)

  static double _clampPan(double x, double viewport, double diameter, bool tight) {
    final double margin = diameter * 0.99 + (viewport - diameter) / 2.0;
    return x.clamp(-margin, margin);
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
    } else if (_shouldAutofocus) {
      _shouldAutofocus = false;
      _centerOn(widget.recommendedFocus.value!);
    }
  }
  
  @override
  Widget build(BuildContext context) {
    _lastScale = null;
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
              // TODO: don't unlock the pan if we have a _centerNode
              _updatePan(_pan.value + sigma / _lastScale! - sigma / newScale, newScale, zoom: _zoom.value + deltaZoom);
              _lastScale = newScale;
            });
          }
        });
      },
      child: GestureDetector(
        trackpadScrollCausesScale: true,
        onScaleUpdate: (ScaleUpdateDetails details) {
          setState(() {
            final RenderBoxToRenderWorldAdapter box = _worldRoot;
            setState(() {
              _lastScale ??= box.layoutScale;
              final double newScale = max(box.minScale, _lastScale! * details.scale);
              // TODO: check that this works when you pan AND zoom
              // TODO: make the pan relative to the _centerNode if we have one
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
        child: ZoomProvider(
          state: this,
          child: ListenableBuilder(
            listenable: Listenable.merge(<Listenable?>[widget.rootNode, _controller]),
            builder: (BuildContext context, Widget? child) {
              if (_centerNode != null) {
                _updateTo(
                  log(widget.rootNode.diameter / _centerNode!.diameter) / 1.5,
                  -_centerNode!.computePosition(<VoidCallback>[markNeedsBuild]),
                );
              }
              return BoxToWorldAdapter(
                key: _worldRootKey,
                diameter: widget.rootNode.diameter,
                zoom: max(0.0, _zoom.value),
                pan: _pan.value,
                centerNode: _centerNode,
                child: widget.rootNode.build(context),
              );
            },
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

  @override
  bool updateShouldNotify(ZoomProvider oldWidget) => state != oldWidget.state;
}

class BoxToWorldAdapter extends SingleChildRenderObjectWidget {
  const BoxToWorldAdapter({
    super.key,
    required this.diameter,
    required this.zoom,
    required this.pan,
    required this.centerNode,
    super.child,
  });

  final double diameter;
  final double zoom;
  final Offset pan;
  final WorldNode? centerNode;

  @override
  RenderBoxToRenderWorldAdapter createRenderObject(BuildContext context) {
    return RenderBoxToRenderWorldAdapter(
      diameter: diameter,
      zoom: zoom,
      pan: pan,
      centerNode: centerNode,
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderBoxToRenderWorldAdapter renderObject) {
    renderObject
      ..diameter = diameter
      ..zoom = zoom
      ..pan = pan
      ..centerNode = centerNode;
  }
}

class RenderBoxToRenderWorldAdapter extends RenderBox with RenderObjectWithChildMixin<RenderWorld> {
  RenderBoxToRenderWorldAdapter({
    RenderWorld? child,
    required double diameter,
    required double zoom,
    required Offset pan,
    required WorldNode? centerNode,
  }) : _diameter = diameter,
       _zoom = zoom,
       _pan = pan,
       _centerNode = centerNode {
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

  // in meters
  Offset get pan => _pan;
  Offset _pan;
  set pan (Offset value) {
    if (value != _pan) {
      _pan = value;
      markNeedsLayout();
    }
  }

  WorldNode? get centerNode => _centerNode;
  WorldNode? _centerNode;
  set centerNode (WorldNode? value) {
    if (value != _centerNode) {
      _centerNode = value;
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

  double get layoutScale => _layoutScale;
  double _layoutScale = 0.0;

  @override
  void performLayout() {
    size = constraints.constrain(Size.zero);
    if (child != null) {
      _minScale = size.shortestSide / diameter;
      _layoutScale = exp(zoom) * _minScale;
      final Size scaledSize = size / _layoutScale;
      final Offset scaledPan = scaledSize.center(pan);
      child!.layout(WorldConstraints(
        viewport: Offset.zero & size,
        zoom: zoom,
        scale: _layoutScale, // pixels per meter
        pan: size.center(pan * _layoutScale),
        scaledPan: scaledPan,
        scaledViewport: Rect.fromLTWH(
          -scaledPan.dx,
          -scaledPan.dy,
          scaledSize.width,
          scaledSize.height,
        ),
      ));
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child != null) {
      context.paintChild(child!, offset);
    }
  }

  @override
  bool hitTest(BoxHitTestResult result, { required Offset position }) {
    result.add(BoxHitTestEntry(this, position));
    return true;
  }

  WorldTapTarget? routeTap(Offset offset) {
    if (child != null) {
      return child!.routeTap(offset);
    }
    return null;
  }
}
