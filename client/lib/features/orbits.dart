import 'package:flutter/widgets.dart';

import '../assets.dart';
import 'placeholder.dart';

typedef Orbit = ({ double a, double e, double theta, double omega });

class OrbitFeature extends ContainerFeature {
  OrbitFeature(this.spaceTime, this.children);

  final SpaceTime spaceTime;
  final Map<AssetNode, Orbit> children;

  @override
  void attach(WorldNode parent) {
    super.attach(parent);
    for (AssetNode child in children.keys) {
      assert(child.parent == null);
      child.parent = parent;
    }
  }

  @override
  void detach() {
    for (AssetNode child in children.keys) {
      assert(child.parent == parent);
      child.parent = null;
    }
    super.detach();
  }

  @override
  Widget buildRenderer(BuildContext context, Widget? child) {
    return WorldPlaceholder(diameter: parent.diameter, color: const Color(0xFFFFFF00));
  }

  @override
  Offset findLocationForChild(AssetNode child, List<VoidCallback> callbacks) {
    parent.addTransientListeners(callbacks);
    parent.computeTime(spaceTime, callbacks);
    return throw UnimplementedError();
  }
}
