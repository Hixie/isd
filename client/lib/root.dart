import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'assets.dart' show WorldNode;
import 'layout.dart';

class WorldRoot extends StatefulWidget {
  const WorldRoot({super.key, required this.rootNode});

  final WorldNode rootNode;

  @override
  _WorldRootState createState() => _WorldRootState();
}

class _WorldRootState extends State<WorldRoot> {
  double _zoom = 4.0; // log scale
  Offset _pan = Offset.zero; // meters offset from center of galaxy being in center of screen
  WorldNode? _centerNode;

  WorldTapTarget? _currentTarget;

  final GlobalKey _worldRootKey = GlobalKey();
  RenderBoxToRenderWorldAdapter get _worldRoot => _worldRootKey.currentContext!.findRenderObject()! as RenderBoxToRenderWorldAdapter;

  void markNeedsBuild() {
    setState(() { });
  }

  void _centerOn(WorldNode node) {
    setState(() {
      _centerNode = node;
      _pan = -_centerNode!.computePosition([markNeedsBuild]);
      _zoom = log(widget.rootNode.diameter / node.diameter);
    });
  }

  double? _lastScale; // tracks into-frame scales in case scale events come in faster than the refresh rate (easy to do with a mousewheel)

  static double _clampPan(double x, double viewport, double diameter, bool tight) {
    final double margin = diameter * 0.99 + (viewport - diameter) / 2.0;
    return x.clamp(-margin, margin);
  }

  // should be called inside setState
  void _updatePan(Offset newPan, double scale) {
    final Size size = _worldRoot.size;
    _pan = Offset(
      _clampPan(newPan.dx, size.width / scale, widget.rootNode.diameter, size.width < size.height),
      _clampPan(newPan.dy, size.height / scale, widget.rootNode.diameter, size.height < size.width),
    );
    _centerNode = null;
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
              final double deltaZoom = max(0.0 - _zoom, -event.scrollDelta.dy / 1000.0);
              // I don't understand why I need the negative sign below.
              // All the math I did suggests it should be positive, not negative.
              final sigma = -Offset(event.localPosition.dx - size.width / 2.0, event.localPosition.dy - size.height / 2.0);
              _lastScale ??= box.layoutScale;
              final double newScale = max(box.minScale, _lastScale! * exp(deltaZoom));
              _zoom += deltaZoom;
              _updatePan(_pan + sigma / _lastScale! - sigma / newScale, newScale);
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
              _zoom += log(details.scale);
              _updatePan(_pan + details.focalPointDelta / _lastScale!, newScale); // TODO: check that this works when you pan AND zoom
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
            listenable: widget.rootNode,
            builder: (BuildContext context, Widget? child) {
              return BoxToWorldAdapter(
                key: _worldRootKey,
                diameter: widget.rootNode.diameter,
                zoom: _zoom,
                pan: _pan,
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
        scaledPosition: Offset.zero, // distance from canvas origin to child origin, without pan
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
}
