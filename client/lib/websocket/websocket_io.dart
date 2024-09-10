import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'dart:typed_data';

import 'websocket_types.dart';

class WebSocket {
  WebSocket._(this._socket, this.onText, this.onBinary) {
    assert(_socket.readyState >= io.WebSocket.open);
    _subscription = _socket.listen(
      _handleData,
      onError: _handleError,
      onDone: _handleDone,
      cancelOnError: true,
    );
  }

  static Future<WebSocket> connect(String url, { WebSocketTextHandler? onText, WebSocketBinaryHandler? onBinary }) async {
    final io.WebSocket socket = await io.WebSocket.connect(url)
      ..pingInterval = const Duration(seconds: 60);
    return WebSocket._(socket, onText, onBinary);
  }

  final io.WebSocket _socket;

  final WebSocketTextHandler? onText;
  final WebSocketBinaryHandler? onBinary;

  final Completer<void> _closure = Completer<void>();
  Future<void> get closure => _closure.future;
  bool _closed = false;

  void close() {
    assert(!_closed);
    assert(_socket.readyState < io.WebSocket.closing);
    _socket.close();
    _subscription.cancel();
    if (!_closed) {
      _closed = true;
      _closure.complete();
    }
  }

  late final StreamSubscription<Object?> _subscription;

  void _handleData(Object? data) {
    if (data is String) {
      if (onText != null) {
        onText!(data);
      }
    } else if (data is Uint8List) {
      if (onBinary != null) {
        onBinary!(data);
      }
    } else {
      assert(false, 'received (${data.runtimeType}): "$data"');
      throw StateError('invalid io.WebSocket data received');
    }
  }

  void _handleError(Object error) {
    assert(_socket.readyState >= io.WebSocket.closing);
    if (!_closed) {
      _closed = true;
      _closure.complete();
    }
  }

  void _handleDone() {
    if (!_closed) {
      _closed = true;
      _closure.complete();
    }
  }

  void sendText(String message) {
    assert(!_closed);
    assert(_socket.readyState < io.WebSocket.closing);
    _socket.addUtf8Text(utf8.encode(message));
  }
}
