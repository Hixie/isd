import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';

import 'containers/orbits.dart';
import 'dynasty.dart';
import 'hud.dart';
import 'icons.dart';
import 'layout.dart';
import 'nodes/system.dart';
import 'prettifiers.dart';
import 'root.dart';
import 'widgets.dart';
import 'world.dart';

typedef WalkCallback = bool Function(AssetNode node);

enum RendererType {
  /// do not include this feature in the rendering
  none,

  /// this is some sort of UI element, should be put in a field or be in a virtual asset container
  ui,

  /// this is a UI element that can be placed directly on top of the other renderers
  overlay,

  /// this is a square renderer
  square,

  /// this is a round renderer
  circle,

  /// this renderer doesn't really have a shape (e.g. orbits)
  space,
}

abstract class Feature extends Node {
  Feature({ AssetNode? super.parent });

  /// Current host for this feature.
  ///
  /// Only valid while attached.
  @override
  AssetNode get parent => super.parent! as AssetNode;

  @override
  void attach(Node parent) {
    assert(parent is AssetNode);
    super.attach(parent);
  }

  void init(Feature? oldFeature) {
    assert(oldFeature == null || oldFeature.runtimeType == runtimeType);
  }

  RendererType get rendererType;

  bool get debugExpectVirtualChildren => false;

  String? get status => null;

  Widget buildRenderer(BuildContext context); // this one is abstract; containers always need to build something

  Widget? buildHeader(BuildContext context) => null;

  Widget? buildDialog(BuildContext context) {
    debugPrint('warning: $runtimeType has no buildDialog');
     return null;
  }

  @override
  String toString() => '$runtimeType@${hashCode.toRadixString(16)}';
}

const EdgeInsets dialogPadding = EdgeInsets.only(left: 12.0, right: 12.0, top: 8.0);
const EdgeInsets sectionPadding = EdgeInsets.only(left: 12.0, right: 12.0, top: 12.0);
const EdgeInsets featurePadding = EdgeInsets.only(left: 20.0, top: 4.0);

abstract class AbilityFeature extends Feature {
  AbilityFeature();

  @override
  Widget buildRenderer(BuildContext context) {
    assert(rendererType == RendererType.none, '$runtimeType does not override buildRenderer');
    throw StateError('buildRenderer should not be called if rendererType is RendererType.none');
  }
}

/// Features that have children, which have positions.
///
/// Subclasses are expected to attach children (set their `parent` field) on
/// [attach], and reset them on [detach].
abstract class ContainerFeature extends Feature {
  ContainerFeature();

  Offset findLocationForChild(AssetNode child, List<VoidCallback> callbacks);

  void walk(WalkCallback callback);
}

class AssetNode extends WorldNode {
  AssetNode({ super.parent, required this.id });

  final int id;

  int get assetClassID => _assetClassID!;
  int? _assetClassID;
  set assetClassID(int value) {
    if (_assetClassID != value) {
      _assetClassID = value;
      notifyListeners();
    }
  }

  Dynasty? get ownerDynasty => _ownerDynasty;
  Dynasty? _ownerDynasty;
  set ownerDynasty(Dynasty? value) {
    if (_ownerDynasty != value) {
      _ownerDynasty = value;
      notifyListeners();
    }
  }

  double get mass => _mass!; // kg
  double? _mass;
  set mass(double value) {
    if (_mass != value) {
      _mass = value;
      notifyListeners();
    }
  }

  double get massFlowRate => _massFlowRate!; // kg
  double? _massFlowRate;
  set massFlowRate(double value) {
    if (_massFlowRate != value) {
      _massFlowRate = value;
      notifyListeners();
    }
  }

  int get timeOrigin => _timeOrigin!; // ms
  int? _timeOrigin;
  set timeOrigin(int value) {
    if (_timeOrigin != value) {
      _timeOrigin = value;
      notifyListeners();
    }
  }

  double get size => _size!; // meters
  double? _size;
  set size(double value) {
    if (_size != value) {
      _size = value;
      notifyListeners();
    }
  }

  bool get isVirtual => mass == 0.0 && massFlowRate == 0.0 && size == 0.0;
  bool get isGhost => mass == 0.0 && massFlowRate == 0.0 && size != 0.0;

  String get name => _name ?? '';
  String? _name;
  set name(String? value) {
    if (_name != value) {
      _name = value;
      notifyListeners();
    }
  }

  String get icon => _icon!;
  String? _icon;
  set icon(String value) {
    if (_icon != value) {
      _icon = value;
      notifyListeners();
    }
  }

  String get className => _className!;
  String? _className;
  set className(String value) {
    if (_className != value) {
      _className = value;
      notifyListeners();
    }
  }

  String get nameOrClassName => name.isEmpty ? className : name;

