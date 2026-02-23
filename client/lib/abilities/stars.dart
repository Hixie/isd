import 'dart:ui';

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../assets.dart';
import '../layout.dart';
import '../nodes/system.dart';
import '../shaders.dart';
import '../spacetime.dart';
import '../widgets.dart';
import '../world.dart';

class StarFeature extends AbilityFeature {
  StarFeature(this.starId);

  final int starId;

  @override
  Widget buildRenderer(BuildContext context) {
    return StarWidget(
      node: parent,
      starId: starId,
      spaceTime: SystemNode.of(parent).spaceTime,
    );
  }

  @override
  RendererType get rendererType => RendererType.circle;

  @override
  Widget buildDialog(BuildContext context) {
    final int category = starId >> 20;
    return ListBody(
      children: <Widget>[
        const Text('Astronomy', style: bold),
        Padding(
          padding: featurePadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('Star identifier: $starId'), // '(0x${starId.toRadixString(16).padLeft(8, "0")})'
              Text('Star category: $category'),
            ],
          ),
        ),
      ],
    );
  }
}

class StarWidget extends LeafRenderObjectWidget {
  const StarWidget({
    super.key,
    required this.node,
    required this.starId,
    required this.spaceTime,
  });

  final WorldNode node;
  final int starId;
  final SpaceTime spaceTime;

  @override
  RenderStar createRenderObject(BuildContext context) {
    return RenderStar(
      node: node,
      starId: starId,
      shaders: ShaderProvider.of(context),
      spaceTime: spaceTime,
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderStar renderObject) {
    renderObject
      ..node = node
      ..starId = starId
      ..shaders = ShaderProvider.of(context)
      ..spaceTime = spaceTime;
  }
}

class RenderStar extends RenderWorldNode {
  RenderStar({
    required super.node,
    required int starId,
    required ShaderLibrary shaders,
    required SpaceTime spaceTime,
  }) : _starId = starId,
       _shaders = shaders,
       _spaceTime = spaceTime;

  int get starId => _starId;
  int _starId;
  set starId (int value) {
    if (value != _starId) {
      _starId = value;
      _starShader = null;
      markNeedsPaint();
    }
  }

  ShaderLibrary get shaders => _shaders;
  ShaderLibrary _shaders;
  set shaders (ShaderLibrary value) {
    if (value != _shaders) {
      _shaders = value;
      _starShader = null;
      markNeedsPaint();
    }
  }

  SpaceTime get spaceTime => _spaceTime;
  SpaceTime _spaceTime;
  set spaceTime (SpaceTime value) {
    if (value != _spaceTime) {
      _spaceTime = value;
      markNeedsPaint();
    }
  }

  @override
  void computeLayout(WorldConstraints constraints, double actualDiameter) { }

  FragmentShader? _starShader;
  final Paint _starPaint = Paint();

  @override
  void computePaint(PaintingContext context, Offset offset, double actualDiameter) {
    // TODO: starId-based paint
    _starShader ??= shaders.stars(0); // TODO: use actual star category id
    final double time = spaceTime.computeTime(<VoidCallback>[markNeedsPaint]);
    _starShader!.setFloat(uT, time);
    _starShader!.setFloat(uX, offset.dx);
    _starShader!.setFloat(uY, offset.dy);
    _starShader!.setFloat(uD, actualDiameter);
    _starPaint.shader = _starShader;
    // The texture we draw onto is intentionally much bigger than the star
    // (radius is twice the star's radius) so that the star can have solar
    // flares and such.
    context.canvas.drawRect(Rect.fromCircle(center: offset, radius: actualDiameter), _starPaint);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, { required Offset position }) {
    return false;
  }

  @override
  WorldTapTarget? computeTap(Offset offset) {
    return null; // TODO
  }
}
