import 'dart:async';

import 'package:flutter/foundation.dart';

import 'binarystream.dart';
import 'stringstream.dart';
import 'websocket/websocket.dart';

typedef ConnectedCallback = Future<void> Function();
typedef ErrorCallback = void Function(Exception error, Duration delay);
typedef TextMessageCallback = void Function(StreamReader reader);
typedef BinaryMessageCallback = void Function(Uint8List bytes);

class NetworkError implements Exception {
  NetworkError(this.message);
  
  final String message;
  
  @override
  String toString() => message;
}

class _Conversation {
  const _Conversation(this.id, this.request, this.response, { required this.queue });

  final int id;
  final String request;
  final Completer<StreamReader> response;
  final bool queue;

  static bool queued(_Conversation conversation) => conversation.queue;
  static bool notQueued(int id, _Conversation conversation) => !conversation.queue;
}

class Connection {
  Connection(this.url, { this.onConnected, this.onTextMessage, this.onBinaryMessage, this.onError, this.timeout }) {
    log('$url creating connection object');
    _loop(url);
  }

  final String url;
  final ConnectedCallback? onConnected;
  final ErrorCallback? onError;
  final TextMessageCallback? onTextMessage;
  final BinaryMessageCallback? onBinaryMessage;
  final Duration? timeout;
  
  WebSocket? _websocket;
  CodeTables? _codeTables;
  bool _active = true;

  // only valid when handling a message synchronously
  CodeTables get codeTables => _codeTables!;
  
  Timer? _timer;
  Completer<void>? _hold;

  void _resetTimer() {
    _hold = null;
    if (timeout != null) {
      _timer?.cancel();
      _timer = Timer(timeout!, _handleTimer);
    }
  }

  void _handleTimer() {
    _timer = null;
    _websocket?.close();
    _websocket = null;
    _codeTables = null;
    assert(_hold == null);
    if (_conversations.isEmpty) {
      _hold = Completer<void>();
    }
  }
  
  final ValueNotifier<bool> _connected = ValueNotifier<bool>(false);
  ValueListenable<bool> get connected => _connected;

  int _nextConversation = 1;
  final Map<int, _Conversation> _conversations = <int, _Conversation>{};

  Future<void> _loop(String url) async {
    var connectDelay = const Duration(seconds: 1);
    while (_active) {
      try {
        try {
          if (_hold != null) {
            assert(_timer == null);
            assert(_conversations.isEmpty);
            await _hold!.future;
            assert(_hold == null);
          }
          log('$url connecting; ${_conversations.length} conversations to send');
          _websocket = await WebSocket.connect(url, onText: _textHandler, onBinary: _binaryHandler);
          _codeTables = CodeTables();
          if (!_active) {
            return;
          }
          log('$url opened; ${_conversations.length} conversations to send');
          if (onConnected != null) {
            log('$url handling connection boilerplate...');
            await onConnected!();
          }
          for (_Conversation conversation in _conversations.values.where(_Conversation.queued)) {
            log('$url sending ${prettyText(conversation.request)}');
            _websocket!.sendText(conversation.request);
          }
          _conversations.removeWhere(_Conversation.notQueued);
          _connected.value = true;
          connectDelay = const Duration(seconds: 1);
          _resetTimer();
          log('$url idle; listening');
          await _websocket!.closure;
          log('$url stream terminated with ${_conversations.length} conversations pending');
        } finally {
          _websocket = null;
          _codeTables = null;
          _connected.value = false;
        }
      } on Exception catch (e) {
        if (onError != null)
          onError!(e, connectDelay);
        if (!_active) {
          return;
        }
      }
      await Future<void>.delayed(connectDelay);
      connectDelay *= 2;
    }
  }

  void _textHandler(String message) {
    _resetTimer();
    log('$url received ${prettyText(message)}');
    final reader = StreamReader(message);
    if (reader.readString() == 'reply') {
      final int conversationId = reader.readInt();
      final bool success = reader.readBool();
      if (conversationId == 0) {
        // login conversation
        if (!success) {
          if (onError != null)
            onError!(NetworkError('credentials rejected by server: ${reader.readString()}'), Duration.zero);
        }
      } else {
        final _Conversation? conversation = _conversations.remove(conversationId);
        if (conversation == null) {
          if (onError != null)
            onError!(NetworkError('unexpected reply on conversation ID $conversationId: $message'), Duration.zero);
        } else if (success) {
          conversation.response.complete(reader);
        } else {
          conversation.response.completeError(NetworkError(reader.readString()));
        }
      }
    } else {
      reader.reset();
      if (onTextMessage != null)
        onTextMessage!(reader);
    }
  }