  String get description => _description!;
  String? _description;
  set description(String value) {
    if (_description != value) {
      _description = value;
      notifyListeners();
    }
  }

  Iterable<Feature> get features => _features;
  final List<Feature> _features = <Feature>[];
  ContainerFeature? _container;

  List<Feature> updateFeatures(List<Feature> newFeatures) {
    final List<Feature> oldFeatures = <Feature>[];
    ContainerFeature? newContainer;
    int index = 0;
    for (index = 0; index < newFeatures.length; index += 1) {
      final Feature newFeature = newFeatures[index];
      Feature? oldFeature;
      if (index < _features.length) {
        oldFeature = _features[index];
        if (_container == oldFeature)
          _container = null;
        if (oldFeature.runtimeType != newFeature.runtimeType) {
          oldFeatures.add(oldFeature);
          oldFeature = null;
        }
        _features[index] = newFeature;
      } else {
        oldFeature = null;
        _features.add(newFeature);
      }
      newFeature.init(oldFeature);
      if (oldFeature != null)
        oldFeatures.add(oldFeature);
      newFeature.attach(this);
      if (newFeature is ContainerFeature) {
        assert(newContainer == null);
        newContainer = newFeature;
      }
    }
    for (index = newFeatures.length; index < _features.length; index += 1) {
      final Feature oldFeature = _features[index];
      if (_container == oldFeature)
        _container = null;
      oldFeatures.add(oldFeature);
    }
    _features.length = newFeatures.length;
    assert(_container == null);
    _container = newContainer;
    notifyListeners();
    return oldFeatures;
  }

  @override
  double get diameter {
    assert(_size != null, 'unknown size for asset $id');
    return _size!;
  }

  @override
  double get maxRenderDiameter {
    if (parent is OrbitFeature) { // TODO: this is a hack
      return worldParent!.maxRenderDiameter;
    }
    return super.maxRenderDiameter; // returns this.diameter
  }

  @override
  Offset findLocationForChild(WorldNode child, List<VoidCallback> callbacks) {
    assert(child is AssetNode);
    if (_container != null) {
      return _container!.findLocationForChild(child as AssetNode, callbacks);
    }
    throw UnimplementedError();
  }

  void walk(WalkCallback callback) {
    if (callback(this)) {
      _container?.walk(callback);
    }
  }

  HudHandle? _hud;

  void showInspector(BuildContext context, { bool toggle = true }) {
    if (_container is OrbitFeature) {
      // TODO: this feels like a hack
      (_container! as OrbitFeature).originChild.showInspector(context, toggle: toggle);
      return;
    }
    if (_hud != null) {
      if (toggle) {
        _hud!.cancel();
        _hud = null;
      } else {
        _hud!.bringToFront();
      }
    } else {
      _hud = HudProvider.add(
        context,
        const Size(480.0, 512.0),
        AssetInspector(
          SystemNode.of(this),
          DynastyManager.of(context),
          this,
          onClose: () { _hud = null; },
        ),
      );
    }
  }

  @override
  void dispose() {
    _hud?.cancel();
    for (Feature feature in _features) {
      feature.detach();
    }
    super.dispose();
  }

  @override
  Widget buildRenderer(BuildContext context, [ Widget? nil ]){
    // TODO: compute actualDiameter here, and short-circuit if it's too small
    List<Widget>? backgrounds;
    List<Widget>? overlays;
    List<Widget>? boxes;
    BoxShape? shape;
    for (Feature feature in _features) {
      switch (feature.rendererType) {
        case RendererType.none:
          ;
        case RendererType.ui:
          boxes ??= <Widget>[];
          boxes.add(feature.buildRenderer(context));
        case RendererType.overlay:
          overlays ??= <Widget>[];
          overlays.add(feature.buildRenderer(context));
        case RendererType.circle:
          backgrounds ??= <Widget>[];
          backgrounds.add(feature.buildRenderer(context));
          shape ??= BoxShape.circle; // does not override RendererType.square
        case RendererType.square:
          backgrounds ??= <Widget>[];
          backgrounds.add(feature.buildRenderer(context));
          shape = BoxShape.rectangle; // does override RendererType.circle
        case RendererType.space:
          backgrounds ??= <Widget>[];
          backgrounds.add(feature.buildRenderer(context));
      }
    }
    if (isVirtual) {
      assert((parent is Feature) && (parent! as Feature).debugExpectVirtualChildren);
      // virtual assets only have RendererType.ui renderers
      assert(overlays == null);
      assert(backgrounds == null);
      final Widget result;
      if (boxes != null) {
        if (boxes.length > 1) {
          result = ListBody(children: boxes);
        } else {
          assert(boxes.length == 1);
          result = boxes.single;
        }
      } else {
        result = const Placeholder();
      }
      return result;
    }
    assert((parent is! Feature) || (!(parent! as Feature).debugExpectVirtualChildren));
    // non-virtual assets assume a RenderWorld world
    backgrounds ??= <Widget>[];
    if (backgrounds.isEmpty) {
      shape = BoxShape.rectangle;
      backgrounds.insert(0, WorldIcon(
        node: this,
        diameter: diameter,
        maxDiameter: worldParent!.maxRenderDiameter,
        icon: icon,
        ghost: isGhost,
      ));
    }
    if (boxes != null) {
      backgrounds.add(WorldFields(
        node: this,
        icon: icon,
        maxDiameter: worldParent!.maxRenderDiameter,
        diameter: diameter,
        children: boxes,
     ));
    }
    if (shape != null) {
      backgrounds.insert(0, WorldTapDetector(
        node: this,
        diameter: diameter,
        maxDiameter: worldParent!.maxRenderDiameter,
        shape: shape,
        onTap: showInspector,
      ));
    }
    if (overlays != null) {
      backgrounds.addAll(overlays);
    }
    if (backgrounds.length > 1) {
      return WorldStack(
        node: this,
        maxDiameter: worldParent!.maxRenderDiameter,
        diameter: diameter,
        children: backgrounds,
      );
    }
    return backgrounds.single;
  }

