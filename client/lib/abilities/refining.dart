import 'package:flutter/material.dart';

import '../assets.dart';
import '../icons.dart';
import '../nodes/system.dart';
import '../prettifiers.dart';
import '../widgets.dart';

// TODO: share code with nearly-identical MiningFeature

class RefiningFeature extends AbilityFeature {
  RefiningFeature({
    required this.material,
    required this.currentRate,
    required this.maxRate,
    required this.enabled,
    required this.active,
    required this.sourceLimiting,
    required this.targetLimiting,
  });

  final int material;
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

  late final _RefiningHudState _state = _RefiningHudState(this);

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
      return enabled ? const Text('Disabling refining...') :
                       const Text('Enabling refining...');
    }
    if (!enabled) {
      return const Text('Refining disabled.');
    }
    if (!active) {
      return const Text('Nothing to refine.');
    }
    if (sourceLimiting) {
      if (currentRate > 0.0) {
        return Text('Shortage of ore to refine. Refining throttled to ${prettyMass(currentRate * 1000.0 * 60.0 * 60.0)} per hour (${prettyFraction(currentRate / maxRate)})');
      }
      return const Text('Shortage of ore to refine.\nAdd more holes to restart refining.');
    }
    if (targetLimiting) {
      if (currentRate > 0.0) {
        return Text('Capacity full. Refining throttled to ${prettyMass(currentRate * 1000.0 * 60.0 * 60.0)} per hour (${prettyFraction(currentRate / maxRate)})');
      }
      return const Text('Capacity full.\nAdd more piles to restart refining.');
    }
    assert(currentRate == maxRate);
    return Text('Refining at ${prettyMass(currentRate * 1000.0 * 60.0 * 60.0)} per hour'); // convert from kg/ms to kg/h
  }

  @override
  Widget buildDialog(BuildContext context) {
    final double fontSize = DefaultTextStyle.of(context).style.fontSize!;
    final IconsManager icons = IconsManagerProvider.of(context);
    final SystemNode system = SystemNode.of(parent);
    return ListenableBuilder(
      listenable: _state,
      builder: (BuildContext context, Widget? child) => ListBody(
        children: <Widget>[
          Text.rich(
            TextSpan(
              text: 'Refining',
              style: bold,
              children: <InlineSpan>[
                if (material != 0)
                  const TextSpan(text: ' '),
                if (material != 0)
                  system.material(material).describe(context, icons, iconSize: fontSize),
                const TextSpan(text: ':'),
              ],
            ),
          ),
          Padding(
            padding: featurePadding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('Current refining rate: ${prettyMass(currentRate * 1000.0 * 60.0 * 60.0)} per hour'),
                Text('Maximum refining rate: ${prettyMass(maxRate * 1000.0 * 60.0 * 60.0)} per hour'),
                if (!enabled)
                  const Text('Refining is disabled.')
                else if (!active)
                  const Text('Refining is not possible here.')
                else if (sourceLimiting && currentRate == 0.0)
                  const Text('No ore remains to be refined.')
                else if (sourceLimiting)
                  Text('Limited ore supplies; refining throttled to (${prettyFraction(currentRate / maxRate)}.')
                else if (targetLimiting && currentRate == 0.0)
                  const Text('Refining paused; no storage capacity for refined ore.')
                else if (targetLimiting)
                  Text('Limited storage capacity; refining throttled to (${prettyFraction(currentRate / maxRate)}.')
                else
                  const Text('Refining at full rate.'),
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

class _RefiningHudState extends ChangeNotifier {
  _RefiningHudState(this.feature) : _enabled = feature.enabled;

  final RefiningFeature feature;

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
