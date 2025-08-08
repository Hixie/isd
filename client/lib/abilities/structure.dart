import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../assets.dart';
import '../icons.dart';
import '../materials.dart';
import '../nodes/system.dart';
import '../prettifiers.dart';
import '../spacetime.dart';
import '../widgets.dart';

class StructuralComponent {
  StructuralComponent({
    required this.max,
    required this.componentName,
    required this.materialID,
    required this.materialName,
  });

  final int max;
  final String? componentName;
  final int materialID;
  final String materialName;
}

class StructureFeature extends AbilityFeature {
  StructureFeature({
    required this.structuralComponents,
    required this.timeOrigin,
    required this.spaceTime,
    required this.materialsCurrent,
    required this.materialsRate,
    required this.structuralIntegrityCurrent,
    required this.structuralIntegrityRate,
    required this.minIntegrity,
    required this.max,
  });

  final List<StructuralComponent> structuralComponents;
  final int timeOrigin;
  final SpaceTime spaceTime;
  final int materialsCurrent;
  final double materialsRate;
  final int structuralIntegrityCurrent;
  final double structuralIntegrityRate;
  final int? minIntegrity;
  final int? max;

  @override
  RendererType get rendererType => RendererType.overlay;

  Widget? _cachedBuild;

  @override
  Widget buildRenderer(BuildContext context) {
    return _cachedBuild ??= WorldToBoxAdapter(
      node: parent,
      diameter: parent.diameter,
      maxDiameter: parent.maxRenderDiameter,
      child: (max == null) || (minIntegrity == null) || (structuralIntegrityCurrent == max!) ? const SizedBox.shrink() : Align(
        alignment: Alignment.topCenter,
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            return SizedBox(
              width: double.infinity,
              height: math.min(20.0, constraints.maxWidth / 20.0),
              // TODO: Semantics
              child: CustomPaint(
                painter: HealthBar(this),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildProgressBar(BuildContext context, IconsManager icons, SystemNode system, double duration, { required double fontSize }) {
    int remaining = math.min(max ?? materialsCurrent, materialsCurrent + (duration * materialsRate).truncate());
    final int structuralIntegrity = math.min(remaining, structuralIntegrityCurrent + (duration * structuralIntegrityRate).truncate());

    double smallest = double.infinity;
    for (StructuralComponent component in structuralComponents) {
      if (component.max < smallest) {
        smallest = component.max.toDouble();
      }
    }
    final double scaleFactor = fontSize * 3.0 / smallest;

    final double total = (max ?? materialsCurrent).toDouble();
    final double height = total * scaleFactor;
    final bool goodHealth = (minIntegrity == null) || (structuralIntegrity >= minIntegrity!);

    final List<Widget> bars = <Widget>[];

    for (StructuralComponent component in structuralComponents) {
      final int maxAmount = component.max;
      final int actualAmount = remaining >= component.max ? component.max : remaining;
      remaining -= actualAmount;
      final Material? material;
      InlineSpan label;
      if (component.materialID == 0) {
        material = null;
        if (actualAmount < component.max) {
          label = TextSpan(text: '${prettyFraction(actualAmount / component.max)} ${component.materialName}');
        } else {
          label = TextSpan(text: component.materialName);
        }
      } else {
        material = system.material(component.materialID);
        label = material.describeQuantity(context, icons, maxAmount, iconSize: fontSize);
      }
      if (component.componentName != null)
        label = TextSpan(text: '${component.componentName}\n', children: <InlineSpan>[label]);
      bars.add(
        SizedBox(
          height: maxAmount * scaleFactor,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              SizedBox(
                width: fontSize * 2.0,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    image: material?.asDecorationImage(context, icons, size: fontSize),
                    gradient: actualAmount >= maxAmount
                      ? const LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: <Color>[
                            HealthBar.darkBlue,
                            HealthBar.blue,
                          ],
                        )
                      : LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: const <Color>[
                            HealthBar.darkBlue,
                            HealthBar.blue,
                            HealthBar.darkGrey,
                            HealthBar.grey,
                          ],
                          stops: <double>[
                            0.0,
                            actualAmount / maxAmount,
                            actualAmount / maxAmount,
                            1.0,
                          ],
                        ),
                  ),
                ),
              ),
              SizedBox(width: fontSize / 2.0),
              SizedBox(
                width: fontSize,
                child: CustomPaint(painter: Brace(fontSize)),
              ),
              SizedBox(width: fontSize / 2.0),
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text.rich(label),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListBody(
      children: <Widget>[
        if (max != null)
          Text('Total: $structuralIntegrity / $max hp')
        else
          Text('Total: $structuralIntegrity hp'),
        SizedBox(
          height: height,
          child: Stack(
            children: <Widget>[
              if (minIntegrity != null)
                if (minIntegrity! * scaleFactor < height - fontSize * 2.0)
                  Positioned(
                    left: 0.0,
                    bottom: minIntegrity! * scaleFactor,
                    width: fontSize * 5.0,
                    child: const DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            width: 2.0,
                          ),
                        ),
                      ),
                      child: Text('Minimum', textAlign: TextAlign.center, style: italic),
                    ),
                  )
                else
                  Positioned(
                    left: 0.0,
                    top: (total - minIntegrity!) * scaleFactor,
                    width: fontSize * 5.0,
                    child: const DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border(
                          top: BorderSide(
                            width: 2.0,
                          ),
                        ),
                      ),
                      child: Text('Minimum', textAlign: TextAlign.center, style: italic),
                    ),
                  ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  SizedBox(
                    width: fontSize * 2.0,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: goodHealth
                            ? const <Color>[
                              HealthBar.darkGreen,
                              HealthBar.green,
                              HealthBar.darkGrey,
                              HealthBar.grey,
                            ]
                            : const <Color>[
                              HealthBar.darkRed,
                              HealthBar.red,
                              HealthBar.darkGrey,
                              HealthBar.grey,
                            ],
                          stops: <double>[
                            0.0,
                            structuralIntegrity / total,
                            structuralIntegrity / total,
                            1.0,
                          ],
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: fontSize),
                  Expanded(
                    child: SizedBox(
                      child: Column(
                        verticalDirection: VerticalDirection.up,
                        children: bars,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget buildDialog(BuildContext context) {
    final double fontSize = DefaultTextStyle.of(context).style.fontSize!;
    final IconsManager icons = IconsManagerProvider.of(context);
    final SystemNode system = SystemNode.of(parent);
    Widget result;
    if ((materialsRate == 0.0) && (structuralIntegrityRate == 0.0)) {
      result = _buildProgressBar(context, icons, system, 0.0, fontSize: fontSize);
    } else {
      result = ValueListenableBuilder<double>(
        valueListenable: spaceTime.asListenable(),
        builder: (BuildContext context, double time, Widget? widget) {
          final double elapsed = time - timeOrigin; // ms
          return _buildProgressBar(context, icons, system, elapsed, fontSize: fontSize);
        },
      );
    }
    return ListBody(
      children: <Widget>[
        const Text('Structural integrity and construction', style: bold),
        Padding(
          padding: featurePadding,
          child: result,
        ),
      ],
    );
  }
}

class HealthBar extends CustomPainter {
  HealthBar(this.feature)
    : super(repaint: (feature.structuralIntegrityRate != 0.0) || (feature.materialsRate != 0.0) ? feature.spaceTime.asListenable() : null);

  final StructureFeature feature;

  static const Color green = Color(0x7F00FF20);
  static const Color darkGreen = Color(0x7F009020);
  static const Color red = Color(0x7FFF0020);
  static const Color darkRed = Color(0x7F900020);
  static const Color grey = Color(0x7F666666);
  static const Color darkGrey = Color(0x7F333333);
  static const Color blue = Color(0x7F6060FF);
  static const Color darkBlue = Color(0x7F202099);

  static final Paint _green = Paint()
    ..color = green;

  static final Paint _red = Paint()
    ..color = red;

  static final Paint _grey = Paint()
    ..color = grey;

  @override
  void paint(Canvas canvas, Size size) {
    final double duration = feature.spaceTime.computeTime(const <VoidCallback>[]) - feature.timeOrigin;
    final int actualCurrent = math.min(
      feature.structuralIntegrityCurrent + (duration * feature.structuralIntegrityRate).truncate(),
      math.min(
        feature.materialsCurrent + (duration * feature.materialsRate).truncate(),
        feature.max!,
      ),
    );
    final Paint paint = actualCurrent < feature.minIntegrity! ? _red : _green;
    double segmentWidth = size.width / feature.max!;
    if (segmentWidth < size.height) {
      final double x = size.width * actualCurrent / feature.max!;
      canvas.drawRect(Rect.fromLTRB(0.0, 0.0, x, size.height), paint);
      canvas.drawRect(Rect.fromLTRB(x, 0.0, size.width, size.height), _grey);
      return;
    }
    final double maxWidth = math.min(size.height * 10.0, size.width);
    double x = 0.0;
    if (segmentWidth > maxWidth) {
      segmentWidth = maxWidth;
      x = (size.width - segmentWidth * feature.max!) / 2.0;
      assert(x > 0);
    }
    for (int cell = 0; cell < actualCurrent; cell += 1) {
      canvas.drawRect(
        Rect.fromLTWH(x + cell * segmentWidth + 0.75, 0.0, segmentWidth - 1.5, size.height),
        paint,
      );
    }
    for (int cell = actualCurrent; cell < feature.max!; cell += 1) {
      canvas.drawRect(
        Rect.fromLTWH(x + cell * segmentWidth + 0.75, 0.0, segmentWidth - 1.5, size.height),
        _grey,
      );
    }
  }

  @override
  bool shouldRepaint(HealthBar old) {
    return feature != old.feature;
  }
}

class Brace extends CustomPainter {
  Brace(this.dim);

  final double dim;

  static final Paint _paint = Paint()
    ..style = PaintingStyle.stroke;

  static const double margin = 1.0;

  @override
  void paint(Canvas canvas, Size size) {
    assert(size.width >= dim);
    assert(size.height >= dim * 3.0, '${size.height} < $dim * 3.0 (${dim * 3.0})');
    assert(dim > margin * 6);
    final Path path = Path()
      ..moveTo(0.0, margin)
      ..arcToPoint(Offset(dim / 2.0, dim / 2.0), radius: Radius.circular((dim - margin) / 2.0))
      ..lineTo(dim / 2.0, (size.height - dim / 2.0) / 2.0)
      ..lineTo(dim, (size.height) / 2.0)
      ..lineTo(dim / 2.0, (size.height + dim / 2.0) / 2.0)
      ..lineTo(dim / 2.0, size.height - dim / 2.0)
      ..arcToPoint(Offset(0.0, size.height - margin), radius: Radius.circular((dim - margin) / 2.0));
    canvas.drawPath(path, _paint);
  }

  @override
  bool shouldRepaint(Brace old) => false;
}
