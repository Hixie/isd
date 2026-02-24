import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart' hide Gradient;

import 'assets.dart';

class DockLayout extends StatefulWidget {
  const DockLayout({
    super.key,
    required this.builder,
  });

  final TransitionBuilder builder;

  @override
  State<DockLayout> createState() => _DockLayoutState();
}

class _DockLayoutState extends State<DockLayout> {
  final LinkedHashSet<DockHandle> _handles = <DockHandle>{} as LinkedHashSet<DockHandle>;

  DockHandle _register(Feature feature) {
    assert(mounted);
    final DockHandle result = DockHandle(this, feature);
    scheduleMicrotask(() { // TODO: find a way to do this that doesn't require a microtask
      // (normally this is called from build, because we discover we have a grid while we're building, then we pop the dock in)
      setState(() {
        _handles.add(result);
      });
    });
    return result;
  }

  void remove(DockHandle handle) {
    scheduleMicrotask(() {
      if (mounted) {
        setState(() {
          _handles.remove(handle);
        });
      }
    });
  }

  final List<Widget> _docks = <Widget>[];

  void _updateDocks(double height) {
    _docks.clear();
    for (DockHandle handle in _handles) {
      final Widget? widget = handle._buildDock(context, height);
      if (widget != null)
        _docks.add(widget);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DockProvider(
      onRegister: _register,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          _updateDocks(constraints.maxHeight);
          return widget.builder(
            context,
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ListBody(
                mainAxis: Axis.horizontal,
                children: _docks,
              ),
            ),
          );
        },        
      ),
    );
  }
}

typedef DockProviderRegisterCallback = DockHandle Function(Feature feature);

class DockProvider extends InheritedWidget {
  const DockProvider({ super.key, required this.onRegister, required super.child });

  final DockProviderRegisterCallback onRegister;

  static DockHandle add(BuildContext context, Feature feature) {
    final DockProvider? provider = context.dependOnInheritedWidgetOfExactType<DockProvider>();
    assert(provider != null, 'No DockProvider found in context');
    return provider!.onRegister(feature);
  }

  @override
  bool updateShouldNotify(DockProvider oldWidget) => false;
}

class _DockRoot extends InheritedWidget {
  const _DockRoot({ /*super.key,*/ required this.handle, required super.child });

  final DockHandle handle;

  @override
  bool updateShouldNotify(_DockRoot oldWidget) => handle != oldWidget.handle;
}

class DockHandle {
  DockHandle(this._state, this._feature);

  final _DockLayoutState _state;
  final Feature _feature;

  Widget? _buildDock(BuildContext context, double height) {
    return _feature.buildDock(context, height);
  }

  void dismiss() {
    _state.remove(this);
  }

  static DockHandle of(BuildContext context) {
    final _DockRoot? provider = context.dependOnInheritedWidgetOfExactType<_DockRoot>();
    assert(provider != null, 'No DockHandle found in context');
    return provider!.handle;
  }
}

class Dock extends StatelessWidget {
  const Dock({
    super.key,
    required this.child,
  });

  final Widget child;
  
  @override
  Widget build(BuildContext context) {
    return child;
  }
}
