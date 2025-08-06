import 'package:flutter/material.dart';

import '../assets.dart';
import '../containers/messages.dart';
import '../nodes/system.dart';
import '../widgets.dart';

class MessageFeature extends AbilityFeature with ChangeNotifier {
  MessageFeature(this.systemID, this.timestamp, this.isRead, this.subject, this.from, this.body);
  
  final int systemID;
  final int timestamp; // TODO: show this in the UI!
  final bool isRead;
  final String subject;
  final String from;
  final String body;

  @override
  RendererType get rendererType => RendererType.ui;

  // TODO: we shouldn't replace the entire node, losing state, when the server updates us
  // because that way, we lose the "ambiguous" boolean state.
  // Instead we should have some long-lived state and we should clear the "ambiguous" boolean
  // either when the state is obsolete (node is gone entirely), or when the `play()` method's
  // returned Future completes.

  // TODO: have a button to pop-out a message

  // TODO: automatically pop-out a message when it comes in?

  bool _ambiguous = false;
  
  @override
  Widget buildRenderer(BuildContext context) {
    final MessageBoardMode? mode = MessageBoardMode.of(context);
    if (mode?.showBody == true) {
      mode!;
      return ListBody(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(8.0, 4.0, 8.0, 0.0),
            child: Text(
              'Subject: $subject',
              style: isRead ? null : bold,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8.0, 0.0, 8.0, 0.0),
            child: Text('From: $from'),
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(8.0, 0.0, 8.0, 0.0),
            child: Text(body),
          ),
          const Divider(),
          ListenableBuilder(
            listenable: this,
            builder: (BuildContext context, Widget? child) {
              return CheckboxListTile(
                title: const Text('Message is read'),
                value: _ambiguous ? null : isRead,
                tristate: _ambiguous,
                onChanged: (bool? value) {
                  if (!_ambiguous) {
                    _ambiguous = true;
                    notifyListeners();
                    SystemNode.of(parent).play(<Object>[parent.id, isRead ? 'mark-unread' : 'mark-read']);
                  }
                },
              );
            },
          ),
        ],
      );
    }
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: mode?.onSelect,
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Builder(
            builder: (BuildContext context) => ListBody(
              children: <Widget>[
                Text(subject,
                  style: isRead ? null : bold,
                ),
                Text('From: $from',
                  style: DefaultTextStyle.of(context).style.apply(fontSizeFactor: 0.8),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget? buildHeader(BuildContext context) {
    return Row(
      children: <Widget>[
        ListenableBuilder(
          listenable: this,
          builder: (BuildContext context, Widget? child) {
            return IconButton(
              icon: _ambiguous ? const Icon(Icons.pending) : isRead ? const Icon(Icons.mark_email_unread) : const Icon(Icons.mark_email_read),
              tooltip: isRead ? 'Mark as unread' : 'Mark as read',
              onPressed: _ambiguous ? null : () {
                if (!_ambiguous) {
                  _ambiguous = true;
                  notifyListeners();
                  SystemNode.of(parent).play(<Object>[parent.id, isRead ? 'mark-unread' : 'mark-read']);
                }
              },
            );
          },
        ),
      ],
    );
  }
}
