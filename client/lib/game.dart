import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:fs_shim/fs_shim.dart';

import 'connection.dart';
import 'dynasty.dart';
import 'nodes/galaxy.dart';
import 'scores.dart';
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

  @override
  String toString() => '$error';
}

Future<void> _ignore(Object? value) => Future<void>.value();

class Game {
  Game(String? username, String? password) {
    _connectToLoginServer();
    if (username != null && password != null) {
      login(username, password).catchError(_handleAsyncError);
    }
    getGalaxy().then((Galaxy galaxy) {
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
  void _handleAsyncError(Object error) {
    _handleSyncError(error);
    throw HandledError(error);
  }
  void _handleSyncError(Object error) {
    for (ErrorHandler handler in _errorHandlers) {
      handler(error);
    }
  }

  void reportError(String message) {
    _handleSyncError(message);
  }

  ValueListenable<Credentials?> get credentials => _credentials;
  final ValueNotifier<Credentials?> _credentials = ValueNotifier<Credentials?>(null);

  String? _currentToken;

  static const String _loginServerURL = 'wss://interstellar-dynasties.space:10024/';

  Connection get loginServer => _loginServer!;
  Connection? _loginServer;

  Connection get dynastyServer => _dynastyServer!;
  Connection? _dynastyServer;

  final DynastyManager dynastyManager = DynastyManager();

  final Map<String, SystemServer> systemServers = <String, SystemServer>{};

  ValueListenable<bool> get loggedIn => _loggedIn;
  final ValueNotifier<bool> _loggedIn = ValueNotifier<bool>(false);

  ValueListenable<WorldNode?> get recommendedFocus => _recommendedFocus;
  final ValueNotifier<WorldNode?> _recommendedFocus = ValueNotifier<WorldNode?>(null);

  final ConnectionStatus connectionStatus = ConnectionStatus();

  void _connectToLoginServer() {
    _loginServer = Connection(
      _loginServerURL,
      connectionStatus: connectionStatus,
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
    final int code = data.buffer.asByteData(data.offsetInBytes, data.lengthInBytes).getUint32(0, Endian.little);
    assert(_files.containsKey(code));
    _files[code]!.complete(data);
    if (code > 0)
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
        await _loginServer!.send(<Object>['get-file', code]).then(_ignore).catchError(_handleAsyncError);
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
        .catchError(_handleAsyncError),
      _getFile(1)
        .then<void>((Uint8List result) { data = result; }),
    ]);
    return Galaxy.from(data, diameter);
  }

  Future<Uint8List> getSystems() async {
    return _getFile(2);
  }

  Future<HighScores> getHighScores() async {
    final Completer<Uint8List> scores = Completer<Uint8List>();
    _files[0] = scores;
    await _loginServer!.send(<Object>['get-high-scores', ?dynastyManager.currentDynasty?.id]); // errors are propagated to caller!
    return HighScores.from(await scores.future);
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
  Future<void> loginWithCredentials(Credentials credentials) async {
    _clearCredentials();
    _credentials.value = credentials;
    _handleLogin(await _loginServer!.send(<Object>['login', credentials.username, credentials.password]));
    // TODO: handle the case where while we are waiting for the login message to return, we send a different login or new game message
  }

  // throws on error from server
  Future<void> login(String username, String password) {
    return loginWithCredentials(Credentials(username, password));
  }

  // throws on error from server
  Future<NetworkError?> changeCredentials(Credentials credentials) async {
    try {
      if (_credentials.value!.username != credentials.username)
        await _loginServer!.send(<Object>['change-username', _credentials.value!.username, _credentials.value!.password, credentials.username]);
      if (_credentials.value!.password != credentials.password)
        await _loginServer!.send(<Object>['change-password', credentials.username, _credentials.value!.password, credentials.password]);
    } on NetworkError catch (e) {
      return e;
    }
    _credentials.value = credentials;
    return null;
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
    await _loginServer!.send(<Object>['logout', username, password]).then(_ignore).catchError(_handleAsyncError);
  }

  void _clearCredentials() {
    _loggedIn.value = false;
    _credentials.value = null;
    _recommendedFocus.value = null;
    _currentToken = null;
    dynastyManager.setCurrentDynastyId(null);
    rootNode.clearSystems();
    _dynastyServer?.dispose();
    _dynastyServer = null;
    for (SystemServer server in systemServers.values) {
      server.dispose();
    }
    systemServers.clear();
  }

  // DYNASTY SERVER

  void _connectToDynastyServer(String url) {
    _dynastyServer = Connection(
      url,
      connectionStatus: connectionStatus,
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
      dynastyManager.setCurrentDynastyId(reader.readInt());
      _updateSystemServers(reader);
    } on Exception catch (e) {
      _handleAsyncError(e);
    }
  }

  void _handleDynastyServerMessage(StreamReader reader) {
    final String message = reader.readString();
    switch (message) {
      case 'system-servers':
        _updateSystemServers(reader);
      default:
        debugPrint('dynasty server: received unexpected message: $message ($reader)');
    }
  }

  void _updateSystemServers(StreamReader reader) {
    final int serverCount = reader.readInt();
    final Set<String> activeServers = systemServers.keys.toSet();
    for (int index = 0; index < serverCount; index += 1) {
      final String url = reader.readString();
      systemServers.putIfAbsent(url, () => SystemServer(
        url,
        connectionStatus,
        _currentToken!,
        rootNode,
        dynastyManager,
        onError: _handleSystemServerError,
        onColonyShip: (WorldNode? node) {
          _recommendedFocus.value = node;
        },
      ));
      activeServers.remove(url);
    }
    for (String url in activeServers) {
      systemServers.remove(url)!.dispose();
    }
  }

  void _handleDynastyServerError(Exception error, Duration duration) {
    _handleSyncError('dynasty server: $error');
    debugPrint('dynasty server: $error');
    if (duration > Duration.zero)
      debugPrint('reconnecting in ${duration.inMilliseconds}ms');
  }

  void _handleSystemServerError(Exception error, Duration duration) {
    _handleSyncError('system server: $error');
    debugPrint('system server: $error');
    if (duration > Duration.zero)
      debugPrint('reconnecting in ${duration.inMilliseconds}ms');
  }
}
