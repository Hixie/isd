import 'package:flutter/rendering.dart' hide Gradient;
import 'package:flutter/widgets.dart' hide Gradient;

import '../assets.dart';
import '../layout.dart';
import '../world.dart';

typedef MessageBoardParameters = ();

class MessageBoardFeature extends ContainerFeature {
  MessageBoardFeature(this.children);

  // consider this read-only; the entire MessageBoardFeature gets replaced when the child list changes
  final Map<AssetNode, MessageBoardParameters> children;

  @override
  Offset findLocationForChild(AssetNode child, List<VoidCallback> callbacks) {
    // final MessageBoardParameters childData = children[child]!;
    return Offset.zero;
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
    return MessageBoardWidget(
      node: parent,
      diameter: parent.diameter,
      maxDiameter: parent.maxRenderDiameter,
      children: children.keys.map((AssetNode assetChild) => assetChild.build(context)).toList(),
    );
  }
}

class MessageBoardWidget extends MultiChildRenderObjectWidget {
  const MessageBoardWidget({
    super.key,
    required this.node,
    required this.diameter,
    required this.maxDiameter,
    super.children,
  });

  final WorldNode node;
  final double diameter;
  final double maxDiameter;

  @override
  RenderMessageBoard createRenderObject(BuildContext context) {
    return RenderMessageBoard(
      node: node,
      diameter: diameter,
      maxDiameter: maxDiameter,
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderMessageBoard renderObject) {
    renderObject
      ..node = node
      ..diameter = diameter
      ..maxDiameter = maxDiameter;
  }
}

class MessageBoardParentData extends ParentData with ContainerParentDataMixin<RenderWorld> { }

class RenderMessageBoard extends RenderWorldWithChildren<MessageBoardParentData> {
  RenderMessageBoard({
    required super.node,
    required double diameter,
    required double maxDiameter,
  }) : _diameter = diameter,
       _maxDiameter = maxDiameter;

  double get diameter => _diameter;
  double _diameter;
  set diameter (double value) {
    if (value != _diameter) {
      _diameter = value;
      markNeedsPaint();
    }
  }

  double get maxDiameter => _maxDiameter;
  double _maxDiameter;
  set maxDiameter (double value) {
    if (value != _maxDiameter) {
      _maxDiameter = value;
      markNeedsPaint();
    }
  }

  double get radius => diameter / 2.0;

  @override
  void setupParentData(RenderObject child) {
    if (child.parentData is! MessageBoardParentData) {
      child.parentData = MessageBoardParentData();
    }
  }

  @override
  void computeLayout(WorldConstraints constraints) {
    RenderWorld? child = firstChild;
    while (child != null) {
      final MessageBoardParentData childParentData = child.parentData! as MessageBoardParentData;
      child.layout(constraints);
      child = childParentData.nextSibling;
    }
  }

  @override
  WorldGeometry computePaint(PaintingContext context, Offset offset) {
    RenderWorld? child = firstChild;
    final double actualDiameter = computePaintDiameter(diameter, maxDiameter);
    while (child != null) {
      final MessageBoardParentData childParentData = child.parentData! as MessageBoardParentData;
      context.paintChild(child, constraints.paintPositionFor(child.node, offset, <VoidCallback>[markNeedsPaint]));
      child = childParentData.nextSibling;
    }
    return WorldGeometry(shape: Circle(actualDiameter));
  }

  @override
  WorldTapTarget? routeTap(Offset offset) {
    RenderWorld? child = lastChild;
    while (child != null) {
      final MessageBoardParentData childParentData = child.parentData! as MessageBoardParentData;
      final WorldTapTarget? result = child.routeTap(offset);
      if (result != null)
        return result;
      child = childParentData.previousSibling;
    }
    return null;
  }
}