  Widget? buildHeader(BuildContext context) {
    for (Feature feature in _features) {
      final Widget? result = feature.buildHeader(context);
      if (result != null)
        return result;
    }
    return null;
  }

  Widget asIcon(BuildContext context, { required double size, IconsManager? icons, String? tooltip }) {
    return IconsManager.icon(context, icon, size: size, icons: icons, tooltip: tooltip);
  }

  InlineSpan describe(BuildContext context, IconsManager icons, { required double iconSize }) {
    if (_container is OrbitFeature) {
      // TODO: this feels like a hack
      return (_container! as OrbitFeature).originChild.describe(context, icons, iconSize: iconSize);
    }
    final Widget icon = asIcon(context, size: iconSize, icons: icons);
    return TextSpan(
      children: <InlineSpan>[
        WidgetSpan(child: icon),
        TextSpan(text: name.isNotEmpty ? ' $name' : ' $className'),
        WidgetSpan(
          child: Padding(
            padding: const EdgeInsets.only(left: 4.0, bottom: 1.0),
            child: InkResponse(
              radius: iconSize,
              onTap: () {
                ZoomProvider.centerOn(context, this);
              },
              child: Icon(
                Icons.location_searching,
                size: iconSize,
              ),
            ),
          ),
        ),
        WidgetSpan(
          child: Padding(
            padding: const EdgeInsets.only(left: 4.0, bottom: 1.0),
            child: InkResponse(
              radius: iconSize,
              onTap: () {
                showInspector(context, toggle: false);
              },
              child: Icon(
                Icons.assignment_outlined,
                size: iconSize,
              ),
            ),
          ),
        ),
        if (name.isNotEmpty)
          TextSpan(text: ' ($className)'),
      ],
    );
  }

  @override
  String toString() => '<$_className:$name#${hashCode.toRadixString(16)}>';
}

class AssetInspector extends StatefulWidget {
  const AssetInspector(this.system, this.dynastyManager, this.node, { super.key, this.onClose });

  final SystemNode system;
  final DynastyManager dynastyManager;
  final AssetNode node;
  final VoidCallback? onClose;

  @override
  State<AssetInspector> createState() => _AssetInspectorState();
}

class _AssetInspectorState extends State<AssetInspector> {
  @override
  void dispose() {
    _unsubscribe();
    super.dispose();
  }

  void _update() {
    setState(() { });
  }

  List<Listenable> _listenables = <Listenable>[];

  void _resubscribe(List<Listenable> newList) {
    if (!listEquals(newList, _listenables)) {
      _unsubscribe();
      _listenables = newList;
      for (final Listenable listenable in _listenables) {
        listenable.addListener(_update);
      }
    }
  }

