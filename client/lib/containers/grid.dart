import 'dart:math';

import 'package:flutter/rendering.dart' hide Gradient;
import 'package:flutter/widgets.dart' hide Gradient;

import '../assets.dart';
import '../layout.dart';
import '../world.dart';

typedef GridParameters = ({int x, int y}); // could also just store this as an index, and use half the memory

class GridFeature extends ContainerFeature {
  GridFeature(this.cellSize, this.width, this.height, this.children);

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
  void attach(WorldNode parent) {
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
    required this.node,
    required this.cellSize,
    required this.width,
    required this.height,
    super.children,
  });

  final WorldNode node;
  final double cellSize;
  final int width;
  final int height;

  @override
  RenderGrid createRenderObject(BuildContext context) {
    return RenderGrid(
      node: node,
      cellSize: cellSize,
      width: width,
      height: height,
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderGrid renderObject) {
    renderObject
      ..node = node
      ..cellSize = cellSize
      ..width = width
      ..height = height;
  }
}

class GridParentData extends ParentData with ContainerParentDataMixin<RenderWorld> { }

class RenderGrid extends RenderWorldNode with ContainerRenderObjectMixin<RenderWorld, GridParentData> {
  RenderGrid({
    required super.node,
    required double cellSize,
    required int width,
    required int height,
  }) : _cellSize = cellSize,
       _width = width,
       _height = height;

  double get cellSize => _cellSize;
  double _cellSize;
  set cellSize (double value) {
    if (value != _cellSize) {
      _cellSize = value;
      markNeedsPaint();
    }
  }

  int get width => _width;
  int _width;
  set width (int value) {
    if (value != _width) {
      _width = value;
      markNeedsPaint();
    }
  }

  int get height => _height;
  int _height;
  set height (int value) {
    if (value != _height) {
      _height = value;
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

  @override
  WorldGeometry computePaint(PaintingContext context, Offset offset) {
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
    RenderWorld? child = firstChild;
    while (child != null) {
      final GridParentData childParentData = child.parentData! as GridParentData;
      // TODO: something...
      child = childParentData.nextSibling;
    }
    return null;
  }
}
