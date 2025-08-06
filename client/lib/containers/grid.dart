import 'dart:async';
import 'dart:math' show max;
import 'dart:ui';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide Gradient;
import 'package:flutter/rendering.dart' hide Gradient;

import '../assetclasses.dart';
import '../assets.dart';
import '../hud.dart';
import '../icons.dart';
import '../layout.dart';
import '../nodes/system.dart';
import '../shaders.dart';
import '../spacetime.dart';
import '../stringstream.dart';
import '../widgets.dart';
import '../world.dart';

typedef GridParameters = ({int x, int y}); // could also just store this as an index, and use half the memory

class GridFeature extends ContainerFeature {
  GridFeature(this.cellSize, this.width, this.height, this.children);

  final double cellSize;
  final int width;
  final int height;

  // consider this read-only; the entire GridFeature gets replaced when the child list changes
  final Map<AssetNode, GridParameters> children;

  @override
  Offset findLocationForChild(AssetNode child, List<VoidCallback> callbacks) {
    final GridParameters childData = children[child]!;
    return Offset(
      (childData.x - width / 2 + 0.5) * cellSize,
      (childData.y - height / 2 + 0.5) * cellSize,
    );
  }

  @override
  void attach(AssetNode parent) {
    super.attach(parent);
    for (AssetNode child in children.keys) {
      child.attach(parent);
    }
  }

  @override
  void detach() {
    for (AssetNode child in children.keys) {
      if (child.parent == parent) {
        child.detach();
        // if its parent is not the same as our parent,
        // then maybe it was already added to some other container
      }
    }
    super.detach();
  }

  @override
  void walk(WalkCallback callback) {
    for (AssetNode child in children.keys) {
      assert(child.parent == parent);
      child.walk(callback);
    }
  }

  @override
  RendererType get rendererType => RendererType.square;

  @override
  Widget buildRenderer(BuildContext context) {
    final List<Widget> childList = List<Widget>.generate(width * height, (int index) => DefaultGridCell(
      key: ValueKey<int>(index),
      diameter: cellSize,
      maxDiameter: parent.diameter,
      node: parent,
      x: index % width,
      y: index ~/ width,
    ));
    for (AssetNode child in children.keys) {
      final GridParameters parameters = children[child]!;
      childList[parameters.y * width + parameters.x] = child.build(context);
    }
    return GridWidget(
      spaceTime: SystemNode.of(parent).spaceTime,
      node: parent,
      cellSize: cellSize,
      width: width,
      height: height,
      children: childList,
    );
  }
}

class DefaultGridCell extends StatelessWidget {
  const DefaultGridCell({
    super.key,
    required this.node,
    required this.diameter,
    required this.maxDiameter,
    required this.x,
    required this.y,
  });

  final AssetNode node;
  final double diameter;
  final double maxDiameter;
  final int x;
  final int y;

  @override
  Widget build(BuildContext context) {
    return WorldToBoxAdapter(
      node: node,
      diameter: diameter,
      maxDiameter: maxDiameter,
      child: CellBuildButton(node: node, x: x, y: y),
    );
  }
}

class CellBuildButton extends StatefulWidget {
  const CellBuildButton({
    super.key,
    required this.node,
    required this.x,
    required this.y,
  });

  final AssetNode node;
  final int x;
  final int y;

  @override
  State<CellBuildButton> createState() => _CellBuildButtonState();
}

class _CellBuildButtonState extends State<CellBuildButton> {
  static const Duration _duration = Duration(milliseconds: 160);

  bool _hover = false;
  bool _tap = false;

  Timer? _tapTimer;

  void _resetTap() {
    setState(() {
        _tap = false;
    });
    _tapTimer?.cancel();
    _tapTimer = null;
  }

  void _startTap() {
    if (!_tap) {
      setState(() {
        _tap = true;
      });
    }
    _tapTimer?.cancel();
    _tapTimer = null;
  }

  void _endTap() {
    _tapTimer?.cancel();
    _tapTimer = Timer(_duration, _resetTap);
  }

  HudHandle? _build;

  void _triggerBuild() {
    _build = HudProvider.add(context, const Size(480.0, 512.0), HudDialog(
       heading: const Text('Build'),
       child: BuildUi(
         system: SystemNode.of(widget.node),
         node: widget.node,
         x: widget.x,
         y: widget.y,
       ),
    ));
  }

