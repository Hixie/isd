import 'package:flutter/material.dart';

import '../assets.dart';
import '../hud.dart';
import '../nodes/system.dart';
import '../prettifiers.dart';
import '../root.dart';
import '../widgets.dart';

// TODO: automatically pop-out a message when it comes in?

class MessageFeature extends AbilityFeature with ChangeNotifier {
  MessageFeature(this.systemID, this.timestamp, this.isRead, this.subject, this.from, this.body);

  final int systemID;
  final int timestamp;
  final bool isRead;
  final String subject;
  final String? from;
  final String body;

  MessageState? _state;
  
  @override
  void init(Feature? oldFeature) {
    super.init(oldFeature);
    if (oldFeature == null) {
      _state = MessageState(this);
    } else {
      _state = (oldFeature as MessageFeature)._state;
      _state!.update(this);
    }
  }

  @override
  RendererType get rendererType => RendererType.ui;

  void openMail(BuildContext context) {
    _state!.openMail(context, '${parent.nameOrClassName} message');
  }
  
  @override
  Widget buildRenderer(BuildContext context) {
    // Messages that are directly visible in the real world.
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Row(
          children: <Widget>[
            Expanded(
              child: ClipRect(
                child: Text.rich(
                  TextSpan(
                    children: <InlineSpan>[
                      TextSpan(text: '$subject\n', style: isRead ? null : bold),
                      if (from != null)
                        TextSpan(text: 'From: $from\n',
                          style: DefaultTextStyle.of(context).style.apply(fontSizeFactor: 0.8),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.file_open_outlined),
              onPressed: () => openMail(context),
            ),
          ],
        ),
      ),
    );
  }
}

class MessageState extends ChangeNotifier {
  MessageState(this._message);

  MessageFeature get message => _message;
  MessageFeature _message;

  void update(MessageFeature value) { // ignore: use_setters_to_change_properties
    _message = value;
    notifyListeners();
  }
  
  HudHandle? _mail;
  int _busy = 0;

  bool get isOpen => _mail != null;

  static const Size defaultSize = Size(400.0, 500.0);

  void _mark({ required bool read }) {
    _busy += 1;
    notifyListeners();
    SystemNode.of(message.parent).play(<Object>[message.parent.id, read ? 'mark-read' : 'mark-unread']).then((void value) async {
      _busy -= 1;
      if (hasListeners) // otherwise might have been disposed
        notifyListeners();
    });
  }
  
  void openMail(BuildContext context, String heading) {
    if (!message.isRead) {
      _mark(read: true);
    }
    if (_mail != null) {
      _mail!.bringToFront();
      return;
    }
    final Widget widget = ListenableBuilder(
      listenable: message.parent,
      builder: (BuildContext context, Widget? child) {
        final TextStyle style = DefaultTextStyle.of(context).style;
        final TextStyle metadata = style.apply(fontSizeFactor: 0.8);
        final List<Widget> paragraphs = <Widget>[];
        for (String p in message.body.split('\n')) {
          paragraphs.add(const SizedBox(height: 4.0));
          paragraphs.add(Text(p));
        }
        final List<Widget> attachments = <Widget>[];
        if (message.parent.isVirtual) {
          for (Feature feature in message.parent.features) {
            if (feature != message) {
              final Widget? child = feature.buildDialog(context);
              if (child != null)
                attachments.add(child);
            }
          }
        }
        return HudDialog(
          heading: Builder(
            builder: (BuildContext context) {
              final double iconSize = DefaultTextStyle.of(context).style.fontSize!;
              return Row(
                children: <Widget>[
                  message.parent.asIcon(context, size: iconSize),
                  const SizedBox(width: 12.0),
                  Expanded(child: Text(heading)),
                ],
              );
            },
          ),
          buttons: <Widget>[
            IconButton(
              icon: const Icon(Icons.location_searching),
              onPressed: () {
                ZoomProvider.centerOn(context, message.parent);
              },
            ),
          ],
          onClose: _handleClosed,
          child: CustomScrollView(
            slivers: <Widget>[
              SliverPadding(
                padding: const EdgeInsets.only(top: 8.0, left: 12.0, right: 12.0),
                sliver: SliverList.list(
                  children: <Widget>[
                    Text(message.subject, style: style.merge(bold)),
                    if (message.from != null)
                      Text('From: ${message.from!}', style: metadata),
                    Text('Source system: ${prettySystemId(message.systemID)}', style: metadata), // TODO: enable this to be a hyperlink
                    Text('Date: ${prettyTime(message.timestamp)}', style: metadata),
                    ...paragraphs,
                  ],
                ),
              ),
              if (attachments.isNotEmpty)
                const SliverPadding(
                  padding: EdgeInsets.only(top: 12.0, left: 12.0, right: 12.0),
                  sliver: SliverToBoxAdapter(
                    child: Row(
                      children: <Widget>[
                        Icon(Icons.attachment),
                        Expanded(child: Text(' Attachments', style: bold)),
                      ],
                    ),
                  ),
                ),
              if (attachments.isNotEmpty)
                SliverPadding(
                  padding: const EdgeInsets.only(top: 8.0, left: 12.0, right: 12.0),
                  sliver: SliverList.builder(
                    itemCount: attachments.length,
                    itemBuilder: (BuildContext context, int index) {
                      return attachments[index];
                    },
                  ),
                ),
              SliverFillRemaining(
                hasScrollBody: false,
                child: Padding(
                  padding: const EdgeInsets.only(top: 8.0, left: 12.0, right: 12.0, bottom: 12.0),
                  child: Align(
                    alignment: Alignment.bottomLeft,
                    child: ListenableBuilder(
                      listenable: this,
                      builder: (BuildContext context, Widget? child) => Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: <Widget>[
                          OutlinedButton(
                            onPressed: _busy > 0 ? null : () async {
                              _mark(read: !message.isRead);
                            },
                            child: Text(message.isRead ? 'Mark Unread' : 'Mark Read'),
                          ),
                          if (_busy > 0)
                            const Padding(
                              padding: EdgeInsets.only(left: 12.0),
                              child: SizedBox(
                                width: 10.0,
                                height: 10.0,
                                child: LinearProgressIndicator(),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
    _mail = HudProvider.add(context, defaultSize, widget);
    notifyListeners();
  }

  void _handleClosed() {
    _mail = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _mail?.cancel();
    super.dispose();
  }
}
