import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart' hide Material;

import 'assets.dart';
import 'hud.dart';
import 'icons.dart';
import 'materials.dart';
import 'nodes/system.dart';
import 'prettifiers.dart';
import 'stringstream.dart';
import 'widgets.dart';

class AnalysisUi extends StatefulWidget {
  AnalysisUi({
    required this.node,
  }) : super(key: ObjectKey(node));

  final AssetNode node;

  static void showDialog(BuildContext context, AssetNode node) {
    HudProvider.add(
      context,
      switch (MediaQuery.of(context).orientation) {
        Orientation.landscape => const Size(600.0, 400.0),
        Orientation.portrait => const Size(400.0, 600.0),
      },
      HudDialog(
        heading: Text('${node.nameOrClassName} contents analysis'),
        child: AnalysisUi(node: node),
      ),
    );
  }

  static Widget buildButton(BuildContext context, AssetNode node) {
    return OutlinedButton(
      onPressed: () {
        showDialog(context, node);
      },
      child: const Text('Analyze...'),
    );
  }

  @override
  State<AnalysisUi> createState() => _AnalysisUiState();
}

class _AnalysisUiState extends State<AnalysisUi> {
  bool _tired = true;
  bool _pending = true;
  Timer? _loadTimer;

  late final int _time;
  late final double _total;
  late final String _message;
  final Map<Material, int> _analysis = <Material, int>{};
  late final List<Material> _materials;

  @override
  void initState() {
    super.initState();
    final SystemNode system = SystemNode.of(widget.node);
    system
      .play(<Object>[widget.node.id, 'analyze'])
      .then((StreamReader reader) {
        if (mounted) {
          _loadTimer?.cancel();
          setState(() {
            _time = reader.readInt();
            _total = reader.readDouble();
            _message = reader.readString();
            while (!reader.eof) {
              final int materialId = reader.readInt();
              final int quantity = reader.readInt();
              _analysis[system.material(materialId)] = quantity;
            }
            _materials = _analysis.keys.toList();
            _materials.sort(_quantitySort);
            _pending = false;
            _tired = false;
          });
        }
      });
    _loadTimer = Timer(const Duration(milliseconds: 750), _loading);
  }

  void _loading() {
    setState(() {
      _tired = true;
    });
  }

  int _quantitySort(Material a, Material b) {
    return _analysis[b]! - _analysis[a]!;
  }

