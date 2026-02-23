import 'dart:ui';

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../assets.dart';
import '../layout.dart';
import '../nodes/system.dart';
import '../shaders.dart';
import '../spacetime.dart';
import '../world.dart';

class PlanetFeature extends AbilityFeature {
  PlanetFeature({ required this.seed });

  final int seed;

  @override
  Widget buildRenderer(BuildContext context) {
    return PlanetWidget(
      node: parent,
      seed: seed,
      spaceTime: SystemNode.of(parent).spaceTime,
    );
  }

  @override
  RendererType get rendererType => RendererType.circle;
}

class PlanetWidget extends LeafRenderObjectWidget {
  const PlanetWidget({
    super.key,
    required this.node,
    required this.seed,
    required this.spaceTime,
  });

  final WorldNode node;
  final int seed;
  final SpaceTime spaceTime;

  @override
  RenderPlanet createRenderObject(BuildContext context) {
    return RenderPlanet(
      node: node,
      seed: seed,
      shaders: ShaderProvider.of(context),
      spaceTime: spaceTime,
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderPlanet renderObject) {
    renderObject
      ..node = node
      ..seed = seed
      ..shaders = ShaderProvider.of(context)
      ..spaceTime = spaceTime;
  }
}

class RenderPlanet extends RenderWorldNode {
  RenderPlanet({
    required super.node,
    required int seed,
    required ShaderLibrary shaders,
    required SpaceTime spaceTime,
  }) : _seed = seed,
       _shaders = shaders,
       _spaceTime = spaceTime;

  int get seed => _seed;
  int _seed;
  set seed (int value) {
    if (value != _seed) {
      _seed = value;
      markNeedsPaint();
    }
  }

  ShaderLibrary get shaders => _shaders;
  ShaderLibrary _shaders;
  set shaders (ShaderLibrary value) {
    if (value != _shaders) {
      _shaders = value;
      _planetShader = null;
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

  FragmentShader? _planetShader;
  final Paint _planetPaint = Paint();

  @override
  void computePaint(PaintingContext context, Offset offset, double actualDiameter) {
    _planetShader ??= shaders.planet;
    final double time = spaceTime.computeTime(<VoidCallback>[markNeedsPaint]);
    _planetShader!.setFloat(uT, time);
    _planetShader!.setFloat(uX, offset.dx);
    _planetShader!.setFloat(uY, offset.dy);
    _planetShader!.setFloat(uD, actualDiameter);
    _planetShader!.setFloat(uVisible, constraints.viewportSize.shortestSide / actualDiameter);
    _planetShader!.setFloat(uSeed, seed.toDouble());
    _planetPaint.shader = _planetShader;
    // The texture we draw onto is intentionally much bigger than the planet
    // (radius is twice the planet's radius) so that the planet can have
    // effects like solar particles interacting with the magnetosphere. Not that
    // we do anything like that yet.
    context.canvas.drawRect(Rect.fromCircle(center: offset, radius: actualDiameter), _planetPaint);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, { required Offset position }) {
    return false;
  }

  @override
  WorldTapTarget? computeTap(Offset offset) {
    return null;
  }
}
