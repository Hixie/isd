import 'dart:math';
import 'dart:ui';

import 'package:flutter/rendering.dart' hide Gradient;
import 'package:flutter/widgets.dart' hide Gradient;

import '../assets.dart';
import '../layout.dart';
import '../shaders.dart';
import '../spacetime.dart';
import '../world.dart';

typedef GridParameters = ({int x, int y}); // could also just store this as an index, and use half the memory

class GridFeature extends ContainerFeature {
  GridFeature(this.spaceTime, this.cellSize, this.width, this.height, this.children);

  final SpaceTime spaceTime;
  final double cellSize;
  final int width;
  final int height;

  // consider this read-only; the entire GridFeature gets replaced when the child list changes
  final Map<AssetNode, GridParameters> children;

  @override
  Offset findLocationForChild(AssetNode child, List<VoidCallback> callbacks) {
    final GridParameters childData = children[child]!;
    return Offset(
      (childData.x - width / 2 + 0.5) * cellSize,
      (childData.y - height / 2 + 0.5) * cellSize,
    );
  }

  @override
  void attach(AssetNode parent) {
    super.attach(parent);
    for (AssetNode child in children.keys) {
      child.parent = parent;
    }
  }

  @override
  void detach() {
    for (AssetNode child in children.keys) {
      if (child.parent == parent) {
        child.parent = null;
        // if its parent is not the same as our parent,
        // then maybe it was already added to some other container
      }
    }
    super.detach();
  }

  @override
  void walk(WalkCallback callback) {
    for (AssetNode child in children.keys) {
      child.walk(callback);
    }
  }

  @override
  Widget buildRenderer(BuildContext context, Widget? child) {
    return GridWidget(
      spaceTime: spaceTime,
      node: parent,
      cellSize: cellSize,
      width: width,
      height: height,
      children: children.keys.map((AssetNode assetChild) => assetChild.build(context)).toList(),
    );
  }
}

class GridWidget extends MultiChildRenderObjectWidget {
  const GridWidget({
    super.key,
    required this.spaceTime,
    required this.node,
    required this.cellSize,
    required this.width,
    required this.height,
    super.children,
  });

  final SpaceTime spaceTime;
  final WorldNode node;
  final double cellSize;
  final int width;
  final int height;

  @override
  RenderGrid createRenderObject(BuildContext context) {
    return RenderGrid(
      spaceTime: spaceTime,
      shaders: ShaderProvider.of(context),
      node: node,
      cellSize: cellSize,
      width: width,
      height: height,
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderGrid renderObject) {
    renderObject
      ..spaceTime = spaceTime
      ..shaders = ShaderProvider.of(context)
      ..node = node
      ..cellSize = cellSize
      ..width = width
      ..height = height;
  }
}

class GridParentData extends ParentData with ContainerParentDataMixin<RenderWorld> { }

class RenderGrid extends RenderWorldWithChildren<GridParentData> {
  RenderGrid({
    required SpaceTime spaceTime,
    required ShaderLibrary shaders,
    required super.node,
    required double cellSize,
    required int width,
    required int height,
  }) : _spaceTime = spaceTime,
       _shaders = shaders,
       _cellSize = cellSize,
       _width = width,
       _height = height;

  SpaceTime get spaceTime => _spaceTime;
  SpaceTime _spaceTime;
  set spaceTime (SpaceTime value) {
    if (value != _spaceTime) {
      _spaceTime = value;
      markNeedsPaint();
    }
  }

  ShaderLibrary get shaders => _shaders;
  ShaderLibrary _shaders;
  set shaders (ShaderLibrary value) {
    if (value != _shaders) {
      _shaders = value;
      _gridShader = null;
      markNeedsPaint();
    }
  }

  double get cellSize => _cellSize;
  double _cellSize;
  set cellSize (double value) {
    if (value != _cellSize) {
      _cellSize = value;
      _gridShader = null;
      markNeedsPaint();
    }
  }

  int get width => _width;
  int _width;
  set width (int value) {
    if (value != _width) {
      _width = value;
      _gridShader = null;
      markNeedsPaint();
    }
  }

  int get height => _height;
  int _height;
  set height (int value) {
    if (value != _height) {
      _height = value;
      _gridShader = null;
      markNeedsPaint();
    }
  }

  double get diameter => max(width, height) * cellSize;

  @override
  void setupParentData(RenderObject child) {
    if (child.parentData is! GridParentData) {
      child.parentData = GridParentData();
    }
  }

  @override
  void computeLayout(WorldConstraints constraints) {
    RenderWorld? child = firstChild;
    while (child != null) {
      final GridParentData childParentData = child.parentData! as GridParentData;
      child.layout(constraints);
      child = childParentData.nextSibling;
    }
  }

  FragmentShader? _gridShader;
  final Paint _gridPaint = Paint();

  @override
  WorldGeometry computePaint(PaintingContext context, Offset offset) {
    _gridShader ??= shaders.grid(width: width, height: height);
    final double time = spaceTime.computeTime(<VoidCallback>[markNeedsPaint]);
    _gridShader!.setFloat(uT, time);
    _gridShader!.setFloat(uX, offset.dx);
    _gridShader!.setFloat(uY, offset.dy);
    _gridShader!.setFloat(uGridWidth, diameter * constraints.scale);
    _gridShader!.setFloat(uGridHeight, diameter * constraints.scale);
    _gridPaint.shader = _gridShader;
    context.canvas.drawRect(Rect.fromCircle(center: offset, radius: diameter * constraints.scale / 2.0), _gridPaint);
    RenderWorld? child = firstChild;
    while (child != null) {
      final GridParentData childParentData = child.parentData! as GridParentData;
      context.paintChild(child, constraints.paintPositionFor(child.node, offset, <VoidCallback>[markNeedsPaint]));
      child = childParentData.nextSibling;
    }
    return WorldGeometry(shape: Rectangle(Size(width * cellSize, height * cellSize)));
  }

  @override
  WorldTapTarget? routeTap(Offset offset) {
    RenderWorld? child = lastChild;
    while (child != null) {
      final GridParentData childParentData = child.parentData! as GridParentData;
      final WorldTapTarget? result = child.routeTap(offset); // TODO: correct offset
      if (result != null)
        return result;
      child = childParentData.previousSibling;
    }
    return null;
  }
}
