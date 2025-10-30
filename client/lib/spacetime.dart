import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

class SystemClock {
  DateTime get now => _now;
  DateTime _now = DateTime.timestamp();

  bool _active = true;
  bool _pending = false;

  final Set<VoidCallback> _callbacks = <VoidCallback>{};

  void _handler(Duration timeStamp) {
    _pending = false;
    if (_active) {
      _now = DateTime.timestamp();
      final List<VoidCallback> oldCallbacks = _callbacks.toList();
      _callbacks.clear();
      for (VoidCallback callback in oldCallbacks) {
        callback();
      }
    }
  }

  void scheduleTick(VoidCallback callback) {
    _callbacks.add(callback);
    if (_active && !_pending) {
      _pending = true;
      SchedulerBinding.instance.scheduleFrameCallback(_handler);
    }
  }

  void pause() {
    _active = false;
  }

  void resume() {
    _active = true;
    if (!_pending) {
      _pending = true;
      SchedulerBinding.instance.scheduleFrameCallback(_handler);
    }
  }
}

@immutable
class SpaceTime {
  SpaceTime(this.clock, this._anchorTime, this._timeFactor) : _origin = clock.now;

  final SystemClock clock;
  final int _anchorTime; // ms from server
  final double _timeFactor;
  final DateTime _origin;

  static DateTime? _lastFrameTime;
  static final Set<VoidCallback> _callbacks = <VoidCallback>{};
  static bool _pending = false;

  void _handler() {
    _lastFrameTime = clock.now;
    _pending = false;
    final List<VoidCallback> oldCallbacks = _callbacks.toList();
    _callbacks.clear();
    for (VoidCallback callback in oldCallbacks) {
      callback();
    }
  }

  // returns local system time in milliseconds
  double computeTime(List<VoidCallback> callbacks) {
    _lastFrameTime ??= clock.now;
    _callbacks.addAll(callbacks);
    if (!_pending && _callbacks.isNotEmpty) {
      clock.scheduleTick(_handler);
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
