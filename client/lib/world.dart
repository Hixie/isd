import 'dart:math';

import 'package:flutter/widgets.dart';

import 'dynasty.dart';
import 'widgets.dart';
import 'zoom.dart';

abstract class WorldNode extends ChangeNotifier {
  WorldNode();

  Widget build(BuildContext context, ZoomSpecifier zoom) {
    return ListenableBuilder(
      listenable: this,
      builder: (BuildContext context, Widget? child) {
        double transitionLevel;
        WorldNode? zoomedChildNode;
        ZoomSpecifier? zoomedChildZoom;
        PanZoomSpecifier panZoom;
        if (zoom is NodeZoomSpecifier) {
          final Offset childPosition = findLocationForChild(zoom.child);
          panZoom = PanZoomSpecifier(
            childPosition,
            const Offset(0.5, 0.5),
            log(diameter / zoom.child.diameter) * zoom.zoom,
          );
          zoomedChildNode = zoom.child;
          zoomedChildZoom = zoom.next;
          transitionLevel = ((zoom.zoom - 0.90) / 0.05).clamp(0.0, 1.0);
        } else {
          panZoom = zoom as PanZoomSpecifier;
          transitionLevel = 0.0;
        }
        return buildRenderer(context, panZoom, zoomedChildNode, zoomedChildZoom, transitionLevel);
      }
    );
  }

  // canonical location in meters
  Offset findLocationForChild(WorldNode child);

  // in meters
  double get diameter;
  
  Widget buildRenderer(BuildContext context, PanZoomSpecifier zoom, WorldNode? zoomedChildNode, ZoomSpecifier? zoomedChildZoom, double transitionLevel);

  @override
  String toString() => '<$runtimeType>';
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
  Widget buildRenderer(BuildContext context, PanZoomSpecifier zoom, WorldNode? zoomedChildNode, ZoomSpecifier? zoomedChildZoom, double transitionLevel) {
    return root.buildRenderer(context, zoom, zoomedChildNode, zoomedChildZoom, transitionLevel);
  }

  @override
  Offset findLocationForChild(WorldNode child) {
    return root.findLocationForChild(child);
  }

  @override
  double get diameter {
    return root.diameter;
  }
}

abstract class Feature {
  const Feature(this.parent);

  final AssetNode parent;
}

abstract class AbilityFeature extends Feature {
  const AbilityFeature(super.parent);
}

abstract class ContainerFeature extends Feature {
  const ContainerFeature(super.parent);

  Widget buildRenderer(BuildContext context, PanZoomSpecifier zoom, WorldNode? zoomedChildNode, ZoomSpecifier? zoomedChildZoom, double transitionLevel);
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

  final Map<Type, AbilityFeature> _abilities = <Type, AbilityFeature>{};
  final Map<Type, ContainerFeature> _containers = <Type, ContainerFeature>{};

  Type setAbility(AbilityFeature ability) {
    final Type type = ability.runtimeType;
    _abilities[type] = ability;
    return type;
  }

  Type setContainer(ContainerFeature container) {
    final Type type = container.runtimeType;
    _containers[type] = container;
    return type;
  }
  
  Set<Type> get featureTypes {
    return <Type>{
      ..._abilities.keys,
      ..._containers.keys,
    };
  }

  void removeFeatures(Set<Type> features) {
    features.forEach(_abilities.remove);
    features.forEach(_containers.remove);
  }
  
  @override
  Widget buildRenderer(BuildContext context, PanZoomSpecifier zoom, WorldNode? zoomedChildNode, ZoomSpecifier? zoomedChildZoom, double transitionLevel) {
    if (_containers.length == 1) {
      return _containers.values.single.buildRenderer(context, zoom, zoomedChildNode, zoomedChildZoom, transitionLevel);
    }
    return WorldPlaceholder(diameter: diameter, zoom: zoom, transitionLevel: transitionLevel,color: const Color(0xFFFF0000));
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
