import 'package:flutter/material.dart';

import '../assets.dart';
import '../nodes/system.dart';
import '../prettifiers.dart';
import '../widgets.dart';

// TODO: share code with nearly-identical RefiningFeature

class MiningFeature extends AbilityFeature {
  MiningFeature({
    required this.currentRate,
    required this.maxRate,
    required this.enabled,
    required this.active,
    required this.sourceLimiting,
    required this.targetLimiting,
  });

  final double currentRate;
  final double maxRate;
  final bool enabled;
  final bool active;
  final bool sourceLimiting;
  final bool targetLimiting;

  @override
  RendererType get rendererType => RendererType.ui;

  // TODO: we shouldn't replace the entire node, losing state, when the server updates us
  // because that way, we lose the "updating" boolean state.
  // Instead we should have some long-lived state and we should clear the "updating" boolean
  // either when the state is obsolete (node is gone entirely), or when the `play()` method's
  // returned Future completes.

  late final _MinerHudState _state = _MinerHudState(this);

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
              shape: BeveledRectangleBorder(
                side: BorderSide(),
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
                      child: _buildHudStatus(context),
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

  Widget _buildHudStatus(BuildContext context) {
    if (_state.updating) {
      return enabled ? const Text('Disabling mining...') :
                       const Text('Enabling mining...');
    }
    if (!enabled) {
      return const Text('Mining disabled.');
    }
    if (!active) {
      return const Text('No region to mine.');
    }
    if (sourceLimiting) {
      assert(currentRate == 0.0);
      return const Text('Region no longer has anything to mine.');
    }
    if (targetLimiting) {
      if (currentRate > 0.0) {
        return const Text('Capacity full.\nRefining waste is being returned to the ground.');
      }
      return const Text('Capacity full.\nAdd more piles to restart mining.');
    }
    assert(currentRate == maxRate);
    return Text('Mining at ${prettyMass(currentRate * 1000.0 * 60.0 * 60.0)} per hour.'); // convert from kg/ms to kg/h
  }

  @override
  Widget buildDialog(BuildContext context) {
    return ListenableBuilder(
      listenable: _state,
      builder: (BuildContext context, Widget? child) => ListBody(
        children: <Widget>[
          const Text('Mining:', style: bold),
          Padding(
            padding: featurePadding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('Current mining rate: ${prettyMass(currentRate * 1000.0 * 60.0 * 60.0)} per hour'),
                Text('Maximum mining rate: ${prettyMass(maxRate * 1000.0 * 60.0 * 60.0)} per hour'),
                if (!enabled)
                  const Text('Mining is disabled.')
                else if (!active)
                  const Text('No region to mine.')
                else if (sourceLimiting)
                  const Text('Region no longer has anything to mine.')
                else if (!targetLimiting)
                  const Text('Mining at full rate.')
                else if (currentRate == 0.0)
                  const Text('Capacity full. Add more piles to restart mining.')
                else
                  const Text('Capacity full. Refining waste is being returned to the ground.'),
                GestureDetector(
                  onTap: _state.toggleEnabledSwitch,
                  child: Row(
                    children: <Widget>[
                      _state.buildEnabledSwitch(context),
                      const SizedBox(width: 8.0),
                      Text(enabled ? 'Enabled' : 'Enable (currently disabled)'),
                      const SizedBox(width: 8.0),
                      if (_state.updating)
                        const SizedBox(height: 10.0, width: 10.0, child: CircularProgressIndicator()), // TODO: change Switch to allow any widget in the thumb and put this there
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MinerHudState extends ChangeNotifier {
  _MinerHudState(this.feature) : _enabled = feature.enabled;

  final MiningFeature feature;

  bool get enabled => _enabled;
  bool _enabled;
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

  VoidCallback? get toggleEnabledSwitch => updating ? null : _toggleEnabledSwitch;

  void _toggleEnabledSwitch() {
    final SystemNode system = SystemNode.of(feature.parent);
    updating = true; // TODO: this currently gets reset when the server sends an update and we completely destroy the entire feature
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
