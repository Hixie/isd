import 'package:flutter/widgets.dart';

import '../assets.dart';
import '../layout.dart';
import '../spacetime.dart';

class PlanetFeature extends AbilityFeature {
  PlanetFeature(this.spaceTime, this.hp);
  
  final SpaceTime spaceTime;
  final int hp;

  @override
  Widget? buildRenderer(BuildContext context, Widget? child) {
    return PlanetWidget(
      diameter: parent.diameter,
      maxDiameter: parent.maxRenderDiameter,
      spaceTime: spaceTime,
    );
  }
}

class PlanetWidget extends LeafRenderObjectWidget {
  const PlanetWidget({
    super.key,
    required this.diameter,
    required this.maxDiameter,
    required this.spaceTime,
  });

  final double diameter;
  final double maxDiameter;
  final SpaceTime spaceTime;

  @override
  RenderPlanet createRenderObject(BuildContext context) {
    return RenderPlanet(
      diameter: diameter,
      maxDiameter: maxDiameter,
      spaceTime: spaceTime,
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderPlanet renderObject) {
    renderObject
      ..diameter = diameter
      ..maxDiameter = maxDiameter
      ..spaceTime = spaceTime;
  }
}

class RenderPlanet extends RenderWorld {
  RenderPlanet({
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
    ..color = const Color(0xFFFFFFFF);
  
  @override
  WorldGeometry computePaint(PaintingContext context, Offset offset) {
    final double actualDiameter = computePaintDiameter(diameter, maxDiameter);
    context.canvas.drawCircle(offset, actualDiameter / 2.0, _planetPaint);
    return WorldGeometry(shape: Circle(actualDiameter));
  }
  
  @override
  WorldTapTarget? routeTap(Offset offset) {
    return null; // TODO
  }
}
