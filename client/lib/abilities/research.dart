import 'package:flutter/material.dart';

import '../assets.dart';
import '../hud.dart';
import '../nodes/system.dart';
import '../types.dart';
import '../widgets.dart';

class ResearchFeature extends AbilityFeature {
  ResearchFeature({
    required this.disabledReason,
    required this.topics,
    required this.current,
    required this.difficulty,
  });

  final DisabledReason disabledReason;
  final List<String> topics;
  final String current;
  final int difficulty;

  ValueNotifier<List<String>>? _topics;
  
  @override
  void init(Feature? oldFeature) {
    super.init(oldFeature);
    if (oldFeature == null) {
      _topics = ValueNotifier<List<String>>(topics);
    } else {
      _topics = (oldFeature as ResearchFeature)._topics;
      _topics!.value = topics;
    }
  }

  @override
  String get status {
    if (!disabledReason.fullyActive)
      return disabledReason.describe(null);
    return 'Ready';
  }

  @override
  RendererType get rendererType => RendererType.ui;

  @override
  Widget buildRenderer(BuildContext context) {
    final DefaultTextStyle parentTextStyles = DefaultTextStyle.of(context);
    final SystemNode system = SystemNode.of(parent);
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: const Color(0x10000000),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20.0),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          children: <Widget>[
            current.isEmpty ? const Text('No research topic selected.', style: bold, textAlign: TextAlign.center)
                            : const Text('Current research topic:', style: bold, textAlign: TextAlign.center),
            Expanded(
              child: DefaultTextStyle(
                // all these shennanigans are to reset maxLines to null
                style: parentTextStyles.style,
                textWidthBasis: parentTextStyles.textWidthBasis,
                textHeightBehavior: parentTextStyles.textHeightBehavior,
                child: Center(
                  child: Text(
                    current,
                    textAlign: TextAlign.center,
                    softWrap: true,
                    // overflow: TextOverflow.ellipsis, // TODO: figure out why this prevents it from wrapping at all, even when there's vertical room.
                  ),
                ),
              ),
            ),
            switch (difficulty) {
              0 => const Text('No progress is being made.', style: red),
              1 => const Text('Progress is slow.'),
              2 => const Text('Researching in progress!'),
              _ => throw const FormatException('Unknown difficulty!'),
            },
            Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: _ResearchState.build(context, system, parent, _topics!),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget buildDialog(BuildContext context) {
    final SystemNode system = SystemNode.of(parent);
    return ListBody(
      children: <Widget>[
        const Text('Research', style: bold),
        Padding(
          padding: featurePadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('Status: $status'),
              current.isEmpty
                ? const Text('No research topic selected.', style: italic)
                : Text.rich(
                    softWrap: true,
                    TextSpan(
                      children: <InlineSpan>[
                        const TextSpan(text: 'Current research focus: ', style: italic),
                        TextSpan(text: current),
                      ],
                    ),
                  ),
              SizedBox(height: featurePadding.top),
              _ResearchState.build(context, system, parent, _topics!),
            ],
          ),
        ),
      ],
    );
  }
}

class _ResearchState extends ChangeNotifier {
  HudHandle? _dialog;

  bool get active => _dialog != null;

  void activate(BuildContext context, Size size, Widget widget) {
    _dialog = HudProvider.add(context, size, widget);
    notifyListeners();
  }

  void closed() {
    _dialog = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _dialog?.cancel();
    super.dispose();
  }

  static Widget build(BuildContext context, SystemNode system, AssetNode node, ValueNotifier<List<String>> topics) {
    return StateManagerBuilder<_ResearchState>(
      creator: _ResearchState.new,
      disposer: (_ResearchState state) { state.dispose(); },
      builder: (BuildContext context, _ResearchState state) => OutlinedButton(
        onPressed: state.active ? null : () {
          assert(!state.active);
          state.activate(context, const Size(400.0, 300.0), HudDialog(
            heading: const Text('Select Research Topic'),
            child: ResearchTopicUi(
              system: system,
              node: node,
              topics: topics,
              onClose: state.closed,
            ),
            onClose: state.closed,
          ));
        },
        child: const Text('Change Topic'),
      ),
    );
  }
}

class ResearchTopicUi extends StatelessWidget {
  const ResearchTopicUi({
    super.key,
    required this.system,
    required this.node,
    required this.topics,
    this.onClose,
  }); // TODO: hard-code the key to be on all the arguments

  final SystemNode system;
  final AssetNode node;
  final ValueNotifier<List<String>> topics;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0.0, 0.0, 4.0, 0.0),
      child: ValueListenableBuilder<List<String>>(
        valueListenable: topics,
        builder: (BuildContext context, List<String> topics, Widget? child) => ListView.builder(
          padding: const EdgeInsets.fromLTRB(22.0, 4.0, 20.0, 24.0),
          itemCount: topics.length,
          itemBuilder: (BuildContext context, int index) {
            return TextButton(
              child: Text(topics[index]),
              onPressed: () {
                system.play(<Object>[node.id, 'set-topic', topics[index]]);
                HudHandle.of(context).cancel();
                if (onClose != null)
                  onClose!();
              },
            );
          },
        ),
      ),
    );
  }
}
