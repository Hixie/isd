import 'dart:typed_data';
import 'dart:ui';

import 'dynasty.dart';

class Galaxy {
  Galaxy._(this.stars, this.diameter);

  final List<Float32List> stars; // Star positions in meters
  final double diameter; // in meters

  static const double _maxCoordinate = 4294967295; // Galaxy diameter in DWord Units

  static int encodeStarId(int category, int index) => (category << 20) | index; // max 1,048,575 stars per category
  static (int, int) decodeStarId(int id) => (id >> 20, id & 0x000fffff);

  final Map<int, Dynasty> _dynasties = <int, Dynasty>{};
  Dynasty getDynasty(int id) {
    return _dynasties.putIfAbsent(id, () => Dynasty(id));
  }

  Dynasty? get currentDynasty => _currentDynasty;
  Dynasty? _currentDynasty;
  void setCurrentDynastyId(int? id) {
    if (id == null) {
      _currentDynasty = null;
    } else {
      _currentDynasty = getDynasty(id);
    }
  }
  
  factory Galaxy.from(Uint8List rawdata, double diameter) {
    final Uint32List data = rawdata.buffer.asUint32List();
    assert(data[0] == 1);
    final int categoryCount = data[1];
    final categories = <Float32List>[];
    int indexSource = 2 + categoryCount;
    for (var category = 0; category < categoryCount; category += 1) {
      final target = Float32List(data[2 + category] * 2);
      var indexTarget = 0;
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
    final result = <int>[];
    for (var category = 0; category < stars.length; category += 1) {
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
    for (var category = 0; category < stars.length; category += 1) {
      final int index = _binarySearchY(stars[category], target.dy);
      var subindex = 1;
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
