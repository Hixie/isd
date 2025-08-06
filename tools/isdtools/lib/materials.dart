import 'dart:io';
import 'dart:math' show Random, exp, log, max, pow;
import 'dart:ui' show PointMode, lerpDouble;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

const double AU = 1.496e11; // ignore: constant_identifier_names

class MaterialNode implements Comparable<MaterialNode> {
  MaterialNode({
    required this.distance,
    required this.abundance,
  });

  double distance;
  double abundance;

  Offset toOffset() => Offset(distance, abundance);

  Widget build(BuildContext context, double total, Rect graph, double size, double minDistance, double maxDistance, double maxAbundance, Color color, VoidCallback onChange, VoidCallback onRemove, VoidCallback onRemoveLine, { required bool pinned }) {
    final double origAbundance = abundance;
    final double x = graph.left + graph.width * log(distance.clamp(minDistance, maxDistance) / minDistance) / log(maxDistance / minDistance);
    final double y = graph.top + graph.height - graph.height * (total > 0.0 ? abundance / (total * maxAbundance) : 0.0);
    return GraphNodeWidget(
      key: ObjectKey(this),
      x: x,
      y: y,
      size: size,
      onChange: (double x, double y) {
        if (!pinned) {
          distance = (exp((x - graph.left) * log(maxDistance / minDistance) / graph.width) * minDistance).clamp(minDistance, maxDistance);
        }
        if (total > origAbundance) {
          final double graphBottom = graph.top + graph.height;
          final double yPos = max(graphBottom - y, 0.0);
          if (yPos < graph.height / maxAbundance) {
            abundance = yPos * (total - origAbundance) / (graph.height / maxAbundance - yPos);
          }
        } else {
          if (y < graph.bottom && abundance == 0.0) {
            abundance = 1.0; // arbitrary value to bring it above 0.0
          }
        }
        onChange();
      },
      onRemove: distance > minDistance ? onRemove : onRemoveLine,
      decoration: ShapeDecoration(
        shape: pinned ? BeveledRectangleBorder(borderRadius: BorderRadius.circular(10.0)) : const CircleBorder(),
        color: color,
      ),
    );
  }

  @override
  int compareTo(MaterialNode other) {
    return distance.compareTo(other.distance);
  }

  @override
  String toString() {
    return '${abundance.toStringAsPrecision(2)}@${(distance/AU).toStringAsPrecision(2)}AU';
  }
}

class Material {
  Material(this.id, this.label, this.ambiguousName, this.description, this.color, this.tags, this.density, this.bondAlbedo, this.abundanceDistribution);

  final int id;
  final String label;
  final String ambiguousName;
  final String description;
  final Color color;
  final Set<String> tags;
  final double density;
  final double? bondAlbedo;
  final List<MaterialNode> abundanceDistribution;

  double abundanceAt(double distance) {
    assert(distance >= 0);
    assert(abundanceDistribution.first.distance <= distance);
    int index = 0;
    while (index < abundanceDistribution.length && abundanceDistribution[index].distance < distance) {
      index += 1;
    }
    if (index >= abundanceDistribution.length) {
      return abundanceDistribution.last.abundance;
    }
    if (abundanceDistribution[index].distance == distance) {
      return abundanceDistribution[index].abundance;
    }
    return lerpDouble(
      abundanceDistribution[index-1].abundance,
      abundanceDistribution[index].abundance,
      (distance - abundanceDistribution[index-1].distance) / (abundanceDistribution[index].distance - abundanceDistribution[index - 1].distance),
    )!;
  }
}

class MaterialsPane extends StatefulWidget {
  const MaterialsPane({super.key, required this.onExit});

  final VoidCallback onExit;

  @override
  _MaterialsPaneState createState() => _MaterialsPaneState();
}

class _MaterialsPaneState extends State<MaterialsPane> {
  final List<Material> _materials = <Material>[];

  static const EdgeInsets graphPadding = EdgeInsets.fromLTRB(72.0, 0.0, 0.0, 32.0);
  static const double spacing = 8.0;
  static const double minDistance = 0.10 * AU;
  static const double maxDistance = 100.0 * AU;

  double _zoom = 1.0;

  final Random random = Random(0);

