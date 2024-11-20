import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:fs_shim/fs_shim.dart';

import 'connection.dart';
import 'nodes/galaxy.dart';
import 'stringstream.dart';
import 'systems.dart';
import 'world.dart';

class Credentials {
  Credentials(this.username, this.password);
  final String username;
  final String password;
}

typedef ErrorHandler = void Function(Object error);

class HandledError implements Exception {
  const HandledError(this.error);
  final Object error;
}

Future<void> _ignore(Object? value) => Future<void>.value();

class Game {
  Game(String? username, String? password) {
    _connectToLoginServer();
    if (username != null && password != null) {
      login(username, password).catchError(_handleError);
    }
    getGalaxy().then((Galaxy galaxy) {
      print('Galaxy data ready.');
      rootNode.galaxy = galaxy;
    });
  }

  final GalaxyNode rootNode = GalaxyNode();

  final Set<ErrorHandler> _errorHandlers = <ErrorHandler>{};
  void addErrorHandler(ErrorHandler handler) {
    assert(!_errorHandlers.contains(handler));
    _errorHandlers.add(handler);
  }
  void removeErrorHandler(ErrorHandler handler) {
    assert(_errorHandlers.contains(handler));
    _errorHandlers.remove(handler);
  }
  void _handleError(Object error) {
    for (ErrorHandler handler in _errorHandlers) {
      handler(error);
    }
    throw HandledError(error);
  }

  ValueListenable<Credentials?> get credentials => _credentials;
  final ValueNotifier<Credentials?> _credentials = ValueNotifier<Credentials?>(null);

  String? _currentToken;

  static const String _loginServerURL = 'wss://interstellar-dynasties.space:10024/';

  Connection get loginServer => _loginServer!;
  Connection? _loginServer;

  Connection get dynastyServer => _dynastyServer!;
  Connection? _dynastyServer;

  final Set<SystemServer> systemServers = <SystemServer>{};

  ValueListenable<bool> get loggedIn => _loggedIn;
  final ValueNotifier<bool> _loggedIn = ValueNotifier<bool>(false);

  ValueListenable<WorldNode?> get recommendedFocus => _recommendedFocus;
  final ValueNotifier<WorldNode?> _recommendedFocus = ValueNotifier<WorldNode?>(null);

  void _connectToLoginServer() {
    _loginServer = Connection(
      _loginServerURL,
      onError: _handleLoginServerError,
      onTextMessage: _handleLoginServerMessage,
      onBinaryMessage: _handleFile,
      timeout: const Duration(seconds: 10),
    );
  }

  void _handleLoginServerMessage(StreamReader reader) {
    debugPrint('login server: received unexpected message: $reader');
  }

  void _handleLoginServerError(Exception error, Duration duration) {
    debugPrint('login server: received error: $error');
    if (duration > Duration.zero)
      debugPrint('reconnecting in ${duration.inMilliseconds}ms');
  }


  // BINARY FILES

  final Map<int, Completer<Uint8List>> _files = <int, Completer<Uint8List>>{};

  void _handleFile(Uint8List data) {
    // obtained file from network
    final int code = data.buffer.asByteData().getUint32(0, Endian.little);
    assert(_files.containsKey(code));
    _files[code]!.complete(data);
    fileSystemDefault.file('$code.bin').writeAsBytes(data);
  }

  Future<Uint8List> _getFile(int code) async {
    if (!_files.containsKey(code)) {
      _files[code] = Completer<Uint8List>();
      if (await fileSystemDefault.file('$code.bin').exists()) {
        // already cached
        _files[code]!.complete(fileSystemDefault.file('$code.bin').readAsBytes());
      } else {
        // need to get from network
        await _loginServer!.send(<Object>['get-file', code]).then(_ignore).catchError(_handleError);
      }
    }
    return _files[code]!.future;
  }

  Future<Galaxy> getGalaxy() async {
    late final double diameter;
    late final Uint8List data;
    await Future.wait(<Future<void>>[
      _loginServer!.send(<Object>['get-constants'])
        .then<void>((StreamReader reader) { diameter = reader.readDouble(); })
        .catchError(_handleError),
      _getFile(1)
        .then<void>((Uint8List result) { data = result; }),
    ]);
    return Galaxy.from(data, diameter);
  }

  Future<Uint8List> getSystems() async {
    return _getFile(2);
  }


  // LOGIN SERVER COMMANDS

  // throws on error from server
  Future<void> newGame() async {
    _clearCredentials();
    final StreamReader reader = await _loginServer!.send(<Object>['new']);
    _credentials.value = Credentials(reader.readString(), reader.readString());
    _handleLogin(reader);
  }

  // throws on error from server
  Future<void> login(String username, String password) async {
    _clearCredentials();
    _credentials.value = Credentials(username, password);
    _handleLogin(await _loginServer!.send(<Object>['login', username, password]));
  }

  void _handleLogin(StreamReader reader) {
    assert(_currentToken == null);
    final String server = reader.readString();
    _currentToken = reader.readString();
    _connectToDynastyServer(server);
    _loggedIn.value = true;
  }

  Future<void> logout() async {
    final String username = _credentials.value!.username;
    final String password = _credentials.value!.password;
    _clearCredentials();
    await _loginServer!.send(<Object>['logout', username, password]).then(_ignore).catchError(_handleError);
  }

  void _clearCredentials() {
    _loggedIn.value = false;
    _credentials.value = null;
    _recommendedFocus.value = null;
    _currentToken = null;
    rootNode.setCurrentDynastyId(null);
    rootNode.clearSystems();
    _dynastyServer?.dispose();
    _dynastyServer = null;
    for (SystemServer server in systemServers) {
      server.dispose();
    }
    systemServers.clear();
  }

  // DYNASTY SERVER

  void _connectToDynastyServer(String url) {
    _dynastyServer = Connection(
      url,
      onConnected: _handleDynastyConnected,
      onTextMessage: _handleDynastyServerMessage,
      onError: _handleDynastyServerError,
    );
  }

  Future<void> _handleDynastyConnected() async {
    debugPrint('dynasty server: connected, logging in');
    try {
      assert(_currentToken != null);
      final StreamReader reader = await _dynastyServer!.send(<String>['login', _currentToken!], queue: false);
      rootNode.setCurrentDynastyId(reader.readInt());
      final int serverCount = reader.readInt();
      for (int index = 0; index < serverCount; index += 1) {
        systemServers.add(SystemServer(
          reader.readString(),
          _currentToken!,
          rootNode,
          onError: _handleSystemServerError,
          onColonyShip: (WorldNode? node) {
            _recommendedFocus.value = node;
          },
        ));
      }
    } on Exception catch (e) {
      _handleError(e);
    }
  }

  void _handleDynastyServerMessage(StreamReader reader) {
    debugPrint('dynasty server: received unexpected message: $reader');
  }
  
  void _handleDynastyServerError(Exception error, Duration duration) {
    debugPrint('dynasty server: $error');
    if (duration > Duration.zero)
      debugPrint('reconnecting in ${duration.inMilliseconds}ms');
  }

  void _handleSystemServerError(Exception error, Duration duration) {
    debugPrint('system server: $error');
    if (duration > Duration.zero)
      debugPrint('reconnecting in ${duration.inMilliseconds}ms');
  }
}
