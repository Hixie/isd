import 'package:flutter/widgets.dart';

import 'galaxy.dart';
import 'renderers.dart';
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

  // canonical location in node's own units
  Offset findLocationForChild(WorldNode child);

  // in meters
  double get diameter;
  
  Widget buildRenderer(BuildContext context, PanZoomSpecifier zoom, WorldNode? selectedChild, ZoomSpecifier? childZoom);
}

class GalaxyNode extends WorldNode {
  GalaxyNode({ GalaxyTapHandler? onTap }) : _onTap = onTap;

  Galaxy? get galaxy => _galaxy;
  Galaxy? _galaxy;
  set galaxy(Galaxy? value) {
    _galaxy = value;
    notifyListeners();
  }

  GalaxyTapHandler? get onTap => _onTap;
  GalaxyTapHandler? _onTap;
  set onTap(GalaxyTapHandler? value) {
    _onTap = value;
    notifyListeners();
  }
  
  final Set<SystemNode> systems = <SystemNode>{};

  List<Widget>? _children;
  
  void addSystem(SystemNode system) {
    systems.add(system);
    _children = null;
    notifyListeners();
  }

  void clearSystems() {
    systems.clear();
    _children = null;
    notifyListeners();
  }

  @override
  Offset findLocationForChild(WorldNode child) {
    if (galaxy != null) {
      return (child as SystemNode).offset;
    }
    return Offset.zero;
  }

  @override
  double get diameter {
    if (galaxy != null) {
      return galaxy!.diameter;
    }
    return 0;
  }
  
  @override
  Widget buildRenderer(BuildContext context, PanZoomSpecifier zoom, WorldNode? selectedChild, ZoomSpecifier? childZoom) {
    if (galaxy != null) {
      return GalaxyWidget(
        galaxy: galaxy!,
        diameter: diameter,
        zoom: zoom,
        onTap: onTap,
        children: _children ??= _rebuildChildren(context, zoom, selectedChild, childZoom),
      );
    }
    return WorldPlaceholder(
      diameter: diameter,
      zoom: zoom,
      color: const Color(0xFF999999),
    );
  }

  List<Widget> _rebuildChildren(BuildContext context, PanZoomSpecifier zoom, WorldNode? selectedChild, ZoomSpecifier? childZoom) {
    return systems.map((SystemNode childNode) {
      return ListenableBuilder(
        listenable: childNode,
        builder: (BuildContext context, Widget? child) {
          return WorldNodePosition(
            position: findLocationForChild(childNode),
            diameter: childNode.diameter,
            child: child!,
          );
        },
        child: childNode.build(
          context,
          childNode == selectedChild ? childZoom! : PanZoomSpecifier.none,
        ),
      );
    }).toList();
  }
}

class SystemNode extends WorldNode {
  SystemNode(this.offset, this._diameter, this.color);

  final Offset offset; // location in galaxy (in unit square)

  @override
  Widget buildRenderer(BuildContext context, PanZoomSpecifier zoom, WorldNode? selectedChild, ZoomSpecifier? childZoom) {
    return WorldPlaceholder(diameter: diameter, zoom: zoom, color: color);
  }

  @override
  Offset findLocationForChild(WorldNode child) {
    throw UnimplementedError();
  }

  final double _diameter; // should be around 1e16, which is about 1 light year
  final Color color;
  
  @override
  double get diameter {
    return _diameter;
  }
}
