import 'package:flutter/rendering.dart' hide Gradient;
import 'package:flutter/widgets.dart' hide Gradient;

import '../assets.dart';
import '../icons.dart';
import '../layout.dart';
import '../widgets.dart';
import '../world.dart';

class ProxyFeature extends ContainerFeature {
  ProxyFeature(this.child);

  final AssetNode? child;

  @override
  Offset findLocationForChild(AssetNode child, List<VoidCallback> callbacks) {
    assert(child == this.child);
    return Offset.zero;
  }

  @override
  void attach(Node parent) {
    super.attach(parent);
    if (child != null)
      child!.attach(this);
  }

  @override
  void detach() {
    if (child?.parent == this)
      child!.dispose();
    super.detach();
  }

  @override
  void walk(WalkCallback callback) {
    if (child != null) {
      child!.walk(callback);
    }
  }

  @override
  RendererType get rendererType => RendererType.overlay;

  @override
  Widget buildRenderer(BuildContext context) {
    return ProxyWidget(
      node: parent,
      child: child?.build(context),
    );
  }

  @override
  Widget buildDialog(BuildContext context) {
    final double fontSize = DefaultTextStyle.of(context).style.fontSize!;
    final IconsManager icons = IconsManagerProvider.of(context);
    return ListBody(
      children: <Widget>[
        const Text('Structures', style: bold),
        Padding(
          padding: featurePadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (child == null)
                const Text('None', style: italic),
              if (child != null)
                Text.rich(
                  child!.describe(context, icons, iconSize: fontSize),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class ProxyWidget extends SingleChildRenderObjectWidget {
  const ProxyWidget({
    super.key,
    required this.node,
    super.child,
  });

  final WorldNode node;

  @override
  RenderProxy createRenderObject(BuildContext context) {
    return RenderProxy(
      node: node,
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderProxy renderObject) {
    renderObject
      ..node = node;
  }
}

class RenderProxy extends RenderWorldNode with RenderObjectWithChildMixin<RenderWorld> {
  RenderProxy({
    required super.node,
  });

  @override
  void computeLayout(WorldConstraints constraints, double actualDiameter) {
    if (child != null) {
      child!.layout(constraints);
    }
  }

  Offset? _childPosition;

  @override
  void computePaint(PaintingContext context, Offset offset, actualDiameter) {
    if (child != null) {
      // TODO: position the child based on the icon's fields
      // one of the modes should be to center the child's bottom
      // (use this to make crater look better)
      _childPosition = constraints.paintPositionFor(child!.node, offset, <VoidCallback>[markNeedsPaint]);
      context.paintChild(child!, _childPosition!);
    }
  }

  @override
  WorldTapTarget? routeTap(Offset offset) {
    if (child != null) {
      final WorldTapTarget? result = child!.routeTap(offset); // TODO: correct offset
      if (result != null)
        return result;
    }
    return null;
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, { required Offset position }) {
    bool hit = false;
    if (child != null) {
      hit = hit || child!.hitTestChildren(result, position: position);
    }
    return hit;
  }
}
