import 'dart:async';
import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import 'galaxy.dart';
import 'renderers.dart';
import 'world.dart' show WorldNode;
import 'zoom.dart';

class WorldRoot extends StatefulWidget {
  const WorldRoot({super.key, required this.rootNode});

  final WorldNode rootNode;
  
  @override
  _WorldRootState createState() => _WorldRootState();
}

class _WorldRootState extends State<WorldRoot> {
  ZoomSpecifier _zoom = const PanZoomSpecifier.centered(5.0); // this is the global source of truth for zoom!

  PanZoomSpecifier? _zoomAnchor;
  Offset? _focalPoint;

  WorldTapTarget? _currentTarget;
  
  final GlobalKey _worldRootKey = GlobalKey();
  RenderBoxToRenderWorldAdapter get _worldRoot => _worldRootKey.currentContext!.findRenderObject()! as RenderBoxToRenderWorldAdapter;

  void _zoomTo(WorldNode target) {
    setState(() {
      _zoom = _zoom.truncate(widget.rootNode).withChild(target);
    });
  }
  
  @override
  Widget build(BuildContext context) {
    print(_zoom);
    return Listener(
      onPointerSignal: (PointerSignalEvent event) {
        GestureBinding.instance.pointerSignalResolver.register(event, (PointerSignalEvent event) {
          if (event is PointerScrollEvent) {
            final Size size = _worldRootKey.currentContext!.size!;
            final Offset panOffset = _worldRoot.panOffset;
            final double zoomFactor = _worldRoot.zoomFactor;
            setState(() {
              _zoom = _zoom.withScale(
                event.scrollDelta.dy / -1000.0,
                (event.localPosition - panOffset) / (size.shortestSide * zoomFactor),
                Offset(event.localPosition.dx / size.width, event.localPosition.dy / size.height),
              );
            });
          }
        });
      },
      child: GestureDetector(
        trackpadScrollCausesScale: true,
        onScaleStart: (ScaleStartDetails details) {
          _zoomAnchor = _zoom.last;
          _focalPoint = details.focalPoint;
        },
        onScaleUpdate: (ScaleUpdateDetails details) {
          setState(() {
            final Size size = _worldRootKey.currentContext!.size!;
            final Offset delta = details.focalPoint - _focalPoint!;
            // TODO: if delta is non-zero we should truncate the zoom here
            // TODO: we should use withScale
            _zoom = _zoom.withPan(PanZoomSpecifier(
              _zoomAnchor!.sourceFocalPointFraction,
              _zoomAnchor!.destinationFocalPointFraction + Offset(delta.dx / size.width, delta.dy / size.height),
              max(1.0, _zoomAnchor!.zoom * details.scale),
            ));
          });
        },
        onScaleEnd: (ScaleEndDetails details) {
          _zoomAnchor = null;
        },
        onTapDown: (TapDownDetails details) {
          assert(_currentTarget == null);
          _currentTarget = _worldRoot.routeTap(details.localPosition);
          _currentTarget?.handleTapDown();
        },
        onTapCancel: () {
          _currentTarget?.handleTapDown();
          _currentTarget = null;
        },
        onTapUp: (TapUpDetails details) {
          _currentTarget?.handleTapUp();
          _currentTarget = null;
        },
        child: ZoomProvider(
          state: this,
          child: BoxToWorldAdapter(
            key: _worldRootKey,
            child: widget.rootNode.build(context, _zoom),
          ),
        ),
      ),
    );
  }
}

class ZoomProvider extends InheritedWidget {
  const ZoomProvider({ super.key, required this.state, required super.child });

  final _WorldRootState state;

  static void zoom(BuildContext context, WorldNode target) {
    final ZoomProvider? provider = context.dependOnInheritedWidgetOfExactType<ZoomProvider>();
    assert(provider != null, 'No ZoomProvider found in context');
    provider!.state._zoomTo(target);
  }

  @override
  bool updateShouldNotify(ZoomProvider oldWidget) => state != oldWidget.state;
}

class BoxToWorldAdapter extends SingleChildRenderObjectWidget {
  const BoxToWorldAdapter({
    super.key,
    super.child,
  });

  @override
  RenderBoxToRenderWorldAdapter createRenderObject(BuildContext context) {
    return RenderBoxToRenderWorldAdapter();
  }

  @override
  void updateRenderObject(BuildContext context, RenderBoxToRenderWorldAdapter renderObject) { }
}

class GalaxyWidget extends MultiChildRenderObjectWidget {
  const GalaxyWidget({
    super.key,
    required this.galaxy,
    required this.diameter,
    required this.zoom,
    this.onTap,
    super.children,
  });

  final Galaxy galaxy;
  final double diameter;
  final PanZoomSpecifier zoom;
  final GalaxyTapHandler? onTap;
  
  @override
  RenderGalaxy createRenderObject(BuildContext context) {
    return RenderGalaxy(
      galaxy: galaxy,
      diameter: diameter,
      zoom: zoom,
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderGalaxy renderObject) {
    renderObject
      ..galaxy = galaxy
      ..diameter = diameter
      ..zoom = zoom;
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

class WorldPlaceholder extends LeafRenderObjectWidget {
  const WorldPlaceholder({
    super.key,
    required this.diameter,
    required this.zoom,
    required this.color,
  });

  final double diameter;
  final PanZoomSpecifier zoom;
  final Color color;
  
  @override
  RenderWorldPlaceholder createRenderObject(BuildContext context) {
    return RenderWorldPlaceholder(
      diameter: diameter,
      zoom: zoom,
      color: color,
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderWorldPlaceholder renderObject) {
    renderObject
      ..diameter = diameter
      ..zoom = zoom
      ..color = color;
  }
}
