import 'package:flutter/material.dart';

import '../abilities/knowledge.dart';
import '../abilities/message.dart';
import '../assets.dart';
import '../hud.dart';
import '../prettifiers.dart';
import '../root.dart';
import '../widgets.dart';
import '../world.dart';

typedef MailOpener = void Function(BuildContext context);

class MessageBoardFeature extends ContainerFeature {
  MessageBoardFeature(this.children);

  // consider this read-only; the entire MessageBoardFeature gets replaced when the child list changes
  final List<AssetNode> children;

  MessageBoardState? _state;
  
  @override
  void init(Feature? oldFeature) {
    super.init(oldFeature);
    if (oldFeature == null) {
      _state = MessageBoardState(this);
    } else {
      _state = (oldFeature as MessageBoardFeature)._state;
      _state!.update(this);
    }
  }

  @override
  Offset findLocationForChild(AssetNode child, List<VoidCallback> callbacks) {
    return Offset.zero;
  }

  @override
  void attach(Node parent) {
    super.attach(parent);
    for (AssetNode child in children) {
      child.attach(this);
    }
  }

  @override
  void detach() {
    for (AssetNode child in children) {
      if (child.parent == this)
        child.dispose();
    }
    super.detach();
  }

  @override
  void walk(WalkCallback callback) {
    for (AssetNode child in children) {
      child.walk(callback);
    }
  }

  @override
  RendererType get rendererType => RendererType.ui;

  @override
  bool get debugExpectVirtualChildren => true;

  @override
  Widget buildRenderer(BuildContext context) {
    return ListenableBuilder(
      listenable: _state!,
      builder: (BuildContext context, Widget? child) {
        return FittedBox(
          child: IconButton(
            icon: Badge(
              isLabelVisible: _state!.hasUnread,
              label: Text('${_state!.unreadCount}'),
              child: const Icon(Icons.mail),
            ),
            tooltip: 'Open mailbox',
            onPressed: () => _state!.openMail(context),
          ),
        );
      },
    );
  }

