import 'package:flutter/material.dart';

import '../assets.dart';
import '../nodes/system.dart';
import '../widgets.dart';

class OnOffFeature extends AbilityFeature {
  OnOffFeature({
    required this.enabled,
  });

  final bool enabled;

  @override
  RendererType get rendererType => RendererType.ui;

  @override
  void init(Feature? oldFeature) {
    super.init(oldFeature);
    if (oldFeature == null) {
      _state = _OnOffHudState(this);
    } else {
      _state = (oldFeature as OnOffFeature)._state;
      _state.update(this);
    }
  }

  late _OnOffHudState _state;

  @override
  Widget buildRenderer(BuildContext context) {
    return ListenableBuilder(
      listenable: _state,
      builder: (BuildContext context, Widget? child) => Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 100.0),
          child: DecoratedBox(
            decoration: const ShapeDecoration(
              color: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(20.0)),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 20.0),
                    child: FittedBox(
                      alignment: Alignment.centerLeft,
                      child: Text(status),
                    ),
                  ),
                ),
                FittedBox(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 8.0),
                    child: _state.buildEnabledSwitch(context),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  String get status {
    for (Feature feature in parent.features) {
      if (feature == this)
        continue;
      final String? result = feature.status;
      if (result != null)
        return result;
    }
    if (enabled) {
      return 'Enabled.';
    }
    return 'Disabled.';
  }

  @override
  Widget buildDialog(BuildContext context) {
    return ListenableBuilder(
      listenable: _state,
      builder: (BuildContext context, Widget? child) => ListBody(
        children: <Widget>[
          const Text('Control', style: bold),
          Padding(
            padding: featurePadding,
            child: GestureDetector(
              onTap: _state.toggleEnabledSwitch,
              child: Row(
                children: <Widget>[
                  _state.buildEnabledSwitch(context),
                  const SizedBox(width: 8.0),
                  Text(enabled ? 'Enabled.' : 'Enable (currently disabled).'),
                  const SizedBox(width: 8.0),
                  if (_state.updating)
                    const SizedBox(height: 10.0, width: 10.0, child: CircularProgressIndicator()), // TODO: change Switch to allow any widget in the thumb and put this there
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OnOffHudState extends ChangeNotifier {
  _OnOffHudState(OnOffFeature feature) : _feature = feature, _enabled = feature.enabled;

  OnOffFeature get feature => _feature;
  OnOffFeature _feature;
  set feature(OnOffFeature value) {
    if (_feature != value) {
      _feature = value;
      notifyListeners();
    }
  }

  bool get enabled => _enabled;
  bool _enabled = false;
  set enabled(bool value) {
    if (_enabled != value) {
      _enabled = value;
      notifyListeners();
    }
  }

  bool get updating => _updating;
  bool _updating = false;
  set updating(bool value) {
    if (_updating != value) {
      _updating = value;
      notifyListeners();
    }
  }

  void update(OnOffFeature feature) {
    _feature = feature;
    enabled = feature.enabled;
    updating = false; // TODO: technically we should way for the system.play message to return
  }

  VoidCallback? get toggleEnabledSwitch => updating ? null : _toggleEnabledSwitch;

  void _toggleEnabledSwitch() {
    final SystemNode system = SystemNode.of(feature);
    updating = true;
    enabled = !enabled;
    if (enabled) {
      system.play(<Object>[feature.parent.id, 'enable']);
    } else {
      system.play(<Object>[feature.parent.id, 'disable']);
    }
  }

  Widget buildEnabledSwitch(BuildContext context) {
    return Switch(
      value: enabled,
      onChanged: updating ? null : (bool? value) {
        assert(value == !enabled);
        _toggleEnabledSwitch();
      },
    );
  }
}
