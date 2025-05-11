import 'dart:ui' show Codec, ImmutableBuffer;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'http/http.dart' as http;
import 'layout.dart';
import 'world.dart';

class IconsManager {
  IconsManager._(this.httpClient);

  final http.Client httpClient;

  final Set<String> badIcons = <String>{};
  
  static Future<IconsManager> initialize(http.Client httpClient) async {
    // TODO: warm cache?
    return IconsManager._(httpClient);
  }
}

class IconImageProvider extends ImageProvider<IconConfiguration> {
  const IconImageProvider(this.name, this.icons);

  final String name;
  final IconsManager icons;

  @override
  Future<IconConfiguration> obtainKey(ImageConfiguration configuration) {
    // TODO: consider using configuration.devicePixelRatio and configuration.size
    // (but since we zoom in and out so much, does it really matter?)
    return SynchronousFuture<IconConfiguration>(IconConfiguration(
      url: Uri.parse('https://interstellar-dynasties.space/icons/${Uri.encodeComponent(name)}.png'),
      icons: icons,
    ));
  }

  @override
  ImageStreamCompleter loadImage(IconConfiguration key, ImageDecoderCallback decode) {
    return MultiFrameImageStreamCompleter(
      codec: _load(key, decode),
      scale: 1.0, // doesn't matter really, we ignore the scale and draw it at a specific size
      debugLabel: name,
    );
  }

  Future<Codec> _load(IconConfiguration key, ImageDecoderCallback decode) async {
    if (icons.badIcons.contains(name)) {
      throw NetworkImageLoadException(uri: key.url, statusCode: 0);
    }
    assert(() {
      debugPrint('${key.url} fetching icon');
      return true;
    }());
    final http.Response response = await icons.httpClient.get(key.url);
    if (response.statusCode == 200) {
      return decode(await ImmutableBuffer.fromUint8List(response.bodyBytes));
    }
    icons.badIcons.add(name);
    throw NetworkImageLoadException(uri: key.url, statusCode: response.statusCode);
  }
}

@immutable
class IconConfiguration {
  const IconConfiguration({
    required this.url,
    required this.icons,
  });

  final Uri url;
  final IconsManager icons;

  @override
  bool operator ==(Object other) {
    if (other.runtimeType != runtimeType) {
      return false;
    }
    return other is IconConfiguration
        && other.url == url
        && other.icons == icons;
  }

  @override
  int get hashCode => Object.hash(url, icons);
}

class IconsManagerProvider extends InheritedWidget {
  const IconsManagerProvider({ super.key, required this.icons, required super.child });

  final IconsManager icons;

  static IconsManager of(BuildContext context) {
    final IconsManagerProvider? provider = context.dependOnInheritedWidgetOfExactType<IconsManagerProvider>();
    assert(provider != null, 'No IconsManagerProvider found in context');
    return provider!.icons;
  }

  @override
  bool updateShouldNotify(IconsManagerProvider oldWidget) => icons != oldWidget.icons;
}

class WorldIcon extends LeafRenderObjectWidget {
  const WorldIcon({
    super.key,
    required this.node,
    required this.icon,
    required this.diameter,
    required this.maxDiameter,
  });

  final WorldNode node;
  final String icon;
  final double diameter;
  final double maxDiameter;

  @override
  RenderWorldIcon createRenderObject(BuildContext context) {
    return RenderWorldIcon(
      node: node,
      icon: icon,
      diameter: diameter,
      maxDiameter: maxDiameter,
      devicePixelRatio: MediaQuery.of(context).devicePixelRatio,
      icons: IconsManagerProvider.of(context),
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderWorldIcon renderObject) {
    renderObject
      ..node = node
      ..icon = icon
      ..diameter = diameter
      ..maxDiameter = maxDiameter
      ..devicePixelRatio = MediaQuery.of(context).devicePixelRatio
      ..icons = IconsManagerProvider.of(context);
  }
}

class RenderWorldIcon extends RenderWorldNode {
  RenderWorldIcon({
    required super.node,
    required String icon,
    required double diameter,
    required double maxDiameter,
    required double devicePixelRatio,
    required IconsManager icons,
  }) : _icon = icon,
       _diameter = diameter,
       _maxDiameter = maxDiameter,
       _devicePixelRatio = devicePixelRatio,
       _icons = icons;

