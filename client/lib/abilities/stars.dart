import 'dart:ui';

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../assets.dart';
import '../layout.dart';
import '../nodes/system.dart';
import '../shaders.dart';
import '../spacetime.dart';
import '../world.dart';

class StarFeature extends AbilityFeature {
  StarFeature(this.starId);

  final int starId;

  @override
  Widget buildRenderer(BuildContext context) {
    return StarWidget(
      node: parent,
      starId: starId,
      diameter: parent.diameter,
      maxDiameter: parent.maxRenderDiameter,
      spaceTime: SystemNode.of(context).spaceTime,
    );
  }

  @override
  RendererType get rendererType => RendererType.background;
}

class StarWidget extends LeafRenderObjectWidget {
  const StarWidget({
    super.key,
    required this.node,
    required this.starId,
    required this.diameter,
    required this.maxDiameter,
    required this.spaceTime,
  });

  final WorldNode node;
  final int starId;
  final double diameter;
  final double maxDiameter;
  final SpaceTime spaceTime;

  @override
  RenderStar createRenderObject(BuildContext context) {
    return RenderStar(
      node: node,
      starId: starId,
      diameter: diameter,
      maxDiameter: maxDiameter,
      shaders: ShaderProvider.of(context),
      spaceTime: spaceTime,
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderStar renderObject) {
    renderObject
      ..node = node
      ..starId = starId
      ..diameter = diameter
      ..maxDiameter = maxDiameter
      ..shaders = ShaderProvider.of(context)
      ..spaceTime = spaceTime;
  }
}

class RenderStar extends RenderWorldNode {
  RenderStar({
    required super.node,
    required int starId,
    required double diameter,
    required double maxDiameter,
    required ShaderLibrary shaders,
    required SpaceTime spaceTime,
  }) : _starId = starId,
       _diameter = diameter,
       _maxDiameter = maxDiameter,
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
  void computeLayout(WorldConstraints constraints) { }

  FragmentShader? _starShader;
  final Paint _starPaint = Paint();

  @override
  double computePaint(PaintingContext context, Offset offset) {
    // TODO: starId-based paint
    _starShader ??= shaders.stars(0); // TODO: use actual star category id
    final double time = spaceTime.computeTime(<VoidCallback>[markNeedsPaint]);
    final double actualDiameter = computePaintDiameter(diameter, maxDiameter);
    _starShader!.setFloat(uT, time);
    _starShader!.setFloat(uX, offset.dx);
    _starShader!.setFloat(uY, offset.dy);
    _starShader!.setFloat(uD, actualDiameter);
    _starPaint.shader = _starShader;
    // The texture we draw onto is intentionally much bigger than the star
    // (radius is twice the star's radius) so that the star can have solar
    // flares and such.
    context.canvas.drawRect(Rect.fromCircle(center: offset, radius: actualDiameter), _starPaint);
    return actualDiameter;
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, { required Offset position }) {
    return false;
  }

  @override
  WorldTapTarget? routeTap(Offset offset) {
    return null; // TODO
  }
}
