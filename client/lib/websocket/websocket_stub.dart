import 'websocket_types.dart';

class WebSocket {
  static Future<WebSocket> connect(String url, { WebSocketTextHandler? onText, WebSocketBinaryHandler? onBinary }) {
    throw UnimplementedError();
  }

  void sendText(String message) {
    throw UnimplementedError();
  }

  void close() {
    throw UnimplementedError();
  }

  Future<void> get closure => throw UnimplementedError();
}
