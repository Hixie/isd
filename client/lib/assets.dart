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

abstract class Feature {
  Feature();

  /// Current host for this feature.
  ///
  /// Only valid when attached.
  AssetNode get parent => _parent!;
  AssetNode? _parent;

  void attach(AssetNode parent) {
    assert(_parent == null);
    _parent = parent;
  }

  void detach() {
    assert(_parent != null);
    _parent = null;
  }

  RendererType get rendererType;

  Widget buildRenderer(BuildContext context); // this one is abstract; containers always need to build something

  Widget? buildHeader(BuildContext context) => null;

  Widget? buildDialog(BuildContext context) {
    print('warning: $runtimeType has no buildDialog');
     return null;
  }
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

  @override
  void notifyListeners() {
    //print(StackTrace.current);
    super.notifyListeners();
  }

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

  final Map<Type, Feature> _features = <Type, Feature>{};
  ContainerFeature? _container;

  Type setFeature(Feature feature) {
    final Type type = feature.runtimeType;
    _features[type]?.detach();
    _features[type] = feature;
    feature.attach(this);
    if (feature is ContainerFeature)
      _container = feature;
    notifyListeners();
    return type;
  }

  Set<Type> get featureTypes => _features.keys.toSet();

  void removeFeatures(Set<Type> features) {
    if (features.isNotEmpty) {
      for (Type type in features) {
        if (features.runtimeType == _container.runtimeType) {
          _container = null;
        }
        _features.remove(type);
      }
      notifyListeners();
    }
    assert(() {
      int containerCount = 0;
      for (Feature feature in _features.values) {
        if (feature is ContainerFeature) {
          containerCount += 1;
        }
      }
      assert(containerCount <= 1);
      return true;
    }());
  }

  @override
  double get diameter {
    assert(_size != null, 'unknown size for asset $id');
    return _size!;
  }

  @override
  double get maxRenderDiameter {
    if ((parent is AssetNode) && ((parent! as AssetNode)._container is OrbitFeature)) {
      // TODO: this feels like a hack
      return parent!.maxRenderDiameter;
    }
    return super.maxRenderDiameter; // returns this.diameter
  }

  @override
  Offset findLocationForChild(WorldNode child, List<VoidCallback> callbacks) {
    assert(child.parent == this, '$this was asked for location of child $child but that child\'s parent is ${child.parent}');
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
    super.dispose();
  }

  @override
  Widget buildRenderer(BuildContext context, [ Widget? nil ]){
    // TODO: compute actualDiameter here, and short-circuit if it's too small
    List<Widget>? backgrounds;
    List<Widget>? overlays;
    List<Widget>? boxes;
    BoxShape? shape;
    for (Feature feature in _features.values) {
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
    // non-virtual assets assume a RenderWorld world
    backgrounds ??= <Widget>[];
    if (backgrounds.isEmpty) {
      shape = BoxShape.rectangle;
      backgrounds.insert(0, WorldIcon(
        node: this,
        diameter: diameter,
        maxDiameter: parent!.maxRenderDiameter,
        icon: icon,
        ghost: isGhost,
      ));
    }
    if (boxes != null) {
      backgrounds.add(WorldFields(
        node: this,
        icon: icon,
        maxDiameter: parent!.maxRenderDiameter,
        diameter: diameter,
        children: boxes,
     ));
    }
    if (shape != null) {
      backgrounds.insert(0, WorldTapDetector(
        node: this,
        diameter: diameter,
        maxDiameter: parent!.maxRenderDiameter,
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
        maxDiameter: parent!.maxRenderDiameter,
        diameter: diameter,
        children: backgrounds,
      );
    }
    return backgrounds.single;
  }

  Widget? buildHeader(BuildContext context) {
    for (Feature feature in _features.values) {
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

class AssetInspector extends StatelessWidget {
  const AssetInspector(this.system, this.dynastyManager, this.node, { super.key, this.onClose });

  final SystemNode system;
  final DynastyManager dynastyManager;
  final AssetNode node;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: node,
      builder: (BuildContext context, Widget? child) {
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
        } else if (node.ownerDynasty == dynastyManager.currentDynasty) {
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
                        valueListenable: system.spaceTime.asListenable(),
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
        if (node.parent is AssetNode) {
          final double fontSize = DefaultTextStyle.of(context).style.fontSize!;
          final IconsManager icons = IconsManagerProvider.of(context);
          if ((node.parent! as AssetNode)._container is OrbitFeature) {
            if ((node.parent!.parent is AssetNode) && ((node.parent!.parent! as AssetNode)._container is OrbitFeature)) {
              // TODO: this feels like a hack
              details.add(
                Padding(
                  padding: dialogPadding,
                  child: Text.rich(
                    TextSpan(
                      text: 'Location: Orbitting ',
                      children: <InlineSpan>[
                        ((node.parent!.parent! as AssetNode)._container! as OrbitFeature).originChild.describe(context, icons, iconSize: fontSize),
                        // TODO: add our orbit semi major axis here
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
                        (node.parent!.parent! as AssetNode).describe(context, icons, iconSize: fontSize),
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
                      (node.parent! as AssetNode).describe(context, icons, iconSize: fontSize),
                    ],
                  ),
                ),
              ),
            );
          }
        }
        for (Feature feature in node._features.values) {
          final Widget? section = feature.buildDialog(context);
          if (section != null) {
            details.add(Padding(
              key: ObjectKey(feature),
              padding: sectionPadding,
              child: section,
            ));
          }
        }
        if ((node.parent is AssetNode) && ((node.parent! as AssetNode)._container is OrbitFeature)) {
          // TODO: this feels like a hack
          final Widget? section = (node.parent! as AssetNode)._container!.buildDialog(context);
          if (section != null) {
            details.add(Padding(
              key: ObjectKey(node.parent),
              padding: sectionPadding,
              child: section,
            ));
          }
        }
        details.add(const Padding(padding: dialogPadding));
        return HudDialog(
          onClose: onClose,
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
      },
    );
  }
}
