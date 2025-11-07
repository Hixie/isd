import 'dart:math' as math;
import 'dart:ui' show ImageFilter, Paragraph, ParagraphBuilder, ParagraphConstraints, ParagraphStyle, PointMode;

import 'package:flutter/material.dart';

import 'connection.dart' show NetworkError;
import 'game.dart';
import 'scores.dart';

class LoginDialog extends StatefulWidget {
  const LoginDialog({ super.key });

  @override
  State<LoginDialog> createState() => _LoginDialogState();
}

class _LoginDialogState extends State<LoginDialog> with RestorationMixin {
  final FocusNode _passwordFocusNode = FocusNode();

  @override
  String? get restorationId => 'login';

  final RestorableTextEditingController _usernameController = RestorableTextEditingController();
  final RestorableTextEditingController _passwordController = RestorableTextEditingController();

  @override
  void restoreState(RestorationBucket? oldBucket, bool initialRestore) {
    registerForRestoration(_usernameController, 'username');
    registerForRestoration(_passwordController, 'password');
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _submit() {
    Navigator.pop<Credentials>(context, Credentials(
      _usernameController.value.text,
      _passwordController.value.text,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return SpaceDialog(
      children: <Widget>[
        SpaceTextField(
          controller: _usernameController.value,
          labelText: 'Username',
          autofillHints: const <String>[ AutofillHints.username ],
          onEditingComplete: _passwordFocusNode.requestFocus,
        ),
        SpaceDialog.gap,
        SpaceTextField(
          controller: _passwordController.value,
          focusNode: _passwordFocusNode,
          labelText: 'Password',
          autofillHints: const <String>[ AutofillHints.password ],
          obscureText: true,
          onEditingComplete: _submit,
        ),
        SpaceDialog.gap,
        Align(
          alignment: Alignment.centerRight,
          child: ListenableBuilder(
            listenable: Listenable.merge(<Listenable>[_usernameController.value, _passwordController.value]),
            builder: (BuildContext context, Widget? child) => FilledButton(
              child: const Text('Connect...'),
              onPressed: (_usernameController.value.text.isNotEmpty && _passwordController.value.text.isNotEmpty) ? _submit : null,
            ),
          ),
        ),
      ],
    );
  }
}

class ChangeCredentialsDialog extends StatefulWidget {
  const ChangeCredentialsDialog({ super.key, required this.initialUsername, required this.initialPassword });

  final String initialUsername;
  final String initialPassword;

  @override
  State<ChangeCredentialsDialog> createState() => _ChangeCredentialsDialogState();
}

class _ChangeCredentialsDialogState extends State<ChangeCredentialsDialog> with RestorationMixin {
  final FocusNode _password1FocusNode = FocusNode();
  final FocusNode _password2FocusNode = FocusNode();

  @override
  String? get restorationId => 'change-credentials';

  late final RestorableTextEditingController _usernameController = RestorableTextEditingController.fromValue(
    // could also start with the existing username but all selected
    widget.initialUsername.contains('\u0010') ? TextEditingValue.empty : TextEditingValue(text: widget.initialUsername),
  );
  late final RestorableTextEditingController _password1Controller = RestorableTextEditingController(text: widget.initialPassword);
  late final RestorableTextEditingController _password2Controller = RestorableTextEditingController(text: widget.initialPassword);

  @override
  void restoreState(RestorationBucket? oldBucket, bool initialRestore) {
    registerForRestoration(_usernameController, 'username');
    registerForRestoration(_password1Controller, 'password1');
    registerForRestoration(_password2Controller, 'password2');
    _usernameController.value.addListener(_check);
    _password1Controller.value.addListener(_check);
    _password2Controller.value.addListener(_check);
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _password1Controller.dispose();
    _password2Controller.dispose();
    super.dispose();
  }

  String? _message = 'Set new username and password.';

  String? _generateMessage() {
    if (_usernameController.value.text == '') {
      return 'Enter a new username.';
    }
    if (_usernameController.value.text.contains('\u0010')) {
      return 'Enter a new username.';
    }
    if (_usernameController.value.text.runes.length > 127) {
      return 'New username is too long.';
    }
    if (_password1Controller.value.text.runes.length < 6) {
      return 'New password is too short.';
    }
    if (_password1Controller.value.text != _password2Controller.value.text) {
      return 'Passwords do not match.';
    }
    return null;
  }

  void _check() {
    setState(() {
      _message = _generateMessage();
    });
  }

  void _submit() {
    Navigator.pop<Credentials>(context, Credentials(
      _usernameController.value.text,
      _password1Controller.value.text,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return SpaceDialog(
      theme: SpaceTheme.dark,
      children: <Widget>[
        SpaceTextField(
          controller: _usernameController.value,
          labelText: 'New username',
          autofillHints: const <String>[ AutofillHints.username ],
          onEditingComplete: _password1FocusNode.requestFocus,
        ),
        SpaceDialog.gap,
        SpaceTextField(
          controller: _password1Controller.value,
          focusNode: _password1FocusNode,
          labelText: 'New password',
          autofillHints: const <String>[ AutofillHints.password ],
          obscureText: true,
          onEditingComplete: _password2FocusNode.requestFocus,
        ),
        SpaceDialog.gap,
        SpaceTextField(
          controller: _password2Controller.value,
          focusNode: _password2FocusNode,
          labelText: 'Confirm new password',
          autofillHints: const <String>[ AutofillHints.password ],
          obscureText: true,
          onEditingComplete: _submit,
        ),
        SpaceDialog.gap,
        Text(_message ?? 'Ready to change credentials.'),
        SpaceDialog.gap,
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton(
            child: const Text('Change credentials...'),
            onPressed: _message == null ? _submit : null,
          ),
        ),
      ],
    );
  }
}

class ScoresDialog extends StatefulWidget {
  const ScoresDialog({ super.key });

  @override
  State<ScoresDialog> createState() => _ScoresDialogState();
}

class _ScoresDialogState extends State<ScoresDialog> {
  Game? _game;
  HighScores? _scores;
  String? _error;

  @override
  void didChangeDependencies() {
    final Game game = GameProvider.of(context);
    if (game != _game) {
      _game?.loggedIn.removeListener(_handleLoggedIn);
      _game = game;
      _game?.loggedIn.addListener(_handleLoggedIn);
      _update();
    }
    super.didChangeDependencies();
  }

  void _handleLoggedIn() {
    _update();
  }

  @override
  void dispose() {
    _game?.loggedIn.removeListener(_handleLoggedIn);
    super.dispose();
  }

  Future<void> _update() async {
    if (_game != null) {
      try {
        final HighScores scores = await _game!.getHighScores();
        if (mounted) {
          setState(() {
            if (scores.dynasties.isEmpty) {
              _scores = null;
              _error = 'No dynasties.';
            } else {
              _scores = scores;
              _error = null;
            }
          });
        }
      } on NetworkError catch (e) {
        if (mounted) {
          setState(() {
            _scores = null;
            _error = e.message;
          });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return SpaceDialog(
        theme: SpaceTheme.dark,
        constraints: const BoxConstraints(),
        children: <Widget>[
          Text('Error fetching scores: $_error'),
        ],
      );
    }
    if (_scores == null) {
      return const SpaceDialog(
        theme: SpaceTheme.dark,
        constraints: BoxConstraints(),
        children: <Widget>[
          CircularProgressIndicator(),
          SpaceDialog.gap,
          Text('Fetching scores...'),
        ],
      );
    }
    final List<Widget> legend = <Widget>[];
    for (DynastyHistory dynasty in _scores!.dynasties) {
      legend.add(Padding(
        padding: const EdgeInsets.all(8.0),
        child: Text.rich(TextSpan(
          children: <InlineSpan>[
            TextSpan(text: '⚫', style: TextStyle(color: dynasty.color)),
            TextSpan(text: ' Dynasty ${dynasty.dynastyId}'),
          ],
        )),
      ));
    }
    return SpaceDialog(
      theme: SpaceTheme.dark,
      constraints: const BoxConstraints(),
      children: <Widget>[
        AspectRatio(
          aspectRatio: 2.0,
          child: Builder(
            builder: (BuildContext context) => CustomPaint(
              painter: ScoreChart(
                scores: _scores,
                textStyle: DefaultTextStyle.of(context).style,
              ),
            ),
          ),
        ),
        Wrap(children: legend),
      ],
    );
  }
}

class ScoreChart extends CustomPainter {
  ScoreChart({
    required this.scores,
    this.inset = 40.0,
    this.textStyle = const TextStyle(),
  });

  final HighScores? scores;
  final double inset;
  final TextStyle textStyle;

  // TODO: make these final
  Paint get _axisPaint => Paint()
    ..color = const Color(0xFFFFFFFF)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.0;
  Paint get _linePaint => Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 4.0;

  @override
  void paint(Canvas canvas, Size size) {
    int? earliest;
    int? latest;
    double highest = 0.0;
    double lowest = 0.0;
    if (scores != null) {
      for (DynastyHistory dynasty in scores!.dynasties) {
        if (earliest == null || earliest > dynasty.points.first.timestamp)
          earliest = dynasty.points.first.timestamp;
        if (latest == null || latest < dynasty.points.last.timestamp)
          latest = dynasty.points.last.timestamp;
        for (ScorePoint point in dynasty.points) {
          if (highest < point.score) {
            highest = point.score;
          }
          if (lowest > point.score) {
            lowest = point.score;
          }
        }
      }
    }
    final double verticalRange = highest - lowest;
    final double x0 = inset;
    final double y0 = inset + (size.height - inset * 2.0) * highest / verticalRange;
    final double scoreScale = (size.height - inset * 2.0) / verticalRange;
    canvas.drawPoints(PointMode.lines, <Offset>[
      Offset(x0, 0.0), Offset(x0, size.height), // y axis
      Offset(0.0, y0), Offset(size.width, y0), // x axis
    ], _axisPaint);
    if (earliest != null) {
      latest!;
      final int timeRange = latest - earliest;
      final double timeScale = (size.width - x0) / timeRange;
      final List<Offset> points = <Offset>[];
      for (DynastyHistory dynasty in scores!.dynasties) {
        points.clear();
        for (ScorePoint point in dynasty.points) {
          points.add(Offset(x0 + timeScale * (point.timestamp - earliest), y0 - scoreScale * point.score));
        }
        points.add(Offset(size.width, y0 - scoreScale * dynasty.points.last.score));
        canvas.drawPoints(PointMode.polygon, points, _linePaint..color = dynasty.color);
      }
      final int segments = (size.width - inset) ~/ (inset * 4.0);
      // TODO: do something more like what we do with the length scale, so the numbers are cleaner
      if (segments > 2) {
        points.clear();
        for (int index = 1; index < segments; index += 1) {
          final double x = x0 + index * (timeRange / segments) * timeScale;
          points.add(Offset(x, y0));
          points.add(Offset(x, y0 + inset / 4.0));
          final ParagraphBuilder timePB = ParagraphBuilder(ParagraphStyle())
            ..pushStyle(textStyle.getTextStyle()) // TODO: apply global text scaler
            ..addText(prettyTime(((segments - index) * timeRange / segments).round()));
          final Paragraph timeP = timePB.build();
          timeP.layout(const ParagraphConstraints(width: double.infinity));
          final Offset pos = Offset(x - timeP.maxIntrinsicWidth / 2.0, y0 + inset / 4.0);
          canvas.drawParagraph(timeP, pos);
        }
        canvas.drawPoints(PointMode.lines, points, _axisPaint);
      }
    }
    final ParagraphBuilder scorePB = ParagraphBuilder(ParagraphStyle())
      ..pushStyle(textStyle.getTextStyle()) // TODO: apply global text scaler
      ..addText('Happiness');
    final Paragraph scoreP = scorePB.build();
    scoreP.layout(const ParagraphConstraints(width: double.infinity));
    canvas.translate(x0, y0);
    canvas.rotate(-math.pi / 2);
    canvas.translate(-x0, -y0);
    canvas.drawParagraph(scoreP, Offset(x0 + inset / 2.0, y0 - inset / 2.0 - (textStyle.fontSize ?? 10.0)));
  }

  static String prettyTime(int time) {
    double value;
    if (time < 120)
      return '-${time}s';
    value = time / 60.0;
    if (value < 120)
      return '-${value.toStringAsFixed(0)} min';
    value = time / (60.0 * 60.0);
    if (value < 50)
      return '-${value.toStringAsFixed(1)}h';
    value = time / (60.0 * 60.0 * 24.0);
    if (value < 30)
      return '-${value.toStringAsFixed(1)} days';
    value = time / (60.0 * 60.0 * 24.0 * 7.0);
    if (value < 60)
      return '-${value.toStringAsFixed(1)} weeks';
    value = time / (60.0 * 60.0 * 24.0 * 365.25);
    if (value < 15)
      return '-${value.toStringAsFixed(1)} years';
    value = time / (60.0 * 60.0 * 24.0 * 365.25 * 10.0);
    return '-${value.toStringAsFixed(1)} decades';
  }

  @override
  bool shouldRepaint(ScoreChart oldDelegate) => oldDelegate.scores != scores;
}

class SpaceTextField extends StatelessWidget {
  const SpaceTextField({
    super.key,
    this.controller,
    this.focusNode,
    this.labelText,
    this.autofillHints,
    this.obscureText = false,
    this.onEditingComplete,
  });

  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String? labelText;
  final List<String>? autofillHints;
  final bool obscureText;
  final VoidCallback? onEditingComplete;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      autofocus: focusNode == null,
      focusNode: focusNode,
      decoration: InputDecoration(
        filled: true,
        fillColor: const Color(0x22999999),
        labelText: labelText,
        labelStyle: DefaultTextStyle.of(context).style.copyWith(color: Colors.white, fontStyle: FontStyle.italic),
        hoverColor: const Color(0x11FFFFFF),
        border: const OutlineInputBorder(),
      ),
      style: DefaultTextStyle.of(context).style.copyWith(color: Colors.white),
      cursorColor: const Color(0xEEFFFFFF),
      cursorWidth: 1.0,
      autofillHints: autofillHints,
      obscureText: obscureText,
      onEditingComplete: onEditingComplete,
    );
  }
}

enum SpaceTheme { light, dark }

class SpaceDialog extends StatelessWidget {
  const SpaceDialog({
    super.key,
    this.theme = SpaceTheme.light,
    this.children = const <Widget>[],
    this.constraints = const BoxConstraints(maxWidth: 280.0),
  });

  final SpaceTheme theme;
  final List<Widget> children;
  final BoxConstraints constraints;

  static const Widget gap = SizedBox(height: 16.0);

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: theme == SpaceTheme.light ? const Color(0x11FFFFFF) : const Color(0xBB000000),
      clipBehavior: Clip.antiAlias,
      shape: const RoundedSuperellipseBorder(
        borderRadius: BorderRadius.all(Radius.circular(28.0)),
        side: BorderSide(color: Color(0x7FFFFFFF), width: 0.5),
      ),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 1.0, sigmaY: 3.0),
        blendMode: BlendMode.src,
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: AutofillGroup(
            child: Builder(
              builder: (BuildContext context) {
                final Color tint = Theme.of(context).colorScheme.primary;
                return TextSelectionTheme(
                  data: TextSelectionThemeData(
                    selectionColor: tint,
                  ),
                  child: FilledButtonTheme(
                    data: FilledButtonThemeData(
                      style: FilledButton.styleFrom(
                        backgroundColor: tint,
                        disabledBackgroundColor: const Color(0x33999999),
                        disabledForegroundColor: const Color(0xFF999999),
                      ),
                    ),
                    child: DefaultTextStyle(
                      style: DefaultTextStyle.of(context).style.copyWith(color: Colors.white),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: ConstrainedBox(
                          constraints: constraints,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: children,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class GameProvider extends InheritedWidget {
  const GameProvider({
    super.key,
    required this.game,
    required super.child,
  });

  final Game game;

  static Game of(BuildContext context) {
    final GameProvider? provider = context.dependOnInheritedWidgetOfExactType<GameProvider>();
    assert(provider != null, 'No GameProvider found in context');
    return provider!.game;
  }

  @override
  bool updateShouldNotify(GameProvider oldWidget) => game != oldWidget.game;
}
