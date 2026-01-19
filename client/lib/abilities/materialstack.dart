import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../assets.dart';
import '../icons.dart';
import '../nodes/system.dart';
import '../prettifiers.dart';
import '../spacetime.dart';
import '../widgets.dart';

// TODO: share code with nearly-identical MaterialPileFeature

class MaterialStackFeature extends AbilityFeature {
  MaterialStackFeature({
    required this.pileQuantity,
    required this.pileQuantityFlowRate,
    required this.timeOrigin,
    required this.spaceTime,
    required this.capacity,
    required this.materialName,
    required this.material,
  });

  final int pileQuantity;
  final double pileQuantityFlowRate; // units/ms
  final int timeOrigin;
  final SpaceTime spaceTime;
  final int capacity;
  final String materialName;
  final int material;

  @override
  RendererType get rendererType => RendererType.ui;

  Widget _buildForQuantity(BuildContext context, int currentQuantity) {
    return CustomPaint(
      painter: _Stack(
        pileQuantity: currentQuantity,
        capacity: capacity.toDouble(),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: 30.0,
        ),
        child: FittedBox(
          alignment: Alignment.bottomCenter,
          child: Text(
            '${prettyFraction(currentQuantity / capacity)} full\n${prettyQuantity(currentQuantity, zero: "empty")}',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }

  @override
  Widget buildRenderer(BuildContext context) {
    if (pileQuantityFlowRate == 0.0)
      return _buildForQuantity(context, pileQuantity);
    return ValueListenableBuilder<double>(
      valueListenable: spaceTime.asListenable(),
      builder: (BuildContext context, double time, Widget? widget) {
        final double elapsed = time - timeOrigin; // ms
        return _buildForQuantity(context, (pileQuantity + pileQuantityFlowRate * elapsed).truncate());
      },
    );
  }

  Widget _buildDialogInternal(BuildContext context, IconsManager icons, double duration, { required double fontSize }) {
    final int quantity = math.min(pileQuantity + duration * pileQuantityFlowRate, capacity).truncate();
    return ListBody(
      children: <Widget>[
        Text('${prettyQuantity(quantity)} out of ${prettyQuantity(capacity)}'),
        if (quantity == capacity)
          const Text('Storage is full.')
        else if (quantity == 0.0)
          const Text('Storage is empty.')
        else if (pileQuantityFlowRate > 0.0)
          Text('Storage is filling at ${prettyRate(pileQuantityFlowRate, const Quantity('', ''))}.')
        else if (pileQuantityFlowRate < 0.0)
          Text('Storage is draining at ${prettyRate(-pileQuantityFlowRate, const Quantity('', ''))}.')
        else if (pileQuantityFlowRate < 0.0)
          const Text('Storage is not changing.'),
      ],
    );
  }

  @override
  Widget buildDialog(BuildContext context) {
    final double fontSize = DefaultTextStyle.of(context).style.fontSize!;
    final IconsManager icons = IconsManagerProvider.of(context);
    final SystemNode system = SystemNode.of(parent);
    Widget result;
    if (pileQuantityFlowRate == 0.0) {
      result = _buildDialogInternal(context, icons, 0.0, fontSize: fontSize);
    } else {
      result = ValueListenableBuilder<double>(
        valueListenable: spaceTime.asListenable(),
        builder: (BuildContext context, double time, Widget? widget) {
          final double elapsed = time - timeOrigin; // ms
          return _buildDialogInternal(context, icons, elapsed, fontSize: fontSize);
        },
      );
    }
    return ListBody(
      children: <Widget>[
        Text.rich(
          TextSpan(
            style: bold,
            children: <InlineSpan>[
              if (material != 0)
                system.material(material).describe(context, icons, iconSize: fontSize)
              else
                TextSpan(text: materialName),
              const TextSpan(text: ' storage:'),
            ],
          ),
        ),
        Padding(
          padding: featurePadding,
          child: result,
        ),
      ],
    );
  }
}

class _Stack extends CustomPainter {
  const _Stack({ required this.pileQuantity, required this.capacity });

  final int pileQuantity;
  final double capacity;

  static final Paint _innerPaint = Paint()
    ..color = const Color(0xFFFFFFFF);

  static final Paint _outerPaint = Paint()
    ..color = const Color(0xFF000000)
    ..strokeWidth = 12.0
    ..style = PaintingStyle.stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final double top = size.height * (1.0 - pileQuantity / capacity);
    final Path path = Path()
      ..moveTo(0.0, size.height)
      ..lineTo(0.0, top)
      ..lineTo(size.width, top)
      ..lineTo(size.width, size.height);
    canvas.drawPath(path, _innerPaint);
    canvas.drawPath(path, _outerPaint);
  }

  @override
  bool shouldRepaint(_Stack oldDelegate) => oldDelegate.pileQuantity != pileQuantity ||
                                            oldDelegate.capacity != capacity;
}