  static String encodeColor(Color color) {
    final int value = ((color.r * 255).truncate() << 16)
                    + ((color.g * 255).truncate() << 8)
                    + ((color.b * 255).truncate());
    return value.toRadixString(16).padLeft(6, '0');
  }

  @override
  void initState() {
    super.initState();
    _readFile();
  }

  void _readFile() {
    setState(() {
      try {
        final List<String> lines = File('materials.dat').readAsLinesSync();
        int index = 0;
        String readLine() {
          if (index >= lines.length) {
            return '';
          }
          final String result = lines[index];
          index += 1;
          return result;
        }
        _materials.clear();
        while (index < lines.length) {
          final int id = int.parse(readLine(), radix: 10);
          final String name = readLine();
          final String ambiguousName = readLine();
          final String description = readLine();
          final Color color = Color(int.parse(readLine(), radix: 16) | 0xFF000000);
          final Set<String> tags = readLine().split(',').toSet();
          final double density = double.parse(readLine());
          final String bondAlbedoLine = readLine();
          final double? bondAlbedo = bondAlbedoLine == 'n/a' ? null : double.parse(bondAlbedoLine);
          String line;
          final List<MaterialNode> abundanceDistribution = <MaterialNode>[];
          while ((line = readLine()) != '') {
            final List<double> parts = line.split(',').map(double.parse).toList();
            abundanceDistribution.add(MaterialNode(distance: parts[0], abundance: parts[1]));
          }
          _materials.add(Material(id, name, ambiguousName, description, color, tags, density, bondAlbedo, abundanceDistribution));
        }
      } on FileSystemException catch (e) {
        print('$e');
        _materials.clear();
      } on FormatException catch (e) {
        print('$e');
        _materials.clear();
      }
    });
  }

  void _writeFile() {
    final StringBuffer buffer = StringBuffer();
    for (Material material in _materials) {
      buffer.writeln(material.id);
      buffer.writeln(material.label);
      buffer.writeln(material.ambiguousName);
      buffer.writeln(material.description);
      buffer.writeln(encodeColor(material.color));
      buffer.writeln(material.tags.join(','));
      buffer.writeln(material.density);
      buffer.writeln(material.bondAlbedo ?? 'n/a');
      for (MaterialNode node in material.abundanceDistribution) {
        buffer.writeln('${node.distance},${node.abundance}');
      }
      buffer.writeln();
    }
    File('materials.dat').writeAsStringSync(buffer.toString());
  }

  void _newMaterial() {
    setState(() {
      _materials.add(
        Material(
          0,
          'Material #${_materials.length}',
          'Unknown material',
          'Non-descript material.',
          Color(0xFF303030 | random.nextInt(0xFFFFFF)),
          <String>{'matter'},
          1000.0,
          null,
          <MaterialNode>[
            MaterialNode(distance: minDistance, abundance: 0.0),
          ],
        ),
      );
    });
  }

  void _handleChange(Material material) {
    setState(() {
      material.abundanceDistribution.sort();
    });
  }

  void _handleRemove(Material material, MaterialNode node) {
    material.abundanceDistribution.remove(node);
    _handleChange(material);
  }

  void _handleRemoveMaterial(Material material) {
    if (material.abundanceDistribution.length == 1) {
      setState(() {
        _materials.remove(material);
      });
    }
  }

