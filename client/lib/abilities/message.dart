import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../assets.dart';
import '../layout.dart';
import '../world.dart';

class MessageFeature extends AbilityFeature {
  MessageFeature(this.systemID, this.timestamp, this.isRead, this.subject, this.from, this.body);
  
  final int systemID;
  final int timestamp;
  final bool isRead;
  final String subject;
  final String from;
  final String body;

  @override
  Widget? buildRenderer(BuildContext context, Widget? child) {
    return MessageWidget(
      node: parent,
      diameter: parent.diameter,
      maxDiameter: parent.maxRenderDiameter,
      child: Card(
        child: ListView(
          children: <Widget>[
            Text('Subject: $subject'),
            Text('From: $from'),
            const Divider(),
            Text(body),
          ],
        ),
      ),
      systemID: systemID,
      timestamp: timestamp,
      isRead: isRead,
      subject: subject,
      from: from,
      body: body,
    );
  }
}

class MessageWidget extends SingleChildRenderObjectWidget {
  const MessageWidget({
    super.key,
    required this.node,
    required this.diameter,
    required this.maxDiameter,
    super.child,
    required this.systemID,
    required this.timestamp,
    required this.isRead,
    required this.subject,
    required this.from,
    required this.body
  });

  final WorldNode node;
  final double diameter;
  final double maxDiameter;
  final int systemID;
  final int timestamp;
  final bool isRead;
  final String subject;
  final String from;
  final String body;

  @override
  RenderMessage createRenderObject(BuildContext context) {
    return RenderMessage(
      node: node,
      diameter: diameter,
      maxDiameter: maxDiameter,
      systemID: systemID,
      timestamp: timestamp,
      isRead: isRead,
      subject: subject,
      from: from,
      body: body,
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderMessage renderObject) {
    renderObject
      ..node = node
      ..diameter = diameter
      ..maxDiameter = maxDiameter
      ..systemID = systemID
      ..timestamp = timestamp
      ..isRead = isRead
      ..subject = subject
      ..from = from
      ..body = body;
  }
}

class RenderMessage extends RenderWorldNode with RenderObjectWithChildMixin<RenderBox> {
  RenderMessage({
    required super.node,
    required double diameter,
    required double maxDiameter,
    required int systemID,
    required int timestamp,
    required bool isRead,
    required String subject,
    required String from,
    required String body,
  }) : _diameter = diameter,
       _maxDiameter = maxDiameter,
       _systemID = systemID,
       _timestamp = timestamp,
       _isRead = isRead,
       _subject = subject,
       _from = from,
       _body = body;

  double get diameter => _diameter;
  double _diameter;
  set diameter (double value) {
    if (value != _diameter) {
      _diameter = value;
      markNeedsPaint();
    }
  }

  double get maxDiameter => _maxDiameter;
  double _maxDiameter;
  set maxDiameter (double value) {
    if (value != _maxDiameter) {
      _maxDiameter = value;
      markNeedsPaint();
    }
  }

  int get systemID => _systemID;
  int _systemID;
  set systemID (int value) {
    if (value != _systemID) {
      _systemID = value;
      markNeedsPaint();
    }
  }

  int get timestamp => _timestamp;
  int _timestamp;
  set timestamp (int value) {
    if (value != _timestamp) {
      _timestamp = value;
      markNeedsPaint();
    }
  }

  bool get isRead => _isRead;
  bool _isRead;
  set isRead (bool value) {
    if (value != _isRead) {
      _isRead = value;
      markNeedsPaint();
    }
  }

  String get subject => _subject;
  String _subject;
  set subject (String value) {
    if (value != _subject) {
      _subject = value;
      markNeedsLayout();
    }
  }

  String get from => _from;
  String _from;
  set from (String value) {
    if (value != _from) {
      _from = value;
      markNeedsLayout();
    }
  }

  String get body => _body;
  String _body;
  set body (String value) {
    if (value != _body) {
      _body = value;
      markNeedsLayout();
    }
  }

  double _actualDiameter = 0.0;
  
  @override
  void computeLayout(WorldConstraints constraints) {
    _actualDiameter = computePaintDiameter(diameter, maxDiameter);
    if (child != null) {
      child!.layout(BoxConstraints.tight(Size.square(_actualDiameter)));
    }
  }

  Offset? _childPosition;
  
  @override
  WorldGeometry computePaint(PaintingContext context, Offset offset) {
    _childPosition = Offset(offset.dx - _actualDiameter / 2.0, offset.dy - _actualDiameter / 2.0);
    context.paintChild(child!, _childPosition!);
    return WorldGeometry(shape: Square(_actualDiameter));
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, { required Offset position }) {
    return result.addWithPaintOffset(offset: _childPosition, position: position, hitTest: _hitTestChild);
  }

  bool _hitTestChild(BoxHitTestResult result, Offset offset) {
    return child!.hitTest(result, position: offset);
  }

  @override
  WorldTapTarget? routeTap(Offset offset) {
    return null; // TODO
  }
}
