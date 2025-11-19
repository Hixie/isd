import 'package:flutter/material.dart';

import '../assets.dart';
import '../prettifiers.dart';
import '../widgets.dart';

class StaffingFeature extends AbilityFeature {
  StaffingFeature({
    required this.jobs,
    required this.workers,
  });

  final int jobs;
  final int workers;

  @override
  RendererType get rendererType => RendererType.none;

  @override
  Widget buildDialog(BuildContext context) {
    return ListBody(
      children: <Widget>[
        const Text('Workers', style: bold),
        Padding(
          padding: featurePadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (workers == 0 && jobs > 0)
                Text('Workers: none for the ${prettyQuantity(jobs, zero: "zero", singular: " job", plural: " jobs")}')
              else
              if (jobs > 0)
                Text('Workers: ${prettyQuantity(workers, zero: "none", singular: " worker", plural: " workers")} out of ${prettyQuantity(jobs, zero: "zero", singular: " job", plural: " jobs")}')
              else
                Text('Workers: ${prettyQuantity(workers, zero: "none", singular: " worker", plural: " workers")}'),
            ],
          ),
        ),
      ],
    );
  }
}
