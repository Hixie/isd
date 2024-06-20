import 'dart:math';

import 'package:cross_local_storage/cross_local_storage.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import 'game.dart';
import 'renderers.dart';
import 'widgets.dart';
import 'zoom.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final LocalStorageInterface localStorage = await LocalStorage.getInstance();
  final Game game = Game(localStorage.getString('username'), localStorage.getString('password'));
  game.credentials.addListener(() {
    final Credentials? value = game.credentials.value;
    if (value == null) {
      localStorage.remove('username');
      localStorage.remove('password');
    } else {
      localStorage.setString('username', value.username);
      localStorage.setString('password', value.password);
    }
  });
  runApp(InterstellarDynasties(game: game));
}

class InterstellarDynasties extends StatefulWidget {
  InterstellarDynasties({required this.game}) : super(key: ValueKey<Game>(game));

  final Game game;
  
  @override
  _InterstellarDynastiesState createState() => _InterstellarDynastiesState();
}

class _InterstellarDynastiesState extends State<InterstellarDynasties> {
  bool _pending = false;
  
  Future<void> _doNewGame() async {
    setState(() { _pending = true; });
    try {
      await widget.game.newGame();
    } finally {
      setState(() { _pending = false; });
    }
  }

  void _doLogin() {
  }

  ZoomSpecifier _zoom = PanZoomSpecifier.none;
  PanZoomSpecifier? _zoomAnchor;
  Offset? _focalPoint;

  final GlobalKey _worldRootKey = GlobalKey();
  RenderBoxToRenderWorldAdapter get _worldRoot => _worldRootKey.currentContext!.findRenderObject()! as RenderBoxToRenderWorldAdapter;
  
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: widget.game.loggedIn,
      builder: (BuildContext context, bool loggedIn, Widget? child) => WidgetsApp(
        title: 'Interstellar Dynasties',
        color: const Color(0xFF000000),
        builder: (BuildContext context, Widget? navigator) => Stack(
          fit: StackFit.expand,
          children: <Widget>[
            Listener(
              onPointerSignal: (PointerSignalEvent event) {
                GestureBinding.instance.pointerSignalResolver.register(event, (PointerSignalEvent event) {
                  if (event is PointerScrollEvent) {
                    final Size size = _worldRootKey.currentContext!.size!;
                    final Offset panOffset = _worldRoot.panOffset;
                    final double zoomFactor = _worldRoot.zoomFactor;
                    setState(() {
                      _zoom = _zoom.withScale(
                        event.scrollDelta.dy / -1000.0,
                        (event.localPosition - panOffset) / (size.shortestSide * zoomFactor),
                        Offset(event.localPosition.dx / size.width, event.localPosition.dy / size.height),
                      );
                    });
                  }
                });
              },
              child: GestureDetector(
                trackpadScrollCausesScale: true,
                onScaleStart: (ScaleStartDetails details) {
                  _zoomAnchor = _zoom.last;
                  _focalPoint = details.focalPoint;
                },
                onScaleUpdate: (ScaleUpdateDetails details) {
                  setState(() {
                    final Size size = _worldRootKey.currentContext!.size!;
                    final Offset delta = details.focalPoint - _focalPoint!;
                    _zoom = _zoom.withPan(PanZoomSpecifier(
                      _zoomAnchor!.sourceFocalPointFraction,
                      _zoomAnchor!.destinationFocalPointFraction + Offset(delta.dx / size.width, delta.dy / size.height),
                      max(1.0, _zoomAnchor!.zoom * details.scale),
                    ));
                  });
                },
                onScaleEnd: (ScaleEndDetails details) {
                  _zoomAnchor = null;
                },
                child: BoxToWorldAdapter(
                  key: _worldRootKey,
                  child: widget.game.rootNode.build(context, _zoom),
                ),
              ),
            ),
            if (!loggedIn)
              ValueListenableBuilder<bool>(
                valueListenable: widget.game.loginServer.connected,
                builder: (BuildContext context, bool connected, Widget? child) => Menu(
                  active: true,
                  onNewGame: connected && !_pending ? _doNewGame : null,
                  onLogin: connected && !_pending ? _doLogin : null,
                ),
            ),
          ],
        ),
      ),
    );
  }
}

class Menu extends StatefulWidget {
  const Menu({
    super.key,
    required this.active,
    required this.onNewGame,
    required this.onLogin,
  });

  final bool active;
  final VoidCallback? onNewGame;
  final VoidCallback? onLogin;

  @override
  _MenuState createState() => _MenuState();
}

class _MenuState extends State<Menu> {
  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      duration: const Duration(seconds: 2),
      curve: Curves.easeInOutCubic,
      opacity: widget.active ? 1.0 : 0.0,
      child: Row(
        children: <Widget>[
          const Spacer(),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: <Widget>[
                Button(child: const Text('New Game'), onPressed: widget.active ? widget.onNewGame : null),
                Button(child: const Text('Login'), onPressed: widget.active ? widget.onLogin : null),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class Button extends StatefulWidget {
  const Button({super.key, required this.child, required this.onPressed});

  final Widget child;
  final VoidCallback? onPressed;
  
  @override
  _ButtonState createState() => _ButtonState();
}

class _ButtonState extends State<Button> {
  bool _down = false;
  
  void _handleDown(TapDownDetails details) {
    setState(() { _down = true; });
  }
  
  void _handleUp(TapUpDetails details) {
    setState(() { _down = false; });
  }
  
  void _handleCancel() {
    setState(() { _down = false; });
  }
  
  void _handleTap() {
    widget.onPressed!();
  }

  @override
  void didUpdateWidget(Button oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.onPressed == null) {
      _down = false;
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: widget.onPressed == null ? null : _handleDown,
      onTapUp: widget.onPressed == null ? null : _handleUp,
      onTapCancel: widget.onPressed == null ? null : _handleCancel,
      onTap: widget.onPressed == null ? null : _handleTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 80),
        curve: Curves.easeInOut,
        decoration: ShapeDecoration(
          shape: StadiumBorder(
            side: BorderSide(
              width: 4.0,
              color: widget.onPressed == null ? const Color(0xFF999999) : const Color(0xFF999900),
            )
          ),
          color: widget.onPressed == null ? const Color(0xFF666666) : _down ? const Color(0xFFFFFF00) : const Color(0xFFDDCC00),
        ),
        width: 275.0,
        height: 80.0,
        alignment: Alignment.center,
        child: DefaultTextStyle(
          style: const TextStyle(fontSize: 40.0, fontWeight: FontWeight.bold, color: Color(0xFF000000)),
          child: widget.child,
        ),
      ),
    );
  }
}
