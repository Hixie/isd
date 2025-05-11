import 'package:flutter/widgets.dart';

import 'containers/orbits.dart';
import 'dynasty.dart';
import 'icons.dart';
import 'widgets.dart';
import 'world.dart';

abstract class Feature {
  Feature();

  /// Current host for this feature.
  ///
  /// Only valid when attached.
  AssetNode get parent => _parent!;
  AssetNode? _parent;

  void attach(AssetNode parent) {
    assert(_parent == null);
    _parent = parent;
  }

  void detach() {
    assert(_parent != null);
    _parent = null;
  }
}

typedef WalkCallback = bool Function(AssetNode node);

enum RendererType { none, box, world }

abstract class AbilityFeature extends Feature {
  AbilityFeature();

  RendererType get rendererType;
  
  Widget buildRenderer(BuildContext context) {
    assert(rendererType == RendererType.none);
    throw StateError('buildRenderer should not be called if rendererType is RendererType.none');
  }
}

/// Features that have children.
///
/// Subclasses are expected to attach children (set their `parent` field) on
/// [attach], and reset them on [detach].
abstract class ContainerFeature extends Feature {
  ContainerFeature();

  Offset findLocationForChild(AssetNode child, List<VoidCallback> callbacks);

  void walk(WalkCallback callback);

  Widget buildRenderer(BuildContext context); // this one is abstract; containers always need to build something
}

class AssetNode extends WorldNode {
  AssetNode({ super.parent, required this.id });

  final int id;

  int get assetClassID => _assetClassID!;
  int? _assetClassID;
  set assetClassID(int value) {
    if (_assetClassID != value) {
      _assetClassID = value;
      notifyListeners();
    }
  }

  Dynasty? get ownerDynasty => _ownerDynasty;
  Dynasty? _ownerDynasty;
  set ownerDynasty(Dynasty? value) {
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

  double get massFlowRate => _massFlowRate!; // kg
  double? _massFlowRate;
  set massFlowRate(double value) {
    if (_massFlowRate != value) {
      _massFlowRate = value;
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
    notifyListeners();
    return type;
  }

  Type setContainer(ContainerFeature container) {
    final Type type = container.runtimeType;
    _containers[type]?.detach();
    _containers[type] = container;
    container.attach(this);
    notifyListeners();
    return type;
  }

  Set<Type> get featureTypes {
    return <Type>{
      ..._abilities.keys,
      ..._containers.keys,
    };
  }

  void removeFeatures(Set<Type> features) {
    if (features.isNotEmpty) {
      features.forEach(_abilities.remove);
      features.forEach(_containers.remove);
      notifyListeners();
    }
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

  void walk(WalkCallback callback) {
    if (callback(this)) {
      for (ContainerFeature container in _containers.values) {
        container.walk(callback);
      }
    }
  }

  @override
  Widget buildRenderer(BuildContext context, Widget? nil) {
    // TODO: compute actualDiameter here, and short-circuit if it's too small
    final List<Widget> backgrounds = <Widget>[];
    List<Widget>? boxes;
    for (AbilityFeature feature in _abilities.values) {
      switch (feature.rendererType) {
        case RendererType.none:
          ;
        case RendererType.box:
          boxes ??= <Widget>[];
          boxes.add(feature.buildRenderer(context));
        case RendererType.world:
          backgrounds.add(feature.buildRenderer(context));
      }
    }
    for (ContainerFeature feature in _containers.values) {
      backgrounds.add(feature.buildRenderer(context));
    }
    if (backgrounds.isEmpty) {
      if (parent != null) {
        addTransientListener(notifyListeners); // TODO: what does this line do
        assert(parent!.diameter > 0.0, 'parent $parent has zero diameter');
        backgrounds.add(WorldIcon(
          node: this,
          diameter: diameter,
          maxDiameter: parent!.maxRenderDiameter,
          icon: icon,
        ));
      }
      backgrounds.add(WorldIcon(
        node: this,
        diameter: diameter,
        maxDiameter: maxRenderDiameter,
        icon: icon,
      ));
    }
    if (boxes != null && boxes.isNotEmpty) {
      backgrounds.add(WorldBoxGrid(
        node: this,
        maxDiameter: parent!.maxRenderDiameter,
        diameter: diameter,
        children: boxes,
      ));
    }
    if (backgrounds.length == 1) {
      return backgrounds.single;
    }
    assert(backgrounds.length > 1);
    return WorldStack(
      node: this,
      maxDiameter: parent!.maxRenderDiameter,
      diameter: diameter,
      children: backgrounds,
    );
  }

  @override
  String toString() => '<$_className:$name#${hashCode.toRadixString(16)}>';
}
