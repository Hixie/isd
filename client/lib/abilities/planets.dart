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
      diameter: parent.diameter,
      maxDiameter: parent.maxRenderDiameter,
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
    required this.diameter,
    required this.maxDiameter,
    required this.seed,
    required this.spaceTime,
  });

  final WorldNode node;
  final double diameter;
  final double maxDiameter;
  final int seed;
  final SpaceTime spaceTime;

  @override
  RenderPlanet createRenderObject(BuildContext context) {
    return RenderPlanet(
      node: node,
      diameter: diameter,
      maxDiameter: maxDiameter,
      seed: seed,
      shaders: ShaderProvider.of(context),
      spaceTime: spaceTime,
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderPlanet renderObject) {
    renderObject
      ..node = node
      ..diameter = diameter
      ..maxDiameter = maxDiameter
      ..seed = seed
      ..shaders = ShaderProvider.of(context)
      ..spaceTime = spaceTime;
  }
}

class RenderPlanet extends RenderWorldNode {
  RenderPlanet({
    required super.node,
    required double diameter,
    required double maxDiameter,
    required int seed,
    required ShaderLibrary shaders,
    required SpaceTime spaceTime,
  }) : _diameter = diameter,
       _maxDiameter = maxDiameter,
       _seed = seed,
       _shaders = shaders,
       _spaceTime = spaceTime;

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
  void computeLayout(WorldConstraints constraints) { }

  FragmentShader? _planetShader;
  final Paint _planetPaint = Paint();

  @override
  double computePaint(PaintingContext context, Offset offset) {
    _planetShader ??= shaders.planet;
    final double time = spaceTime.computeTime(<VoidCallback>[markNeedsPaint]);
    final double actualDiameter = computePaintDiameter(diameter, maxDiameter);
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
    return actualDiameter;
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, { required Offset position }) {
    return false;
  }

  @override
  WorldTapTarget? routeTap(Offset offset) {
    return null;
  }
}
