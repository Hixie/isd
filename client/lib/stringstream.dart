
class StreamReader {
  StreamReader(this.message);

  final String message;
  int _position = 0;

  String readString() {
    final int nextNull = message.indexOf('\x00', _position);
    if (nextNull < 0)
      throw const FormatException();
    final String result = message.substring(_position, nextNull);
    _position = nextNull + 1;
    return result;
  }

  int readInt() {
    return int.parse(readString());
  }

  double readDouble() {
    return double.parse(readString());
  }

  bool readBool() {
    final String b = readString();
    if (b == 'T') {
      return true;
    }
    if (b == 'F') {
      return false;
    }
    throw const FormatException();
  }

  void reset() {
    _position = 0;
  }

  @override
  String toString() => '<$message>';
}

class StreamWriter {
  StreamWriter();

  final StringBuffer _message = StringBuffer();

  void writeString(String data) {
    _message.write(data);
    _message.write('\x00');
  }

  void writeInt(int value) {
    writeString('$value');
  }

  void writeDouble(double value) {
    writeString('$value');
  }

  void writeBool(bool value) {
    writeString(value ? 'T' : 'F');
  }
  
  String serialize() => _message.toString();
}
