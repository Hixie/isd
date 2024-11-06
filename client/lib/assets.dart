import 'package:flutter/widgets.dart';

import 'containers/orbits.dart';
import 'dynasty.dart';
import 'nodes/placeholder.dart';
import 'world.dart';

abstract class Feature {
  Feature();

  /// Current host for this feature.
  ///
  /// Only valid when attached.
  WorldNode get parent => _parent!;
  WorldNode? _parent;

  void attach(WorldNode parent) {
    assert(_parent == null);
    _parent = parent;
  }

  void detach() {
    assert(_parent != null);
    _parent = null;
  }
}

abstract class AbilityFeature extends Feature {
  AbilityFeature();

  Widget? buildRenderer(BuildContext context, Widget? child) {
    return null;
  }
}

/// Features that have children.
///
/// Subclasses are expected to attach children (set their `parent` field) on
/// [attach], and reset them on [detach].
abstract class ContainerFeature extends Feature {
  ContainerFeature();

  Offset findLocationForChild(AssetNode child, List<VoidCallback> callbacks);

  Widget buildRenderer(BuildContext context, Widget? child);
}

class AssetNode extends WorldNode {
  AssetNode({ super.parent, required this.id });

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

  double get mass => _mass!; // kg
  double? _mass;
  set mass(double value) {
    if (_mass != value) {
      _mass = value;
      notifyListeners();
    }
  }

  double get size => _size!; // meters
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
    _abilities[type]?.detach();
    _abilities[type] = ability;
    ability.attach(this);
    return type;
  }

  Type setContainer(ContainerFeature container) {
    final Type type = container.runtimeType;
    _containers[type]?.detach();
    _containers[type] = container;
    container.attach(this);
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
  double get diameter {
    assert(_size != null, 'unknown size for asset $id');
    return _size!;
  }

  @override
  double get maxRenderDiameter {
    if (parent is AssetNode && (parent! as AssetNode)._containers.containsKey(OrbitFeature)) {
      return parent!.maxRenderDiameter;
    }
    return super.maxRenderDiameter;
  }

  @override
  Offset findLocationForChild(WorldNode child, List<VoidCallback> callbacks) {
    assert(child.parent == this, '$this was asked for location of child $child but that child\'s parent is ${child.parent}');
    assert(child is AssetNode);
    if (_containers.length == 1) {
      return _containers.values.single.findLocationForChild(child as AssetNode, callbacks);
    }
    throw UnimplementedError();
  }

  @override
  Widget buildRenderer(BuildContext context, Widget? nil) {
    if (_containers.length == 1) {
      return _containers.values.single.buildRenderer(context, null);
    }
    for (AbilityFeature feature in _abilities.values) {
      final Widget? result = feature.buildRenderer(context, null);
      if (result != null) {
        return result;
      }
    }
    if (parent != null) {
      parent!.addTransientListener(notifyListeners);
      assert(parent!.diameter > 0.0, 'parent $parent has zero diameter');
      return WorldPlaceholder(
        node: this,
        diameter: diameter,
        maxDiameter: parent!.maxRenderDiameter,
        color: const Color(0xFFFFFF00),
      );
    }
    return WorldPlaceholder(
      node: this,
      diameter: diameter,
      maxDiameter: maxRenderDiameter,
      color: const Color(0xFFFF0000),
    );
  }

  @override
  String toString() => '<$className:$name>';
}
