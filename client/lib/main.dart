import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:cross_local_storage/cross_local_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'connection.dart';
import 'dialogs.dart';
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
  @override
  void reassemble() {
    super.reassemble();
    widget.icons.resetCache();
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF000000),
      child: GameProvider(
        game: widget.game,
        child: MaterialApp(
          // showSemanticsDebugger: true, // TODO: fix a11y (all the RenderWorld nodes don't report semantics)
          restorationScopeId: 'isd',
          title: 'Interstellar Dynasties',
          color: const Color(0xFF000000),
          theme: ThemeData.from(colorScheme: ColorScheme.fromSeed(seedColor: const Color(0x5522FF99))),
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
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class InterstellarDynasties extends StatefulWidget {
  InterstellarDynasties({
    required this.game,
  }) : super(key: ValueKey<Game>(game));

  final Game game;

  @override
  _InterstellarDynastiesState createState() => _InterstellarDynastiesState();
}

@pragma('vm:entry-point')
class _InterstellarDynastiesState extends State<InterstellarDynasties> with RestorationMixin {
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

  // DIALOGS

  @override
  String get restorationId => 'main';

  @override
  void restoreState(RestorationBucket? oldBucket, bool initialRestore) {
    registerForRestoration(_loginRoute, 'login');
    registerForRestoration(_changeCredentialsRoute, 'change-credentials');
    registerForRestoration(_showScoresRoute, 'show-scores');
    registerForRestoration(_aboutRoute, 'about');
  }

  // LOGIN

  late final RestorableRouteFuture<Credentials?> _loginRoute = RestorableRouteFuture<Credentials?>(
    onPresent: (NavigatorState navigator, Object? arguments) {
      return navigator.restorablePush(_loginRouteBuilder, arguments: arguments);
    },
    onComplete: (Credentials? value) async {
      if (value != null) {
        try {
          await widget.game.loginWithCredentials(value);
        } on NetworkError catch (error) {
          _handleError(error);
        }
      }
    },
  );

  @pragma('vm:entry-point')
  static Route<Credentials?> _loginRouteBuilder(BuildContext context, Object? arguments) {
    return DialogRoute<Credentials?>(
      context: context,
      builder: (BuildContext context) => const LoginDialog(),
    );
  }

  void _doLogin() {
    _loginRoute.present();
  }

  // CHANGE USERNAME/PASSWORD

  late final RestorableRouteFuture<Credentials?> _changeCredentialsRoute = RestorableRouteFuture<Credentials?>(
    onPresent: (NavigatorState navigator, Object? arguments) {
      return navigator.restorablePush(_changeCredentialsRouteBuilder, arguments: arguments);
    },
    onComplete: (Credentials? value) async {
      if (value != null) {
        final NetworkError? error = await widget.game.changeCredentials(value);
        if (error != null) {
          _handleError(error);
        } else {
          _setMessage('Username and password set!');
        }
      }
    },
  );

  @pragma('vm:entry-point')
  static Route<Credentials?> _changeCredentialsRouteBuilder(BuildContext context, Object? arguments) {
    final List<String> credentials = arguments! as List<String>;
    return DialogRoute<Credentials?>(
      context: context,
      builder: (BuildContext context) => ChangeCredentialsDialog(initialUsername: credentials[0], initialPassword: credentials[1]),
    );
  }

  void _doChangeCredentials() {
    _changeCredentialsRoute.present(<String>[widget.game.credentials.value?.username ?? '', widget.game.credentials.value?.password ?? '']);
  }

  // SHOW SCORES

  late final RestorableRouteFuture<void> _showScoresRoute = RestorableRouteFuture<void>(
    onPresent: (NavigatorState navigator, Object? arguments) {
      return navigator.restorablePush(_showScoresRouteBuilder, arguments: arguments);
    },
  );

  @pragma('vm:entry-point')
  static Route<void> _showScoresRouteBuilder(BuildContext context, Object? arguments) {
    return DialogRoute<void>(
      context: context,
      builder: (BuildContext context) => const ScoresDialog(),
    );
  }

  void _showScores() {
    _showScoresRoute.present();
  }

  // ABOUT

  late final RestorableRouteFuture<void> _aboutRoute = RestorableRouteFuture<void>(
    onPresent: (NavigatorState navigator, Object? arguments) {
      return navigator.restorablePush(_aboutRouteBuilder, arguments: arguments);
    },
  );

  @pragma('vm:entry-point')
  static Route<void> _aboutRouteBuilder(BuildContext context, Object? arguments) {
    return DialogRoute<void>(
      context: context,
      builder: (BuildContext context) => const AboutDialog(
        applicationName: 'Ian\u00A0Hickson\'s Interstellar\u00A0Dynasties',
        children: <Widget>[
          Padding(
            padding: EdgeInsets.fromLTRB(24.0, 0.0, 24.0, 8.0),
            child: Text('The online multiplayer persistent-universe real-time strategy game of space discovery and empire building.'),
          ),
          Text('https://interstellar-dynasties.space/', textAlign: TextAlign.center),
        ],
      ),
    );
  }

  void _doAbout() {
    _aboutRoute.present();
  }

  // END OF DIALOGS

  final GlobalKey hudKey = GlobalKey();

  void _doLogout() {
    widget.game.logout();
    (hudKey.currentState! as HudLayoutInterface).closeAll();
  }

  void _handleError(Object error) {
    // TODO: prettier error messages
    if (error is NetworkError) {
      switch (error.message) {
        case 'unrecognized credentials':
          _setMessage('Invalid username or password.');
        case 'inadequate username':
          _setMessage('There is already a dynasty using that username.');
        case 'inadequate password':
          _setMessage('That password is not sufficiently secure.');
        default:
          debugPrint('unrecognized error code: ${error.message}');
          _setMessage(error.message);
      }
    } else {
      _setMessage(error.toString());
    }
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
                      PopupMenuItem<void>(
                        child: const ListTile(
                          leading: Icon(Icons.show_chart),
                          title: Text('View high scores'),
                        ),
                        onTap: _showScores,
                      ),
                      if (loggedIn)
                        PopupMenuItem<void>(
                          child: ListTile(
                            leading: const Icon(Icons.password),
                            title: widget.game.credentials.value!.username.contains('\u0010')
                                    ? const Text('Set username and password')
                                    : const Text('Change username or password'),
                          ),
                          onTap: _doChangeCredentials,
                        ),
                      if (loggedIn)
                        PopupMenuItem<void>(
                          child: const ListTile(
                            leading: Icon(Icons.logout),
                            title: Text('Logout'),
                          ),
                          onTap: _doLogout,
                        ),
                      const PopupMenuDivider(),
                      PopupMenuItem<void>(
                        child: const ListTile(
                          leading: Icon(Icons.help),
                          title: Text('About'),
                        ),
                        onTap: _doAbout,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          PositionedDirectional(
            top: 0.0,
            end: 0.0,
            child: ValueListenableBuilder<bool>(
              valueListenable: widget.game.connectionStatus,
              builder: (BuildContext context, bool networkProblem, Widget? child) => DisableSubtree(
                disabled: !networkProblem,
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: AlignmentDirectional.topEnd,
                      end: AlignmentDirectional.bottomStart,
                      colors: <Color>[
                        Color(0x99000000),
                        Color(0x00000000),
                        Color(0x00000000),
                      ],
                    ),
                  ),
                  child: SafeArea(
                    child: Padding(
                      padding: const EdgeInsetsDirectional.fromSTEB(32.0, 8.0, 8.0, 32.0),
                      child: IconButton(
                        icon: Icon(Icons.cloud_off, shadows: kElevationToShadow[1]),
                        tooltip: 'Try to reconnect immediately',
                        color: Theme.of(context).colorScheme.onSecondary,
                        onPressed: () {
                          widget.game.connectionStatus.triggerReset();
                        },
                      ),
                    ),
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
            filter: ImageFilter.blur(sigmaX: 1.0, sigmaY: 3.0),
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
