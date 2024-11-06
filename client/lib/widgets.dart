import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'layout.dart';
import 'world.dart';

class WorldLayoutBuilder extends ConstrainedLayoutBuilder<WorldConstraints> {
  const WorldLayoutBuilder({ super.key, required super.builder });

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderWorldLayoutBuilder();
}

class _RenderWorldLayoutBuilder extends RenderWorld
      with RenderObjectWithChildMixin<RenderWorld>, RenderConstrainedLayoutBuilder<WorldConstraints, RenderWorld> {
  _RenderWorldLayoutBuilder();

  @override
  WorldNode get node => child!.node;

  @override
  void computeLayout(WorldConstraints constraints) {
    rebuildIfNecessary();
    if (child != null) {
      child!.layout(constraints, parentUsesSize: true);
    }
  }

  @override
  WorldTapTarget? routeTap(Offset offset) {
    return child?.routeTap(offset);
  }

  @override
  WorldGeometry computePaint(PaintingContext context, Offset offset) {
    if (child != null) {
      context.paintChild(child!, offset);
      return child!.geometry;
    }
    return const WorldGeometry(shape: Circle(0.0));
  }
}

class WorldNull extends LeafRenderObjectWidget {
  const WorldNull({
    super.key,
    required this.node,
  });

  final WorldNode node;
  
  @override
  RenderWorldNull createRenderObject(BuildContext context) {
    return RenderWorldNull(node: node);
  }
}

class RenderWorldNull extends RenderWorldNode {
  RenderWorldNull({ required super.node });

  @override
  void computeLayout(WorldConstraints constraints) { }

  @override
  WorldGeometry computePaint(PaintingContext context, Offset offset) {
    return const WorldGeometry(shape: Circle(0.0));
  }

  @override
  WorldTapTarget? routeTap(Offset offset) => null;
}
