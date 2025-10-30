import 'dart:math' show Random;
import 'dart:typed_data';
import 'dart:ui' show Color;

class ScorePoint {
  const ScorePoint(this.index, this.timestamp, this.score);
  final int index;
  final int timestamp;
  final double score;
}

class DynastyHistory {
  const DynastyHistory(this.dynastyId, this.points);

  final int dynastyId;
  final List<ScorePoint> points;

  Color get color {
    return Color(Random(dynastyId).nextInt(0x00FFFFFF) | 0xFF707070);
  }
}

class HighScores {
  const HighScores(this.dynasties);

  factory HighScores.from(Uint8List data) {
    final ByteReader reader = ByteReader.fromUint8List(data);
    final int code = reader.getUint32(); // file code
    assert(code == 0);
    final List<DynastyHistory> scores = <DynastyHistory>[];
    while (reader.hasRemaining) {
      final int dynastyID = reader.getUint32();
      final int lastIndex = reader.getUint32();
      final int count = reader.getUint32();
      final List<ScorePoint> points = <ScorePoint>[];
      for (int index = 0; index < count; index += 1) {
        points.add(ScorePoint(
          lastIndex - count + index + 1,
          reader.getUint64(),
          reader.getDouble(),
        ));
      }
      scores.add(DynastyHistory(dynastyID, points));
    }
    return HighScores(scores);
  }

  final List<DynastyHistory> dynasties;
}

// TODO: consider replacing with BinaryStreamReader from binarystream.dart
class ByteReader {
  ByteReader(this.data);

  factory ByteReader.fromUint8List(Uint8List data) {
    return ByteReader(data.buffer.asByteData(data.offsetInBytes, data.lengthInBytes));
  }

  final ByteData data;

  int _position = 0;

  int getUint32() {
    final int result = data.getUint32(_position, Endian.little);
    _position += 4;
    return result;
  }

  int getUint64() { // TODO: returns a signed int64
    final int result = data.getUint64(_position, Endian.little);
    _position += 8;
    return result;
  }

  double getDouble() {
    final double result = data.getFloat64(_position, Endian.little);
    _position += 8;
    return result;
  }

  bool get hasRemaining {
    return _position < data.lengthInBytes;
  }
}