  String get icon => _icon;
  String _icon;
  set icon (String value) {
    if (value != _icon) {
      _icon = value;
      markNeedsLayout();
    }
  }

  double get diameter => _diameter;
  double _diameter;
  set diameter (double value) {
    if (value != _diameter) {
      _diameter = value;
      markNeedsLayout();
    }
  }

  double get maxDiameter => _maxDiameter;
  double _maxDiameter;
  set maxDiameter (double value) {
    if (value != _maxDiameter) {
      _maxDiameter = value;
      markNeedsLayout();
    }
  }

  double get devicePixelRatio => _devicePixelRatio;
  double _devicePixelRatio;
  set devicePixelRatio (double value) {
    if (value != _devicePixelRatio) {
      _devicePixelRatio = value;
      markNeedsLayout();
    }
  }

  IconsManager get icons => _icons;
  IconsManager _icons;
  set icons (IconsManager value) {
    if (value != _icons) {
      _icons = value;
      markNeedsLayout();
    }
  }

  ImageStream? _imageStream;
  double? _actualDiameter;
  
  @override
  void computeLayout(WorldConstraints constraints) {
    final ImageStream? oldImageStream = _imageStream;
    _actualDiameter = computePaintDiameter(diameter, maxDiameter);
    _imageStream = IconImageProvider(icon, icons).resolve(ImageConfiguration(
      devicePixelRatio: devicePixelRatio,
      size: Size.square(_actualDiameter!),
    ));
    if (_imageStream!.key != oldImageStream?.key) {
      oldImageStream?.removeListener(_imageChangeListener);
      _imageStream!.addListener(_imageChangeListener);
    }
  }

  ImageInfo? _imageInfo;
  
  late final ImageStreamListener _imageChangeListener = ImageStreamListener(_imageChangeHandler, onError: _imageErrorHandler);
  void _imageChangeHandler(ImageInfo imageInfo, bool synchronousCall) {
    _imageInfo?.dispose();
    _imageInfo = imageInfo;
    markNeedsPaint();
  }
  void _imageErrorHandler(Object exception, StackTrace? stackTrace) {
    _imageStream = null;
    _imageInfo = null;
    markNeedsPaint();
  }
  
  @override
  void dispose() {
    _imageStream?.removeListener(_imageChangeListener);
    _imageInfo?.dispose();
    super.dispose();
  }
    
  @override
  double computePaint(PaintingContext context, Offset offset) {
    if (_imageInfo == null) {
      context.canvas.drawCircle(offset, _actualDiameter! / 2.0, Paint()
        ..color = const Color(0x7FFF0000)
        ..strokeWidth = _actualDiameter! / 10.0
        ..style = PaintingStyle.stroke
      );
    } else {
      paintImage(
        canvas: context.canvas,
        rect: Rect.fromCircle(center: offset, radius: _actualDiameter! / 2.0),
        image: _imageInfo!.image,
        debugImageLabel: '$icon icon (${_imageInfo!.debugLabel})',
        scale: _imageInfo!.scale,
        fit: BoxFit.cover,
        // filterQuality: ...,
        // isAntiAlias: ...,
      );
    }
    if (debugPaintSizeEnabled) {
      context.canvas.drawCircle(offset, _actualDiameter! / 2.0, Paint()
        ..color= const Color(0x7FFFFF00)
        ..strokeWidth = 1.0
        ..style= PaintingStyle.stroke
      );
    }
    return _actualDiameter!;
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, { required Offset position }) {
    return false;
  }

  @override
  WorldTapTarget? routeTap(Offset offset) {
    return null; // TODO
  }
}
