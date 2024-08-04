import 'dart:math';
import 'dart:ui';

import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';

import 'world.dart';

@immutable
sealed class ZoomSpecifier {
  const ZoomSpecifier();

  ZoomSpecifier withScale(double delta, Offset? newSourceFocalPointFraction, Offset? newDestinationFocalPointFraction) {
    final (ZoomSpecifier result, double remainingDelta) = computeWithScale(delta, newSourceFocalPointFraction, newDestinationFocalPointFraction);
    return result;
  }

  // changes the zooms so that the cumulativeZoom is the specified amount
  ZoomSpecifier withZoom(double total);

  // changes the end of the zoom to the specified pan
  ZoomSpecifier withPan(PanZoomSpecifier newEnd);

  // changes the end of the zoom to the specified child node with a centered pan
  ZoomSpecifier withChild(WorldNode newChild);

  PanZoomSpecifier get last;

  @protected
  (ZoomSpecifier, double) computeWithScale(double delta, Offset? newSourceFocalPointFraction, Offset? newDestinationFocalPointFraction);

  double get cumulativeZoom;

  (double zoomOut, double zoomIn) measureZooms(ZoomSpecifier other) => (cumulativeZoom, other.cumulativeZoom);

  ZoomSpecifier truncate(WorldNode parent);
}

class ZoomTween extends Tween<ZoomSpecifier> {
  ZoomTween({ super.begin, super.end,
      required this.panFraction,
      required this.rootNode,
      required this.outCurve,
      required this.panCurve,
      required this.inCurve,
  }) : assert(panFraction >= 0.0),
       assert(panFraction < 1.0);

  bool _dirty = true;

  @override
  set begin(ZoomSpecifier? value) {
    super.begin = value;
    _dirty = true;
  }

  @override
  set end(ZoomSpecifier? value) {
    super.end = value;
    _dirty = true;
  }

  final double panFraction;
  final WorldNode rootNode;
  final Curve outCurve;
  final Curve panCurve;
  final Curve inCurve;

  late double _outFraction;
  late double _inFraction;
  late double _out;
  late double _in;
  late ZoomSpecifier _panZoomChain;
  late PanZoomSpecifier _panSource;
  late PanZoomSpecifier _panTarget;
  
  @override
  ZoomSpecifier lerp(double t) {
    assert(begin != null);
    assert(end != null);
    if (_dirty) {
      final (double outZoom, inZoom) = begin!.measureZooms(end!);
      _out = outZoom;
      _in = inZoom;
      final double pan = panFraction * (inZoom + outZoom) / (1.0 - panFraction);
      final double total = _out + pan + _in;
      _outFraction = total / _out;
      _inFraction = total / _in;
      assert(panFraction == total / pan);
      _panZoomChain = begin!.withScale(-outZoom, null, null).truncate(rootNode);
      _panSource = _panZoomChain.last;
      _panTarget = end!.withScale(-inZoom, null, null).truncate(rootNode).last;
    }
    if (t < _outFraction) {
      t = outCurve.transform(t / _outFraction);
      return begin!.withScale(-t * _out, null, null);
    }
    t -= _outFraction;
    if (t < panFraction) {
      t = panCurve.transform(t / panFraction);
      return _panZoomChain.withPan(PanZoomSpecifier.lerp(_panSource, _panTarget, t, /* unzoom: 1.0 - TODO: compute minimum unzoom to see both points */));
    }
    assert(t <= _inFraction);
    t = 1.0 - (t - panFraction);
    return end!.withScale(-t * _in, null, null);
  }
}

class NodeZoomSpecifier extends ZoomSpecifier {
  const NodeZoomSpecifier(this.child, this.zoom, this.next) : assert(zoom >= 0.0), assert(zoom <= 1.0);

  final WorldNode child;
  final double zoom; // 0..1
  final ZoomSpecifier next;

  @override
  ZoomSpecifier withZoom(double total) {
    if (total > 1.0) {
      return NodeZoomSpecifier(child, 1.0, next.withZoom(total - 1.0));
    }
    return NodeZoomSpecifier(child, total, next.withZoom(0.0));
  }
  
  @override
  ZoomSpecifier withPan(PanZoomSpecifier newEnd) {
    return NodeZoomSpecifier(child, zoom, next.withPan(newEnd));
  }

  @override
  ZoomSpecifier withChild(WorldNode newChild) {
    return NodeZoomSpecifier(child, zoom, next.withChild(newChild));
  }

  @override
  PanZoomSpecifier get last => next.last;

  @override
  (ZoomSpecifier, double) computeWithScale(double delta, Offset? newSourceFocalPointFraction, Offset? newDestinationFocalPointFraction) {
    if (delta > 0.0) {
      final double newZoom = zoom + delta;
      if (newZoom > 1.0) {
        final (ZoomSpecifier newNext, double remainingDelta) = next.computeWithScale(newZoom - 1.0, newSourceFocalPointFraction, newDestinationFocalPointFraction);
        return (NodeZoomSpecifier(child, 1.0, newNext), 0.0);
      }
      return (NodeZoomSpecifier(child, newZoom, next), 0.0);
    }
    final (ZoomSpecifier newNext, double remainingDelta) = next.computeWithScale(delta, newSourceFocalPointFraction, newDestinationFocalPointFraction);
    assert(remainingDelta <= 0.0);
    if (zoom + remainingDelta < 0.0) {
      return (NodeZoomSpecifier(child, 0.0, newNext), remainingDelta + zoom);
    }
    return (NodeZoomSpecifier(child, zoom + remainingDelta, newNext), 0.0);
  }

