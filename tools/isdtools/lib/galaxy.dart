import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:isd/assets.dart';
import 'package:isd/nodes/galaxy.dart';
import 'package:isd/root.dart';

const double lightYearInM = 9460730472580800.0;
const double galaxyDiameter = 1e21;
const double systemGroupingThreshold = 1 * lightYearInM;

class GalaxySettings {
  GalaxySettings({
    required this.arms,
    required this.randomSeed,
    required this.width,
    required this.twistiness,
    required this.galaxyCount,
    required this.starCount,
    required this.redCount,
  });
  final int arms;
  final int randomSeed;
  final double width;
  final double twistiness;
  final int galaxyCount;
  final int starCount;
  final int redCount;
}

class GalaxyStats {
  GalaxyStats({
    required this.stars,
    required this.starCount,
    required this.systemCount,
    required this.groups,
    required this.groupSizes,
  });

  final List<StarStats> stars;
  final int starCount;
  final int systemCount;
  final Map<int, Set<int>> groups;
  final Map<int, int> groupSizes;

  String get description {
    final StringBuffer result = StringBuffer('$starCount stars in $systemCount systems: ');
    bool first = true;
    int last = 0;
    for (int count in groupSizes.keys.toList()..sort()) {
      if (first) {
        first = false;
      } else {
        result.write(', ');
      }
      if (last != count - 1) {
        result.write(' ... ');
      }
      last = count;
      result.write('${groupSizes[count]}x$count');
    }
    return result.toString();
  }
}

class StarStats {
  StarStats(this.offset, this.category, this.index, this.group);
  final Offset offset;
  final int category;
  final int index;
  int get id => Galaxy.encodeStarId(category, index);
  Set<StarStats>? group;
}

class HomeCandidateStar {
  HomeCandidateStar(this.position, this.distance);
  final Offset position;
  final double distance;
  bool used = false;
  double? scratch;

