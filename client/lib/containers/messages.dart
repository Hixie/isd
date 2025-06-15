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
    return NoZoom(
      child: StateManagerBuilder<MessagesState>(
        creator: () => MessagesState(children.length),
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
          final AssetNode child = children[index];
          return MessageBoardMode(
            onUp: state.up,
            onLeft: state.left,
            onRight: state.right,
            child: Builder(
              builder: (BuildContext context) => Column(
                children: <Widget>[
                  AppBar(
                    leading: IconButton(
                      icon: const Icon(Icons.arrow_upward),
                      tooltip: 'Go to message list',
                      onPressed: state.up,
                    ),
                    title: child.buildHeader(context),
                    actions: <Widget>[
                      IconButton(
                        icon: const Icon(Icons.arrow_back),
                        tooltip: 'Go to previous message',
                        onPressed: state.left,
                      ),
                      IconButton(
                        icon: const Icon(Icons.arrow_forward),
                        tooltip: 'Go to next message',
                        onPressed: state.right,
                      ),
                    ],
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      child: Card(
                        child: child.buildRenderer(context),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
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

  static MessageBoardMode? of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<MessageBoardMode>();
  }

  @override
  bool updateShouldNotify(MessageBoardMode oldWidget) => oldWidget.showBody != showBody;
}

class MessagesState extends ChangeNotifier {
  MessagesState(this._count);
  
  int get count => _count;
  int _count = 0;
  set count(int value) {
    _count = value;
    if (_selectedMessage != null && _selectedMessage! >= _count) {
      _selectedMessage = null;
      notifyListeners();
    }
  }
  
  int? get selectedMessage => _selectedMessage;
  int? _selectedMessage;
  set selectedMessage(int? value) {
    _selectedMessage = value;
    notifyListeners();
  }

  VoidCallback? get up => selectedMessage == null ? null : () {
    selectedMessage = null;
  };

  VoidCallback? get left => selectedMessage == null || selectedMessage! <= 0 ? null : () {
    selectedMessage = selectedMessage! - 1;
  };
  
  VoidCallback? get right => selectedMessage == null || selectedMessage! >= count - 1 ? null : () {
    selectedMessage = selectedMessage! + 1;
  };
}