  static double nearestNotUnder(List<double> sortedList, double value) {
    int min = 0;
    int max = sortedList.length;
    while (min < max) {
      final int mid = min + ((max - min) >> 1);
      final double element = sortedList[mid];
      final int comp = element.compareTo(value);
      if (comp == 0) {
        return element;
      }
      if (comp < 0) {
        min = mid + 1;
      } else {
        max = mid;
      }
    }
    return sortedList[min];
  }

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: _zoom),
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeIn,
      builder: (BuildContext context, double zoom, Widget? child) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                IconButton(
                  icon: const Icon(Icons.zoom_in),
                  onPressed: () { setState(() { _zoom *= 2.0; }); },
                ),
                IconButton(
                  icon: const Icon(Icons.zoom_out),
                  onPressed: _zoom > 1.0 ? () { setState(() { _zoom = max(1.0, _zoom / 2.0); }); } : null,
                ),
                const SizedBox(width: 20.0),
                SizedBox(
                  width: 100.0,
                  child: Text(
                    'Zoom: x${zoom.toStringAsFixed(1)}',
                  ),
                ),
                const SizedBox(width: 20.0),
                OutlinedButton.icon(
                  icon: const Icon(Icons.file_open),
                  label: const Text('Load'),
                  onPressed: _readFile,
                ),
                const SizedBox(width: 8.0),
                OutlinedButton.icon(
                  icon: const Icon(Icons.save),
                  label: const Text('Save'),
                  onPressed: _writeFile,
                ),
                const SizedBox(width: 8.0),
                OutlinedButton.icon(
                  icon: const Icon(Icons.new_label),
                  label: const Text('New Material'),
                  onPressed: _newMaterial,
                ),
              ],
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(spacing, spacing, spacing, spacing),
                child: LayoutBuilder(
                  builder: (BuildContext context, BoxConstraints constraints) {
                    final Rect graph = graphPadding.topLeft & graphPadding.deflateSize(constraints.biggest);
                    final Set<double> distancesUnsorted = <double>{minDistance, maxDistance};
                    for (Material material in _materials) {
                      distancesUnsorted.addAll(material.abundanceDistribution.map((MaterialNode node) => node.distance.clamp(minDistance, maxDistance)));
                    }
                    final double pixelCount = graph.width * MediaQuery.of(context).devicePixelRatio;
                    final double k = pow(maxDistance / minDistance, 1.0 / pixelCount).toDouble();
                    for (int index = 1; index < pixelCount - 1; index += 1) {
                      distancesUnsorted.add(minDistance * pow(k, index));
                    }
                    final List<double> distances = distancesUnsorted.toList()..sort();
                    final Map<double, double> abundanceSums = <double, double>{};
                    for (double x in distances) {
                      double total = 0.0;
                      for (Material material in _materials) {
                        total += material.abundanceAt(x);
                      }
                      abundanceSums[x] = total;
                    }
                    final List<Color> colors = <Color>[];
                    final List<List<Offset>> lines = <List<Offset>>[];
                    for (Material material in _materials) {
                      colors.add(material.color);
                      final List<Offset> points = <Offset>[];
                      for (int index = 0; index < distances.length; index += 1) {
                        final double x = distances[index];
                        final double y = material.abundanceAt(x);
                        final double total = abundanceSums[x]!;
                        final double abundance = total == 0.0 ? 0.0 : y / total;
                        points.add(Offset(x, abundance));
                      }
                      lines.add(points);
                    }
                    Material? ghostMaterial;
                    const double ghostSize = spacing * 4.0;
                    late double ghostX;
                    late double ghostY;
                    late double ghostDistance;
                    late double ghostAbundance;
                    return StatefulBuilder(
                      builder: (BuildContext context, StateSetter setState) => ClipRect(
                        child: CustomPaint(
                          painter: GraphPainter(
                            margin: graphPadding,
                            spacing: spacing,
                            colors: colors,
                            lines: lines,
                            minDistance: minDistance,
                            maxDistance: maxDistance,
                            maxAbundance: 1.0 / zoom,
                          ),
                          child: Listener(
                            behavior: HitTestBehavior.opaque,
                            onPointerHover: (PointerHoverEvent event) {
                              setState(() {
                                ghostMaterial = null;
                                final double x = (event.localPosition.dx - graph.left) / graph.width;
                                if (x < 0.0 || x > 1.0) {
                                  return;
                                }
                                final double realX = minDistance * pow(maxDistance / minDistance, x);
                                ghostDistance = nearestNotUnder(distances, realX);
                                final double y = ((graph.bottom - event.localPosition.dy) / (graph.height * zoom)).clamp(0.0, 1.0);
                                double bestD = double.infinity;
                                late double bestY;
                                late double bestAbundance;
                                for (Material material in _materials) {
                                  final double candidateAbundance = material.abundanceAt(ghostDistance);
                                  final double candidateY = candidateAbundance / abundanceSums[ghostDistance]!;
                                  final double d = (candidateY - y).abs();
                                  if (d < bestD && d < 48.0 / graph.height) {
                                    bestD = d;
                                    bestY = candidateY;
                                    ghostMaterial = material;
                                    bestAbundance = candidateAbundance;
                                  }
                                }
                                if (ghostMaterial != null) {
                                  ghostAbundance = bestAbundance;
                                  ghostX = graph.left + graph.width * x;
                                  ghostY = graph.top + graph.height - graph.height * bestY * _zoom;
                                }
                              });
                            },
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: <Widget>[
                                if (ghostMaterial != null)
                                  Positioned(
                                    left: ghostX - ghostSize / 2.0,
                                    top: ghostY - ghostSize / 2.0,
                                    width: ghostSize,
                                    height: ghostSize,
                                    child: GestureDetector(
                                      onTap: () {
                                        ghostMaterial!.abundanceDistribution.add(MaterialNode(distance: ghostDistance, abundance: ghostAbundance));
                                        _handleChange(ghostMaterial!);
                                      },
                                      child: DecoratedBox(
                                        decoration: ShapeDecoration(
                                          shape: const StarBorder(
                                            points: 8.0,
                                          ),
                                          color: ghostMaterial!.color.withValues(alpha: 0.35),
                                        ),
                                      ),
                                    ),
                                  ),
                                ..._materials.expand((Material material) => material.abundanceDistribution.map(
                                  (MaterialNode node) => node.build(
                                    context,
                                    abundanceSums[node.distance.clamp(minDistance, maxDistance)]!,
                                    graph,
                                    spacing * 3.0,
                                    minDistance,
                                    maxDistance,
                                    1.0 / zoom,
                                    material.color,
                                    () => _handleChange(material),
                                    () => _handleRemove(material, node),
                                    () => _handleRemoveMaterial(material),
                                    pinned: node == material.abundanceDistribution.first,
                                  ),
                                )),
                                if (ghostMaterial != null)
                                  Positioned(
                                    left: ghostX < graph.width / 2.0 ? ghostX : null,
                                    right: ghostX < graph.width / 2.0 ? null : graph.right - ghostX,
                                    top: ghostY < graph.height / 2.0 ? ghostY : ghostY - spacing * 10.0,
                                    child: Padding(
                                      padding: const EdgeInsets.all(spacing * 5.0),
                                      child: DecoratedBox(
                                        decoration: ShapeDecoration(
                                          shape: const StadiumBorder(),
                                          color: ghostMaterial!.color.withValues(alpha: 0.35),
                                        ),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: spacing * 2.0, vertical: spacing / 2.0),
                                          child: Text(ghostMaterial!.label),
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class GraphPainter extends CustomPainter {
  GraphPainter({
    required this.margin,
    required this.spacing,
    required this.colors,
    required this.lines,
    required this.minDistance,
    required this.maxDistance,
    required this.maxAbundance,
  }) : assert(lines.length == colors.length);

  final EdgeInsets margin;
  final double spacing;
  final List<Color> colors;
  final List<List<Offset>> lines;
  final double minDistance;
  final double maxDistance;
  final double maxAbundance; // 0 < maxAbundance <= 1.0

  static final Paint axisPaint = Paint()
    ..strokeWidth = 2.0
    ..color = const Color(0xFF000000);

  @override
  void paint(Canvas canvas, Size size) {
    final Size graph = margin.deflateSize(size);
    // AXES
    const TextStyle labelStyle = TextStyle(
      color: Color(0xFF000000),
      fontSize: 12.0,
    );
    // x axis
    canvas.drawLine(Offset(margin.left - spacing * 2.0, margin.top + graph.height), Offset(size.width - margin.right, margin.top + graph.height), axisPaint);
    final double labelWidth = spacing * 10.0;
    double x = 3.0 * labelWidth / 4.0;
    while (x < graph.width - labelWidth / 4.0) {
      final String labelText = (minDistance * pow(maxDistance / minDistance, x / graph.width) / AU).toStringAsPrecision(2);
      final TextPainter label = TextPainter(text: TextSpan(text: '$labelText AU', style: labelStyle), textDirection: TextDirection.ltr, textAlign: TextAlign.center);
      label.layout(minWidth: labelWidth, maxWidth: labelWidth);
      label.paint(canvas, Offset(margin.left + x - labelWidth / 2.0, margin.top + graph.height + spacing * 2.0));
      label.dispose();
      canvas.drawLine(Offset(margin.left + x, margin.top + graph.height), Offset(margin.left + x, margin.top + graph.height + spacing * 2.0), axisPaint);
      x += labelWidth;
    }
    // y axis
    canvas.drawLine(Offset(margin.left, margin.top), Offset(margin.left, margin.top + graph.height + spacing * 2.0), axisPaint);
    double y = margin.top + spacing;
    if (maxAbundance == 1.0) {
      final TextPainter label = TextPainter(text: const TextSpan(text: 'most abundant', style: labelStyle), textDirection: TextDirection.ltr, textAlign: TextAlign.right);
      label.layout(minWidth: margin.left - spacing, maxWidth: margin.left - spacing);
      label.paint(canvas, Offset(0.0, y));
      canvas.drawLine(Offset(margin.left - spacing * 2.0, margin.top + axisPaint.strokeWidth / 2.0), Offset(margin.left, margin.top + axisPaint.strokeWidth / 2.0), axisPaint);
      y += label.height + spacing;
      label.dispose();
    } else {
      canvas.drawPoints(
        PointMode.polygon,
        <Offset>[
          Offset(margin.left - spacing, margin.top + spacing),
          Offset(margin.left, margin.top),
          Offset(margin.left + spacing, margin.top + spacing),
        ], axisPaint,
      );
      y += spacing * 2.0;
    }
    final double remainder = margin.top + graph.height - y;
    final double delta = remainder / (remainder / (labelStyle.fontSize! * 4.0)).truncate();
    while (y < margin.top + graph.height - delta / 2.0) {
      final String labelText = (100.0 * (maxAbundance * (graph.height + margin.top - y) / graph.height)).toStringAsFixed(1);
      final TextPainter label = TextPainter(text: TextSpan(text: '$labelText%', style: labelStyle), textDirection: TextDirection.ltr, textAlign: TextAlign.right);
      label.layout(minWidth: margin.left - spacing, maxWidth: margin.left - spacing);
      label.paint(canvas, Offset(0.0, y - labelStyle.fontSize! / 2.0));
      canvas.drawLine(Offset(margin.left - spacing, y), Offset(margin.left, y), axisPaint);
      y += delta;
      label.dispose();
    }
    // LINES
    for (int index = 0; index < lines.length; index += 1) {
      final Paint linePaint = Paint()
        ..strokeWidth = 4.0
        ..color = colors[index];
      final List<Offset> points = <Offset>[];
      for (Offset offset in lines[index]) {
        points.add(Offset(margin.left + graph.width * log(offset.dx / minDistance) / log(maxDistance / minDistance), margin.top + graph.height - graph.height * (offset.dy / maxAbundance)));
      }
      canvas.drawPoints(PointMode.polygon, points, linePaint);
    }
  }

  @override
  bool shouldRepaint(GraphPainter oldDelegate) {
    return margin != oldDelegate.margin
        || colors != oldDelegate.colors
        || lines != oldDelegate.lines
        || minDistance != oldDelegate.minDistance
        || maxDistance != oldDelegate.maxDistance
        || maxAbundance != oldDelegate.maxAbundance;
  }
}

typedef GraphNodeChangeCallback = void Function(double x, double y);

class GraphNodeWidget extends StatefulWidget {
  const GraphNodeWidget({
    super.key,
    required this.x,
    required this.y,
    required this.size,
    required this.onChange,
    required this.onRemove,
    required this.decoration,
  });

  final double x;
  final double y;
  final double size;
  final GraphNodeChangeCallback onChange;
  final VoidCallback? onRemove;
  final Decoration decoration;

  @override
  State<GraphNodeWidget> createState() => _GraphNodeWidgetState();
}

class _GraphNodeWidgetState extends State<GraphNodeWidget> {
  late double _x, _y;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: widget.x - widget.size / 2.0,
      top: widget.y - widget.size / 2.0,
      width: widget.size,
      height: widget.size,
      child: GestureDetector(
        onPanStart: (DragStartDetails details) {
          _x = widget.x;
          _y = widget.y;
        },
        onPanUpdate: (DragUpdateDetails details) {
          _x += details.delta.dx;
          _y += details.delta.dy;
          widget.onChange(_x, _y);
        },
        onSecondaryTap: widget.onRemove,
        child: DecoratedBox(
          decoration: widget.decoration,
        ),
      ),
    );
  }
}
