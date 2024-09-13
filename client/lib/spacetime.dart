import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

@immutable
class SpaceTime {
  const SpaceTime(this._anchorTime, this._timeFactor, this._origin);

  final int _anchorTime;
  final double _timeFactor;
  final DateTime _origin;

  static DateTime? _lastFrameTime;
  static final Set<VoidCallback> _callbacks = <VoidCallback>{};
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
