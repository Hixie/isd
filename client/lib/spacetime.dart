import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

@immutable
class SpaceTime {
  const SpaceTime(this._anchorTime, this._timeFactor, this._origin);

  final int _anchorTime; // ms from server
  final double _timeFactor;
  final DateTime _origin;

  static DateTime? _lastFrameTime;
  static final Set<VoidCallback> _callbacks = <VoidCallback>{};
  static bool _pending = false;

  void _handler(Duration timestamp) {
    _lastFrameTime = DateTime.now();
    _pending = false;
    final List<VoidCallback> oldCallbacks = _callbacks.toList();
    _callbacks.clear();
    for (VoidCallback callback in oldCallbacks) {
      callback();
    }
  }

  // returns local system time in milliseconds
  double computeTime(List<VoidCallback> callbacks) {
    _lastFrameTime ??= DateTime.now();
    _callbacks.addAll(callbacks);
    if (!_pending && _callbacks.isNotEmpty) {
      SchedulerBinding.instance.scheduleFrameCallback(_handler);
      _pending = true;
    }
    assert(_origin.isUtc);
    final int realElapsed = _lastFrameTime!.difference(_origin).inMicroseconds;
    return _anchorTime + (realElapsed * _timeFactor) / 1e3;
  }

  ValueListenable<double> asListenable() {
    return _SpaceTimeListenable(this);
  }
}

class _SpaceTimeListenable extends ValueNotifier<double> {
  _SpaceTimeListenable(this.spaceTime) : super(spaceTime.computeTime(const <VoidCallback>[]));
  
  final SpaceTime spaceTime;

  void _update() {
    if (hasListeners) {
      value = spaceTime.computeTime(<VoidCallback>[_update]);
    }
  }
  
  @override
  void addListener(VoidCallback listener) {
    if (!hasListeners) {
      value = spaceTime.computeTime(<VoidCallback>[_update]);
    }
    super.addListener(listener);
  }
}