  @override
  double get cumulativeZoom {
    double result = zoom;
    if (zoom == 1.0) {
      result += next.cumulativeZoom;
    }
    return result;
  }

  @override
  (double zoomOut, double zoomIn) measureZooms(ZoomSpecifier other) {
    if (other is NodeZoomSpecifier && other.child == child) {
      // at this level we're just staring at the same child node.
      if (other.zoom == zoom) {
        // and we're zoomed in the same.
        if (zoom == 1.0) {
          // if we're zoomed in all the way on both, what it really
          // means is that the interesting stuff is below us.
          return next.measureZooms(other.next);
        }
        // if we're not zoomed in all the way, that implies the two
        // states are identical.
        return (0.0, 0.0);
      }
      // the states aren't identical here.
      if (zoom == 1.0) {
        // we're zoomed in all the way, they're not.
        // so we need to zoom out, but not in.
        return (next.cumulativeZoom - other.zoom, 0.0);
      }
      if (other.zoom == 1.0) {
        // we're not zoomed in, but they are.
        // so we need to zoom in, but not out.
        return (0.0, next.cumulativeZoom - zoom);
      }
      // neither state is fully zoomed in, so we're just talking
      // about a minor adjustment.
      if (zoom < other.zoom) {
        // we're less zoomed in, so we need to zoom in.
        return (0.0, other.zoom - zoom);
      }
      // they're less zoomed in, so we need to zoom out.
      return (other.zoom - zoom, 0.0);
    }
    return super.measureZooms(other);
  }

  @override
  ZoomSpecifier truncate(WorldNode parent) {
    if (zoom < 1.0) {
      return PanZoomSpecifier(parent.findLocationForChild(child), const Offset(0.5, 0.5), log(parent.diameter / child.diameter) + 1);
    }
    return NodeZoomSpecifier(child, zoom, next.truncate(child));
  }

  @override
  String toString() => '--[ $zoom $child ]-->$next';
}

class PanZoomSpecifier extends ZoomSpecifier {
  const PanZoomSpecifier(this.sourceFocalPointFraction, this.destinationFocalPointFraction, this.zoom) : assert(zoom >= 1.0), assert(zoom < double.infinity);

  const PanZoomSpecifier.centered(this.zoom)
    : sourceFocalPointFraction = const Offset(0.5, 0.5),
      destinationFocalPointFraction = const Offset(0.5, 0.5);

  static const PanZoomSpecifier none = PanZoomSpecifier.centered(1.0);

  final Offset sourceFocalPointFraction; // location in the world

  final Offset destinationFocalPointFraction; // location on the screen 

  final double zoom; // >=1.0

  double get inputZoom => 1.0 + log(zoom);

  @override
  ZoomSpecifier withZoom(double total) {
    return PanZoomSpecifier(sourceFocalPointFraction, destinationFocalPointFraction, total + 1.0);
  }

  @override
  ZoomSpecifier withPan(PanZoomSpecifier newEnd) {
    return newEnd;
  }

  @override
  ZoomSpecifier withChild(WorldNode newChild) {
    return NodeZoomSpecifier(newChild, 1.0, none);
  }

  @override
  PanZoomSpecifier get last => this;

  @override
  (ZoomSpecifier, double) computeWithScale(double delta, Offset? newSourceFocalPointFraction, Offset? newDestinationFocalPointFraction) {
    final Offset effectiveSource = newSourceFocalPointFraction ?? sourceFocalPointFraction;
    final Offset effectiveDestination = newDestinationFocalPointFraction ?? destinationFocalPointFraction;
    if (delta > 0.0) {
      // zoom in, always works
      // TODO: figure out how to snap zoom to a child when appropriate
      return (PanZoomSpecifier(effectiveSource, effectiveDestination, zoom + delta), 0);
    }
    final double newZoom = zoom + delta;
    if (newZoom < 1.0) {
      // zoomed out all the way, spill the remainder up
      return (PanZoomSpecifier(effectiveSource, effectiveDestination, 1.0), delta + (zoom - 1.0));
    }
    // zoom out
    return (PanZoomSpecifier(effectiveSource, effectiveDestination, newZoom), 0.0);
  }

  @override
  double get cumulativeZoom {
    return zoom - 1.0;
  }

  @override
  ZoomSpecifier truncate(WorldNode parent) {
    return this;
  }

  static PanZoomSpecifier lerp(PanZoomSpecifier a, PanZoomSpecifier b, double t, { double unzoom = 1.0 }) {
    return PanZoomSpecifier(
      Offset.lerp(a.sourceFocalPointFraction, b.sourceFocalPointFraction, t)!,
      Offset.lerp(a.destinationFocalPointFraction, b.destinationFocalPointFraction, t)!,
      t < 0.5 ? lerpDouble(a.zoom, unzoom, t * 2.0)! : lerpDouble(unzoom, b.zoom, (t - 0.5) * 2.0)!,
    );
  }

  @override
  String toString() => '--PanZoomSpecifier($sourceFocalPointFraction for $destinationFocalPointFraction x$zoom)';
}
