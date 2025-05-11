import 'package:flutter/material.dart';

import '../assets.dart';
import '../nodes/system.dart';
import '../widgets.dart';

class MessageFeature extends AbilityFeature {
  MessageFeature(this.systemID, this.timestamp, this.isRead, this.subject, this.from, this.body);
  
  final int systemID;
  final int timestamp;
  final bool isRead;
  final String subject;
  final String from;
  final String body;

  @override
  Widget buildRenderer(BuildContext context) {
    bool ambiguous = false;
    return Sizer(
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
            StatefulBuilder(
              builder: (BuildContext context, StateSetter setState) {
                return CheckboxListTile(
                  title: const Text('Message is read'),
                  value: ambiguous ? null : isRead,
                  tristate: ambiguous,
                  onChanged: (bool? value) {
                    if (!ambiguous) {
                      setState(() { ambiguous = true; });
                      SystemNode.of(context).play(<Object>[parent.id, isRead ? 'mark-unread' : 'mark-read']);
                    }
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  RendererType get rendererType => RendererType.box;
}