  void _unsubscribe() {
    for (final Listenable listenable in _listenables) {
      listenable.removeListener(_update);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AssetNode node = widget.node;
    final List<Listenable> dependencies = <Listenable>[];
    dependencies.add(node);
    final List<Widget> details = <Widget>[
      if (node.name.isNotEmpty) // we'll put the asset name in the header
        Padding(
          padding: dialogPadding,
          child: Text(node.className, style: bold),
        ),
      Padding(
        padding: dialogPadding,
        child: Text(node.description, softWrap: true, overflow: TextOverflow.visible),
      ),
    ];
    if (node.ownerDynasty == null) {
      assert(!node.isGhost);
      details.add(
        const Padding(
          padding: dialogPadding,
          child: Text('No dynasty controls this.'),
        ),
      );
    } else if (node.ownerDynasty == widget.dynastyManager.currentDynasty) {
      if (node.isGhost) {
        details.add(
          const Padding(
            padding: dialogPadding,
            child: Text('We have planned to build this.'),
          ),
        );
      } else {
        details.add(
          const Padding(
            padding: dialogPadding,
            child: Text('We control this.'),
          ),
        );
      }
    } else {
      assert(!node.isGhost);
      details.add(
        const Padding(
          padding: dialogPadding,
          child: Text('Another dynasty controls this.'),
        ),
      );
    }
    details.add(
      Padding(
        padding: dialogPadding,
        child: Row(
          children: <Widget>[
            Expanded(child: Text('Size: ${prettyLength(node.size)}')),
            Expanded(
              child: node.massFlowRate != 0.0
                ? ValueListenableBuilder<double>(
                    valueListenable: widget.system.spaceTime.asListenable(),
                    builder: (BuildContext context, double time, Widget? child) {
                      return Text('Mass: ${prettyMass(node.mass + node.massFlowRate * (time - node.timeOrigin))}');
                    },
                  )
                : Text(node.mass == 0.0 ? node.isGhost ? 'Not yet built' : 'Massless' : 'Mass: ${prettyMass(node.mass)}'),
            ),
          ],
        ),
      ),
    );
    final WorldNode? parentAsset = node.worldParent;
    if (parentAsset != null)
      dependencies.add(parentAsset);
    if (parentAsset is AssetNode) {
      final double fontSize = DefaultTextStyle.of(context).style.fontSize!;
      final IconsManager icons = IconsManagerProvider.of(context);
      // TODO: all this stuff with orbits is hacky, why can't the orbit feature do it itself
      if (node.parent is OrbitFeature) {
        final AssetNode grandparentAsset = parentAsset.worldParent! as AssetNode; // orbit can't be root of system
        dependencies.add(grandparentAsset);
        if (parentAsset.parent is OrbitFeature) {
          final OrbitFeature orbit = parentAsset.parent! as OrbitFeature;
          final AssetNode orbittingParent = orbit.originChild;
          dependencies.add(orbittingParent);
          final double distance = orbit.findLocationForChild(parentAsset, const <VoidCallback>[]).distance - orbittingParent.diameter / 2.0;
          details.add(
            Padding(
              padding: dialogPadding,
              child: Text.rich(
                TextSpan(
                  text: 'Location: ${distance > 0 ? "Orbitting ${prettyLength(distance)} above" : "Flying over"} ',
                  children: <InlineSpan>[
                    orbittingParent.describe(context, icons, iconSize: fontSize),
                  ],
                ),
              ),
            ),
          );
        } else {
          details.add(
            Padding(
              padding: dialogPadding,
              child: Text.rich(
                TextSpan(
                  text: 'Location: In ',
                  children: <InlineSpan>[
                    grandparentAsset.describe(context, icons, iconSize: fontSize),
                  ],
                ),
              ),
            ),
          );
        }
      } else {
        details.add(
          Padding(
            padding: dialogPadding,
            child: Text.rich(
              TextSpan(
                text: 'Location: ',
                children: <InlineSpan>[
                  parentAsset.describe(context, icons, iconSize: fontSize),
                ],
              ),
            ),
          ),
        );
      }
    }
    for (Feature feature in node._features) {
      final Widget? section = feature.buildDialog(context);
      if (section != null) {
        details.add(Padding(
          key: ObjectKey(feature),
          padding: sectionPadding,
          child: section,
        ));
      }
    }
    if (node.parent is OrbitFeature) {
      // TODO: this is more of the same hack as above
      assert(dependencies.contains(parentAsset));
      final Widget section = (node.parent! as OrbitFeature).buildDialog(context);
      details.add(Padding(
        key: ObjectKey(node.parent),
        padding: sectionPadding,
        child: section,
      ));
    }
    details.add(const SizedBox(height: 12.0));
    _resubscribe(dependencies);
    return HudDialog(
      onClose: widget.onClose,
      heading: Builder(
        builder: (BuildContext context) {
          final double iconSize = DefaultTextStyle.of(context).style.fontSize!;
          return Row(
            children: <Widget>[
              node.asIcon(context, size: iconSize),
              const SizedBox(width: 12.0),
              Expanded(child: Text(node.nameOrClassName)),
            ],
          );
        },
      ),
      buttons: <Widget>[
        IconButton(
          icon: const Icon(Icons.location_searching),
          onPressed: () {
            ZoomProvider.centerOn(context, node);
          },
        ),
      ],
      child: DefaultTextStyle.merge(
        softWrap: false,
        overflow: TextOverflow.ellipsis,
        child: SingleChildScrollView(
          child: ListBody(
            children: details,
          ),
        ),
      ),
    );
  }
}
