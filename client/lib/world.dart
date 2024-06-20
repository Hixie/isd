import 'package:flutter/widgets.dart';

import 'galaxy.dart';
import 'widgets.dart';
import 'zoom.dart';

abstract class WorldNode extends ChangeNotifier {
  WorldNode();

  Widget build(BuildContext context, ZoomSpecifier zoom) {
    return ListenableBuilder(
      listenable: this,
      builder: (BuildContext context, Widget? child) {
        WorldNode? selectedChild;
        ZoomSpecifier? childZoom;
        PanZoomSpecifier panZoom;
        if (zoom is NodeZoomSpecifier) {
          final Offset childPosition = findLocationForChild(zoom.child);
          panZoom = PanZoomSpecifier(
            childPosition,
            childPosition,
            zoom.zoom * diameter / zoom.child.diameter,
          );
          selectedChild = zoom.child;
          childZoom = zoom.next;
        } else {
          panZoom = zoom as PanZoomSpecifier;
        }
        return buildRenderer(context, panZoom, selectedChild, childZoom);
      }
    );
  }

  // canonical location in unit square
  Offset findLocationForChild(WorldNode child);

  // in meters
  double get diameter;
  
  Widget buildRenderer(BuildContext context, PanZoomSpecifier zoom, WorldNode? selectedChild, ZoomSpecifier? childZoom);
}

class GalaxyNode extends WorldNode {
  GalaxyNode();

  Galaxy? get galaxy => _galaxy;
  Galaxy? _galaxy;
  set galaxy(Galaxy? value) {
    _galaxy = value;
    notifyListeners();
  }
  
  final List<SystemNode> systems = <SystemNode>[];

  @override
  Offset findLocationForChild(WorldNode child) {
    throw UnimplementedError();
  }

  @override
  double get diameter {
    // TODO: consider reducing this by 10 or more
    return 1e21; // approx 105700 light years
  }

  @override
  Widget buildRenderer(BuildContext context, PanZoomSpecifier zoom, WorldNode? selectedChild, ZoomSpecifier? childZoom) {
    return GalaxyWidget(
      galaxy: galaxy,
      diameter: diameter,
      zoom: zoom,
      children: systems.map((SystemNode child) {
        if (child == selectedChild) {
          assert(childZoom != null);
          return child.build(context, childZoom!);
        }
        return child.build(context, PanZoomSpecifier.none);
      }).toList(),
    );
  }
}

class SystemNode extends WorldNode {
  SystemNode(this.offset);

  final Offset offset; // location in galaxy (in unit square)

  @override
  Widget buildRenderer(BuildContext context, PanZoomSpecifier zoom, WorldNode? selectedChild, ZoomSpecifier? childZoom) {
    return const Placeholder();
  }

  @override
  Offset findLocationForChild(WorldNode child) {
    throw UnimplementedError();
  }

  @override
  double get diameter {
    return 1e16; // about 1 light year
  }
}
