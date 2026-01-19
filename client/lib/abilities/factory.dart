import 'dart:async';

import 'package:flutter/material.dart';

import '../assets.dart';
import '../icons.dart';
import '../nodes/system.dart';
import '../prettifiers.dart';
import '../types.dart';
import '../widgets.dart';

class FactoryFeature extends AbilityFeature {
  FactoryFeature({
    required this.inputs,
    required this.outputs,
    required this.maxRate,
    required this.configuredRate,
    required this.currentRate,
    required this.disabledReason,
  });

  final Map<int, int> inputs;
  final Map<int, int> outputs;
  final double maxRate;
  final double configuredRate;
  final double currentRate;
  final DisabledReason disabledReason;

  @override
  RendererType get rendererType => RendererType.none;

  @override
  void init(Feature? oldFeature) {
    super.init(oldFeature);
    if (oldFeature == null) {
      _state = _FactoryHudState(this);
    } else {
      _state = (oldFeature as FactoryFeature)._state;
      _state.update(this);
    }
  }

  late _FactoryHudState _state;

  @override
  String get status {
    if (!disabledReason.fullyActive) {
      return disabledReason.describe(currentRate);
    }
    if (currentRate == maxRate)
      return 'Working at maximum rate.';
    if (currentRate == configuredRate)
      return 'Working at configured rate.';
    assert(currentRate < configuredRate);
    assert(false); // should never get here if there's no disabled reason
    return 'Working at reduced rate.';
  }

  @override
  Widget buildDialog(BuildContext context) {
    final double fontSize = DefaultTextStyle.of(context).style.fontSize!;
    final IconsManager icons = IconsManagerProvider.of(context);
    final SystemNode system = SystemNode.of(parent);
    return ListBody(
      children: <Widget>[
        const Text('Factory', style: bold),
        Padding(
          padding: featurePadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('Status: $status'),
              Text('Current rate: ${prettyRate(currentRate, const Iterations())}.'),
              Text('Input${ inputs.entries.length == 1 ? "" : "s" }:'),
              ...inputs.entries.map((MapEntry<int, int> entry) => Text.rich(
                  TextSpan(
                    text: '  ',
                    children: <InlineSpan>[
                      system.material(entry.key).describeQuantity(context, icons, entry.value, iconSize: fontSize),
                    ],
                  )
              )),
              Text('Output${ outputs.entries.length == 1 ? "" : "s" }:'),
              ...outputs.entries.map((MapEntry<int, int> entry) => Text.rich(
                  TextSpan(
                    text: '  ',
                    children: <InlineSpan>[
                      system.material(entry.key).describeQuantity(context, icons, entry.value, iconSize: fontSize),
                    ],
                  )
              )),
              Text('Maximum rate: ${prettyRate(maxRate, const Iterations())}.'),
              Text('Configured rate: ${prettyRate(configuredRate, const Iterations())}.'),
              ListenableBuilder(
                listenable: _state,
                builder: (BuildContext context, Widget? child) {
                  return Slider(
                    onChanged: (double newRate) {
                      _state.setRate(newRate);
                    },
                    onChangeEnd: (double newRate) {
                      _state.sendRate();
                    },
                    value: _state._selectedRate,
                    max: maxRate,
                  );
                }
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _FactoryHudState extends ChangeNotifier {
  _FactoryHudState(FactoryFeature feature) :
    _feature = feature,
    _lastServerRate = feature.configuredRate,
    _selectedRate = feature.configuredRate,
    _lastSentRate = feature.configuredRate;

  FactoryFeature _feature;
  
  double get selectedRate => _selectedRate;
  double _selectedRate;
  double _lastServerRate;
  double _lastSentRate;

  int _pending = 0;
  
  void update(FactoryFeature feature) {
    _feature = feature;
    _lastServerRate = feature.configuredRate;
    if (_pending == 0) {
      _lastSentRate = _lastServerRate;
      _selectedRate = _lastServerRate;
      notifyListeners();
    }
  }

  Timer? _sendValueTimer;
  
  void setRate(double newRate) {
    _selectedRate = newRate;
    notifyListeners();
    _sendValueTimer?.cancel();
    _sendValueTimer = null;
    _sendValueTimer = Timer(const Duration(milliseconds: 500), sendRate);
  }
  
  Future<void> sendRate() async {
    _sendValueTimer?.cancel();
    _sendValueTimer = null;
    if (_lastSentRate != _selectedRate) {
      _pending += 1;
      _lastSentRate = _selectedRate;
      await SystemNode.of(_feature.parent).play(<Object>[_feature.parent.id, 'set-rate', _selectedRate]);
      _pending -= 1;
    }
  }
}
