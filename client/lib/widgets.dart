import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

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
  late ZoomSpecifier _zoom; // this is the global source of truth for zoom!

  @override
  void initState() {
    super.initState();
    _zoom = PanZoomSpecifier.centered(widget.rootNode.diameter, 4.0);
  }
  
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
    return Listener(
      onPointerSignal: (PointerSignalEvent event) {
        GestureBinding.instance.pointerSignalResolver.register(event, (PointerSignalEvent event) {
          if (event is PointerScrollEvent && event.scrollDelta.dy != 0) {
            final Size size = _worldRootKey.currentContext!.size!;
            final Offset panOffset = _worldRoot.panOffset;
            final double zoomFactor = _worldRoot.zoomFactor;
            setState(() {
              _zoom = _zoom.withScale(
                widget.rootNode,
                event.scrollDelta.dy / -1000.0,
                (event.localPosition - panOffset) / zoomFactor,
                Offset(event.localPosition.dx / size.width, event.localPosition.dy / size.height),
              );
            });
          }
        });
      },
      child: GestureDetector(
        trackpadScrollCausesScale: true,
        onScaleUpdate: (ScaleUpdateDetails details) {
          setState(() {
            final Size size = _worldRootKey.currentContext!.size!;
            final ZoomSpecifier truncatedZoom = _zoom.truncate(widget.rootNode);
            final PanZoomSpecifier anchor = truncatedZoom.last;
            _zoom = truncatedZoom.withScale(
              widget.rootNode,
              log(details.scale),
              anchor.sourceFocalPoint,
              anchor.destinationFocalPointFraction + details.focalPointDelta.scale(1.0 / size.width, 1.0 / size.height),
            );
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

class WorldPlaceholder extends LeafRenderObjectWidget {
  const WorldPlaceholder({
    super.key,
    required this.diameter,
    required this.zoom,
    required this.transitionLevel,
    required this.color,
  });

  final double diameter;
  final PanZoomSpecifier zoom;
  final double transitionLevel;
  final Color color;
  
  @override
  RenderWorldPlaceholder createRenderObject(BuildContext context) {
    return RenderWorldPlaceholder(
      diameter: diameter,
      zoom: zoom,
      transitionLevel: transitionLevel,
      color: color,
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderWorldPlaceholder renderObject) {
    renderObject
      ..diameter = diameter
      ..zoom = zoom
      ..transitionLevel = transitionLevel
      ..color = color;
  }
}
