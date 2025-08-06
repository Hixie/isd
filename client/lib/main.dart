import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:cross_local_storage/cross_local_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'connection.dart';
import 'game.dart';
import 'http/http.dart' as http;
import 'hud.dart';
import 'icons.dart';
import 'root.dart';
import 'shaders.dart';

int kCacheSize = 10 * 1024 * 1024;

void main() async {
  print('INTERSTELLAR DYNASTIES CLIENT');
  WidgetsFlutterBinding.ensureInitialized()
    .platformDispatcher.onError = (Object exception, StackTrace stackTrace) {
      if (exception is HandledError)
        return true;
      return false;
    };
  // TODO: show widgets while the async load is happening
  final Stopwatch stopwatch = Stopwatch()..start();
  late final ShaderLibrary shaders;
  late final LocalStorageInterface localStorage;
  late final IconsManager icons;
  await Future.wait(<Future<void>>[
    ShaderLibrary.initialize().then((ShaderLibrary value) async { shaders = value; }),
    IconsManager.initialize(http.createClient(userAgent: 'ISD/1', cacheSize: kCacheSize)).then((IconsManager value) async { icons = value; }),
    Future<LocalStorageInterface>.value(LocalStorage.getInstance()).then((LocalStorageInterface value) async { localStorage = value; }),
  ]);
  final Game game = Game(
    localStorage.getString('username'),
    localStorage.getString('password'),
  );
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
  print('Startup took ${stopwatch.elapsed}');
  runApp(GameRoot(
    game: game,
    shaders: shaders,
    icons: icons,
  ));
}

class GameRoot extends StatefulWidget {
  const GameRoot({
    super.key,
    required this.game,
    required this.shaders,
    required this.icons,
  });

  final Game game;
  final ShaderLibrary shaders;
  final IconsManager icons;

  @override
  State<GameRoot> createState() => _GameRootState();
}

class _GameRootState extends State<GameRoot> {
  bool _debug = false;

  @override
  void reassemble() {
    super.reassemble();
    widget.icons.resetCache();
  }
  
  @override
  Widget build(BuildContext context) {
    Widget app = MaterialApp(
      // showSemanticsDebugger: true, // TODO: fix a11y (all the RenderWorld nodes don't report semantics)
      title: 'Interstellar Dynasties',
      color: const Color(0xFF000000),
      home: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light, // TODO: make this depend on the actual UI
        child: Material(
          type: MaterialType.transparency,
          child: ShaderProvider(
            shaders: widget.shaders,
            child: IconsManagerProvider(
              icons: widget.icons,
              child: InterstellarDynasties(
                game: widget.game,
                onToggleDebug: () { setState(() { _debug = !_debug; }); },
              ),
            ),
          ),
        ),
      ),
    );
    if (_debug) {
      app = Padding(
        padding: const EdgeInsets.all(36.0),
        child: app,
      );
    }
    return ColoredBox(
      color: const Color(0xFF000000),
      child: app,
    );
  }
}

class InterstellarDynasties extends StatefulWidget {
  InterstellarDynasties({
    required this.game,
    required this.onToggleDebug,
  }) : super(key: ValueKey<Game>(game));

  final Game game;
  final VoidCallback onToggleDebug;

  @override
  _InterstellarDynastiesState createState() => _InterstellarDynastiesState();
}

class _InterstellarDynastiesState extends State<InterstellarDynasties> {
  bool _pending = false;
  bool _showMessage = false;
  String _message = '';
  Timer? _messageTimer;

  @override
  void initState() {
    super.initState();
    widget.game.addErrorHandler(_handleError);
  }

