import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import 'galaxy.dart';
import 'renderers.dart';
import 'world.dart';
import 'zoom.dart';

class WorldRoot extends StatefulWidget {
  const WorldRoot({super.key, required this.rootNode});

  final WorldNode rootNode;
  
  @override
  _WorldRootState createState() => _WorldRootState();
}

class _WorldRootState extends State<WorldRoot> {
  ZoomSpecifier _zoom = const PanZoomSpecifier.centered(5.0);

  PanZoomSpecifier? _zoomAnchor;
  Offset? _focalPoint;

  final GlobalKey _worldRootKey = GlobalKey();
  RenderBoxToRenderWorldAdapter get _worldRoot => _worldRootKey.currentContext!.findRenderObject()! as RenderBoxToRenderWorldAdapter;
  
  @override
  Widget build(BuildContext context) {
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
        onTapUp: (TapUpDetails details) {
          _worldRoot.handleTap(details.localPosition);
        },
        child: BoxToWorldAdapter(
          key: _worldRootKey,
          child: widget.rootNode.build(context, _zoom),
        ),
      ),
    );
  }
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
      onTap: onTap,
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderGalaxy renderObject) {
    renderObject
      ..galaxy = galaxy
      ..diameter = diameter
      ..zoom = zoom
      ..onTap = onTap;
  }
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

class WorldNodePosition extends ParentDataWidget<WorldParentData> {
  const WorldNodePosition({
    super.key,
    required this.position,
    required this.diameter,
    required super.child,
  });

  final Offset position;
  final double diameter;

  @override
  void applyParentData(RenderObject renderObject) {
    final WorldParentData parentData = renderObject.parentData! as WorldParentData;
    if (parentData.position != position ||
        parentData.diameter != diameter) {
      parentData.position = position;
      parentData.diameter = diameter;
      renderObject.parent!.markNeedsLayout();
    }
  }

  @override
  Type get debugTypicalAncestorWidgetClass => RenderGalaxy;
}
