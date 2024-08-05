import 'dart:math';

import 'package:flutter/widgets.dart';

import 'dynasty.dart';
import 'galaxy.dart';
import 'widgets.dart';
import 'zoom.dart';

abstract class WorldNode extends ChangeNotifier {
  WorldNode();

  Widget build(BuildContext context, ZoomSpecifier zoom) {
    return ListenableBuilder(
      listenable: this,
      builder: (BuildContext context, Widget? child) {
        WorldNode? zoomedChildNode;
        ZoomSpecifier? zoomedChildZoom;
        PanZoomSpecifier panZoom;
        if (zoom is NodeZoomSpecifier) {
          final Offset childPosition = findLocationForChild(zoom.child);
          panZoom = PanZoomSpecifier(
            childPosition / diameter,
            const Offset(0.5, 0.5),
            log(diameter / zoom.child.diameter) * zoom.zoom,
          );
          zoomedChildNode = zoom.child;
          zoomedChildZoom = zoom.next;
        } else {
          panZoom = zoom as PanZoomSpecifier; 
        }
        return buildRenderer(context, panZoom, zoomedChildNode, zoomedChildZoom);
      }
    );
  }

  // canonical location in meters
  Offset findLocationForChild(WorldNode child);

  // in meters
  double get diameter;
  
  Widget buildRenderer(BuildContext context, PanZoomSpecifier zoom, WorldNode? zoomedChildNode, ZoomSpecifier? zoomedChildZoom);

  @override
  String toString() => '<$runtimeType>';
}

class GalaxyNode extends WorldNode {
  GalaxyNode();

  Galaxy? get galaxy => _galaxy;
  Galaxy? _galaxy;
  set galaxy(Galaxy? value) {
    if (_galaxy != value) {
      _galaxy = value;
      notifyListeners();
    }
  }
  
  final Set<SystemNode> systems = <SystemNode>{};

  List<Widget>? _children;
  
  void addSystem(SystemNode system) {
    if (systems.add(system)) {
      _children = null;
      notifyListeners();
    }
  }
  
  void removeSystem(SystemNode system) {
    if (systems.remove(system)) {
      _children = null;
      notifyListeners();
    }
  }

  void clearSystems() {
    if (systems.isNotEmpty) {
      systems.clear();
      _children = null;
      notifyListeners();
    }
  }

  final Map<int, Dynasty> _dynasties = <int, Dynasty>{};
  Dynasty getDynasty(int id) {
    return _dynasties.putIfAbsent(id, () => Dynasty(id));
  }

  Dynasty? get currentDynasty => _currentDynasty;
  Dynasty? _currentDynasty;
  void setCurrentDynastyId(int? id) {
    if (id == null) {
      _currentDynasty = null;
    } else {
      _currentDynasty = getDynasty(id);
    }
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
  Widget buildRenderer(BuildContext context, PanZoomSpecifier zoom, WorldNode? zoomedChildNode, ZoomSpecifier? zoomedChildZoom) {
    if (galaxy != null) {
      return GalaxyWidget(
        galaxy: galaxy!,
        diameter: galaxy!.diameter,
        zoom: zoom,
        children: _children ??= _rebuildChildren(context, zoom, zoomedChildNode, zoomedChildZoom),
      );
    }
    return WorldPlaceholder(
      diameter: diameter,
      zoom: zoom,
      color: const Color(0xFF999999),
    );
  }

  List<Widget> _rebuildChildren(BuildContext context, PanZoomSpecifier zoom, WorldNode? zoomedChildNode, ZoomSpecifier? zoomedChildZoom) {
    return systems.map((SystemNode childNode) {
      return ListenableBuilder(
        listenable: childNode,
        builder: (BuildContext context, Widget? child) {
          return GalaxyChildData(
            position: findLocationForChild(childNode),
            diameter: childNode.diameter,
            label: childNode.label,
            child: child!,
            onTap: () {
              ZoomProvider.zoom(context, childNode);
            },
          );
        },
        child: childNode.build(
          context,
          childNode == zoomedChildNode ? zoomedChildZoom! : PanZoomSpecifier.none,
        ),
      );
    }).toList();
  }
}

class SystemNode extends WorldNode {
  SystemNode(this.id);

  final int id;

  String get label => _label;
  String _label = '';

  void _updateLabel() {
    assert(_root != null);
    if (_root!.name != _label) {
      _label = _root!.name;
      notifyListeners();
    }
  }
  
  AssetNode get root => _root!;
  AssetNode? _root;
  set root(AssetNode value) {
    if (_root != value) {
      _root?.removeListener(_updateLabel);
      _root = value;
      _label = _root!.name;
      notifyListeners();
      _root!.addListener(_updateLabel);
    }
  }

  Offset get offset => _offset!;
  Offset? _offset;
  set offset(Offset value) {
    if (_offset != value) {
      _offset = value;
      notifyListeners();
    }
  }
  
  @override
  Widget buildRenderer(BuildContext context, PanZoomSpecifier zoom, WorldNode? zoomedChildNode, ZoomSpecifier? zoomedChildZoom) {
    return WorldPlaceholder(diameter: diameter, zoom: zoom, color: const Color(0xFFFFFFFF));
  }

  @override
  Offset findLocationForChild(WorldNode child) {
    throw UnimplementedError();
  }

  @override
  double get diameter {
    return root.diameter;
  }
}

class Feature {
  const Feature();
}

class AssetNode extends WorldNode {
  AssetNode(this.id);

  final int id;

  int get assetClass => _assetClass!;
  int? _assetClass;
  set assetClass(int value) {
    if (_assetClass != value) {
      _assetClass = value;
      notifyListeners();
    }
  }

  Dynasty get ownerDynasty => _ownerDynasty!;
  Dynasty? _ownerDynasty;
  set ownerDynasty(Dynasty value) {
    if (_ownerDynasty != value) {
      _ownerDynasty = value;
      notifyListeners();
    }
  }

  double get mass => _mass!; // meters
  double? _mass;
  set mass(double value) {
    if (_mass != value) {
      _mass = value;
      notifyListeners();
    }
  }

  double get size => _size!; // kg
  double? _size;
  set size(double value) {
    if (_size != value) {
      _size = value;
      notifyListeners();
    }
  }

  String get name => _name ?? '';
  String? _name;
  set name(String? value) {
    if (_name != value) {
      _name = value;
      notifyListeners();
    }
  }

  String get icon => _icon!;
  String? _icon;
  set icon(String value) {
    if (_icon != value) {
      _icon = value;
      notifyListeners();
    }
  }

  String get className => _className!;
  String? _className;
  set className(String value) {
    if (_className != value) {
      _className = value;
      notifyListeners();
    }
  }

  String get description => _description!;
  String? _description;
  set description(String value) {
    if (_description != value) {
      _description = value;
      notifyListeners();
    }
  }

  final Map<Type, Feature> _features = <Type, Feature>{};
  
  Set<Type> get featureTypes {
    return _features.keys.toSet();
  }

  Type setFeature(Feature feature) {
    final Type type = feature.runtimeType;
    _features[type] = feature;
    return type;
  }

  void removeFeatures(Set<Type> features) {
    features.forEach(_features.remove);
  }
  
  @override
  Widget buildRenderer(BuildContext context, PanZoomSpecifier zoom, WorldNode? zoomedChildNode, ZoomSpecifier? zoomedChildZoom) {
    return WorldPlaceholder(diameter: diameter, zoom: zoom, color: const Color(0xFFFF0000));
  }

  @override
  Offset findLocationForChild(WorldNode child) {
    throw UnimplementedError();
  }

  @override
  double get diameter {
    return _size!;
  }
}
