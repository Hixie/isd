import 'dart:math' show max, min, pi;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide Gradient;

class HudLayout extends StatefulWidget {
  const HudLayout({
    super.key,
    required this.zoom,
    required this.child,
  });

  final Listenable zoom;
  final Widget child;

  @override
  State<HudLayout> createState() => _HudLayoutState();
}

class _HudLayoutState extends State<HudLayout> {
  final List<HudHandle> _handles = <HudHandle>[];
  
  HudHandle _register(BuildContext context, Size initialSize, Widget hudWidget) {
    final HudHandle result = HudHandle(this, context, hudWidget, initialSize);
    _handles.add(result);
    return result;
  }

  void _remove(HudHandle handle) {
    _handles.remove(handle);
  }

  final List<Widget> _huds = <Widget>[];
  late Size _hudSize;
  
  void _updateHuds(Size hudSize) {
    _hudSize = hudSize;
    _huds.clear();
    for (HudHandle handle in _handles) {
      _huds.add(handle._buildHud(context, hudSize));
    }
    // TODO: also draw a line from the target to the HUD element.
    // The way to do this is to insert a layer into the target and a layer into the hud manager,
    // then in the hud manager layer, find the target layers and draw the picture on demand.
  }
  
  @override
  Widget build(BuildContext context) {
    return HudProvider(
      onRegister: _register,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) => ListenableBuilder(
          listenable: widget.zoom,
          builder: (BuildContext context, Widget? child) {
            _updateHuds(constraints.biggest);
            return Stack(
              fit: StackFit.expand,
              clipBehavior: Clip.none,
              children: <Widget>[
                widget.child,
                ..._huds,
              ],
            );
          },
        ),
      ),
    );
  }
}

typedef HudProviderRegisterCallback = HudHandle Function(BuildContext context, Size initialSize, Widget hudWidget);

class HudProvider extends InheritedWidget {
  const HudProvider({ super.key, required this.onRegister, required super.child });

  final HudProviderRegisterCallback onRegister;

  static HudHandle add(BuildContext context, Size initialSize, Widget hudWidget) {
    final HudProvider? provider = context.dependOnInheritedWidgetOfExactType<HudProvider>();
    assert(provider != null, 'No HudProvider found in context');
    return provider!.onRegister(context, initialSize, hudWidget);
  }

  @override
  bool updateShouldNotify(HudProvider oldWidget) => false;
}

class _HudRoot extends InheritedWidget {
  const _HudRoot({ /*super.key,*/ required this.handle, required super.child });

  final HudHandle handle;

  @override
  bool updateShouldNotify(_HudRoot oldWidget) => handle != oldWidget.handle;
}

class HudHandle {
  HudHandle(this._state, this._targetContext, this._widget, Size initialSize) :
    _box = _computeBox(_state.context, _targetContext, initialSize);

  static Rect _computeBox(BuildContext a, BuildContext b, Size size) {
    final Matrix4 transform = b.findRenderObject()!.getTransformTo(a.findRenderObject());
    // should be only a translation. if it's more, we're in trouble.
    assert(size.width >= minWidth);
    assert(size.height >= minHeight);
    return Offset(max(transform.storage[12] - 64.0, minX), max(transform.storage[13] - 36.0, minY)) & size;
  }

  final _HudLayoutState _state;
  // ignore: unused_field
  final BuildContext _targetContext; // draw a line from here to there
  final Widget _widget;

  Rect _box;

  static const double minY = 0.0;
  static const double minOverlap = 48.0;
  static const double minX = 0.0;
  static const double minWidth = 400.0;
  static const double minHeight = 240.0;
  
  Widget _buildHud(BuildContext context, Size hudSize) {
    assert(_box.width.round() >= minWidth.round(), 'invalid box: $_box (minWidth=$minWidth)');
    assert(_box.height.round() >= minHeight.round(), 'invalid box: $_box (minHeight=$minHeight)');
    assert(_box.left.round() >= minX.round(), 'invalid box: $_box (minX=$minX)');
    assert(_box.top.round() >= minY.round(), 'invalid box: $_box (minY=$minY)');
    return Positioned(
      top: _box.top.clamp(minY, hudSize.height - minY - minOverlap),
      left: _box.left.clamp(minX, hudSize.width - minX - _box.width),
      width: min(_box.width, hudSize.width),
      height: _box.height,
      child: _HudRoot(
        handle: this,
        child: _widget,
      ),
    );
  }

  void updatePosition(Offset delta) {
    _state.setState(() { // ignore: invalid_use_of_protected_member
      _box = Offset(
        (_box.left + delta.dx).clamp(minX, _state._hudSize.width - minX - _box.width),
        (_box.top + delta.dy).clamp(minY, _state._hudSize.height - minY - minOverlap),
      ) & _box.size;
    });
  }

  void updateSize(Offset delta) {
    _state.setState(() { // ignore: invalid_use_of_protected_member
      _box = _box.topLeft & Size(
        (_box.width + delta.dx).clamp(minWidth, max(minWidth, _state._hudSize.width)),
        max(_box.height + delta.dy, minHeight),
      );
    });
    print(_box.height);
  }
  
  void cancel() {
    _state._remove(this);
  }

  static HudHandle of(BuildContext context) {
    final _HudRoot? provider = context.dependOnInheritedWidgetOfExactType<_HudRoot>();
    assert(provider != null, 'No HudHandle found in context');
    return provider!.handle;
  }
}

class HudDialog extends StatelessWidget {
  const HudDialog({
    super.key,
    this.heading = const Text(''),
    this.child = const Placeholder(),
    this.onClose,
  });

  final Widget child;
  final Widget heading;
  final VoidCallback? onClose;
  
  @override
  Widget build(BuildContext context) {
    return Dialog(
      elevation: 24.0,
      shadowColor: const Color(0xFF000000),
      clipBehavior: Clip.antiAlias,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerSignal: (PointerSignalEvent event) {
          GestureBinding.instance.pointerSignalResolver.register(event, (PointerSignalEvent event) {
            // eat the signal so it doesn't zoom something behind us
          });
        },
        child: Stack(
          children: <Widget>[
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                // TODO: a11y
                GestureDetector(
                  // TODO: consider pinning the cursor while you're dragging, because otherwise it'll
                  // get reset if you drag too far, even though you're still resizing.
                  behavior: HitTestBehavior.opaque,
                  onPanUpdate: (DragUpdateDetails details) {
                    HudHandle.of(context).updatePosition(details.delta);
                  },
                  child: MouseRegion(
                    cursor: SystemMouseCursors.move,
                    child: Row(
                      children: <Widget>[
                        const SizedBox(width: 24.0),
                        Expanded(
                          child: DefaultTextStyle(
                            style: Theme.of(context).textTheme.titleLarge ?? const TextStyle(),
                            child: heading,
                          ),
                        ),
                        const SizedBox(width: 24.0),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () {
                            HudHandle.of(context).cancel();
                            if (onClose != null)
                              onClose!();
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: child,
                ),
              ],
            ),
            Positioned(
              // TODO: a11y
              bottom: 0,
              right: 0,
              child: GestureDetector(
                // TODO: consider pinning the cursor while you're dragging, because otherwise it'll
                // get reset if you drag too far, even though you're still resizing.
                onPanUpdate: (DragUpdateDetails details) {
                  HudHandle.of(context).updateSize(details.delta);
                },
                child: MouseRegion(
                  cursor: SystemMouseCursors.resizeDownRight,
                  child: SizedBox(
                    width: 36.0,
                    height: 36.0,
                    child: Transform.rotate(
                      angle: -pi / 4,
                      child: const Icon(Icons.drag_handle),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
