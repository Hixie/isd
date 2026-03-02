import 'dart:ui';

import 'package:flutter/material.dart' hide Gradient;
import 'package:flutter/rendering.dart' hide Gradient;

import '../assetclasses.dart';
import '../assets.dart';
import '../dock.dart';
import '../icons.dart';
import '../layout.dart';
import '../nodes/system.dart';
import '../shaders.dart';
import '../spacetime.dart';
import '../widgets.dart';
import '../world.dart';

typedef Buildable = ({AssetClass assetClass, int size});
typedef GridParameters = ({int x, int y, int size});

// TODO: when the connection drops, we create new AssetClass instances, but we don't update the _GridState's selection

class _GridState extends ChangeNotifier {
  _GridState(this._feature, this._selection);
  
  GridFeature get feature => _feature;
  GridFeature _feature;
  set feature(GridFeature feature) {
    _feature = feature;
    notifyListeners();
  }
  
  AssetClass? get selection => _selection;
  AssetClass? _selection;
  set selection(AssetClass? value) {
    _selection = value;
    notifyListeners();
  }

  Widget? buildDock(BuildContext context, double height) {
    if (feature.buildables.isEmpty)
      return null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: ListenableBuilder(
        listenable: this,
        builder: (BuildContext context, Widget? child) {
          return BuildableDish(
            label: feature.parent.nameOrClassName,
            assetClasses: feature.buildables.map((Buildable buildable) => buildable.assetClass).toList(),
            onSelect: (AssetClass? assetClass) => selection = assetClass,
            selection: selection,
          );
        },
      ),
    );
  }
}

class GridFeature extends ContainerFeature {
  GridFeature(this.cellSize, this.dimension, Set<Buildable> buildables, this.assetClassMap, this.children) : buildables = buildables.toList()..sort(_sortBuildables);

  static int _sortBuildables(Buildable a, Buildable b) {
    return a.assetClass.name.compareTo(b.assetClass.name);
  }
  
  final double cellSize;
  final int dimension;

  final List<Buildable> buildables;
  final AssetClassMap assetClassMap;

  // consider this read-only; the entire GridFeature gets replaced when the child list changes
  final Map<AssetNode, GridParameters> children;

  _GridState? _state;

  @override
  void init(Feature? oldFeature) {
    super.init(oldFeature);
    if (oldFeature is GridFeature) {
      _state = oldFeature._state;
      _state!.feature = this;
      if (_state!._selection != null) {
        _state!._selection = assetClassMap.assetClass(_state!._selection!.id);
      }
    } else {
      _state = _GridState(this, null);
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

  DockHandle? _dock;

  @override
  Widget buildRenderer(BuildContext context, double paintDiameter) {
    final SystemNode system = SystemNode.of(this);
    final int assetID = parent.id;
    return StateManagerBuilder<_GridState>(
      creator: () {
        _dock = DockProvider.add(context, this);
        return _state!;
      },
      disposer: (_GridState state) {
        _dock!.dismiss();
        _dock = null;
      },
      builder: (BuildContext context, _GridState value) => GridWidget(
        spaceTime: SystemNode.of(parent).spaceTime,
        selection: _state!.selection,
        node: parent,
        cellSize: cellSize,
        dimension: dimension,
        paintDiameter: paintDiameter,
        children: children.keys.map((AssetNode node) => node.build(context)).toList(),
        onBuild: _state!.selection == null ? null : (int x, int y) {
          system.play(<Object>[assetID, 'build', x, y, _state!.selection!.id]);
        },
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
                Text('Can build ${buildables.length} types of structures.'), // TODO: singular
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

  @override
  Widget? buildDock(BuildContext context, double height) => _state!.buildDock(context, height);
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
    required this.paintDiameter,
    super.children,
  });

  final SpaceTime spaceTime;
  final WorldNode node;
  final double cellSize;
  final int dimension;
  final BuildCallback? onBuild;
  final AssetClass? selection;
  final double paintDiameter;

  @override
  RenderGrid createRenderObject(BuildContext context) {
    return RenderGrid(
      spaceTime: spaceTime,
      shaders: ShaderProvider.of(context),
      node: node,
      cellSize: cellSize,
      dimension: dimension,
      onBuild: onBuild,
      paintDiameter: paintDiameter,
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
      ..onBuild = onBuild
      ..paintDiameter = paintDiameter;
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
    required super.paintDiameter,
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
  void computePaint(PaintingContext context, Offset offset) {
    _gridShader ??= shaders.grid(height: dimension, width: dimension);
    final double time = spaceTime.computeTime(<VoidCallback>[markNeedsPaint]);
    _gridShader!.setFloat(uT, time);
    _gridShader!.setFloat(uX, offset.dx);
    _gridShader!.setFloat(uY, offset.dy);
    _gridShader!.setFloat(uGridWidth, paintDiameter);
    _gridShader!.setFloat(uGridHeight, paintDiameter);
    _gridPaint.shader = _gridShader;
    final Rect rect = Rect.fromCircle(center: offset, radius: paintDiameter / 2.0);
    context.canvas.drawRect(rect, _gridPaint);
    RenderWorld? child = firstChild;
    while (child != null) {
      final GridParentData childParentData = child.parentData! as GridParentData;
      childParentData._computedPosition = constraints.paintPositionFor(child.node, offset, <VoidCallback>[markNeedsPaint]);
      context.paintChild(child, childParentData._computedPosition!);
      child = childParentData.nextSibling;
    }
  }

  @override
  WorldTapTarget? computeTap(Offset offset) {
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
