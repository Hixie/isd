import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:fs_shim/fs_shim.dart';

import 'connection.dart';
import 'galaxy.dart';
import 'stringstream.dart';
import 'world.dart';

class Credentials {
  Credentials(this.username, this.password);
  final String username;
  final String password;
}

class Game {
  Game(String? username, String? password) {
    _connectToLoginServer();
    if (username != null && password != null) {
      login(username, password);
    }
    getGalaxy().then((Galaxy galaxy) {
      rootNode.galaxy = galaxy;
    });
  }

  ValueListenable<Credentials?> get credentials => _credentials;
  final ValueNotifier<Credentials?> _credentials = ValueNotifier<Credentials?>(null);
  
  static const String _loginServerURL = 'wss://interstellar-dynasties.space:10024/';
  
  Connection get loginServer => _loginServer!;
  Connection? _loginServer;
  
  Connection get dynastyServer => _dynastyServer!;
  Connection? _dynastyServer;

  ValueListenable<bool> get loggedIn => _loggedIn;
  final ValueNotifier<bool> _loggedIn = ValueNotifier<bool>(false);
  
  void _connectToLoginServer() {
    _loginServer = Connection(
      _loginServerURL,
      onMessage: _handleLoginServerMessage,
      onError: _handleLoginServerError,
      onFile: _handleFile,
    );
  }

  void _handleLoginServerMessage(StreamReader reader) {
    print('login server: received unexpected message: $reader');
  }

  void _handleLoginServerError(Exception error) {
    print('login server: $error');
    _loginServer!.dispose();
    _connectToLoginServer();
    if (_credentials.value != null) {
      login(_credentials.value!.username, _credentials.value!.password);
    }
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
        await _loginServer!.send(<Object>['get-file']);
      }
    }
    return _files[code]!.future;
  }
  
  Future<Galaxy> getGalaxy() async {
    final StreamReader reader = await _loginServer!.send(<Object>['get-constants']);
    final double diameter = reader.readDouble();
    return Galaxy.from(await _getFile(1), diameter);
  }
  
  Future<Uint8List> getSystems() async {
    return _getFile(2);
  }


  // LOGIN SERVER COMMANDS
  
  Future<void> newGame() async {
    final StreamReader reader = await _loginServer!.send(<Object>['new']);
    _credentials.value = Credentials(reader.readString(), reader.readString());
    _connectToDynastyServer(reader.readString(), reader.readString());
  }

  Future<void> login(String username, String password) async {
    _credentials.value = Credentials(username, password);
    final StreamReader reader = await _loginServer!.send(<Object>['login', username, password]);
    _connectToDynastyServer(reader.readString(), reader.readString());
  }

  Future<void> logout() async {
    final String username = _credentials.value!.username;
    final String password = _credentials.value!.password;
    _loggedIn.value = false;
    _credentials.value = null;
    _dynastyServer?.dispose();
    _dynastyServer = null;
    await _loginServer!.send(<Object>['logout', username, password]);
  }


  // DYNASTY SERVER
  
  void _connectToDynastyServer(String url, String token) {
    _dynastyServer = Connection(
      url,
      onMessage: _handleDynastyServerMessage,
      onError: _handleDynastyServerError,
      login: <String>['login', token],
    );
    _loggedIn.value = true;
  }

  void _handleDynastyServerMessage(StreamReader reader) {
    print('dynasty server: received unexpected message: $reader');
  }

  void _handleDynastyServerError(Exception error) {
    print('dynasty server: $error');
    _dynastyServer!.dispose();
    _dynastyServer = null;
    _loggedIn.value = false;
  }

  final GalaxyNode rootNode = GalaxyNode();
}