  @override
  void didUpdateWidget(InterstellarDynasties oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.game != widget.game) {
      oldWidget.game.removeErrorHandler(_handleError);
      widget.game.addErrorHandler(_handleError);
    }
  }

  Future<void> _doNewGame() async {
    setState(() { _pending = true; });
    try {
      debugPrint('Starting new game...');
      await widget.game.newGame();
    } on NetworkError catch (e) {
      debugPrint('$e');
      _setMessage(e.message);
    } finally {
      setState(() { _pending = false; });
    }
  }

  void _doLogin() {
    // TODO: show dialog asking for credentials
    // see https://main-api.flutter.dev/flutter/widgets/RestorableRouteFuture-class.html
  }

  void _changeCredentials() {
    // TODO: show dialog asking for credentials
    // see https://main-api.flutter.dev/flutter/widgets/RestorableRouteFuture-class.html
  }

  final GlobalKey hudKey = GlobalKey();
  
  void _doLogout() {
    widget.game.logout();
    (hudKey.currentState! as HudLayoutInterface).closeAll();
  }

  void _doAbout() {
    showAboutDialog(
      context: context,
      applicationName: 'Ian\u00A0Hickson\'s Interstellar\u00A0Dynasties',
      children: const <Widget>[
        Padding(
          padding: EdgeInsets.fromLTRB(24.0, 0.0, 24.0, 8.0),
          child: Text('The online multiplayer persistent-universe real-time strategy game of space discovery and empire building.'),
        ),
        Text('https://interstellar-dynasties.space/', textAlign: TextAlign.center),
      ],
    );
  }

  // TODO: make it clearer when we are currently disconnected (e.g. show a pulsing "disconnect" icon)
  
  void _handleError(Object error) {
    // TODO: prettier error messages
    _setMessage(error.toString());
  }

  void _setMessage(String message) {
    if (message != _message || !_showMessage) {
      _messageTimer?.cancel();
      setState(() {
        _message = message;
        _showMessage = true;
      });
      _messageTimer = Timer(const Duration(seconds: 10), () {
        setState(() { _showMessage = false; });
      });
    }
  }

  @override
  void dispose() {
    widget.game.removeErrorHandler(_handleError);
    _messageTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: widget.game.loggedIn,
      builder: (BuildContext context, bool loggedIn, Widget? child) => Stack(
        fit: StackFit.expand,
        children: <Widget>[
          WorldRoot(
            rootNode: widget.game.rootNode,
            recommendedFocus: widget.game.recommendedFocus,
            dynastyManager: widget.game.dynastyManager,
            hudKey: hudKey,
          ),
          Positioned(
            top: 0.0,
            left: 0.0,
            right: 0.0,
            child: IgnorePointer(
              child: AnimatedOpacity(
                duration: loggedIn ? const Duration(milliseconds: 5000) : const Duration(milliseconds: 1000),
                curve: Curves.easeIn,
                opacity: loggedIn ? 0.0 : 1.0,
                child: const FittedBox(
                  child: Padding(
                    padding: EdgeInsets.all(200.0),
                    child: Text(
                      'Interstellar\nDynasties',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 200.0,
                        fontWeight: FontWeight.w900,
                        shadows: <Shadow>[Shadow(offset: Offset(0.0, 10.0), blurRadius: 100.0)],
                        height: 0.45,
                        color: Color(0xFFFFFFFF),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          // TODO: have a third state, "logging in", during which the UI is disabled and we show a progress indicator
          DisableSubtree(
            disabled: loggedIn,
            child: ValueListenableBuilder<bool>(
              valueListenable: widget.game.loginServer.connected,
              builder: (BuildContext context, bool connected, Widget? child) => CustomSingleChildLayout(
                delegate: const MenuLayoutDelegate(),
                child: FittedBox(
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: SizedBox(
                      height: 120.0,
                      width: 150.0,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          const Spacer(),
                          Expanded(
                            child: Button(child: const Text('New Game'), onPressed: !_pending ? _doNewGame : null),
                          ),
                          const Spacer(),
                          Expanded(
                            child: Button(child: const Text('Login'), onPressed: !_pending ? _doLogin : null),
                          ),
                          const Spacer(),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          PositionedDirectional(
            top: 0.0,
            start: 0.0,
            child: DecoratedBox(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: AlignmentDirectional.topStart,
                  end: AlignmentDirectional.bottomEnd,
                  colors: <Color>[
                    Color(0x99000000),
                    Color(0x00000000),
                    Color(0x00000000),
                  ],
                ),
              ),
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(8.0, 8.0, 32.0, 32.0),
                  child: PopupMenuButton<void>(
                    icon: Icon(Icons.settings, shadows: kElevationToShadow[1]),
                    popUpAnimationStyle: const AnimationStyle(
                      curve: Curves.easeInCubic,
                      reverseCurve: Curves.decelerate,
                      duration: Duration(milliseconds: 400),
                    ),
                    iconColor: Theme.of(context).colorScheme.onSecondary,
                    itemBuilder: (BuildContext context) => <PopupMenuEntry<void>>[
                      if (loggedIn)
                        PopupMenuItem<void>(
                          child: const Text('Change username or password'),
                          onTap: _changeCredentials,
                        ),
                      if (loggedIn)
                        PopupMenuItem<void>(
                          child: const Text('Logout'),
                          onTap: _doLogout,
                        ),
                      if (loggedIn)
                        const PopupMenuDivider(),
                      PopupMenuItem<void>(
                        child: const Text('About'),
                        onTap: _doAbout,
                      ),
                      if (!kReleaseMode)
                        const PopupMenuDivider(),
                      if (!kReleaseMode)
                        PopupMenuItem<void>(
                          child: const Text('Toggle Debug'),
                          onTap: widget.onToggleDebug,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: DisableSubtree(
              disabled: !_showMessage,
              child: GestureDetector(
                onTap: () { setState(() { _showMessage = false; }); },
                child: FittedBox(
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Card(
                      elevation: 8.0,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: 2.0,
                          horizontal: 8.0,
                        ),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            minWidth: 400.0,
                          ),
                          child: Text(
                            _message,
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class Button extends StatelessWidget {
  const Button({super.key, required this.child, required this.onPressed});

  final Widget child;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      child: OutlinedButton(
        onPressed: onPressed,
        clipBehavior: Clip.antiAlias,
        child: DefaultTextStyle(
          style: const TextStyle(
            fontWeight: FontWeight.w700,
          ),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 4.0, sigmaY: 4.0),
            blendMode: BlendMode.src,
            child: child,
          ),
        ),
      ),
    );
  }
}

class DisableSubtree extends StatelessWidget {
  const DisableSubtree({super.key, this.disabled = true, required this.child});

  final bool disabled;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeInOut,
      opacity: disabled ? 0.0 : 1.0,
      child: IgnorePointer(
        ignoring: disabled,
        child: ExcludeFocus(
          excluding: disabled,
          child: ExcludeSemantics(
            excluding: disabled,
            child: child,
          ),
        ),
      ),
    );
  }
}

class MenuLayoutDelegate extends SingleChildLayoutDelegate {
  const MenuLayoutDelegate();

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    return BoxConstraints.tight(Size(
      math.min(math.max(600.0, constraints.maxWidth / 2.0), constraints.maxWidth),
      math.min(math.max(400.0, constraints.maxHeight / 2.0), constraints.maxHeight),
    ));
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    return Alignment.bottomRight.inscribe(childSize, Offset.zero & size).topLeft;
  }

  @override
  bool shouldRelayout(MenuLayoutDelegate oldDelegate) => false;
}