  static int binarySearch(List<HomeCandidateStar> list, double targetDistance, [ int min = 0, int? maxLimit ]) {
    int max = maxLimit ?? list.length;
    while (min < max) {
      final int mid = min + ((max - min) >> 1);
      final double element = list[mid].distance;
      final int comp = (element - targetDistance).sign.toInt();
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
}

class GalaxyPane extends StatefulWidget {
  const GalaxyPane({super.key, this.onExit});

  final VoidCallback? onExit;
  
  @override
  _GalaxyPaneState createState() => _GalaxyPaneState();
}

class _GalaxyPaneState extends State<GalaxyPane> {
  int _arms = 2;
  int _randomSeed = 0;
  double _width = 0.15; // for 1e6 use 0.15, for 1e5 use 0.2
  double _twistiness = 0.9; // for 1e6 use 0.9, for 1e5 use 1.0
  int _galaxyCount = 200;
  int _starCount = 7500; // 750000
  int _redCount = 10;

  static int _offsetSort(Offset a, Offset b) {
    if (a.dy == b.dy) {
      return (a.dx - b.dx).sign.toInt();
    }
    return (a.dy - b.dy).sign.toInt();
  }

  static List<List<Offset>> generateGalaxy(GalaxySettings settings) {
    // unit square coordinate system
    final Random random = Random(settings.randomSeed);
    final List<List<Offset>> stars = List<List<Offset>>.generate(11, (int index) => <Offset>[], growable: false);
    final Random subrandom = Random(random.nextInt(1 << 32));
    for (int i = 0; i < settings.galaxyCount; i += 1) {
      stars[0].add(Offset(subrandom.nextDouble(), subrandom.nextDouble()));
      stars[1].add(Offset(subrandom.nextDouble(), subrandom.nextDouble()));
    }
    for (int i = 0; i < settings.starCount; i += 1) {
      final double q1 = random.nextDouble();
      final double q2 = random.nextDouble();
      final double r = 1 - sqrt(q1); // distance from center
      final double theta;
      if (settings.arms > 0) {
        final int arm = random.nextInt(settings.arms);
        final double w = tan(pi * q2 + pi / 2.0) * settings.width + 0.5;
        theta = (arm/settings.arms * 2.0 * pi) + (w * 2 * pi / settings.arms) + r * settings.twistiness * 2 * pi + 0.8;
      } else {
        theta = q2 * 2.0 * pi;
      }

      final double x = r * cos(theta);
      final double y = r * sin(theta);
      final int category = random.nextInt(stars.length - 2) + 2;
      if (category < 10 || r > 0.4) {
        stars[category].add(Offset(x/2.0 + 0.5, y/2.0 + 0.5));
      }
    }
    for (int index = 10; index < stars.length; index += 1) {
      if (stars[index].length > settings.redCount) {
        stars[index].length = settings.redCount;
      }
    }
    for (List<Offset> substars in stars) {
      substars.sort(_offsetSort);
    }
    return stars;
  }

  static int _byOffset(StarStats a, StarStats b) {
    if (a.offset.dy == b.offset.dy) {
      return (a.offset.dx - b.offset.dx).sign.toInt();
    }
    return (a.offset.dy - b.offset.dy).sign.toInt();
  }
  
  static Uint32List encode(List<List<Offset>> stars) {
    // converts unit square coordinate to dword units
    final Uint32List data = Uint32List(stars.fold(2 + stars.length, (int count, List<Offset> substars) => count + substars.length * 2));
    int position = 0;
    data[position++] = 1; // file ID
    data[position++] = stars.length;
    for (List<Offset> substars in stars) {
      data[position++] = substars.length;
    }
    for (List<Offset> substars in stars) {
      for (Offset point in substars) {
        data[position++] = (point.dx * 4294967296.0).round();
        data[position++] = (point.dy * 4294967296.0).round();
      }
    }
    return data;
  }

  List<List<Offset>> _stars = <List<Offset>>[];
  Uint32List _encodedStars = Uint32List(0);
  GalaxyStats? _stats;
  final GalaxyNode _galaxyNode = GalaxyNode();
  int? _home;

  bool _generating = false;
  bool _dirty = true;
  
  Future<void> _regenerate() async {
    if (_generating) {
      _dirty = true;
      return;
    }
    setState(() {
      _generating = true;
    });
    _stars = await compute(generateGalaxy, GalaxySettings(
      arms: _arms,
      randomSeed: _randomSeed,
      width: _width,
      twistiness: _twistiness,
      galaxyCount: _galaxyCount,
      starCount: _starCount,
      redCount: _redCount,
    ));
    if (mounted) {
      setState(() {
        _encodedStars = encode(_stars);
        _galaxyNode.galaxy = Galaxy.from(_encodedStars.buffer.asUint8List(), galaxyDiameter);
        _galaxyNode.clearSystems();
        _stats = null;
        _generating = false;
        _home = null;
      });
      if (_dirty) {
        _dirty = false;
        return _regenerate();
      }
    }
  }

  static GalaxyStats analyzeGalaxy(({List<List<Offset>> stars, double threshold}) input) {
    // unit square coordinate system
    final double thresholdSquared = input.threshold * input.threshold;
    int starCount = 0;
    final List<StarStats> starStats = <StarStats>[];
    for (int index = 2; index < input.stars.length; index += 1) {
      starCount += input.stars[index].length;
      for (int subindex = 0; subindex < input.stars[index].length; subindex += 1) {
        starStats.add(StarStats(input.stars[index][subindex], index, subindex, null));
      }
    }
    starStats.sort(_byOffset);
    // find stars within threshold
    for (int index = 0; index < starStats.length; index += 1) {
      final StarStats star = starStats[index];
      star.group ??= <StarStats>{star};
      final Offset a = star.offset;
      int subindex = 1;
      while ((index + subindex < starStats.length) &&
             (starStats[index + subindex].offset.dy - star.offset.dy < input.threshold)) {
        final StarStats other = starStats[index + subindex];
        final Offset b = other.offset;
        if ((b - a).distanceSquared < thresholdSquared) {
          if (other.group == null) {
            other.group = star.group;
          } else if (other.group != star.group) {
            for (StarStats target in other.group!) {
              star.group!.add(target);
              target.group = star.group;
            }
          }
          star.group!.add(other);
        }
        subindex += 1;
      }
    }
    // group groups within diameter of each group
    final Set<Set<StarStats>> done = <Set<StarStats>>{};
    bool didSomething;
    do {
      didSomething = false;
      for (int index = 0; index < starStats.length; index += 1) {
        final StarStats star = starStats[index];
        if (star.group!.length <= 2 || done.contains(star.group)) {
          continue;
        }
        // find center of group
        double sumX = 0.0;
        double sumY = 0.0;
        for (StarStats substar in star.group!) {
          sumX += substar.offset.dx;
          sumY += substar.offset.dy;
        }
        final Offset center = Offset(sumX, sumY) / star.group!.length.toDouble();
        double diameterSquared = 0;
        for (StarStats substar in star.group!) {
          final double candidateSquared = (center - substar.offset).distanceSquared;
          if (candidateSquared > diameterSquared) {
            diameterSquared = candidateSquared;
          }
        }
        final double diameter = sqrt(diameterSquared);
        bool addedAny = false;
        int subindex = 1;
        while ((index + subindex < starStats.length) &&
               (starStats[index + subindex].offset.dy - center.dy < diameter)) {
          final StarStats other = starStats[index + subindex];
          if ((other.group != star.group) &&
              ((center - other.offset).distanceSquared < diameterSquared)) {
            addedAny = true;
            star.group!.addAll(other.group!);
            for (StarStats target in other.group!) {
              target.group = star.group;
            }
            didSomething = true;
          }
          subindex += 1;
        }
        subindex = 1;
        while ((index - subindex >= 0) &&
               (starStats[index - subindex].offset.dy - center.dy < diameter)) {
          final StarStats other = starStats[index - subindex];
          if ((other.group != star.group) &&
              ((center - other.offset).distanceSquared < diameterSquared)) {
            addedAny = true;
            star.group!.addAll(other.group!);
            for (StarStats target in other.group!) {
              target.group = star.group;
            }
            didSomething = true;
          }
          subindex += 1;
        }
        if (!addedAny)
          done.add(star.group!);
      }
    } while (didSomething);
    // summarize
    final Map<Set<StarStats>, Set<int>> groupMapping = <Set<StarStats>, Set<int>>{};
    final Map<int, Set<int>> starGroups = <int, Set<int>>{};
    for (StarStats star in starStats) {
      groupMapping.putIfAbsent(star.group!, () => star.group!.map<int>((StarStats star) => star.id).toSet());
      starGroups[star.id] = groupMapping[star.group!]!;
    }
    final Map<int, int> groupSizes = <int, int>{};
    for (Set<StarStats> group in groupMapping.keys) {
      groupSizes.putIfAbsent(group.length, () => 0);
      groupSizes[group.length] = groupSizes[group.length]! + 1;
    }
    return GalaxyStats(
      stars: starStats,
      starCount: starCount,
      systemCount: groupMapping.length,
      groups: starGroups,
      groupSizes: groupSizes,
    );
  }

  Future<void> _analyze() async {
    if (_generating)
      return;
    _galaxyNode.clearSystems();
    _home = null;
    setState(() {
      _generating = true;
    });
    _stats = await compute(analyzeGalaxy, (stars: _stars, threshold: systemGroupingThreshold / _galaxyNode.diameter)); // 1 light year in unit square units
    if (mounted) {
      setState(() {
        _generating = false;
      });
    }
  }
  
  void _selectHomes() {
    assert(_home != null);
    final (int homeCategory, int homeIndex) = Galaxy.decodeStarId(_home!);
    assert(homeCategory >= 2);
    final Offset homePosition = _stars[homeCategory][homeIndex] * _galaxyNode.galaxy!.diameter;

    const double minDistanceFromHome = lightYearInM * 500.0;
    const double localSpaceRadius = lightYearInM * 250.0;

    final List<HomeCandidateStar> candidates = <HomeCandidateStar>[];
    for (StarStats star in _stats!.stars) {
      if (star.category >= 2 && star.category < 10) {
        final double distance = ((star.offset * _galaxyNode.galaxy!.diameter) - homePosition).distance;
        if (distance > minDistanceFromHome && star.group!.length <= 3 &&
            (_stats!.groups[star.id]!.toList()..sort()).first == star.id) {
          candidates.add(HomeCandidateStar(star.offset * _galaxyNode.galaxy!.diameter, distance));
        }
      }
    }
    candidates.sort((HomeCandidateStar a, HomeCandidateStar b) => (a.distance - b.distance).sign.toInt());
    const int minStarsPerPlayer = 5;

    int count = 0;
    for (int index = 0; index < candidates.length; index += 1) {
      // find nearby stars
      final HomeCandidateStar star = candidates[index];
      if (star.used) {
        continue;
      }
      final int min = HomeCandidateStar.binarySearch(candidates, star.distance - localSpaceRadius);
      final int max = HomeCandidateStar.binarySearch(candidates, star.distance + localSpaceRadius, min);
      final List<HomeCandidateStar> nearbyStars = <HomeCandidateStar>[];
      for (int subindex = min; subindex < max; subindex += 1) {
        final HomeCandidateStar substar = candidates[subindex];
        if ((substar.used) ||
            (substar == star) ||
            (substar.position.dx < star.position.dx - localSpaceRadius) ||
            (substar.position.dx > star.position.dx + localSpaceRadius) ||
            (substar.position.dy < star.position.dy - localSpaceRadius) ||
            (substar.position.dy > star.position.dy + localSpaceRadius)) {
          continue;
        }
        substar.scratch = (star.position - substar.position).distanceSquared;
        nearbyStars.add(substar);
      }
      if (nearbyStars.length > minStarsPerPlayer) {
        nearbyStars.sort((HomeCandidateStar a, HomeCandidateStar b) => (a.scratch! - b.scratch!).sign.toInt());
        for (HomeCandidateStar substar in nearbyStars.take(minStarsPerPlayer)) {
          substar.used = true;
        }
        star.used = true;
        count += 1;
      }
    }
    print('Found $count home systems with $minStarsPerPlayer reserved stars per home system.');
  }
  
  void _save() {
    // TODO: chose filename
    File('stars.dat').writeAsBytesSync(_encodedStars.buffer.asUint8List());
  }

  void _saveStats() {
    // TODO: chose filename
    final List<int> groups = _stats!.groups.keys.where(
      (int star) => (_stats!.groups[star]!.toList()..sort()).first != star,
    ).toList()..sort();
    final Uint32List systems = Uint32List(groups.length * 2 + 1);
    int index = 0;
    systems[index++] = 2;
    for (int star in groups) {
      systems[index++] = star;
      systems[index++] = (_stats!.groups[star]!.toList()..sort()).first;
    }
    File('systems.dat').writeAsBytesSync(systems.buffer.asUint8List());
  }

  void _load() {
    // TODO: chose filename
    final Uint8List buffer = File('stars.dat').readAsBytesSync();
    setState(() {
      _encodedStars = buffer.buffer.asUint32List();
      assert(_encodedStars[0] == 1);
      final int categoryCount = _encodedStars[1];
      _stars = <List<Offset>>[];
      int indexSource = 2 + categoryCount;
      for (int category = 0; category < categoryCount; category += 1) {
        _stars.add(<Offset>[]);
        while (_stars.last.length < _encodedStars[2 + category]) {
          _stars.last.add(Offset(
            _encodedStars[indexSource] / (1 << 32),
            _encodedStars[indexSource + 1] / (1 << 32),
          ));
          indexSource += 2;
        }
      }
      _galaxyNode.galaxy = Galaxy.from(buffer, galaxyDiameter);
      _galaxyNode.clearSystems();
      _home = null;
      _stats = null;
      _generating = false;
    });
  }

  void _handleStarTap(Offset offset, double zoomFactor) {
    if (_stats == null) {
      return;
    }
    final int match = _galaxyNode.galaxy!.hitTestNearest(offset);
    assert(match >= 0);
    _home = null;
    final (int category, int index) = Galaxy.decodeStarId(match);
    if (category <= 1) {
      _galaxyNode.addSystem(SystemNode(id: match));
    } else {
      if (_stats!.groups[match]!.length == 1 && category >= 2) {
        setState(() {
          _home = match;
        });
      }
      for (int star in _stats!.groups[match]!) {
        // final (int category, int index) = Galaxy.decodeStarId(star);
        _galaxyNode.addSystem(SystemNode(id: star));
      }
    }
  }
  
  @override
  void initState() {
    super.initState();
    // _galaxyNode.onTap = _handleStarTap; // TODO: port to new API
    _regenerate();
  }
  
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8.0,
                      children: <Widget>[
                        SliderBlock(
                          label: 'Arms:',
                          value: _arms.toDouble(),
                          min: 0.0,
                          max: 4.0,
                          onChanged: (double value) {
                            setState(() {
                              _arms = value.round();
                              _regenerate();
                            });
                          },
                        ),
                        SliderBlock(
                          label: 'Arm width:',
                          value: _width,
                          min: 0.0,
                          max: 0.5,
                          onChanged: (double value) {
                            setState(() {
                              _width = value;
                              _regenerate();
                            });
                          },
                        ),
                        SliderBlock(
                          label: 'Twistiness:',
                          value: _twistiness,
                          min: 0.0,
                          max: 2.5,
                          onChanged: (double value) {
                            setState(() {
                              _twistiness = value;
                              _regenerate();
                            });
                          },
                        ),
                        SliderBlock(
                          label: 'Galaxy count:',
                          value: _galaxyCount.toDouble(),
                          min: 0.0,
                          max: 1000.0,
                          onChanged: (double value) {
                            setState(() {
                              _galaxyCount = value.round();
                              _regenerate();
                            });
                          },
                        ),
                        SliderBlock(
                          label: 'Star count:',
                          value: _starCount.toDouble(),
                          min: 0.0,
                          max: 1000000.0,
                          onChanged: (double value) {
                            setState(() {
                              _starCount = value.round();
                              _regenerate();
                            });
                          },
                        ),
                        SliderBlock(
                          label: 'Red star count:',
                          value: _redCount.toDouble(),
                          min: 0.0,
                          max: 100.0,
                          onChanged: (double value) {
                            setState(() {
                              _redCount = value.round();
                              _regenerate();
                            });
                          },
                        ),
                        const SizedBox(width: 16.0),
                        OutlinedButton.icon(
                          onPressed: () {
                            setState(() {
                              _randomSeed = Random.secure().nextInt(1 << 32);
                              _regenerate();
                            });
                          },
                          icon: const Icon(Icons.hotel_class_outlined),
                          label: const Text('Randomize'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _save,
                          icon: const Icon(Icons.save_outlined),
                          label: const Text('Save'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _load,
                          icon: const Icon(Icons.file_open_outlined),
                          label: const Text('Load'),
                        ),
                        FilledButton.icon(
                          onPressed: (_stats != null) || _generating ? null : _analyze,
                          icon: const Icon(Icons.hub),
                          label: const Text('Analyze'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _stats == null ? null : _saveStats,
                          icon: const Icon(Icons.scatter_plot_outlined),
                          label: const Text('Export stats'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _home == null ? null : _selectHomes,
                          icon: const Icon(Icons.home),
                          label: const Text('Count homes'),
                        ),
                        OutlinedButton.icon(
                          onPressed: widget.onExit,
                          icon: const Icon(Icons.exit_to_app),
                          label: const Text('Exit'),
                        ),
                        if (_stats != null)
                          Text(_stats!.description),
                        if (_home != null)
                          Text('Selected star: ${Galaxy.decodeStarId(_home!)}'),
                      ],
                    ),
                  ),
                  AnimatedOpacity(
                    duration: const Duration(milliseconds: 150),
                    opacity: _generating ? 1.0 : 0.0,
                    child: CircularProgressIndicator(value: _generating ? null : 0.0),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ColoredBox(
                color: Colors.black,
                child: SizedBox.expand(
                  child: WorldRoot(rootNode: _galaxyNode),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SliderBlock extends StatelessWidget {
  const SliderBlock({
    super.key,
    required this.label,
    required this.min,
    required this.max,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final double min;
  final double max;
  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(label),
        SizedBox(
          width: 150.0,
          child: Slider(
            value: value,
            min: min,
            max: max,
            label: value.toStringAsFixed(2),
            onChanged: onChanged,
          ),
        ),
        const SizedBox(width: 16.0),
      ],
    );
  }
}
