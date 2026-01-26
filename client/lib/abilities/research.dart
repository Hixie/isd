import 'dart:async';

import 'package:flutter/material.dart';

import '../assets.dart';
import '../hud.dart';
import '../nodes/system.dart';
import '../stringstream.dart';
import '../types.dart';
import '../widgets.dart';

class ResearchFeature extends AbilityFeature {
  ResearchFeature({
    required this.disabledReason,
    required this.current,
    required this.progress,
  });

  final DisabledReason disabledReason;
  final String current;
  final int progress;

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
            switch (progress) {
              0 => const Text('No progress is being made.'),
              1 => const Text('Progress is slow.'),
              2 => const Text('Researching in progress!'),
              _ => throw const FormatException('Unknown progress!'),
            },
            Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: _ResearchState.build(context, system, this),
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
              const SizedBox(height: 8.0),
              _ResearchState.build(context, system, this),
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

  static Widget build(BuildContext context, SystemNode system, ResearchFeature feature) {
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
              node: feature.parent,
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

class ResearchTopicUi extends StatefulWidget {
  const ResearchTopicUi({
    super.key,
    required this.system,
    required this.node,
    this.onClose,
  }); // TODO: hard-code the key to be on all the arguments

  final SystemNode system;
  final AssetNode node;
  final VoidCallback? onClose;

  @override
  State<ResearchTopicUi> createState() => _ResearchTopicUiState();
}

@immutable
class _Topic {
  const _Topic(this.name, this.label);
  final String name;
  final String label;

  static int alphabeticalSort(_Topic a, _Topic b) {
    return a.label.compareTo(b.label);
  }
}

class _ResearchTopicUiState extends State<ResearchTopicUi> {
  final List<_Topic> _options = <_Topic>[];

  bool _pending = true;
  bool _tired = false;
  Timer? _loadTimer;

  @override
  void initState() {
    super.initState();
    widget.system
      .play(<Object>[widget.node.id, 'get-topics'])
      .then((StreamReader reader) {
        if (mounted) {
          _loadTimer?.cancel();
          setState(() {
            while (!reader.eof) {
              final String name = reader.readString();
              if (reader.readBool())
                _options.add(_Topic(name, name));
            }
            _options.sort(_Topic.alphabeticalSort);
            _options.add(const _Topic('', 'Undirected research'));
            _pending = false;
            _tired = false;
          });
        }
      });
    _loadTimer = Timer(const Duration(milliseconds: 750), _loading);
  }

  void _loading() {
    setState(() {
      _tired = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    Widget body;
    if (_pending) {
      if (_tired) {
        body = const Center(
          child: CircularProgressIndicator(),
        );
      } else {
        body = const SizedBox.shrink();
      }
    } else {
      body = Padding(
        padding: const EdgeInsets.fromLTRB(0.0, 0.0, 4.0, 0.0),
        child: ListView.builder(
          padding: const EdgeInsets.fromLTRB(22.0, 4.0, 20.0, 24.0),
          itemCount: _options.length,
          itemBuilder: (BuildContext context, int index) {
            return TextButton(
              child: Text(_options[index].label),
              onPressed: () {
                widget.system.play(<Object>[widget.node.id, 'set-topic', _options[index].name]);
                HudHandle.of(context).cancel();
                if (widget.onClose != null)
                  widget.onClose!();
              },
            );
          },
        ),
      );
    }
    return AnimatedSwitcher(
      child: body,
      duration: const Duration(milliseconds: 160),
      switchInCurve: Curves.easeInOut,
      switchOutCurve: Curves.easeInOut,
    );
  }
}
