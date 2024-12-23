import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'layout.dart';
import 'world.dart';

final CurveTween hudTween = CurveTween(curve: Curves.ease);
const Duration hudAnimationDuration = Duration(milliseconds: 250);
const double hudAnimationPauseLength = 75.0; // TODO: convert this to a duration

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
  WorldGeometry computePaint(PaintingContext context, Offset offset) {
    if (child != null) {
      context.paintChild(child!, offset);
      return child!.geometry;
    }
    return const WorldGeometry(shape: Circle(0.0));
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, { required Offset position }) {
    return child?.hitTestChildren(result, position: position) ?? false;
  }

  @override
  WorldTapTarget? routeTap(Offset offset) {
    return child?.routeTap(offset);
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
  bool hitTestChildren(BoxHitTestResult result, { required Offset position }) {
    return false;
  }

  @override
  WorldTapTarget? routeTap(Offset offset) => null;
}


typedef TickerProviderWidgetBuilder = Widget Function(BuildContext context, TickerProvider vsync);

class TickerProviderBuilder extends StatefulWidget {
  const TickerProviderBuilder({ super.key, required this.builder });

  final TickerProviderWidgetBuilder builder;

  @override
  State<TickerProviderBuilder> createState() => _TickerProviderBuilderState();
}

class _TickerProviderBuilderState extends State<TickerProviderBuilder> with TickerProviderStateMixin {
  @override
  Widget build(BuildContext context) {
    return widget.builder(context, this);
  }
}

class Sizer extends StatelessWidget {
  const Sizer({
    super.key,
    this.skipSize = const Size.square(8.0),
    this.minSize = const Size.square(224.0),
    this.maxSize = const Size.square(350.0),
    required this.child,
    this.placeholder = const Placeholder(),
  });

  final Size skipSize;
  final Size minSize;
  final Size maxSize;

  final Widget child;
  final Widget placeholder;
  
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final Size requested = constraints.biggest;
        if ((requested.width < skipSize.width) ||
            (requested.height < skipSize.height)) {
          return placeholder;
        }
        return FittedBox(
          child: SizedBox(
            width: requested.width.clamp(minSize.width, maxSize.width),
            height: requested.height.clamp(minSize.height, maxSize.height),
            child: child,
          ),
        );
      },
    );
  }
}
