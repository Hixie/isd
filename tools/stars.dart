import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/material.dart';

void main() {
  runApp(const Padding(
    padding: EdgeInsets.all(20.0),
    child: Center(
      child: AspectRatio(
        aspectRatio: 1.0,
        child: Galaxy(),
      ),
    ),
  ));
}

class Galaxy extends StatefulWidget {
  const Galaxy({super.key});

  @override
  State<Galaxy> createState() => _GalaxyState();
}

class _GalaxyState extends State<Galaxy> {

  final List<List<Offset>> stars = List<List<Offset>>.generate(11, (int index) => <Offset>[], growable: false);
  static const int arms = 2;
  static const double armWidth = 2 * pi / arms;

  static int _offsetSort(Offset a, Offset b) {
    if (a.dy == b.dy) {
      return (a.dx - b.dx).sign.toInt();
    }
    return (a.dy - b.dy).sign.toInt();
  }
  
  void _initStars() {
    for (List<Offset> substars in stars) {
      substars.clear();
    }
    Random random = Random();
    for (int i = 0; i < 200; i += 1) {
      stars[0].add(Offset(random.nextDouble(), random.nextDouble()));
      stars[1].add(Offset(random.nextDouble(), random.nextDouble()));
    }
    for (int i = 0; i < 750000; i += 1) {
      final double q1 = random.nextDouble(); // uniform distribution
      final double q2 = random.nextDouble(); // uniform distribution
      final int arm = random.nextInt(arms);
      final double r = 1 - sqrt(q1); // distance from center

      const double width = 0.15; // for 1e6 use 0.15, for 1e5 use 0.2
      final double w = tan(pi * q2 + pi / 2.0) * width + 0.5;
      const double spirals = 0.9; // for 1.6 use 0.9, for 1e5 use 1.0
      final double theta = (arm/arms * 2.0 * pi) + (w * armWidth) + r * spirals * 2 * pi + 0.8;

      final double x = r * cos(theta);
      final double y = r * sin(theta);
      final int category = random.nextInt(stars.length - 2) + 2;
      if (category < 10 || r > 0.4) {
        stars[category].add(Offset(x/2.0 + 0.5, y/2.0 + 0.5));
      }
    }
    for (int index = 10; index < stars.length; index += 1) {
      if (stars[index].length > 10) {
        stars[index].length = 10;
      }
    }
    for (List<Offset> substars in stars) {
      substars.sort(_offsetSort);
    }
    final Uint32List data = Uint32List(stars.fold(1 + stars.length, (int count, List<Offset> substars) => count + substars.length * 2));
    int position = 0;
    data[position++] = stars.length;
    for (List<Offset> substars in stars) {
      data[position++] = substars.length;
    }
    for (List<Offset> substars in stars) {
      for (Offset point in substars) {
        data[position++] = (point.dx * 4294967296).round();
        data[position++] = (point.dy * 4294967296).round();
      }
    }
    File('stars.dat').writeAsBytesSync(data.buffer.asUint8List());
  }

  @override
  void initState() {
    super.initState();
    _initStars();
  }

  @override
  void reassemble() {
    super.reassemble();
    _initStars();
  }

  static int binarySearchY(List<Offset> list, double target, [ int min = 0, int? maxLimit ]) {
    int max = maxLimit ?? list.length;
    while (min < max) {
      final int mid = min + ((max - min) >> 1);
      final Offset element = list[mid];
      final int comp = (element.dy - target).sign.toInt();
      if (comp == 0) {
        return mid;
      }
      if (comp < 0) {
        min = mid + 1;
      } else {
        max = mid;
      }
    }
    return min;
  }
                                                                      

  int _highlightMin = -1;
  int _highlightMax = -1;
  
  void _tapDownHandler(TapDownDetails details) {
    Size size = context.size!;
    Offset target = Offset(details.localPosition.dx / size.width, details.localPosition.dy / size.height);
    int minY = binarySearchY(stars[0], target.dy - 0.01);
    int maxY = binarySearchY(stars[0], target.dy + 0.01, minY);
    setState(() {
      _highlightMin = minY;
      _highlightMax = maxY;
    });
  }
  
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: _tapDownHandler,
      child: CustomPaint(
        painter: Painter(stars, _highlightMin, _highlightMax),
      ),
    );
  }
}

class Painter extends CustomPainter {
  Painter(this.stars, this.highlightMin, this.highlightMax);

  final List<List<Offset>> stars;
  final int highlightMin;
  final int highlightMax;

