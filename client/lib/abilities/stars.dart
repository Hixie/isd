import 'package:flutter/widgets.dart';

import '../assets.dart';
import '../layout.dart';

class StarFeature extends AbilityFeature {
  StarFeature(this.starId);
  final int starId;

  @override
  Widget? buildRenderer(BuildContext context, Widget? child) {
    return StarWidget(
      starId: starId,
      diameter: parent.diameter,
      maxDiameter: parent.maxRenderDiameter,
    );
  }
}

class StarWidget extends LeafRenderObjectWidget {
  const StarWidget({
    super.key,
    required this.starId,
    required this.diameter,
    required this.maxDiameter,
  });

  final int starId;
  final double diameter;
  final double maxDiameter;

  @override
  RenderStar createRenderObject(BuildContext context) {
    return RenderStar(
      starId: starId,
      diameter: diameter,
      maxDiameter: maxDiameter,
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderStar renderObject) {
    renderObject
      ..starId = starId
      ..diameter = diameter
      ..maxDiameter = maxDiameter;
  }
}

class RenderStar extends RenderWorld {
  RenderStar({
    required int starId,
    required double diameter,
    required double maxDiameter,
  }) : _starId = starId,
       _diameter = diameter,
       _maxDiameter = maxDiameter;

  int get starId => _starId;
  int _starId;
  set starId (int value) {
    if (value != _starId) {
      _starId = value;
      markNeedsLayout();
    }
  }

  double get diameter => _diameter;
  double _diameter;
  set diameter (double value) {
    if (value != _diameter) {
      _diameter = value;
      markNeedsLayout();
    }
  }

  double get maxDiameter => _maxDiameter;
  double _maxDiameter;
  set maxDiameter (double value) {
    if (value != _maxDiameter) {
      _maxDiameter = value;
      markNeedsLayout();
    }
  }
  
  @override
  void computeLayout(WorldConstraints constraints) { }

  static final Paint _paint = Paint()
    ..color = const Color(0xFFEE9900);

  @override
  WorldGeometry computePaint(PaintingContext context, Offset offset) {
    // TODO: starId-based paint
    context.canvas.drawCircle(offset, computePaintDiameter(diameter, maxDiameter) / 2.0, _paint);
    return WorldGeometry(shape: Circle(diameter));
  }
  
  @override
  WorldTapTarget? routeTap(Offset offset) {
    return null; // TODO
  }
}