  @override
  Widget buildDialog(BuildContext context) {
    return ListBody(
      children: <Widget>[
        const Text('Mail', style: bold),
        Padding(
          padding: featurePadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (children.isEmpty)
                const Text('You have no messages.', style: italic)
              else
                Text('You have ${_state!.unreadCount} unread messages out of ${_state!.totalCount} total messages.'),
              SizedBox(height: featurePadding.top),
              OutlinedButton(
                child: const Text('Open mailbox'),
                onPressed: () async {
                  _state!.openMail(context);
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MessageBoardStateInheritedWidget extends InheritedWidget {
  const _MessageBoardStateInheritedWidget({
    // super.key,
    required this.state,
    required super.child,
  });

  final MessageBoardState state;

  @override
  bool updateShouldNotify(_MessageBoardStateInheritedWidget oldWidget) => oldWidget.state != state;
}

class MessageBoardState extends ChangeNotifier {
  MessageBoardState(this._board);

  MessageBoardFeature get board => _board;
  MessageBoardFeature _board;

  final Set<AssetNode> _subscribedChildren = <AssetNode>{};
  
  void update(MessageBoardFeature value) { // ignore: use_setters_to_change_properties
    _unsubscribeAllChildren();
    _board = value;
    _dirty = true;
    notifyListeners();
  }

  bool get hasUnread => unreadCount > 0;
  int get unreadCount {
    if (_dirty)
      _updateCaches();
    return _unreadCount;
  }
  int get totalCount {
    if (_dirty)
      _updateCaches();
    return _totalCount;
  }

  bool _dirty = true;
  int _unreadCount = 0;
  int _totalCount = 0;
  
  void _updateCaches() {
    _unreadCount = 0;
    _totalCount = 0;
    for (AssetNode child in board.children) {
      bool found = false;
      for (Feature feature in child.features) {
        if (feature is MessageFeature) {
          found = true;
          if (!feature.isRead)
            _unreadCount += 1;
          _totalCount += 1;
        }
      }
      if (found && !_subscribedChildren.contains(child)) {
        _subscribedChildren.add(child);
        child.addListener(_childUpdated);
      }
    }
    _dirty = false;
  }

  void _unsubscribeAllChildren() {
    for (AssetNode child in _subscribedChildren)
      child.removeListener(_childUpdated);
  }

  void _childUpdated() {
    _dirty = true;
    notifyListeners();
  }

  static MessageBoardState? of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<_MessageBoardStateInheritedWidget>()?.state;
  }

  HudHandle? _mailBox;

  bool get isOpen => _mailBox != null;

  static const Size defaultSize = Size(600.0, 500.0);
  
  void openMail(BuildContext context) {
    if (_mailBox != null) {
      _mailBox!.bringToFront();
      return;
    }
    final Widget widget = ListenableBuilder(
      listenable: board.parent,
      builder: (BuildContext context, Widget? child) {
        final TextStyle style = DefaultTextStyle.of(context).style;
        return HudDialog(
          heading: Builder(
            builder: (BuildContext context) {
              final double iconSize = DefaultTextStyle.of(context).style.fontSize!;
              return Row(
                children: <Widget>[
                  board.parent.asIcon(context, size: iconSize),
                  const SizedBox(width: 12.0),
                  Expanded(child: Text('${board.parent.nameOrClassName} mailbox')),
                ],
              );
            },
          ),
          buttons: <Widget>[
            IconButton(
              icon: const Icon(Icons.location_searching),
              onPressed: () {
                ZoomProvider.centerOn(context, board.parent);
              },
            ),
          ],
          onClose: _handleClosed,
          child: ListView.builder(
            padding: const EdgeInsets.only(top: 8.0, left: 12.0, right: 12.0, bottom: 12.0),
            itemCount: board.children.length,
            itemBuilder: (BuildContext context, int index) {
              final AssetNode asset = board.children[index];
              return ListenableBuilder(
                listenable: asset,
                builder: (BuildContext context, Widget? child) {
                  String from = '';
                  String subject = 'no subject';
                  String body = '';
                  String when = '';
                  bool isUnread = false;
                  MailOpener? open;
                  bool hasAttachment = false;
                  for (Feature feature in asset.features) {
                    switch (feature) {
                      case final MessageFeature message:
                        from = message.from ?? '';
                        subject = message.subject;
                        body = message.body.replaceAll('\n', ' ');
                        open = message.openMail;
                        when = prettyTime(message.timestamp);
                        if (!message.isRead)
                          isUnread = true;
                      case final KnowledgeFeature knowledge:
                        if (knowledge.assetClasses.isNotEmpty || knowledge.materials.isNotEmpty)
                          hasAttachment = true;
                    }
                  }
                  TextStyle lineStyle = style;
                  if (isUnread)
                    lineStyle = lineStyle.merge(bold);
                  return InkWell(
                    onTap: open == null ? null : () => open!(context),
                    child: DefaultTextStyle.merge(
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      child: Row(
                        children: <Widget>[
                          Expanded(
                            flex: 2,
                            child: Text(from, style: lineStyle),
                          ),
                          const SizedBox(width: 12.0),
                          Expanded(
                            flex: 5,
                            child: Text.rich(
                              TextSpan(
                                text: subject,
                                style: lineStyle,
                                children: <InlineSpan>[
                                  TextSpan(text: ' - $body', style: style),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 4.0),
                          Text(when),
                          const SizedBox(width: 4.0),
                          hasAttachment ? const Icon(Icons.attachment) : const Icon(null),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        );
      },
    );
    _mailBox = HudProvider.add(context, defaultSize, widget);
    notifyListeners();
  }

  void _handleClosed() {
    _mailBox = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _mailBox?.cancel();
    _unsubscribeAllChildren();
    super.dispose();
  }
}
