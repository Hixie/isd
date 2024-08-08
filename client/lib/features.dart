import 'package:flutter/widgets.dart';

import 'components.dart';
import 'widgets.dart';
import 'world.dart';
import 'zoom.dart';

class StarFeature extends AbilityFeature {
  const StarFeature(super.parent, this.starId);
  final int starId;
}

typedef Orbit = ({ double a, double e, double theta, double omega, AssetNode child });

class OrbitFeature extends ContainerFeature {
  const OrbitFeature(super.parent, this.timeOrigin, this.timeFactor, this.children);

  final int timeOrigin;
  final double timeFactor;
  final Set<Orbit> children;

  @override
  Widget buildRenderer(BuildContext context, PanZoomSpecifier zoom, WorldNode? zoomedChildNode, ZoomSpecifier? zoomedChildZoom, double transitionLevel) {
    return WorldPlaceholder(diameter: parent.diameter, zoom: zoom, transitionLevel: transitionLevel, color: const Color(0xFFFFFF00));
  }
}

class StructureFeature extends AbilityFeature {
  const StructureFeature({
    required AssetNode parent,
    required this.structuralComponents,
    required this.current,
    required this.min,
    required this.max,
  }) : super(parent);

  final List<StructuralComponent> structuralComponents;

  // structural integrity
  final int current;
  final int? min;
  final int? max;
}

class SpaceSensorsFeature extends AbilityFeature {
  const SpaceSensorsFeature({
    required AssetNode parent,
    required this.reach,
    required this.up,
    required this.down,
    required this.minSize,
    required this.nearestOrbit,
    required this.topOrbit,
    required this.detectedCount,
  }) : super(parent);

  final int reach;
  final int up;
  final int down;
  final double minSize;
  final AssetNode? nearestOrbit;
  final AssetNode? topOrbit;
  final int? detectedCount;
}
