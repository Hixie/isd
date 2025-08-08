import 'dart:async';
import 'dart:math' show max, min, pi;

import 'package:flutter/material.dart' hide Gradient;

import 'layout.dart';
import 'widgets.dart';

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

abstract interface class HudLayoutInterface { // ignore: one_member_abstracts
  void closeAll();
}

class _HudLayoutState extends State<HudLayout> implements HudLayoutInterface {
  final List<HudHandle> _handles = <HudHandle>[];

  HudHandle _register(BuildContext context, Size initialSize, Widget hudWidget) {
    assert(mounted);
    final HudHandle result = HudHandle(this, context, hudWidget, initialSize);
    setState(() {
      _handles.add(result);
    });
    return result;
  }

  void remove(HudHandle handle) {
    scheduleMicrotask(() {
      if (mounted) {
        setState(() {
          _handles.remove(handle);
        });
      }
    });
  }

  void bringToFront(HudHandle handle) {
    assert(mounted);
    setState(() {
      _handles.remove(handle);
      _handles.add(handle);
    });
  }

  // HudLayoutInterface
  @override
  void closeAll() {
    // does not call onClose for any of the handles
    assert(mounted);
    setState(_handles.clear);
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
    final RenderObject target = b.findRenderObject()!;
    final RenderObject source = a.findRenderObject()!;
    final Matrix4 transform = target.getTransformTo(source);
    // should be only a translation. if it's more, we're in trouble.
    Offset delta = Offset(transform.storage[12] - 64.0, transform.storage[13] - 36.0);
    if (target is RenderWorld) {
      delta += target.paintCenter;
    }
    assert(source is RenderBox); // should be the HudLayout
    final double maxTop = (source as RenderBox).size.height * 0.75;
    delta = Offset(max(minX, delta.dx), max(minY, min(delta.dy, maxTop)));
    assert(size.width >= minWidth);
    assert(size.height >= minHeight);
    return delta & size;
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
      key: ObjectKey(this),
      top: _box.top.clamp(minY, max(hudSize.height - minY - minOverlap, minY + minHeight)),
      left: _box.left.clamp(minX, max(hudSize.width - minX - _box.width, minX + minWidth)),
      width: min(_box.width, max(hudSize.width, minWidth)),
      height: _box.height,
      child: _HudRoot(
        handle: this,
        child: _widget,
      ),
    );
  }

  void updatePosition(Offset delta) {
    assert(_state.mounted);
    _state.setState(() { // ignore: invalid_use_of_protected_member
      _box = Offset(
        (_box.left + delta.dx).clamp(minX, _state._hudSize.width - minX - _box.width),
        (_box.top + delta.dy).clamp(minY, _state._hudSize.height - minY - minOverlap),
      ) & _box.size;
    });
  }

  void updateSize(Offset delta) {
    assert(_state.mounted);
    _state.setState(() { // ignore: invalid_use_of_protected_member
      _box = _box.topLeft & Size(
        (_box.width + delta.dx).clamp(minWidth, max(minWidth, _state._hudSize.width)),
        max(_box.height + delta.dy, minHeight),
      );
    });
  }

  void cancel() {
    _state.remove(this);
  }

  void bringToFront() {
    _state.bringToFront(this);
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
    this.buttons = const <Widget>[],
    this.onClose,
  });

  final Widget child;
  final Widget heading;
  final List<Widget> buttons;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(28.0)),
        side: BorderSide(width: 0.75, color: Color(0x7F666666)),
      ),
      elevation: 24.0,
      shadowColor: const Color(0xFF000000),
      clipBehavior: Clip.antiAlias,
      child: NoZoom(
        child: Listener(
          onPointerDown: (PointerDownEvent event) {
            HudHandle.of(context).bringToFront();
          },
          child: Stack(
            children: <Widget>[
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  // TODO: a11y
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    // TODO: when moving, if you go out of bounds, the cursor gets unpinned from the dialog.
                    onPanUpdate: (DragUpdateDetails details) {
                      HudHandle.of(context).updatePosition(details.delta);
                    },
                    child: MouseRegion(
                      cursor: SystemMouseCursors.move,
                      child: DecoratedBox(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: <Color>[
                              Color(0x00000000),
                              Color(0x11000000),
                              Color(0x00000000),
                              Color(0x11000000),
                              Color(0x00000000),
                              Color(0x11000000),
                              Color(0x00000000),
                              Color(0x11000000),
                              Color(0x00000000),
                            ],
                          ),
                        ),
                        child: Row(
                          children: <Widget>[
                            const SizedBox(width: 24.0),
                            Expanded(
                              child: DefaultTextStyle(
                                style: (Theme.of(context).textTheme.titleLarge ?? const TextStyle()).copyWith(fontWeight: FontWeight.w500),
                                softWrap: false,
                                overflow: TextOverflow.ellipsis,
                                child: heading,
                              ),
                            ),
                            const SizedBox(width: 24.0),                            
                            ...buttons,
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
                  // TODO: when resizing smaller than minimum size, the cursor gets unpinned from the corner.
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
      ),
    );
  }
}