  void _binaryHandler(Uint8List message) {
    _resetTimer();
    log('$url received (binary) ${prettyBytes(message)}');
    if (onBinaryMessage != null) {
      onBinaryMessage!(message);
    }
  }
  
  _Conversation _prepareConversation(int conversationId, List<Object> messageParts, { required bool queue }) {
    final message = StreamWriter();
    message.writeInt(conversationId);
    for (Object value in messageParts) {
      if (value is String) {
        message.writeString(value);
      } else if (value is int) {
        message.writeInt(value);
      } else if (value is double) {
        message.writeDouble(value);
      } else if (value is bool) {
        message.writeBool(value);
      } else {
        throw StateError('unknown type ${value.runtimeType}');
      }
    }
    return _Conversation(
      conversationId,
      message.serialize(),
      Completer<StreamReader>(),
      queue: queue,
    );
  }
  
  Future<StreamReader> send(List<Object> messageParts, { bool queue = true }) {
    final _Conversation conversation = _prepareConversation(_nextConversation, messageParts, queue: queue);
    log('$url adding new conversation $_nextConversation: ${prettyText(conversation.request)}');
    _nextConversation += 1;
    if (_websocket != null) {
      log('$url sending ${prettyText(conversation.request)}');
      _websocket!.sendText(conversation.request);
    }
    if (_hold != null) {
      _hold!.complete();
      _hold = null;
    }
    _conversations[conversation.id] = conversation;
    return conversation.response.future;
  }
  
  void dispose() {
    _active = false;
    _timer?.cancel();
    _timer = null;
    _websocket?.close();
    _websocket = null;
    _codeTables = null;
  }

  static String prettyText(String message) {
    final result = StringBuffer();
    for (int code in message.runes) {
      if (code == 0) {
        result.write('␀');
      } else if (code == 0x0A) {
        result.write('↵');
      } else {
        result.write(String.fromCharCode(code));
      }
    }
    return result.toString();
  }

  static String prettyBytes(Iterable<int> message) {
    final bits = <String>[];
    final buffer = <int>[];
    bool? isText;
    int? lastInteger;

    void processInteger() {
      assert(buffer.length == 4);
      final int thisInteger = (buffer[0]) + (buffer[1] << 8) + (buffer[2] << 16) + (buffer[3] << 24);
      late double value;
      if (lastInteger != null && bits.isNotEmpty) {
        final scratch = ByteData(8);
        scratch.setUint32(0, lastInteger!, Endian.little);
        scratch.setUint32(4, thisInteger, Endian.little);
        value = scratch.getFloat64(0, Endian.little);
        if (value.isFinite && value > 1 && value < 1e100) {
          bits.removeLast();
          bits.add('$value');
          buffer.clear();
          isText = null;
          lastInteger = null;
          return;
        }
      }
      if (thisInteger < 256) {
        bits.add('$thisInteger');
      } else {
        bits.add('0x${thisInteger.toRadixString(16).padLeft(8, "0")}');
      }
      buffer.clear();
      isText = null;
      lastInteger = thisInteger;
    }
    
    for (int byte in message.take(256)) {
      if (byte < 0x20 || byte > 0x7E) {
        if (buffer.length > 4) {
          bits.add('\'${String.fromCharCodes(buffer)}\'');
          buffer.clear();
        } else if (buffer.length == 4) {
          processInteger();
        }
        isText = false;
        buffer.add(byte);
      } else {
        if ((byte >= 0x30 && byte <= 0x39) || (byte >= 0x41 && byte <= 0x5A) || (byte >= 0x61 && byte <= 0x7A)) {
          isText ??= true;
        }
        buffer.add(byte);
      }
      if (buffer.length == lastInteger && ((isText == true) || (isText == null && lastInteger != null && lastInteger! > 3))) {
        bits.removeLast();
        bits.add('"${String.fromCharCodes(buffer)}"');
        buffer.clear();
        lastInteger = null;
      } else if ((isText != true || lastInteger == null) && buffer.length == 4) {
        processInteger();
      }
    }
    if (buffer.isNotEmpty) {
      if (isText == true) {
        bits.add('\'${String.fromCharCodes(buffer)}\'');
      } else {
        bits.addAll(buffer.map((int code) => '0x${code.toRadixString(16).padLeft(2, "0")}'));
      }
    }
    if (message.length > 256) {
      bits.add(' ...');
    }
    return bits.join(' ');
  }

  void log(String s) {
    debugPrint(s);
  }
}
