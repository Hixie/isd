import 'package:flutter/widgets.dart';

import 'galaxy.dart';
import 'renderers.dart';
import 'zoom.dart';

class BoxToWorldAdapter extends SingleChildRenderObjectWidget {
  const BoxToWorldAdapter({
    super.key,
    super.child,
  });

  @override
  RenderBoxToRenderWorldAdapter createRenderObject(BuildContext context) {
    return RenderBoxToRenderWorldAdapter();
  }

  @override
  void updateRenderObject(BuildContext context, RenderBoxToRenderWorldAdapter renderObject) { }
}

class GalaxyWidget extends MultiChildRenderObjectWidget {
  const GalaxyWidget({
    super.key,
    required this.galaxy,
    required this.diameter,
    required this.zoom,
    super.children,
  });

  final Galaxy? galaxy;
  final double diameter;
  final PanZoomSpecifier zoom;
  
  @override
  RenderGalaxy createRenderObject(BuildContext context) {
    return RenderGalaxy(
      galaxy: galaxy,
      diameter: diameter,
      zoom: zoom,
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderGalaxy renderObject) {
    renderObject
      ..galaxy = galaxy
      ..zoom = zoom;
  }
}
