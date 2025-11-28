import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart' hide Gradient;
import 'package:flutter/rendering.dart' hide Gradient;

import '../assetclasses.dart';
import '../assets.dart';
import '../icons.dart';
import '../layout.dart';
import '../nodes/system.dart';
import '../shaders.dart';
import '../spacetime.dart';
import '../widgets.dart';
import '../world.dart';

typedef Buildable = ({AssetClass assetClass, int size});
typedef GridParameters = ({int x, int y, int size});

class _GridState extends ChangeNotifier {
  AssetClass? get selection => _selection;
  AssetClass? _selection;
  set selection(AssetClass? value) {
    _selection = value;
    scheduleMicrotask(notifyListeners);
  }
}

class GridFeature extends ContainerFeature {
  GridFeature(this.cellSize, this.dimension, this.buildables, this.children);

  final double cellSize;
  final int dimension;

  final List<Buildable> buildables;

  // consider this read-only; the entire GridFeature gets replaced when the child list changes
  final Map<AssetNode, GridParameters> children;

  _GridState? _state;

  @override
  void init(Feature? oldFeature) {
    super.init(oldFeature);
    if (oldFeature is GridFeature) {
      _state = oldFeature._state;
    } else {
      _state = _GridState();
    }
  }

  @override
  Offset findLocationForChild(AssetNode child, List<VoidCallback> callbacks) {
    final GridParameters childData = children[child]!;
    return Offset(
      (childData.x + childData.size / 2.0 - dimension / 2.0) * cellSize,
      (childData.y + childData.size / 2.0 - dimension / 2.0) * cellSize,
    );
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
  RendererType get rendererType => RendererType.square;

  void _build(int x, int y) {
    final SystemNode system = SystemNode.of(this);
    system.play(<Object>[parent.id, 'build', x, y, _state!.selection!.id]);
  }

  @override
  Widget buildRenderer(BuildContext context) {
    return ListenableBuilder(
      listenable: _state!,
      builder: (BuildContext context, Widget? child) => GridWidget(
        spaceTime: SystemNode.of(parent).spaceTime,
        selection: _state!.selection,
        node: parent,
        cellSize: cellSize,
        dimension: dimension,
        children: children.keys.map((AssetNode node) => node.build(context)).toList(),
        onBuild: _state!.selection == null ? null : _build,
      ),
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
              if (buildables.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: ListenableBuilder(
                    listenable: _state!,
                    builder: (BuildContext context, Widget? child) => BuildableDish(
                      // TODO: let the user drag the palette out and close the inspector
                      assetClasses: buildables.map((Buildable buildable) => buildable.assetClass).toList(),
                      onSelect: (AssetClass? assetClass) => _state!.selection = assetClass,
                      selection: _state!.selection,
                    ),
                  ),
                ),
              if (children.isEmpty)
                Text('No structures present in ${parent.nameOrClassName}.', style: italic),
              for (AssetNode child in children.keys)
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

class BuildTile extends StatelessWidget {
  const BuildTile({
    super.key,
    required this.assetClass,
    required this.icons,
    required this.textTheme,
    this.onBuild,
  });

  final AssetClass assetClass;
  final IconsManager icons;
  final TextTheme textTheme;
  final VoidCallback? onBuild;

  @override
  Widget build(BuildContext context) {
    const double iconSize = 48.0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(0.0, 2.0, 0.0, 2.0),
      child: InkWell(
        onTap: onBuild,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(2.0, 6.0, 2.0, 6.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(0.0, 0.0, 12.0, 0.0),
                child: assetClass.asIcon(context, icons: icons, size: iconSize),
              ),
              Expanded(
                child: ListBody(
                  children: <Widget>[
                    Text(assetClass.name, style: textTheme.titleMedium),
                    Text(assetClass.description, style: textTheme.bodyMedium),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

typedef BuildCallback = void Function(int x, int y);

class GridWidget extends MultiChildRenderObjectWidget {
  const GridWidget({
    super.key,
    required this.spaceTime,
    required this.node,
    required this.cellSize,
    required this.dimension,
    required this.selection,
    required this.onBuild,
    super.children,
  });

  final SpaceTime spaceTime;
  final WorldNode node;
  final double cellSize;
  final int dimension;
  final BuildCallback? onBuild;
  final AssetClass? selection;

  @override
  RenderGrid createRenderObject(BuildContext context) {
    return RenderGrid(
      spaceTime: spaceTime,
      shaders: ShaderProvider.of(context),
      node: node,
      cellSize: cellSize,
      dimension: dimension,
      onBuild: onBuild,
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderGrid renderObject) {
    renderObject
      ..spaceTime = spaceTime
      ..shaders = ShaderProvider.of(context)
      ..node = node
      ..cellSize = cellSize
      ..dimension = dimension
      ..onBuild = onBuild;
  }
}

class GridParentData extends ParentData with ContainerParentDataMixin<RenderWorld> {
  Offset? _computedPosition;
}

class RenderGrid extends RenderWorldWithChildren<GridParentData> {
  RenderGrid({
    required SpaceTime spaceTime,
    required ShaderLibrary shaders,
    required super.node,
    required double cellSize,
    required int dimension,
    required this.onBuild,
  }) : _spaceTime = spaceTime,
       _shaders = shaders,
       _cellSize = cellSize,
       _dimension = dimension;

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

  int get dimension => _dimension;
  int _dimension;
  set dimension (int value) {
    if (value != _dimension) {
      _dimension = value;
      _gridShader = null;
      markNeedsPaint();
    }
  }

  BuildCallback? onBuild;

  double get diameter => dimension * cellSize;

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
  double computePaint(PaintingContext context, Offset offset) {
    _gridShader ??= shaders.grid(height: dimension, width: dimension);
    final double time = spaceTime.computeTime(<VoidCallback>[markNeedsPaint]);
    final double diameter = this.diameter; // cache computation
    _gridShader!.setFloat(uT, time);
    _gridShader!.setFloat(uX, offset.dx);
    _gridShader!.setFloat(uY, offset.dy);
    _gridShader!.setFloat(uGridWidth, diameter * constraints.scale);
    _gridShader!.setFloat(uGridHeight, diameter * constraints.scale);
    _gridPaint.shader = _gridShader;
    final Rect rect = Rect.fromCircle(center: offset, radius: diameter * constraints.scale / 2.0);
    context.canvas.drawRect(rect, _gridPaint);
    RenderWorld? child = firstChild;
    while (child != null) {
      final GridParentData childParentData = child.parentData! as GridParentData;
      childParentData._computedPosition = constraints.paintPositionFor(child.node, offset, <VoidCallback>[markNeedsPaint]);
      context.paintChild(child, childParentData._computedPosition!);
      child = childParentData.nextSibling;
    }
    return diameter * constraints.scale;
  }

  @override
  WorldTapTarget? routeTap(Offset offset) {
    if (!isInsideSquare(offset))
      return null;
    RenderWorld? child = lastChild;
    while (child != null) {
      final GridParentData childParentData = child.parentData! as GridParentData;
      final WorldTapTarget? result = child.routeTap(offset);
      if (result != null)
        return result;
      child = childParentData.previousSibling;
    }
    if (onBuild != null) {
      final double radius = paintDiameter / 2.0;
      final Offset topLeft = paintCenter.translate(-radius, -radius);
      return _GridTapTarget((offset - topLeft) / (paintDiameter / dimension), onBuild!);
    }
    return null;
  }
}

class _GridTapTarget implements WorldTapTarget {
  _GridTapTarget(this.offset, this.onBuild);

  final Offset offset;
  final BuildCallback onBuild;

  @override
  void handleTapDown() {
    onBuild(offset.dx.truncate(), offset.dy.truncate());
  }

  @override
  void handleTapCancel() {
  }

  @override
  void handleTapUp() {
  }
}
