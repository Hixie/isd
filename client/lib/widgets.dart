import 'dart:math' show sqrt;

import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'assetclasses.dart';
import 'icons.dart';
import 'layout.dart';
import 'materials.dart';
import 'world.dart';

final CurveTween hudTween = CurveTween(curve: Curves.ease);
const Duration hudAnimationDuration = Duration(milliseconds: 250);
const double hudAnimationPauseLength = 75.0; // TODO: convert this to a duration

const TextStyle bold = TextStyle(fontWeight: FontWeight.bold);
const TextStyle italic = TextStyle(fontStyle: FontStyle.italic);

class WorldLayoutBuilder extends ConstrainedLayoutBuilder<WorldConstraints> {
  const WorldLayoutBuilder({ super.key, required super.builder });

  @override
  RenderAbstractLayoutBuilderMixin<WorldConstraints, RenderWorld> createRenderObject(BuildContext context) => _RenderWorldLayoutBuilder();
}

class _RenderWorldLayoutBuilder extends RenderWorld
      with RenderObjectWithChildMixin<RenderWorld>,
           RenderObjectWithLayoutCallbackMixin,
           RenderAbstractLayoutBuilderMixin<WorldConstraints, RenderWorld> {
  _RenderWorldLayoutBuilder();

  @override
  WorldNode get node => child!.node;

  @override
  void computeLayout(WorldConstraints constraints) {
    runLayoutCallback();
    if (child != null) {
      child!.layout(constraints, parentUsesSize: true);
    }
  }

  @override
  double computePaint(PaintingContext context, Offset offset) {
    if (child != null) {
      context.paintChild(child!, offset);
      return child!.paintBounds.width;
    }
    return 0.0;
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
  double computePaint(PaintingContext context, Offset offset) {
    return 0.0;
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

typedef StateManagerWidgetBuilder<T> = Widget Function(BuildContext context, T value);

class StateManagerBuilder<T extends Listenable> extends StatefulWidget {
  const StateManagerBuilder({
    super.key,
    required this.creator,
    required this.builder,
    required this.disposer,
  });

  final ValueGetter<T> creator;
  final StateManagerWidgetBuilder<T> builder;
  final ValueSetter<T> disposer;

  @override
  State<StateManagerBuilder<T>> createState() => _StateManagerState<T>();
}

class _StateManagerState<T extends Listenable> extends State<StateManagerBuilder<T>> {
  T? _value;

  @override
  void initState() {
    super.initState();
    _value = widget.creator();
    _value!.addListener(_update);
  }

  @override
  void dispose() {
    _value!.removeListener(_update);
    widget.disposer(_value!);
    super.dispose();
  }

  void _update() {
    setState(() { /* value changed */ });
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(context, _value!);
  }
}

@Deprecated('Unused')
class Sizer extends StatelessWidget {
  @Deprecated('Unused')
  const Sizer({
    super.key,
    this.skipSize = const Size.square(4.0),
    this.minSize = const Size.square(224.0),
    this.maxSize = const Size.square(350.0),
    required this.child,
    this.placeholder = const Placeholder(color: Color(0x7FCCCCCC)),
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

class WorldBoxGrid extends MultiChildRenderObjectWidget {
  const WorldBoxGrid({
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
  RenderWorldBoxGrid createRenderObject(BuildContext context) {
    return RenderWorldBoxGrid(
      node: node,
      diameter: diameter,
      maxDiameter: maxDiameter,
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderWorldBoxGrid renderObject) {
    renderObject
      ..node = node
      ..diameter = diameter
      ..maxDiameter = maxDiameter;
  }
}

class WorldBoxGridParentData extends ContainerBoxParentData<RenderBox> {
  Offset? _computedPosition;
}

class RenderWorldBoxGrid extends RenderWorldNode with ContainerRenderObjectMixin<RenderBox, WorldBoxGridParentData>, RenderBoxContainerDefaultsMixin<RenderBox, WorldBoxGridParentData> {
  RenderWorldBoxGrid({
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
      markNeedsLayout();
    }
  }

  double get maxDiameter => _maxDiameter;
  double _maxDiameter;
  set maxDiameter (double value) {
    if (value != _maxDiameter) {
      _maxDiameter = value;
      markNeedsLayout();
    }
  }

  @override
  void setupParentData(RenderObject child) {
    if (child.parentData is! WorldBoxGridParentData) {
      child.parentData = WorldBoxGridParentData();
    }
  }

  int? _cellCount;
  double? _actualDiameter;
  double? _cellSize;

  @override
  void computeLayout(WorldConstraints constraints) {
    final int count = childCount;
    _cellCount = sqrt(count).ceil();
    _actualDiameter = computePaintDiameter(diameter, maxDiameter);
    _cellSize = _actualDiameter! / _cellCount!;
    final BoxConstraints childConstraints = BoxConstraints.tightFor(width: _cellSize, height: _cellSize);
    RenderBox? child = firstChild;
    while (child != null) {
      final WorldBoxGridParentData childParentData = child.parentData! as WorldBoxGridParentData;
      child.layout(childConstraints);
      child = childParentData.nextSibling;
    }
  }

  @override
  double computePaint(PaintingContext context, Offset offset) {
    RenderBox? child = firstChild;
    double x = 0;
    double y = 0;
    while (child != null) {
      final WorldBoxGridParentData childParentData = child.parentData! as WorldBoxGridParentData;
      final Offset childOffset = offset + Offset(x * _cellSize!, y * _cellSize!);
      childParentData._computedPosition = childOffset.translate(-_cellSize! / 2.0, -_cellSize! / 2.0);
      if (debugPaintSizeEnabled) {
        context.canvas.drawRect(childParentData._computedPosition! & Size.square(_cellSize!), Paint()..color=const Color(0xFFFFFF00)..strokeWidth=1..style=PaintingStyle.stroke);
      }
      context.paintChild(child, childParentData._computedPosition!);
      child = childParentData.nextSibling;
      x += 1;
      if (x >= _cellCount!) {
        x = 0;
        y += 1;
      }
    }
    if (debugPaintSizeEnabled) {
      context.canvas.drawRect(Rect.fromCircle(center: offset, radius: _actualDiameter! / 2.0), Paint()..color=const Color(0x7FFF00FF)..strokeWidth=2..style=PaintingStyle.stroke);
    }
    return _actualDiameter!;
  }

  @override
  WorldTapTarget? routeTap(Offset offset) {
    return null; // TODO: figure out what this should do, if anything
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, { required Offset position }) {
    return defaultHitTestChildren(result, position: position);
  }
}

class WorldStack extends MultiChildRenderObjectWidget {
  const WorldStack({
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
  RenderWorldStack createRenderObject(BuildContext context) {
    return RenderWorldStack(
      node: node,
      diameter: diameter,
      maxDiameter: maxDiameter,
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderWorldStack renderObject) {
    renderObject
      ..node = node
      ..diameter = diameter
      ..maxDiameter = maxDiameter;
  }
}

class StackParentData extends ParentData with ContainerParentDataMixin<RenderWorld> { }

class RenderWorldStack extends RenderWorldWithChildren<StackParentData> {
  RenderWorldStack({
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
      markNeedsLayout();
    }
  }

  double get maxDiameter => _maxDiameter;
  double _maxDiameter;
  set maxDiameter (double value) {
    if (value != _maxDiameter) {
      _maxDiameter = value;
      markNeedsLayout();
    }
  }

  @override
  void setupParentData(RenderObject child) {
    if (child.parentData is! StackParentData) {
      child.parentData = StackParentData();
    }
  }

  @override
  void computeLayout(WorldConstraints constraints) {
    RenderWorld? child = firstChild;
    while (child != null) {
      final StackParentData childParentData = child.parentData! as StackParentData;
      child.layout(constraints);
      child = childParentData.nextSibling;
    }
  }

  @override
  double computePaint(PaintingContext context, Offset offset) {
    // TODO: apply maxDiameter (ideally by refactoring it so they all do)
    RenderWorld? child = firstChild;
    while (child != null) {
      final StackParentData childParentData = child.parentData! as StackParentData;
      context.paintChild(child, offset);
      child = childParentData.nextSibling;
    }
    return diameter * constraints.scale;
  }

  @override
  WorldTapTarget? routeTap(Offset offset) {
    RenderWorld? child = lastChild;
    while (child != null) {
      final StackParentData childParentData = child.parentData! as StackParentData;
      final WorldTapTarget? result = child.routeTap(offset);
      if (result != null)
        return result;
      child = childParentData.previousSibling;
    }
    return null;
  }
}

class WorldToBoxAdapter extends SingleChildRenderObjectWidget {
  const WorldToBoxAdapter({
    super.key,
    required this.node,
    required this.diameter,
    required this.maxDiameter,
    super.child,
  });

  final WorldNode node;
  final double diameter;
  final double maxDiameter;

  @override
  RenderWorldToBoxAdapter createRenderObject(BuildContext context) {
    return RenderWorldToBoxAdapter(
      node: node,
      diameter: diameter,
      maxDiameter: maxDiameter,
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderWorldToBoxAdapter renderObject) {
    renderObject
      ..node = node
      ..diameter = diameter
      ..maxDiameter = maxDiameter;
  }
}

class RenderWorldToBoxAdapter extends RenderWorldNode with RenderObjectWithChildMixin<RenderBox> {
  RenderWorldToBoxAdapter({
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

  double _actualDiameter = 0.0;

  @override
  void computeLayout(WorldConstraints constraints) {
    _actualDiameter = computePaintDiameter(diameter, maxDiameter);
    if (child != null) {
      child!.layout(BoxConstraints.tight(Size.square(_actualDiameter)));
    }
  }

  Offset? _childPosition;

  @override
  double computePaint(PaintingContext context, Offset offset) {
    _childPosition = Offset(offset.dx - _actualDiameter / 2.0, offset.dy - _actualDiameter / 2.0);
    context.paintChild(child!, _childPosition!);
    if (debugPaintSizeEnabled) {
      context.canvas.drawRect(_childPosition! & Size.square(_actualDiameter), Paint()..color=const Color(0x7FFFFF00)..strokeWidth=10..style=PaintingStyle.stroke);
    }
    return _actualDiameter;
  }

  @override
  void applyPaintTransform(covariant RenderObject child, Matrix4 transform) {
    // This assumes that 0,0 is the center of the canvas, and that the transform is transforming to that.
    transform.translateByDouble(_childPosition!.dx, _childPosition!.dy, 0.0, 1.0);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, { required Offset position }) {
    return result.addWithPaintOffset(offset: _childPosition, position: position, hitTest: _hitTestChild);
  }

  bool _hitTestChild(BoxHitTestResult result, Offset offset) {
    return child!.hitTest(result, position: offset);
  }

  @override
  WorldTapTarget? routeTap(Offset offset) {
    return null; // we don't tap into the RenderBox world
  }
}

class NoZoom extends StatelessWidget {
  const NoZoom({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerSignal: (PointerSignalEvent event) {
        GestureBinding.instance.pointerSignalResolver.register(event, (PointerSignalEvent event) {
          // eat the signal so it doesn't zoom something behind us
        });
      },
      child: child,
    );
  }
}

class KnowledgeDish extends StatelessWidget {
  const KnowledgeDish({super.key, this.assetClasses = const <AssetClass>[], this.materials = const <Material>[]});

  final List<AssetClass> assetClasses;
  final List<Material> materials;

  @override
  Widget build(BuildContext context) {
    const double padding = 12.0;
    return ClipRRect(
      borderRadius: BorderRadius.circular(padding),
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: ShapeDecoration(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(padding),
            side: const BorderSide(),
          ),

        ),
        child: DecoratedBox(
          decoration: ShapeDecoration(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(padding),
            ),
            shadows: const <BoxShadow>[
              BoxShadow(
                color: Color(0x33000000),
              ),
              BoxShadow(
                offset: Offset(padding / 2.0, padding / 2.0),
                blurRadius: padding / 2.0,
                color: Color(0xFFFFFFFF),
              ),
            ],
          ),
          child: SizedBox(
            height: IconsManager.knowledgeIconSize + padding * 2,
            child: ListView(
              // TODO: scrollbar?
              scrollDirection: Axis.horizontal,
              children: <Widget>[
                for (AssetClass assetClass in assetClasses)
                  Padding(
                    key: ObjectKey(assetClass),
                    padding: const EdgeInsets.only(left: padding, top: padding, bottom: padding),
                    child: assetClass.asKnowledgeIcon(context),
                  ),
                for (Material material in materials)
                  Padding(
                    key: ObjectKey(material),
                    padding: const EdgeInsets.only(left: padding, top: padding, bottom: padding),
                    child: material.asKnowledgeIcon(context),
                  ),
                const SizedBox(width: padding),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
