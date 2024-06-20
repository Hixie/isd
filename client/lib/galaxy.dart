import 'dart:typed_data';

class Galaxy {
  Galaxy._(this.stars);

  final List<Float32List> stars;
  
  static const int maxCoordinate = 4294967295;
  
  factory Galaxy.from(Uint8List rawdata) {
    final Uint32List data = rawdata.buffer.asUint32List();
    assert(data[0] == 1);
    final int categoryCount = data[1];
    final List<Float32List> categories = <Float32List>[];
    int indexSource = 2 + categoryCount;
    for (int category = 0; category < categoryCount; category += 1) {
      final Float32List target = Float32List(data[2 + category] * 2);
      int indexTarget = 0;
      while (indexTarget < target.length) {
        target[indexTarget] = data[indexSource].toDouble();
        indexTarget += 1;
        indexSource += 1;
      }
      categories.add(target);
    }
    return Galaxy._(categories);
  }
}
