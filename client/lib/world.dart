import 'package:flutter/widgets.dart';

import 'spacetime.dart';

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

  // in meters
  double get maxRenderDiameter => diameter;

  // in meters relative to parent, used by computePosition
  Offset findLocationForChild(WorldNode child, List<VoidCallback> callbacks);

  final Set<VoidCallback> _transientListeners = <VoidCallback>{};

  void addTransientListener(VoidCallback callback) {
    _transientListeners.add(callback);
  }

  void addTransientListeners(List<VoidCallback> callbacks) {
    _transientListeners.addAll(callbacks);
  }

  @override
  void notifyListeners() {
    final List<VoidCallback> listeners = _transientListeners.toList();
    _transientListeners.clear();
    for (VoidCallback callback in listeners) {
      callback();
    }
    super.notifyListeners();
  }

  // returns local system time in seconds
  double computeTime(SpaceTime spaceTime, List<VoidCallback> callbacks) {
    return spaceTime.computeTime(<VoidCallback>[notifyListeners, ...callbacks]);
  }

  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: this,
      builder: buildRenderer,
    );
  }

  @protected
  Widget buildRenderer(BuildContext context, Widget? nil);

  @override
  String toString() => '<$runtimeType>';
}
