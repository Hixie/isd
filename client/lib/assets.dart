import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'dynasty.dart';
import 'features/placeholder.dart';

@immutable
class SpaceTime {
  const SpaceTime(this._anchorTime, this._timeFactor, this._origin);

  final int _anchorTime;
  final double _timeFactor;
  final DateTime _origin;

  static DateTime? _lastFrameTime;
  static final Set<VoidCallback> _callbacks = {};
  static bool _pending = false;

  void _handler(Duration timestamp) {
    _lastFrameTime = DateTime.now();
    _pending = false;
    for (VoidCallback callback in _callbacks) {
      callback();
    }
    _callbacks.clear();
  }

  // returns local system time in seconds
  double computeTime(List<VoidCallback> callbacks) {
    _lastFrameTime ??= DateTime.now();
    _callbacks.addAll(callbacks);
    if (!_pending) {
      SchedulerBinding.instance.scheduleFrameCallback(_handler);
      _pending = true;
    }
    assert(_origin.isUtc);
    final int realElapsed = _lastFrameTime!.difference(_origin).inMicroseconds;
    return _anchorTime / 1e3 + (realElapsed * _timeFactor) / 1e6;
  }
}

abstract class WorldNode extends ChangeNotifier {
  WorldNode({ this.parent });

  // The node that considers this node a child.
  //
  // For orphan nodes (e.g. while nodes are being parsed in an update message)
  // and for the root node, this will be null.
  //
  // Changing this does _not_ trigger notifications. This is expected to be set
  // before the node is used in the render tree. When a node's parent changes,
  // the parent is expected to trigger notifications so that _it_ can be
  // rebuilt; the child does not need to update.
  WorldNode? parent;

  // in meters
  double get diameter;

  // in meters relative to parent
  Offset findLocationForChild(WorldNode child, List<VoidCallback> callbacks);

  // absolute position in meters
  Offset computePosition(List<VoidCallback> callbacks) {
    addTransientListeners(callbacks);
    if (parent == null) {
      return Offset.zero;
    }
    return parent!.computePosition(callbacks) + parent!.findLocationForChild(this, callbacks);
  }

  final Set<VoidCallback> _transientListeners = {};

  void addTransientListeners(List<VoidCallback> callbacks) {
    _transientListeners.addAll(callbacks);
  }

  @override
  void notifyListeners() {
    for (VoidCallback callback in _transientListeners) {
      callback();
    }
    _transientListeners.clear();
    super.notifyListeners();
  }

  // returns local system time in seconds
  double computeTime(SpaceTime spaceTime, List<VoidCallback> callbacks) {
    return spaceTime.computeTime([notifyListeners, ...callbacks]);
  }

  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: this,
      builder: buildRenderer,
    );
  }

  @protected
  Widget buildRenderer(BuildContext context, Widget? child);

  @override
  String toString() => '<$runtimeType>';
}

class SystemNode extends WorldNode {
  SystemNode({ super.parent, required this.id });

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
  double get diameter => root.diameter;

  @override
  Offset findLocationForChild(WorldNode child, List<VoidCallback> callbacks) {
    return root.findLocationForChild(child, callbacks);
  }

  @override
  Widget buildRenderer(BuildContext context, Widget? child) {
    return root.build(context);
  }
}

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
  AssetNode({ super.parent, required this.id, });

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
    return _size!;
  }

  @override
  Offset findLocationForChild(WorldNode child, List<VoidCallback> callbacks) {
    assert(child.parent == this);
    assert(child is AssetNode);
    if (_containers.length == 1) {
      return _containers.values.single.findLocationForChild(child as AssetNode, callbacks);
    }
    throw UnimplementedError();
  }

  @override
  Widget buildRenderer(BuildContext context, Widget? child) {
    if (_containers.length == 1) {
      return _containers.values.single.buildRenderer(context, null);
    }
    return WorldPlaceholder(diameter: diameter, color: const Color(0xFFFF0000));
  }
}
