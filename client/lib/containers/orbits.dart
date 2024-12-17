import 'dart:math';

import 'package:flutter/rendering.dart' hide Gradient;
import 'package:flutter/widgets.dart' hide Gradient;

import '../assets.dart';
import '../layout.dart';
import '../spacetime.dart';
import '../world.dart';

typedef Orbit = ({
  double a, // semi-major axis
  double e, // eccentricity
  double omega, // orientation of the orbit
  int timeOrigin, // time at which theta was zero (periapsis)
  bool clockwise, // direction of orbit
});

const Orbit nilOrbit = (a: 0.0, e: 0.0, omega: 0.0, timeOrigin: 0, clockwise: true);

const double gravitationalConstant = 6.67430e-11; // N m^2 kg^−2

Offset _computeOrbit(Orbit orbit, double primaryMass, double time) {
  assert(orbit.e <= 0.95); // above this, this approximation falls apart
  assert(time.isFinite);
  assert(primaryMass.isFinite);
  final double period = 2 * pi * sqrt(orbit.a * orbit.a * orbit.a / (gravitationalConstant * primaryMass)); // in seconds
  assert(period.isFinite);
  assert(period > 0.0);
  final double tau = ((time - orbit.timeOrigin) % period) / period;
  assert(tau.isFinite);
  assert(tau >= 0.0);
  assert(tau < 1.0);
  final double q = -0.99 * (pi / 4) * (orbit.e - 3 * sqrt(orbit.e)); // approximation constant
  assert(q.isFinite);
  final double L = orbit.a * (1 - orbit.e * orbit.e); // length of the semi latus rectum
  assert(L.isFinite);
  double theta;
  if (q == 0) {
    assert(orbit.e == 0.0);
    // avoids discontinuity when tan(q) == 0.0, which happens when e == 0.0.
    theta = 2 * pi * tau;
  } else {
    assert(orbit.e != 0.0);
    final double tanQ = tan(q);
    assert(tanQ.isFinite);
    // estimate of the angle from the focal point on the semi major axis to the orbital child
    // theta = 2 * pi * (tan(tau * 2 * q - q) - (tan(-q))) / (tan(q) - tan(-q));
    theta = 2 * pi * (tan(tau * 2 * q - q) + tanQ) / (tanQ * 2);
    assert(theta.isFinite);
  }
  if (!orbit.clockwise) {
    theta = -theta;
  }
  final double r = L / (1 + orbit.e * cos(theta)); // distance between the orbiting child and the child at the focal point
  assert(r.isFinite);
  assert(r >= 0.0);
  return Offset(
    r * cos(theta + orbit.omega),
    r * sin(theta + orbit.omega),
  );
}

class OrbitFeature extends ContainerFeature {
  OrbitFeature(this.spaceTime, this.originChild, this.children);

  final SpaceTime spaceTime;
  final AssetNode originChild;
  final Map<AssetNode, Orbit> children;

  @override
  void attach(AssetNode parent) {
    super.attach(parent);
    assert(originChild.parent == null);
    originChild.attach(parent);
    for (AssetNode child in children.keys) {
      assert(child.parent == null, '$child (${child.hashCode}) already has a parent: ${child.parent} (${child.parent.hashCode})');
      child.attach(parent);
    }
  }

  @override
  void detach() {
    assert(originChild.parent == parent);
    originChild.detach();
    for (AssetNode child in children.keys) {
      assert(child.parent == parent);
      child.detach();
    }
    super.detach();
  }

  @override
  void walk(WalkCallback callback) {
    originChild.walk(callback);
    for (AssetNode child in children.keys) {
      child.walk(callback);
    }
  }

  @override
  Widget buildRenderer(BuildContext context, Widget? child) {
    final List<Widget> childList = <Widget>[
      OrbitChildData(
        mass: originChild.mass,
        orbit: nilOrbit,
        child: originChild.build(context),
      ),
    ];
    double radius = 0.0;
    for (AssetNode asset in children.keys) {
      final Orbit orbit = children[asset]!;
      final double childRadius = orbit.a * (1 + orbit.e) + asset.diameter / 2.0;
      if (childRadius > radius) {
        radius = childRadius;
      }
      childList.add(
        OrbitChildData(
          mass: asset.mass,
          orbit: orbit,
          child: asset.build(context),
        ),
      );
    }
    return OrbitWidget(
      node: parent,
      diameter: radius * 2.0,
      spaceTime: spaceTime,
      children: childList,
    );
  }

  @override
  Offset findLocationForChild(AssetNode child, List<VoidCallback> callbacks) {
    if (child == originChild) {
      return Offset.zero;
    }
    assert(children.containsKey(child), '$parent has no child $child; children are ${children.keys} and $originChild');
    parent.addTransientListeners(callbacks);
    final double time = parent.computeTime(spaceTime, callbacks);
    return _computeOrbit(children[child]!, originChild.mass, time);
  }
}

