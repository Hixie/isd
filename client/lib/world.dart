import 'package:flutter/widgets.dart';

import 'layout.dart';
import 'spacetime.dart';
import 'widgets.dart';

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

  @protected
  WorldNode cartoonZoomRoot(WorldNode child) => child;
  
  @protected
  Widget buildRenderer(BuildContext context, double paintDiameter);
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
  double get actualDiameter;

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

  @protected
  double computePaintDiameter(WorldConstraints constraints) {
    return actualDiameter * constraints.scale;
  }

  Widget build(BuildContext context) => ListenableBuilder(
    listenable: this,
    builder: (BuildContext context, Widget? child) => WorldLayoutBuilder(
      builder: (BuildContext context, WorldConstraints constraints) {
        final double paintDiameter = computePaintDiameter(constraints);
        if (paintDiameter < WorldGeometry.minAssetRenderDiameter)
          return WorldNull(node: this, paintDiameter: paintDiameter);
        
        return buildRenderer(context, paintDiameter);
      },
    ),
  );

  @override
  String toString() => '<$runtimeType>';
}
