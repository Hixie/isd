import 'dart:typed_data';
import 'dart:ui';

class Galaxy {
  Galaxy._(this.stars, this.diameter);

  final List<Float32List> stars; // Star posititions in meters
  final double diameter; // in meters

  static const double standardDiameter = 1e21; // meters; approx 105700 light years
  static const double _maxCoordinate = 4294967295; // Galaxy diameter in DWord Units

  static int encodeStarId(int category, int index) => (category << 32) | index;
  static (int, int) decodeStarId(int id) => (id >> 32, id & 0xffffffff);
  
  factory Galaxy.from(Uint8List rawdata, double diameter) {
    final Uint32List data = rawdata.buffer.asUint32List();
    assert(data[0] == 1);
    final int categoryCount = data[1];
    final List<Float32List> categories = <Float32List>[];
    int indexSource = 2 + categoryCount;
    for (int category = 0; category < categoryCount; category += 1) {
      final Float32List target = Float32List(data[2 + category] * 2);
      int indexTarget = 0;
      while (indexTarget < target.length) {
        target[indexTarget] = data[indexSource] * diameter / _maxCoordinate;
        indexTarget += 1;
        indexSource += 1;
      }
      categories.add(target);
    }
    return Galaxy._(categories, diameter);
  }

  // returns first entry to be greater than or equal to target
  int _binarySearchY(Float32List list, double target, [ int min = 0, int? maxLimit ]) {
    int max = maxLimit ?? list.length ~/ 2;
    while (min < max) {
      final int mid = min + ((max - min) >> 1);
      final double element = list[mid * 2 + 1];
      final int comp = (element - target).sign.toInt();
      if (comp == 0) {
        return mid;
      }
      if (comp < 0) {
        min = mid + 1;
      } else {
        max = mid;
      }
    }
    return min;
  }

  List<int> hitTest(Offset target, double threshold) {
    // in meters
    final List<int> result = <int>[];
    for (int category = 0; category < stars.length; category += 1) {
      final int firstCandidate = _binarySearchY(stars[category], target.dy - threshold);
      final int lastCandidate = _binarySearchY(stars[category], target.dy + threshold, firstCandidate);
      for (int index = firstCandidate; index < lastCandidate; index += 1) {
        final double x = stars[category][index * 2];
        if (target.dx - threshold < x && x < target.dx + threshold) {
          result.add(encodeStarId(category, index));
        }
      }
    }
    return result;
  }

  int hitTestNearest(Offset target) {
    // in meters
    double currentDistance = double.infinity;
    int result = -1;
    bool test(int category, int index) {
      final double y = stars[category][index * 2 + 1];
      if ((target.dy - y).abs() > currentDistance) 
        return true;
      final double x = stars[category][index * 2];
      final double distance = (target - Offset(x, y)).distance;
      if (distance < currentDistance) {
        result = encodeStarId(category, index);
        currentDistance = distance;
      }
      return false;
    }
    for (int category = 0; category < stars.length; category += 1) {
      final int index = _binarySearchY(stars[category], target.dy);
      int subindex = 1;
      while ((index - subindex) >= 0) {
        if (test(category, index - subindex)) {
          break;
        }
        subindex += 1;
      }
      subindex = 0;
      while ((index + subindex) < stars[category].length ~/ 2) {
        if (test(category, index + subindex)) {
          break;
        }
        subindex += 1;
      }
    }
    return result;
  }
}
