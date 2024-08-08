import 'dart:math';

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../renderers.dart';
import '../world.dart';
import '../zoom.dart';

typedef SpaceChild = ({ double r, double theta, AssetNode child });

class SpaceFeature extends ContainerFeature {
  SpaceFeature(super.parent, this.children);
  final Set<SpaceChild> children;

  List<Widget>? _children;

  // TODO: deduplicate this code, there's lots of common code here and in galaxy.dart
  // TODO: shouldn't need to recompute the children positions each time we change zoom
  
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
    return SpaceWidget(
      zoom: zoom,
      transitionLevel: transitionLevel,
      children: _children ??= _rebuildChildren(context, zoom, zoomedChildNode, zoomedChildZoom),
    );
  }

  List<Widget> _rebuildChildren(BuildContext context, PanZoomSpecifier zoom, WorldNode? zoomedChildNode, ZoomSpecifier? zoomedChildZoom) {
    return children.map((SpaceChild childData) {
      return ListenableBuilder(
        listenable: childData.child,
        builder: (BuildContext context, Widget? child) {
          final position = Offset(
            childData.r * sin(childData.theta),
            childData.r * cos(childData.theta),
          );
          return SpaceChildData(
            position: position,
            diameter: childData.child.diameter,
            child: child!,
          );
        },
        child: childData.child.build(
          context,
          childData.child == zoomedChildNode ? zoomedChildZoom! : PanZoomSpecifier.centered(childData.child.diameter, 0.0),
        ),
      );
    }).toList();
  }
}

class SpaceWidget extends MultiChildRenderObjectWidget {
  const SpaceWidget({
    super.key,
    required this.zoom,
    required this.transitionLevel,
    super.children,
  });

  final PanZoomSpecifier zoom;
  final double transitionLevel;
  
  @override
  RenderSpace createRenderObject(BuildContext context) {
    return RenderSpace(
      zoom: zoom,
      transitionLevel: transitionLevel,
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderSpace renderObject) {
    renderObject
      ..zoom = zoom
      ..transitionLevel = transitionLevel;
  }
}

class SpaceChildData extends ParentDataWidget<SpaceParentData> {
  const SpaceChildData({
    super.key, // ignore: unused_element
    required this.position,
    required this.diameter,
    required super.child,
  });

  final Offset position;
  final double diameter;
  
  @override
  void applyParentData(RenderObject renderObject) {
    final SpaceParentData parentData = renderObject.parentData! as SpaceParentData;
    if (parentData.position != position ||
        parentData.diameter != diameter) {
      parentData.position = position;
      parentData.diameter = diameter;
      renderObject.parent!.markNeedsLayout();
    }
  }

  @override
  Type get debugTypicalAncestorWidgetClass => RenderSpace;
}

class SpaceParentData extends ParentData with ContainerParentDataMixin<RenderWorld> {
  Offset position = Offset.zero; // in meters
  double diameter = 0; // in meters
}

class RenderSpace extends RenderWorld with ContainerRenderObjectMixin<RenderWorld, SpaceParentData> {
  RenderSpace({
    required PanZoomSpecifier zoom,
    required double transitionLevel,
  }) : _zoom = zoom,
       _transitionLevel = transitionLevel;

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
    if (child.parentData is! SpaceParentData) {
      child.parentData = SpaceParentData();
    }
  }

  @override
  void hitTestChildren(WorldHitTestResult result, { required Offset position }) {
    RenderWorld? child = firstChild;
    while (child != null) {
      final SpaceParentData childParentData = child.parentData! as SpaceParentData;
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
      final SpaceParentData childParentData = child.parentData! as SpaceParentData;
      child = childParentData.nextSibling;
    }
  }

  Offset _panOffset = Offset.zero;
  Offset _scaledPanOffset = Offset.zero;
  double _scaleFactor = 1.0;

  @override
  void performLayout() {
    _panOffset = Offset.zero; // TODO:
    _scaleFactor = exp(zoom.zoom);
    _scaledPanOffset = _panOffset * _scaleFactor;
    RenderWorld? child = firstChild;
    while (child != null) {
      final SpaceParentData childParentData = child.parentData! as SpaceParentData;
      assert(childParentData.diameter > 0);
      final double realDiameter = childParentData.diameter;
      final double minVisibleDiameter = 32.0 / (constraints.currentScale * _scaleFactor);
      final double childDiameter = max(realDiameter, minVisibleDiameter);
      child.layout(WorldConstraints(
        size: Size.square(childDiameter), // in meters
        currentScale: constraints.currentScale * _scaleFactor,
      ));
      child = childParentData.nextSibling;
    }
  }

  TransformLayer? _transformLayer;
  
  @override
  void paint(PaintingContext context, Offset offset) {
    context.canvas.drawRect(
      Rect.fromCircle(center: offset, radius: constraints.size.shortestSide),
      Paint()..style=PaintingStyle.stroke..strokeWidth = 10.0 / constraints.currentScale..color=Color(0xFF0066CC),
    );
    final transform = Matrix4.identity()
      ..scale(_scaleFactor);
    _transformLayer = context.pushTransform(
      needsCompositing,
      offset,
      transform,
      _paintSpace,
      oldLayer: _transformLayer,
    );
  }
  
  void _paintSpace(PaintingContext context, Offset offset) {
    RenderWorld? child = firstChild;
    while (child != null) {
      final SpaceParentData childParentData = child.parentData! as SpaceParentData;
      context.paintChild(child, offset + (childParentData.position + _scaledPanOffset));
      child = childParentData.nextSibling;
    }
  }

  @override
  void applyPaintTransform(RenderWorld child, Matrix4 transform) {
    transform.multiply(_transformLayer!.transform!);
  }
  
  @override
  WorldTapTarget? routeTap(Offset offset) {
    RenderWorld? child = firstChild;
    while (child != null) {
      final SpaceParentData childParentData = child.parentData! as SpaceParentData;
      // TODO: something...
      child = childParentData.nextSibling;
    }
    return null;
  }

  @override
  Offset get panOffset => _panOffset; // TODO: defer to child if fully zoomed

  @override
  double get zoomFactor => _scaleFactor; // TODO: defer to child if fully zoomed
}
