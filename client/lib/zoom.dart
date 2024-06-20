import 'dart:ui';

import 'world.dart';

sealed class ZoomSpecifier {
  const ZoomSpecifier();

  ZoomSpecifier withScale(double delta, Offset newSourceFocalPointFraction, Offset newDestinationFocalPointFraction) {
    final (ZoomSpecifier result, double remainingDelta) = _withScale(delta, newSourceFocalPointFraction, newDestinationFocalPointFraction);
    return result;
  }
  ZoomSpecifier withPan(PanZoomSpecifier newEnd);
  PanZoomSpecifier get last;

  (ZoomSpecifier, double) _withScale(double delta, Offset newSourceFocalPointFraction, Offset newDestinationFocalPointFraction);
}

class NodeZoomSpecifier extends ZoomSpecifier {
  const NodeZoomSpecifier(this.child, this.zoom, this.next);

  final WorldNode child;
  final double zoom; // 0..1
  final ZoomSpecifier next;

  @override
  ZoomSpecifier withPan(PanZoomSpecifier newEnd) {
    return NodeZoomSpecifier(child, zoom, next.withPan(newEnd));
  }

  @override
  PanZoomSpecifier get last => next.last;

  @override
  (ZoomSpecifier, double) _withScale(double delta, Offset newSourceFocalPointFraction, Offset newDestinationFocalPointFraction) {
    if (delta > 0.0) {
      final double newZoom = zoom + delta;
      if (newZoom > 1.0) {
        final (ZoomSpecifier newNext, double remainingDelta) = next._withScale(newZoom - 1.0, newSourceFocalPointFraction, newDestinationFocalPointFraction);
        return (NodeZoomSpecifier(child, 1.0, newNext), 0.0);
      }
      return (NodeZoomSpecifier(child, newZoom, next), 0.0);
    }
    final (ZoomSpecifier newNext, double remainingDelta) = next._withScale(delta, newSourceFocalPointFraction, newDestinationFocalPointFraction);
    assert(remainingDelta <= 0.0);
    if (zoom + remainingDelta < 0.0) {
      return (NodeZoomSpecifier(child, 0.0, newNext), remainingDelta + zoom);
    }
    return (NodeZoomSpecifier(child, zoom + remainingDelta, newNext), 0.0);
  }
}

class PanZoomSpecifier extends ZoomSpecifier {
  PanZoomSpecifier(this.sourceFocalPointFraction, this.destinationFocalPointFraction, this.zoom) : assert(zoom >= 1.0);

  const PanZoomSpecifier._none()
    : sourceFocalPointFraction = const Offset(0.5, 0.5),
      destinationFocalPointFraction = const Offset(0.5, 0.5),
      zoom = 1.0;

  static const PanZoomSpecifier none = PanZoomSpecifier._none();

  final Offset sourceFocalPointFraction; // location in the world
  final Offset destinationFocalPointFraction; // location on the screen 
  final double zoom; // >=1.0

  @override
  ZoomSpecifier withPan(PanZoomSpecifier newEnd) {
    return newEnd;
  }

  @override
  PanZoomSpecifier get last => this;

  @override
  (ZoomSpecifier, double) _withScale(double delta, Offset newSourceFocalPointFraction, Offset newDestinationFocalPointFraction) {
    final Offset effectiveSource = newSourceFocalPointFraction;
    final Offset effectiveDestination = newDestinationFocalPointFraction;
    if (delta > 0.0) {
      // zoom in
      return (PanZoomSpecifier(effectiveSource, effectiveDestination, zoom + delta), 0);
    }
    final double newZoom = zoom + delta;
    if (newZoom < 1.0) {
      // zoomed out all the way, spill the remainder up
      return (PanZoomSpecifier(effectiveSource, effectiveDestination, 1.0), newZoom + 1.0);
    }
    // zoom out
    return (PanZoomSpecifier(effectiveSource, effectiveDestination, newZoom), 0.0);
  }

  @override
  String toString() => 'PanZoomSpecifier($sourceFocalPointFraction->$destinationFocalPointFraction x$zoom)';
}