  @override
  void dispose() {
    _build?.cancel();
    _tapTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      hitTestBehavior: HitTestBehavior.deferToChild,
      onEnter: (PointerEnterEvent event) { setState(() { _hover = true; }); },
      onExit: (PointerExitEvent event) { setState(() { _hover = false; }); },
      cursor: SystemMouseCursors.contextMenu, // TODO: use an image
      child: GestureDetector(
        onTapDown: (TapDownDetails details) { _startTap(); },
        onTapCancel: _resetTap,
        onTapUp: (TapUpDetails details) { _endTap(); },
        onTap: _triggerBuild,
        child: FittedBox(
          child: SizedBox(
            width: 100.0,
            height: 100.0,
            child: Padding(
              padding: const EdgeInsets.all(10.0),
              child: AnimatedContainer(
                duration: _duration,
                curve: Curves.easeOutCubic,
                decoration: ShapeDecoration(
                  color: _hover || _tap ? const Color(0xFFCCCCCC) : const Color(0xFFEEEEEE),
                  shape: _tap ? const StarBorder(points: 4) : const CircleBorder(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class BuildUi extends StatefulWidget {
  const BuildUi({
    super.key,
    required this.system,
    required this.node,
    required this.x,
    required this.y,
  }); // TODO: hard-code the key to be on all the arguments

  final SystemNode system;
  final AssetNode node;
  final int x;
  final int y;

  @override
  State<BuildUi> createState() => _BuildUiState();
}

class _BuildUiState extends State<BuildUi> {
  final List<AssetClass> _options = <AssetClass>[];

  bool _pending = true;
  bool _tired = false;
  Timer? _loadTimer;

  @override
  void initState() {
    super.initState();
    widget.system
      .play(<Object>[widget.node.id, 'get-buildings', widget.x, widget.y])
      .then((StreamReader reader) {
        if (mounted) {
          _loadTimer?.cancel();
          setState(() {
            while (!reader.eof) {
              _options.add(AssetClass(
                id: reader.readInt(),
                icon: reader.readString(),
                name: reader.readString(),
                description: reader.readString(),
              ));
            }
            _options.sort(AssetClass.alphabeticalSort);
            _pending = false;
            _tired = false;
          });
        }
      });
    _loadTimer = Timer(const Duration(milliseconds: 750), _loading);
  }

  void _loading() {
    setState(() {
      _tired = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    Widget body;
    if (_pending) {
      if (_tired) {
        body = const Center(
          child: CircularProgressIndicator(),
        );
      } else {
        body = const SizedBox.shrink();
      }
    } else {
      final IconsManager icons = IconsManagerProvider.of(context);
      final TextTheme textTheme = Theme.of(context).textTheme;
      body = Padding(
        padding: const EdgeInsets.fromLTRB(0.0, 0.0, 4.0, 0.0),
        child: ListView.builder(
          padding: const EdgeInsets.fromLTRB(22.0, 4.0, 20.0, 24.0),
          itemCount: _options.length,
          itemBuilder: (BuildContext context, int index) {
            return BuildTile(
              assetClass: _options[index],
              icons: icons,
              textTheme: textTheme,
              onBuild: () {
                widget.system.play(<Object>[widget.node.id, 'build', widget.x, widget.y, _options[index].id]);
                HudHandle.of(context).cancel();
              },
            );
          },
        ),
      );
    }
    return AnimatedSwitcher(
      child: body,
      duration: const Duration(milliseconds: 160),
      switchInCurve: Curves.easeInOut,
      switchOutCurve: Curves.easeInOut,
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

class GridWidget extends MultiChildRenderObjectWidget {
  const GridWidget({
    super.key,
    required this.spaceTime,
    required this.node,
    required this.cellSize,
    required this.width,
    required this.height,
    super.children,
  });

  final SpaceTime spaceTime;
  final WorldNode node;
  final double cellSize;
  final int width;
  final int height;

  @override
  RenderGrid createRenderObject(BuildContext context) {
    return RenderGrid(
      spaceTime: spaceTime,
      shaders: ShaderProvider.of(context),
      node: node,
      cellSize: cellSize,
      width: width,
      height: height,
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderGrid renderObject) {
    renderObject
      ..spaceTime = spaceTime
      ..shaders = ShaderProvider.of(context)
      ..node = node
      ..cellSize = cellSize
      ..width = width
      ..height = height;
  }
}

class GridParentData extends ParentData with ContainerParentDataMixin<RenderWorld> { }

class RenderGrid extends RenderWorldWithChildren<GridParentData> {
  RenderGrid({
    required SpaceTime spaceTime,
    required ShaderLibrary shaders,
    required super.node,
    required double cellSize,
    required int width,
    required int height,
  }) : _spaceTime = spaceTime,
       _shaders = shaders,
       _cellSize = cellSize,
       _width = width,
       _height = height;

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

  int get width => _width;
  int _width;
  set width (int value) {
    if (value != _width) {
      _width = value;
      _gridShader = null;
      markNeedsPaint();
    }
  }

  int get height => _height;
  int _height;
  set height (int value) {
    if (value != _height) {
      _height = value;
      _gridShader = null;
      markNeedsPaint();
    }
  }

  double get diameter => max(width, height) * cellSize;

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
    _gridShader ??= shaders.grid(width: width, height: height);
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
    final Offset topLeftOffset = rect.topLeft;
    final double actualCellSize = cellSize * constraints.scale;
    int x = 0;
    int y = 0;
    RenderWorld? child = firstChild;
    while (child != null) {
      // TODO: this should probably use paintPositionFor
      final GridParentData childParentData = child.parentData! as GridParentData;
      final Offset childOffset = topLeftOffset + Offset((0.5 + x) * actualCellSize, (0.5 + y) * actualCellSize);
      context.paintChild(child, childOffset);
      x += 1;
      if (x >= width) {
        x = 0;
        y += 1;
      }
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
    return null;
  }
}
