import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'layout.dart';

class WorldLayoutBuilder extends ConstrainedLayoutBuilder<WorldConstraints> {
  const WorldLayoutBuilder({ super.key, required super.builder });

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderWorldLayoutBuilder();
}

class _RenderWorldLayoutBuilder extends RenderWorld
      with RenderObjectWithChildMixin<RenderWorld>, RenderConstrainedLayoutBuilder<WorldConstraints, RenderWorld> {
  _RenderWorldLayoutBuilder();

  @override
  WorldGeometry computeLayout(WorldConstraints constraints) {
    rebuildIfNecessary();
    if (child != null) {
      child!.layout(constraints.forChild(Offset.zero), parentUsesSize: true);
      return child!.geometry;
    }
    return WorldGeometry(shape: Circle(center: constraints.scaledPosition, diameter: 0.0));
  }

  @override
  bool hitTestChildren(WorldHitTestResult result, { required Offset position }) {
    return child?.hitTest(result, position: position) ?? false;
  }

  @override
  WorldTapTarget? routeTap(Offset offset) {
    return child?.routeTap(offset);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child != null) {
      context.paintChild(child!, offset);
    }
  }
}


class WorldNull extends LeafRenderObjectWidget {
  const WorldNull({
    super.key,
  });

  @override
  RenderWorldNull createRenderObject(BuildContext context) {
    return RenderWorldNull();
  }
}

class RenderWorldNull extends RenderWorld {
  RenderWorldNull();

  @override
  WorldGeometry computeLayout(WorldConstraints constraints) {
    return WorldGeometry(shape: Circle(center: constraints.scaledPosition, diameter: 0.0));
  }

  @override
  void paint(PaintingContext context, Offset offset) { }

  @override
  WorldTapTarget? routeTap(Offset offset) => null;
}
