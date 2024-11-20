import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:cross_local_storage/cross_local_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'connection.dart';
import 'game.dart';
import 'root.dart';
import 'shaders.dart';

void main() async {
  print('INTERSTELLAR DYNASTIES CLIENT');
  WidgetsFlutterBinding.ensureInitialized()
    .platformDispatcher.onError = (Object exception, StackTrace stackTrace) {
      if (exception is HandledError)
        return true;
      return false;
    };
  final ShaderLibrary shaders = await ShaderLibrary.initialize();
  final LocalStorageInterface localStorage = await LocalStorage.getInstance();
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
  runApp(GameRoot(game: game, shaders: shaders));
}

class GameRoot extends StatelessWidget {
  const GameRoot({super.key, required this.game, required this.shaders});

  final Game game;
  final ShaderLibrary shaders;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF000000),
      child: MaterialApp(
        title: 'Interstellar Dynasties',
        color: const Color(0xFF000000),
        home: AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle.light, // TODO: make this depend on the actual UI
          child: Material(
            type: MaterialType.transparency,
            child: ShaderProvider(
              shaders: shaders,
              child: InterstellarDynasties(game: game),
            ),
          ),
        ),
      ),
    );
  }
}

class InterstellarDynasties extends StatefulWidget {
  InterstellarDynasties({required this.game}) : super(key: ValueKey<Game>(game));

  final Game game;

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
  }

  void _changeCredentials() {
  }

  void _doLogout() {
    widget.game.logout();
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
          Positioned(
            top: 0.0,
            left: 0.0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: PopupMenuButton<void>(
                  icon: const Icon(Icons.settings), // TODO: put a dark triangle in the corner in case the game area is white and the icon becomes invisible
                  popUpAnimationStyle: AnimationStyle(
                    curve: Curves.easeInCubic,
                    reverseCurve: Curves.decelerate,
                    duration: const Duration(milliseconds: 400),
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
                  ],
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
