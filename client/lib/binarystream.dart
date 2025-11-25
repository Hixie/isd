import 'dart:convert';
import 'dart:typed_data';

import 'assetclasses.dart';

class SystemSingletons {
  final Map<int, String> _strings = <int, String>{};
  final Map<int, AssetClass> _assetClasses = <int, AssetClass>{};

  AssetClass assetClass(int id) => _assetClasses[id]!;

  void reset() {
    _strings.clear();
    _assetClasses.clear();
  }
}

typedef ObjectReader = Object Function();

class BinaryStreamReader {
  BinaryStreamReader(this._bytes, this._singletons) : _source = _bytes.buffer.asByteData(_bytes.offsetInBytes, _bytes.lengthInBytes);

  final Uint8List _bytes;
  final ByteData _source;
  int _position = 0;

  final SystemSingletons _singletons;

  bool readBool() {
    final int result = _source.getUint8(_position);
    _position += 1;
    return result == 0x01;
  }

  int readUInt8() {
    final int result = _source.getUint8(_position);
    _position += 1;
    return result;
  }

  int readUInt32() {
    final int result = _source.getUint32(_position, Endian.little);
    _position += 4;
    return result;
  }

  int readInt32() {
    final int result = _source.getInt32(_position, Endian.little);
    _position += 4;
    return result;
  }

  int readInt64() {
    final int result = _source.getInt64(_position, Endian.little);
    _position += 8;
    return result;
  }

  double readDouble() {
    final double result = _source.getFloat64(_position, Endian.little);
    _position += 8;
    return result;
  }

  String readRawString() {
    final int length = readInt32();
    if (length == 0) {
      return '';
    }
    final String result = utf8.decode(_bytes.sublist(_position, _position + length));
    _position += length;
    return result;
  }

  String readString() {
    assert(!checkpointed);
    final int code = readInt32();
    return _singletons._strings.putIfAbsent(code, readRawString);
  }

  AssetClass _readRawAssetClass(int id) {
    return AssetClass(
      id: id,
      icon: readString(),
      name: readString(),
      description: readString(),
    );
  }
  
  AssetClass? readAssetClass({ bool allowUnknowns = false }) {
    assert(!checkpointed);
    final int code = readInt32();
    if (code == 0) {
      if (allowUnknowns)
        return _readRawAssetClass(0);
      return null;
    }
    return _singletons._assetClasses.putIfAbsent(code, () => _readRawAssetClass(code));
  }

  List<int>? _checkpoints;

  void saveCheckpoint() {
    _checkpoints ??= <int>[];
    _checkpoints!.add(_position);
  }

  void restoreCheckpoint() {
    _position = _checkpoints!.removeLast();
  }

  void discardCheckpoint() {
    _checkpoints!.removeLast();
  }

  bool get checkpointed => _checkpoints != null && _checkpoints!.isNotEmpty;

  bool get done => _position >= _source.lengthInBytes;
}

String hexDump(Uint8List bytes) {
  final StringBuffer out = StringBuffer('creating binary stream from:\n');
  final StringBuffer s = StringBuffer();
  for (int index = 0; index < bytes.length; index += 1) {
    final int c = bytes[index];
    out.write(' ${c.toRadixString(16).padLeft(2, "0")}');
    if (c >= 0x20 && c <= 0x7e) {
      s.write(String.fromCharCode(c));
    } else {
      s.write('.');
    }
    if (index % 16 == 7) {
      out.write(' ');
    } else if (index % 16 == 15) {
      out.write('  |$s|\n');
      s.clear();
    }
  }
  return out.toString();
}
