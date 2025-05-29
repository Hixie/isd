import 'package:flutter/material.dart';

import '../assets.dart';
import '../widgets.dart';

class MessageBoardFeature extends ContainerFeature {
  MessageBoardFeature(this.children);

  // consider this read-only; the entire MessageBoardFeature gets replaced when the child list changes
  final List<AssetNode> children;

  @override
  Offset findLocationForChild(AssetNode child, List<VoidCallback> callbacks) {
    // final MessageBoardParameters childData = children[child]!;
    return Offset.zero;
  }

  @override
  void attach(AssetNode parent) {
    super.attach(parent);
    for (AssetNode child in children) {
      child.attach(parent);
    }
  }

  @override
  void detach() {
    for (AssetNode child in children) {
      if (child.parent == parent) {
        child.detach();
        // if its parent is not the same as our parent,
        // then maybe it was already added to some other container
      }
    }
    super.detach();
  }

  @override
  void walk(WalkCallback callback) {
    for (AssetNode child in children) {
      assert(child.parent == parent);
      child.walk(callback);
    }
  }

  @override
  RendererType get rendererType => RendererType.box;

  @override
  Widget buildRenderer(BuildContext context) {
    return StateManagerBuilder<MessagesState>(
      creator: MessagesState.new,
      disposer: (MessagesState state) => state.dispose(),
      builder: (BuildContext context, MessagesState state) {
        if (state.selectedMessage == null) {
          return ListView.builder(
            itemCount: children.length,
            itemBuilder: (BuildContext context, int index) {
              return MessageBoardMode(
                showBody: false,
                onSelect: () {
                  state.selectedMessage = index;
                },
                child: children[index].build(context),
              );
            },
          );
        }
        final int index = state.selectedMessage!;
        return MessageBoardMode(
          onUp: () {
            state.selectedMessage = null;
          },
          onLeft: index <= 0 ? null : () {
            state.selectedMessage = index - 1;
          },
          onRight: index >= children.length - 1 ? null : () {
            state.selectedMessage = index + 1;
          },
          child: children[index].build(context),
        );
      },
    );
  }
}

class MessageBoardMode extends InheritedWidget {
  const MessageBoardMode({
    super.key,
    this.showBody = true,
    this.onSelect,
    this.onUp,
    this.onLeft,
    this.onRight,
    required super.child,
  });

  final bool showBody;
  final VoidCallback? onSelect;
  final VoidCallback? onUp;
  final VoidCallback? onLeft;
  final VoidCallback? onRight;

  static MessageBoardMode of(BuildContext context) {
    final MessageBoardMode? provider = context.dependOnInheritedWidgetOfExactType<MessageBoardMode>();
    assert(provider != null, 'No MessageBoardMode found in context');
    return provider!;
  }

  @override
  bool updateShouldNotify(MessageBoardMode oldWidget) => oldWidget.showBody != showBody;
}

class MessagesState extends ChangeNotifier {
  int? get selectedMessage => _selectedMessage;
  int? _selectedMessage;
  set selectedMessage(int? value) {
    _selectedMessage = value;
    notifyListeners();
  }
}
