import 'package:flutter/widgets.dart' hide Gradient, ProxyWidget;

import '../assets.dart';
import '../icons.dart';
import '../prettifiers.dart';
import '../spacetime.dart';
import '../widgets.dart';
import '../world.dart';
import 'proxy.dart';

class SampleAssetFeature extends ContainerFeature {
  SampleAssetFeature({
    required this.size,
    required this.mass,
    required this.massFlowRate,
    required this.timeOrigin,
    required this.spaceTime,
    required this.child,
  });

  final double size;
  final double mass;
  final double massFlowRate;
  final int timeOrigin;
  final SpaceTime spaceTime;
  final AssetNode? child;

  @override
  Offset findLocationForChild(AssetNode child, List<VoidCallback> callbacks) {
    assert(child == this.child);
    return Offset.zero;
  }

  @override
  void attach(Node parent) {
    super.attach(parent);
    if (child != null)
      child!.attach(this);
  }

  @override
  void detach() {
    if (child?.parent == this)
      child!.dispose();
    super.detach();
  }

  @override
  void walk(WalkCallback callback) {
    if (child != null) {
      child!.walk(callback);
    }
  }

  @override
  RendererType get rendererType => RendererType.overlay;

  @override
  Widget buildRenderer(BuildContext context) {
    return ProxyWidget(
      node: parent,
      diameter: parent.diameter,
      maxDiameter: parent.maxRenderDiameter,
      child: child?.build(context),
    );
  }

  Widget _buildMass(BuildContext context) {
    if (massFlowRate == 0.0)
      return Text(prettyMass(mass));
    return ValueListenableBuilder<double>(
      valueListenable: spaceTime.asListenable(),
      builder: (BuildContext context, double time, Widget? widget) {
        final double elapsed = time - timeOrigin; // ms
        return Text(prettyMass(mass + massFlowRate * elapsed));
      },
    );
  }

  @override
  Widget buildDialog(BuildContext context) {
    final double fontSize = DefaultTextStyle.of(context).style.fontSize!;
    final IconsManager icons = IconsManagerProvider.of(context);
    return ListBody(
      children: <Widget>[
        const Text('Sample container', style: bold),
        Padding(
          padding: featurePadding,
          child: _buildMass(context),
        ),
        Padding(
          padding: featurePadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (child == null)
                const Text('Empty', style: italic),
              if (child != null)
                Text.rich(
                  child!.describe(context, icons, iconSize: fontSize),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
