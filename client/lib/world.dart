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
  //
  // Changing this (via attach/detach) does _not_ trigger notifications. This is
  // expected to be set before the node is used in the render tree. When a
  // node's parent changes, the parent is expected to trigger notifications so
  // that _it_ can be rebuilt; the child does not need to update.
  Node? get parent => _parent;
  Node? _parent;

  // ignore: use_setters_to_change_properties
  void attach(Node parent) {
    // it's possible that _parent is not null here
    // because the child might get updated before the old parent
    _parent = parent;
  }

  void detach() {
    assert(_parent != null);
    _parent = null;
  }

  void dispose() {
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

  @override
  void dispose() {
    super.dispose();
    _parent = null; // because ChangeNotifier.dispose doesn't call super.dispose
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