  @override
  void paint(Canvas canvas, Size size) {

    // final List<Paint> paints = <Paint>[
    //   Paint()..color = const Color(0x7FFFFFFF)..strokeCap = StrokeCap.round..strokeWidth = 0.0050,
    //   Paint()..color = const Color(0x7FCCBBAA)..strokeCap = StrokeCap.round..strokeWidth = 0.0030,
    //   Paint()..color = const Color(0x8FFF0000)..strokeCap = StrokeCap.round..strokeWidth = 0.0010,
    //   Paint()..color = const Color(0x7FFF9900)..strokeCap = StrokeCap.round..strokeWidth = 0.0015,
    //   Paint()..color = const Color(0x6FFFFFFF)..strokeCap = StrokeCap.round..strokeWidth = 0.0010,
    //   Paint()..color = const Color(0x5FFFFFFF)..strokeCap = StrokeCap.round..strokeWidth = 0.0025,
    //   Paint()..color = const Color(0x1F0099FF)..strokeCap = StrokeCap.round..strokeWidth = 0.0020,
    //   Paint()..color = const Color(0x1F0000FF)..strokeCap = StrokeCap.round..strokeWidth = 0.0010,
    //   Paint()..color = const Color(0x2FFF9900)..strokeCap = StrokeCap.round..strokeWidth = 0.0010,
    //   Paint()..color = const Color(0x1FFFFFFF)..strokeCap = StrokeCap.round..strokeWidth = 0.0010,
    //   Paint()..color = const Color(0x5FFF2200)..strokeCap = StrokeCap.round..strokeWidth = 0.0200..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8.0), // opacity 0x5F for 1e6, 0x3F for 1e5
    // ];

    final List<Paint> paints = <Paint>[
      Paint()..color = const Color(0x7FFFFFFF)..strokeCap = StrokeCap.round..strokeWidth = 0.0040..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.0),
      Paint()..color = const Color(0xCFCCBBAA)..strokeCap = StrokeCap.round..strokeWidth = 0.0025,
      Paint()..color = const Color(0xDFFF0000)..strokeCap = StrokeCap.round..strokeWidth = 0.0005,
      Paint()..color = const Color(0xCFFF9900)..strokeCap = StrokeCap.round..strokeWidth = 0.0007,
      Paint()..color = const Color(0xBFFFFFFF)..strokeCap = StrokeCap.round..strokeWidth = 0.0005,
      Paint()..color = const Color(0xAFFFFFFF)..strokeCap = StrokeCap.round..strokeWidth = 0.0012,
      Paint()..color = const Color(0x2F0099FF)..strokeCap = StrokeCap.round..strokeWidth = 0.0010,
      Paint()..color = const Color(0x2F0000FF)..strokeCap = StrokeCap.round..strokeWidth = 0.0005,
      Paint()..color = const Color(0x4FFF9900)..strokeCap = StrokeCap.round..strokeWidth = 0.0005,
      Paint()..color = const Color(0x2FFFFFFF)..strokeCap = StrokeCap.round..strokeWidth = 0.0005,
      Paint()..color = const Color(0x5FFF2200)..strokeCap = StrokeCap.round..strokeWidth = 0.0200..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8.0),
    ];

    // const zoom = 2000.0;
    // canvas.save();
    // canvas.scale(zoom, zoom);
    // canvas.translate(-631.75, -631.75);
    const zoom = 1;
    
    int index = 0;
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size.width / 2.0, size.height / 2.0),
        width: size.width,
        height: size.height,
      ),
      //Paint()..color = const Color(0x55114499)..maskFilter = MaskFilter.blur(BlurStyle.normal, size.shortestSide / 2.0),
      Paint()..color = const Color(0x5566BBFF)..maskFilter = MaskFilter.blur(BlurStyle.normal, size.shortestSide / 8.0),
    );
    for (List<Offset> substars in stars) {
      canvas.drawPoints(
        PointMode.points,
        substars.map((Offset offset) => offset.scale(size.width, size.height)).toList(),
        Paint.from(paints[index])..strokeWidth = paints[index].strokeWidth * size.shortestSide / zoom,
      );
      index += 1;
    }
    if (highlightMin >= 0) {
      for (int index = highlightMin; index < highlightMax; index += 1) {
        Offset target = stars[0][index];
        canvas.drawCircle(Offset(target.dx * size.width, target.dy * size.height), size.shortestSide * 0.01, Paint()..color = Colors.white..style = PaintingStyle.stroke);
      }
    }

//    canvas.restore();
  }
  
  @override
  bool shouldRepaint(Painter oldDelegate) => stars != oldDelegate.stars || highlightMin != oldDelegate.highlightMin || highlightMax != oldDelegate.highlightMax;
}