class OrbitWidget extends MultiChildRenderObjectWidget {
  const OrbitWidget({
    super.key,
    required this.node,
    required this.diameter,
    required this.spaceTime,
    required super.children,
  });

  final WorldNode node;
  final double diameter;
  final SpaceTime spaceTime;

  @override
  RenderOrbit createRenderObject(BuildContext context) {
    return RenderOrbit(
      node: node,
      diameter: diameter,
      spaceTime: spaceTime,
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderOrbit renderObject) {
    renderObject
      ..node = node
      ..diameter = diameter
      ..spaceTime = spaceTime;
  }
}

class OrbitChildData extends ParentDataWidget<OrbitParentData> {
  const OrbitChildData({
    super.key, // ignore: unused_element
    required this.mass,
    required this.orbit,
    required super.child,
  });

  final double mass;
  final Orbit orbit;

  @override
  void applyParentData(RenderObject renderObject) {
    final OrbitParentData parentData = renderObject.parentData! as OrbitParentData;
    if (parentData.orbit != orbit || parentData.mass != mass) {
      parentData.orbit = orbit;
      parentData.mass = mass;
      renderObject.parent!.markNeedsPaint();
    }
  }

  @override
  Type get debugTypicalAncestorWidgetClass => RenderOrbit;
}

class OrbitParentData extends ParentData with ContainerParentDataMixin<RenderWorld> {
  double mass = 0.0;
  Orbit orbit = nilOrbit;
}

class RenderOrbit extends RenderWorldWithChildren<OrbitParentData> {
  RenderOrbit({
    required super.node,
    required double diameter,
    required SpaceTime spaceTime,
  }) : _diameter = diameter,
       _spaceTime = spaceTime;

  double get diameter => _diameter;
  double _diameter;
  set diameter (double value) {
    if (value != _diameter) {
      _diameter = value;
      markNeedsPaint();
    }
  }

  SpaceTime get spaceTime => _spaceTime;
  SpaceTime _spaceTime;
  set spaceTime (SpaceTime value) {
    if (value != _spaceTime) {
      _spaceTime = value;
      markNeedsPaint();
    }
  }

  @override
  void setupParentData(RenderObject child) {
    if (child.parentData is! OrbitParentData) {
      child.parentData = OrbitParentData();
    }
  }

  @override
  void computeLayout(WorldConstraints constraints) {
    RenderWorld? child = firstChild;
    while (child != null) {
      final OrbitParentData childParentData = child.parentData! as OrbitParentData;
      child.layout(constraints);
      child = childParentData.nextSibling;
    }
  }

  @override
  WorldGeometry computePaint(PaintingContext context, Offset offset) {
    RenderWorld? child = firstChild;
    assert(child != null);
    final OrbitParentData primaryChildParentData = child!.parentData! as OrbitParentData;
    child = primaryChildParentData.nextSibling;
    while (child != null) {
      final OrbitParentData childParentData = child.parentData! as OrbitParentData;
      if (debugPaintSizeEnabled) {
        final double semiMinorAxis = childParentData.orbit.a * sqrt(1 - childParentData.orbit.e * childParentData.orbit.e);
        final double center = childParentData.orbit.e * childParentData.orbit.a; // distance from focal point to center of ellipse, along major axis
        final Rect oval = Rect.fromCenter(
          center: Offset(center, 0.0) * constraints.scale,
          width: childParentData.orbit.a * 2.0 * constraints.scale,
          height: semiMinorAxis * 2.0 * constraints.scale,
        );
        context.canvas.save();
        context.canvas.translate(offset.dx, offset.dy);
        context.canvas.rotate(childParentData.orbit.omega + pi);
        context.canvas.drawOval(oval, Paint()..style= PaintingStyle.stroke..color = const Color(0x40FFFFFF));
        context.canvas.restore();
      }
      context.paintChild(child, constraints.paintPositionFor(child.node, offset, <VoidCallback>[markNeedsPaint]));
      child = childParentData.nextSibling;
    }
    context.paintChild(firstChild!, offset);
    return WorldGeometry(shape: Circle(diameter));
  }

  @override
  WorldTapTarget? routeTap(Offset offset) {
    RenderWorld? child = lastChild;
    while (child != null) {
      final OrbitParentData childParentData = child.parentData! as OrbitParentData;
      final WorldTapTarget? result = child.routeTap(offset); // TODO: correct offset
      if (result != null)
        return result;
      child = childParentData.previousSibling;
    }
    return null;
  }
}
