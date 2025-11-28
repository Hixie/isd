import 'package:flutter/widgets.dart';

import 'spacetime.dart';

abstract class Node {
  Node({
    Node? parent,
  }) : _parent = parent;

  // The node that considers this node a child.
  //
  // For orphan nodes (e.g. while nodes are being parsed in an update message)
  // and for the root node, this will be null.
  Node? get parent => _parent;
  Node? _parent;

  // ignore: use_setters_to_change_properties
  void attach(Node parent) {
    _parent = parent;
  }

  void detach() {
    _parent = null;
  }

  // return the nearest WorldParent ancestor
  WorldNode? get worldParent => parent?._worldParent;
  WorldNode? get _worldParent => parent?._worldParent;
}

abstract class WorldNode extends Node with ChangeNotifier {
  WorldNode({ super.parent });

  @override
  WorldNode? get _worldParent => this;

  // This is used by the layout logic to track when the center node changes.
  ValueSetter<WorldNode>? onDispose;

  @override
  void dispose() {
    if (onDispose != null) {
      onDispose!(this);
    }
    super.detach();
    super.dispose(); // ChangeNotifier.dispose doesn't call super.dispose, so Node can't have a dispose method
  }

  // in meters
  double get diameter;

  // in meters
  double get maxRenderDiameter => diameter;

  // in meters relative to nearest parent WorldNode, used by computePosition
  Offset findLocationForChild(WorldNode child, List<VoidCallback> callbacks);

  final Set<VoidCallback> _transientListeners = <VoidCallback>{};

  void addTransientListener(VoidCallback callback) {
    _transientListeners.add(callback);
  }

  void addTransientListeners(List<VoidCallback> callbacks) {
    _transientListeners.addAll(callbacks);
  }

  void _triggerTransients() {
    if (_parent != null) {
      final List<VoidCallback> listeners = _transientListeners.toList();
      _transientListeners.clear();
      for (VoidCallback callback in listeners) {
        callback();
      }
      notifyListeners();
    }
  }

  // returns local system time in milliseconds
  double computeTime(SpaceTime spaceTime, List<VoidCallback> callbacks) {
    return spaceTime.computeTime(<VoidCallback>[_triggerTransients, ...callbacks]);
  }

  late final Widget _build = ListenableBuilder(
    listenable: this,
    builder: buildRenderer,
  );
  Widget build(BuildContext context) => _build;

  @protected
  Widget buildRenderer(BuildContext context, Widget? nil);

  @override
  String toString() => '<$runtimeType>';
}
