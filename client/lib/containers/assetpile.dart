import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../assets.dart';
import '../icons.dart';
import '../layout.dart';
import '../widgets.dart';
import '../world.dart';

class AssetPileFeature extends ContainerFeature {
  AssetPileFeature(this.children);

  // consider this read-only; the entire AssetPileFeature gets replaced when the child list changes
  final List<AssetNode> children;

  @override
  Offset findLocationForChild(AssetNode child, List<VoidCallback> callbacks) {
    // final AssetPileParameters childData = children[child]!;
    // TODO: offset children pseudo-randomly
    return Offset.zero;
  }

  @override
  void attach(Node parent) {
    super.attach(parent);
    for (AssetNode child in children) {
      child.attach(this);
    }
  }

  @override
  void detach() {
    for (AssetNode child in children) {
      if (child.parent == this)
        child.dispose();
    }
    super.detach();
  }

  @override
  void walk(WalkCallback callback) {
    for (AssetNode child in children) {
      child.walk(callback);
    }
  }

  @override
  RendererType get rendererType => RendererType.square;

  @override
  Widget buildRenderer(BuildContext context) {
    return AssetPileWidget(
      node: parent,
      children: children.map((AssetNode child) => child.build(context)).toList(),
    );
  }

  @override
  Widget buildDialog(BuildContext context) {
    final double fontSize = DefaultTextStyle.of(context).style.fontSize!;
    final IconsManager icons = IconsManagerProvider.of(context);
    return ListBody(
      children: <Widget>[
        const Text('Junk pile', style: bold),
        Padding(
          padding: featurePadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (children.isEmpty)
                const Text('Empty', style: italic),
              for (AssetNode child in children)
                Text.rich(
                  child.describe(context, icons, iconSize: fontSize),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class AssetPileWidget extends MultiChildRenderObjectWidget {
  const AssetPileWidget({
    super.key,
    required this.node,
    super.children,
  });

  final WorldNode node;

  @override
  RenderAssetPile createRenderObject(BuildContext context) {
    return RenderAssetPile(
      node: node,
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderAssetPile renderObject) {
    renderObject
      ..node = node;
  }
}

class AssetPileParentData extends ParentData with ContainerParentDataMixin<RenderWorld> {
  Offset? childPosition;
}

class RenderAssetPile extends RenderWorldWithChildren<AssetPileParentData> {
  RenderAssetPile({
    required super.node,
  });

  @override
  void setupParentData(RenderObject child) {
    if (child.parentData is! AssetPileParentData) {
      child.parentData = AssetPileParentData();
    }
  }

  @override
  void computeLayout(WorldConstraints constraints, double actualDiameter) {
    RenderWorld? child = firstChild;
    while (child != null) {
      final AssetPileParentData childParentData = child.parentData! as AssetPileParentData;
      child.layout(constraints);
      child = childParentData.nextSibling;
    }
  }

  @override
  void computePaint(PaintingContext context, Offset offset, double actualDiameter) {
    RenderWorld? child = firstChild;
    while (child != null) {
      final AssetPileParentData childParentData = child.parentData! as AssetPileParentData;
      childParentData.childPosition = constraints.paintPositionFor(child.node, offset, <VoidCallback>[markNeedsPaint]);
      context.paintChild(child, childParentData.childPosition!);
      child = childParentData.nextSibling;
    }
  }

  @override
  WorldTapTarget? routeTap(Offset offset) {
    if (!isInsideSquare(offset))
      return null;
    RenderWorld? child = lastChild;
    while (child != null) {
      final AssetPileParentData childParentData = child.parentData! as AssetPileParentData;
      final WorldTapTarget? result = child.routeTap(offset);
      if (result != null)
        return result;
      child = childParentData.previousSibling;
    }
    return null;
  }
}
