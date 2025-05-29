import 'package:flutter/material.dart';

import '../assets.dart';
import '../containers/messages.dart';
import '../nodes/system.dart';

class MessageFeature extends AbilityFeature {
  MessageFeature(this.systemID, this.timestamp, this.isRead, this.subject, this.from, this.body);
  
  final int systemID;
  final int timestamp;
  final bool isRead;
  final String subject;
  final String from;
  final String body;

  @override
  RendererType get rendererType => RendererType.exclusive;

  // TODO: we shouldn't replace the entire node, losing state, when the server updates us
  // because that way, we lose the "ambiguous" boolean state.
  // Instead we should have some long-lived state and we should clear the "ambiguous" boolean
  // either when the state is obsolete (node is gone entirely), or when the `play()` method's
  // returned Future completes.

  // TODO: have a button to pop-out a message

  // TODO: automatically pop-out a message when it comes in?
  
  @override
  Widget buildRenderer(BuildContext context) {
    bool ambiguous = false;
    final MessageBoardMode mode = MessageBoardMode.of(context);
    if (mode.showBody) {
      return StatefulBuilder(
        builder: (BuildContext context, StateSetter setState) {
          return Column(
            children: <Widget>[
              AppBar(
                leading: IconButton(
                  icon: const Icon(Icons.arrow_upward),
                  tooltip: 'Go to message list',
                  onPressed: mode.onUp,
                ),
                title: Row(
                  children: <Widget>[
                    IconButton(
                      icon: ambiguous ? const Icon(Icons.pending) : isRead ? const Icon(Icons.mark_email_unread) : const Icon(Icons.mark_email_read),
                      tooltip: isRead ? 'Mark as unread' : 'Mark as read',
                      onPressed: ambiguous ? null : () {
                        if (!ambiguous) {
                          setState(() { ambiguous = true; });
                          SystemNode.of(context).play(<Object>[parent.id, isRead ? 'mark-unread' : 'mark-read']);
                        }
                      },
                    ),
                  ],
                ),
                actions: <Widget>[
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
                    tooltip: 'Go to previous message',
                    onPressed: mode.onLeft,
                  ),
                  IconButton(
                    icon: const Icon(Icons.arrow_forward),
                    tooltip: 'Go to next message',
                    onPressed: mode.onRight,
                  ),
                ],
              ),
              Expanded(
                child: Card(
                  child: ListView(
                    children: <Widget>[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(8.0, 4.0, 8.0, 0.0),
                        child: Text(
                          'Subject: $subject',
                          style: isRead ? null : const TextStyle(fontWeight: FontWeight.bold),
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
                      CheckboxListTile(
                        title: const Text('Message is read'),
                        value: ambiguous ? null : isRead,
                        tristate: ambiguous,
                        onChanged: (bool? value) {
                          if (!ambiguous) {
                            setState(() { ambiguous = true; });
                            SystemNode.of(context).play(<Object>[parent.id, isRead ? 'mark-unread' : 'mark-read']);
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      );
    }
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          mode.onSelect!();
        },
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Builder(
            builder: (BuildContext context) => ListBody(
              children: <Widget>[
                Text(subject,
                  style: isRead ? null : const TextStyle(fontWeight: FontWeight.bold),
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
}
