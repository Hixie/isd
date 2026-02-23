import 'package:flutter/rendering.dart' hide Gradient;
import 'package:flutter/widgets.dart' hide Gradient;

import '../assets.dart';
import '../icons.dart';
import '../layout.dart';
import '../widgets.dart';
import '../world.dart';

typedef SurfaceParameters = ({ Offset position });

class SurfaceFeature extends ContainerFeature {
  SurfaceFeature(this.children);

  // consider this read-only; the entire SurfaceFeature gets replaced when the child list changes
  final Map<AssetNode, SurfaceParameters> children;

  @override
  Offset findLocationForChild(AssetNode child, List<VoidCallback> callbacks) {
    return children[child]!.position;
  }

  @override
  void attach(Node parent) {
    super.attach(parent);
    for (AssetNode child in children.keys) {
      child.attach(this);
    }
  }

  @override
  void detach() {
    for (AssetNode child in children.keys) {
      if (child.parent == this)
        child.dispose();
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
  RendererType get rendererType => RendererType.overlay;

  @override
  Widget buildRenderer(BuildContext context) {
    return SurfaceWidget(
      node: parent,
      children: children.keys.map((AssetNode assetChild) => assetChild.build(context)).toList(),
    );
  }

  @override
  Widget buildDialog(BuildContext context) {
    final double fontSize = DefaultTextStyle.of(context).style.fontSize!;
    final IconsManager icons = IconsManagerProvider.of(context);
    return ListBody(
      children: <Widget>[
        const Text('Settlements', style: bold),
        Padding(
          padding: featurePadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (children.isEmpty)
                const Text('None', style: italic),
              for (AssetNode region in children.keys)
                Text.rich(
                  region.describe(context, icons, iconSize: fontSize),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class SurfaceWidget extends MultiChildRenderObjectWidget {
  const SurfaceWidget({
    super.key,
    required this.node,
    super.children,
  });

  final WorldNode node;

  @override
  RenderSurface createRenderObject(BuildContext context) {
    return RenderSurface(
      node: node,
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderSurface renderObject) {
    renderObject
      ..node = node;
  }
}

class SurfaceParentData extends ParentData with ContainerParentDataMixin<RenderWorld> {
  Offset? _computedPosition;
}

class RenderSurface extends RenderWorldWithChildren<SurfaceParentData> {
  RenderSurface({
    required super.node,
  });

  @override
  void setupParentData(RenderObject child) {
    if (child.parentData is! SurfaceParentData) {
      child.parentData = SurfaceParentData();
    }
  }

  @override
  void computeLayout(WorldConstraints constraints, double actualDiameter) {
    RenderWorld? child = firstChild;
    while (child != null) {
      final SurfaceParentData childParentData = child.parentData! as SurfaceParentData;
      child.layout(constraints);
      child = childParentData.nextSibling;
    }
  }

  @override
  void computePaint(PaintingContext context, Offset offset, double actualDiameter) {
    RenderWorld? child = firstChild;
    while (child != null) {
      final SurfaceParentData childParentData = child.parentData! as SurfaceParentData;
      childParentData._computedPosition = constraints.paintPositionFor(child.node, offset, <VoidCallback>[markNeedsPaint]);
      context.paintChild(child, childParentData._computedPosition!);
      child = childParentData.nextSibling;
    }
  }

  @override
  WorldTapTarget? routeTap(Offset offset) {
    RenderWorld? child = lastChild;
    while (child != null) {
      final SurfaceParentData childParentData = child.parentData! as SurfaceParentData;
      final WorldTapTarget? result = child.routeTap(offset);
      if (result != null)
        return result;
      child = childParentData.previousSibling;
    }
    return null;
  }
}