  @override
  Widget build(BuildContext context) {
    Widget body;
    if (_pending) {
      if (_tired) {
        body = const Center(
          child: CircularProgressIndicator(),
        );
      } else {
        body = const SizedBox.shrink();
      }
    } else {
      body = LayoutBuilder(
        builder: (BuildContext context, BoxConstraints viewportConstraints) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: viewportConstraints.maxHeight),
            child: IntrinsicHeight(
              child: Column(
                children: <Widget>[
                  PieChart(
                    node: widget.node,
                    time: _time,
                    total: _total,
                    analysis: _analysis,
                    materials: _materials,
                  ),
                  if (_message.isNotEmpty)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Center(
                          child: Text(
                            switch (_message) {
                              'not enough materials' => 'Pile has insufficient quantities of any one material for an analysis.',
                              'pile empty' => 'Pile is empty.',
                              _ => _message,
                            },
                            textAlign: TextAlign.center,
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
    }
    return AnimatedSwitcher(
      child: body,
      duration: const Duration(milliseconds: 160),
      switchInCurve: Curves.easeInOut,
      switchOutCurve: Curves.easeInOut,
    );
  }
}

class PieChart extends StatelessWidget {
  const PieChart({
    super.key,
    this.node,
    this.time,
    required this.total,
    required this.analysis,
    required this.materials,
  });

  final AssetNode? node;
  final int? time;
  final double total;
  final Map<Material, int> analysis;
  final List<Material> materials;

  static List<Color> get colors => _genColors();
  static List<Color> _genColors() {
    const int maxA = 8;
    final List<Color> colors = <Color>[];
    for (int a = 0; a < maxA; a += 1) {
      colors.add(HSLColor.fromAHSL(1.0, (70 + 360 * a/maxA) % 360.0, 1.0, 0.35).toColor());
    }
    for (int a = 0; a < maxA; a += 2) {
      colors.add(HSLColor.fromAHSL(1.0, 0, 0.0, a/maxA).toColor());
    }
    for (int a = 0; a < maxA; a += 1) {
      colors.add(HSLColor.fromAHSL(1.0, 360 * a/maxA, 1.0, 0.6).toColor());
    }
    for (int a = 0; a < maxA; a += 2) {
      colors.add(HSLColor.fromAHSL(1.0, 0, 0.0, (1.5 + a)/maxA).toColor());
    }
    for (int a = 0; a < maxA; a += 1) {
      colors.add(HSLColor.fromAHSL(1.0, 360 * a/maxA, 0.6, 0.5).toColor());
    }
    for (int a = 0; a < maxA; a += 1) {
      colors.add(HSLColor.fromAHSL(1.0, 360 * a/maxA, 1.0, 0.8).toColor());
      colors.add(HSLColor.fromAHSL(1.0, 360 * (maxA-a-1)/maxA, 0.3, 0.6).toColor());
    }
    for (int a = 0; a < maxA; a += 1) {
      colors.add(HSLColor.fromAHSL(1.0, 360 * a/maxA, 0.4, 0.45).toColor());
      colors.add(HSLColor.fromAHSL(1.0, 360 * (maxA-a-1)/maxA, 1.0, 0.15).toColor());
    }
    return colors;
  }

  @override
  Widget build(BuildContext context) {
    final double fontSize = DefaultTextStyle.of(context).style.fontSize!;
    final IconsManager icons = IconsManagerProvider.of(context);
    final List<Widget> legend = <Widget>[];
    if (materials.isEmpty) {
      legend.add(const Text('No materials found.'));
    } else {
      double accountedTotal = 0.0;
      for (int index = 0; index < materials.length; index += 1) {
        final Material material = materials[index];
        legend.add(Text.rich(
          TextSpan(
            children: <InlineSpan>[
              TextSpan(text: '●', style: TextStyle(color: colors[index])),
              const TextSpan(text: ' '),
              material.describeQuantity(context, icons, analysis[material]!, iconSize: fontSize),
            ],
          ),
        ));
        accountedTotal += analysis[material]!;
      }
      if (accountedTotal < total) {
        legend.add(const Text('○ Unknown'));
      }
      legend.add(const SizedBox(height: 8.0));
      legend.add(const Text('All numbers are approximate.', style: italic, softWrap: true, overflow: TextOverflow.visible));
    }
    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: Column(
        children: <Widget>[
          if (time != null && node != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: Text.rich(
                TextSpan(
                  style: bold,
                  children: <InlineSpan>[
                    node!.describe(context, icons, iconSize: fontSize),
                    TextSpan(text: ' contents analysis\n${prettyTime(time!)}'),
                  ],
                ),
                textAlign: TextAlign.center,
              ),
            ),
          if (time != null && node == null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: Text(
                'Contents analysis as of ${prettyTime(time!)}',
                style: bold,
                textAlign: TextAlign.center,
              ),
            ),
          if (time == null && node != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: Text.rich(
                TextSpan(
                  style: bold,
                  children: <InlineSpan>[
                    node!.describe(context, icons, iconSize: fontSize),
                    const TextSpan(text: ' contents analysis'),
                  ],
                ),
                textAlign: TextAlign.center,
              ),
            ),
          Wrap(
            children: <Widget>[
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 260.0, maxHeight: 260.0),
                child: AspectRatio(
                  aspectRatio: 1.0,
                  child: CustomPaint(painter: _PieChart(analysis, materials, colors, total)),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: legend,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PieChart extends CustomPainter {
  _PieChart(this.analysis, this.materials, this.colors, this.total);

  final Map<Material, int> analysis;
  final List<Material> materials;
  final List<Color> colors;
  final double total;

  static final Paint _linePaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.0
    ..color = const Color(0x99000000);

  @override
  void paint(Canvas canvas, Size size) {
    assert(colors.length >= materials.length);
    final Rect rect = Offset.zero & size;
    int index = 0;
    double swept = 0;
    final Paint paint = Paint();
    for (Material material in materials) {
      final double angle = 2 * math.pi * analysis[material]! / total;
      paint.color = colors[index];
      canvas.drawArc(rect, swept - math.pi / 2.0, angle, true, paint);
      swept += angle;
      index += 1;
    }
    if (swept < math.pi * 2.0)
      canvas.drawArc(rect, -math.pi / 2.0, swept - 2.0 * math.pi, false, _linePaint);
  }

  @override
  bool shouldRepaint(_PieChart old) => (analysis != old.analysis) || (materials != old.materials) || (colors != old.colors);
}
