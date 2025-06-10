import 'package:flutter/material.dart';

import '../assets.dart';
import '../nodes/system.dart';

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
  RendererType get rendererType => RendererType.box;

  // TODO: we shouldn't replace the entire node, losing state, when the server updates us
  // because that way, we lose the "updating" boolean state.
  // Instead we should have some long-lived state and we should clear the "updating" boolean
  // either when the state is obsolete (node is gone entirely), or when the `play()` method's
  // returned Future completes.
  
  @override
  Widget buildRenderer(BuildContext context) {
    bool updating = false;
    bool lastManualStatus = enabled;
    return StatefulBuilder(
      builder: (BuildContext context, StateSetter setState) {
        final Widget status;
        if (updating) {
          status = enabled ? const Text('Disabling refining...') : 
                             const Text('Enabling refining...');
        } else if (!enabled) {
          status = const Text('Refining disabled.');
        } else if (!active) {
          status = const Text('Nothing to refine.');
        } else if (sourceLimiting) {
          if (currentRate > 0.0) {
            status = Text('Shortage of ore to refine. Refining throttled to ${currentRate * 1000.0 * 60.0 * 6.00} kg/h (${100.0 * currentRate / maxRate}%)'); // TODO: use prettifier
          } else {
            status = const Text('Shortage of ore to refine.\nAdd more holes to restart refining.');
          }
        } else if (targetLimiting) {
          if (currentRate > 0.0) {
            status = Text('Capacity full. Refining throttled to ${currentRate * 1000.0 * 60.0 * 6.00} kg/h (${100.0 * currentRate / maxRate}%)'); // TODO: use prettifier
          } else {
            status = const Text('Capacity full.\nAdd more piles to restart refining.');
          }
        } else {
          assert(currentRate == maxRate);
          status = Text('Refining at ${currentRate * 1000.0 * 60.0 * 60.0} kg/h'); // convert from kg/ms to kg/h // TODO: use prettifier
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
