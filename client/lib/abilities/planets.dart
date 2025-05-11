import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../assets.dart';
import '../layout.dart';
import '../nodes/system.dart';
import '../spacetime.dart';
import '../world.dart';

class PlanetFeature extends AbilityFeature {
  PlanetFeature();

  @override
  Widget buildRenderer(BuildContext context) {
    return PlanetWidget(
      node: parent,
      diameter: parent.diameter,
      maxDiameter: parent.maxRenderDiameter,
      spaceTime: SystemNode.of(context).spaceTime,
    );
  }

  @override
  RendererType get rendererType => RendererType.world;
}

class PlanetWidget extends LeafRenderObjectWidget {
  const PlanetWidget({
    super.key,
    required this.node,
    required this.diameter,
    required this.maxDiameter,
    required this.spaceTime,
  });

  final WorldNode node;
  final double diameter;
  final double maxDiameter;
  final SpaceTime spaceTime;

  @override
  RenderPlanet createRenderObject(BuildContext context) {
    return RenderPlanet(
      node: node,
      diameter: diameter,
      maxDiameter: maxDiameter,
      spaceTime: spaceTime,
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderPlanet renderObject) {
    renderObject
      ..node = node
      ..diameter = diameter
      ..maxDiameter = maxDiameter
      ..spaceTime = spaceTime;
  }
}

class RenderPlanet extends RenderWorldNode {
  RenderPlanet({
    required super.node,
    required double diameter,
    required double maxDiameter,
    required SpaceTime spaceTime,
  }) : _diameter = diameter,
       _maxDiameter = maxDiameter,
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

  Paint get _planetPaint => Paint()
    ..color = const Color(0xFF7FFF7F);

  @override
  double computePaint(PaintingContext context, Offset offset) {
    final double actualDiameter = computePaintDiameter(diameter, maxDiameter);
    context.canvas.drawCircle(offset, actualDiameter / 2.0, _planetPaint);
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
