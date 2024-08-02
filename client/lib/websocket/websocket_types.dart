import 'dart:typed_data';

typedef WebSocketTextHandler = void Function(String text);
typedef WebSocketBinaryHandler = void Function(Uint8List binary);
