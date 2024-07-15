import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:web_socket/web_socket.dart';

import 'stringstream.dart';

typedef MessageCallback = void Function(StreamReader reader);
typedef ErrorCallback = void Function(Exception error);
typedef FileCallback = void Function(Uint8List bytes);

class NetworkError implements Exception {
  NetworkError(this.message);
  
  final String message;
  
  @override
  String toString() => message;
}

class _Conversation {
  const _Conversation(this.id, this.request, this.response);

  final int id;
  final String request;
  final Completer<StreamReader> response;
}

class Connection {
  Connection(this.url, { required this.onMessage, required this.onError, this.onFile, List<Object>? login }) {
    if (login != null) {
      _loginConversation = _prepareConversation(0, login);
    }
    _loop(url);
  }

  final String url;
  final MessageCallback onMessage;
  final ErrorCallback onError;
  final FileCallback? onFile;

  WebSocket? _websocket;
  bool _active = true;

  final ValueNotifier<bool> _connected = ValueNotifier<bool>(false);
  ValueListenable<bool> get connected => _connected;

  _Conversation? _loginConversation;
  
  int _nextConversation = 1;
  final Map<int, _Conversation> _conversations = <int, _Conversation>{};

  Future<void> _loop(String url) async {
    while (_active) {
      try {
        try {
          _websocket = await WebSocket.connect(Uri.parse(url));
          if (!_active) {
            return;
          }
          if (_loginConversation != null) {
            _websocket!.sendText(_loginConversation!.request);
          }
          for (_Conversation conversation in _conversations.values) {
            _websocket!.sendText(conversation.request);
          }
          _connected.value = true;
          await _websocket!.events.listen(_handler).asFuture();
        } finally {
          _websocket = null;
          _connected.value = false;
        }
      } on Exception catch (e) {
        _active = false;
        onError(e);
      }
      await Future<void>.delayed(const Duration(seconds: 2));
    }
  }

  void _handler(WebSocketEvent event) {
    if (event is TextDataReceived) {
      final StreamReader reader = StreamReader(event.text);
      if (reader.readString() == 'reply') {
        final int conversationId = reader.readInt();
        final bool success = reader.readBool();
        if (conversationId == 0) {
          // login conversation
          if (!success) {
            throw NetworkError('credentials rejected by server');
          }
        } else {
          final _Conversation? conversation = _conversations.remove(conversationId);
          if (conversation == null) {
            throw NetworkError('unexpected reply on conversation ID $conversationId');
          } else if (success) {
            conversation.response.complete(reader);
          } else {
            conversation.response.completeError(NetworkError(reader.readString()));
          }
        }
      } else {
        reader.reset();
        onMessage(reader);
      }
    } else if (event is BinaryDataReceived) {
      if (onFile != null) {
        onFile!(event.data);
      }
    }
  }
  
  _Conversation _prepareConversation(int conversationId, List<Object> messageParts) {
    final StreamWriter message = StreamWriter();
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
    );
  }
  
  Future<StreamReader> send(List<Object> messageParts) {
    final _Conversation conversation = _prepareConversation(_nextConversation, messageParts);
    _nextConversation += 1;
    if (_websocket != null) {
      _websocket!.sendText(conversation.request);
    }
    _conversations[conversation.id] = conversation;
    return conversation.response.future;
  }
  
  void dispose() {
    _active = false;
    _websocket?.close();
  }
}
