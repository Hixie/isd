import 'package:flutter/material.dart';

import '../assets.dart';
import '../nodes/system.dart';

enum MiningMode {
  mining,
  pilesFull,
  regionEmpty,
  noRegion,
  disabled,
}

class MiningFeature extends AbilityFeature {
  MiningFeature({required this.rate, required this.mode});

  final double rate;
  final MiningMode mode;

  @override
  RendererType get rendererType => RendererType.box;

  // TODO: we shouldn't replace the entire node, losing state, when the server updates us
  // because that way, we lose the "updating" boolean state.
  // Instead we should have some long-lived state and we should clear the "updating" boolean
  // either when the state is obsolete (node is gone entirely), or when the `play()` method's
  // returned Future completes.
  
  @override
  Widget buildRenderer(BuildContext context) {
    bool updating = false;
    bool lastManualStatus = mode != MiningMode.disabled;
    return StatefulBuilder(
      builder: (BuildContext context, StateSetter setState) {
        final Widget status;
        if (updating) {
          switch (mode) {
            case MiningMode.mining:
            case MiningMode.pilesFull:
            case MiningMode.regionEmpty:
            case MiningMode.noRegion:
              status = const Text('Disabling mining...');
            case MiningMode.disabled:
              status = const Text('Enabling mining...');
          }
        } else {
          status = switch (mode) {
            MiningMode.mining =>
              Text('Mining at ${rate * 1000.0 * 60.0 * 60.0} kg/h'), // convert from kg/ms to kg/h // TODO: use prettifier
            MiningMode.pilesFull =>
              const Text('Capacity full.\nAdd more piles to restart mining.'),
            MiningMode.regionEmpty =>
              const Text('Region has no longer materials to mine.'),
            MiningMode.noRegion =>
              const Text('No region to mine.'),
            MiningMode.disabled =>
              const Text('Mining disabled.'),
          };
        }
        return Align(
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
                        child: status,
                      ),
                    ),
                  ),
                  FittedBox(
                    child: Padding(
                      padding: const EdgeInsets.only(left: 8.0),
                      child: Switch(
                        value: lastManualStatus,
                        onChanged: updating ? null : (bool? value) {
                          setState(() {
                            updating = true;
                            if (value == true) {
                              lastManualStatus = true;
                              SystemNode.of(context).play(<Object>[parent.id, 'enable']);
                            } else if (value == false) {
                              lastManualStatus = false;
                              SystemNode.of(context).play(<Object>[parent.id, 'disable']);
                            }
                          });
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
