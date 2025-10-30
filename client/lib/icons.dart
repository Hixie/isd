import 'dart:math' as math show log, min, pow;
import 'dart:ui' show Codec, FragmentShader, ImmutableBuffer, TargetImageSize;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'http/http.dart' as http;
import 'layout.dart';
import 'nodes/system.dart';
import 'shaders.dart';
import 'spacetime.dart';
import 'world.dart';

@immutable
class IconField {
  const IconField(this.type, this.region, this.size);
  final int type;
  final Rect region; // as a fraction of the image dimensions
  final Size size; // in logical pixels
}

@immutable
class IconDescription {
  const IconDescription(this.bytes, this.fields);
  final Uint8List bytes;
  final List<IconField> fields;

  static IconDescription from(http.Response response) {
    final List<IconField> fields = <IconField>[];
    Size? size;

    final List<double> coords = <double>[];
    void flushParts() {
      if (size == null) {
        if (coords.length == 2) {
          size = Size(coords[0], coords[1]);
        } else {
          throw FormatException('Could not parse header field, first component must have exactly two parts, not ${coords.length}.');
        }
      } else {
        if (coords.length == 5) {
          fields.add(IconField(0, Rect.fromLTWH(coords[0] / size!.width, coords[1] / size!.height, coords[2] / size!.width, coords[3] / size!.height), Size(coords[4], (coords[3] / size!.height) * coords[4] / (coords[2] / size!.width))));
        } else {
          throw FormatException('Could not parse header field, each field component must have exactly five parts, not ${coords.length}.');
        }
      }
      coords.clear();
    }

    bool havePart = false;
    int part = 0;
    void flushPart() {
      if (havePart) {
        coords.add(part.toDouble());
        part = 0;
        havePart = false;
      }
    }

    final String rawFields = response.headers['isd-fields'] ?? '';
    for (final int c in rawFields.runes) {
      switch (c) {
        case 0x20:
          flushPart();
        case 0x3B:
          flushPart();
          flushParts();
        case 0x30:
        case 0x31:
        case 0x32:
        case 0x33:
        case 0x34:
        case 0x35:
        case 0x36:
        case 0x37:
        case 0x38:
        case 0x39:
          part *= 10;
          part += c - 0x30;
          havePart = true;
        default:
          throw FormatException('Could not parse header field "$rawFields", found unexpected character "$c".');
      }
    }
    flushPart();
    if (coords.isNotEmpty)
      flushParts();
    return IconDescription(response.bodyBytes, fields);
  }
}

class IconRedundantBadFetchException implements Exception {
  IconRedundantBadFetchException(this.name);
  final String name;

  @override
  String toString() => 'Tried to fetch icon <$name> which is cached as not available.';
}

class IconsManager {
  IconsManager._(this._httpClient);

  final http.Client _httpClient;

  static Future<IconsManager> initialize(http.Client httpClient) async {
    // TODO: warm cache?
    // TODO: cache on disk
    return IconsManager._(httpClient);
  }

  // TODO: flush cache when running out of memory
  final Map<String, IconDescription?> _cache = <String, IconDescription?>{};
  final Map<String, Future<IconDescription>> _pendingLoads = <String, Future<IconDescription>>{};

  void resetCache() {
    _cache.clear();
  }

  bool isKnownBad(String icon) {
    return _cache.containsKey(icon) && _cache[icon] == null;
  }

  Future<IconDescription> fetch(String icon) {
    if (_cache.containsKey(icon)) {
      final IconDescription? result = _cache[icon];
      if (result == null)
        throw IconRedundantBadFetchException(icon);
      return SynchronousFuture<IconDescription>(result);
    }
    if (_pendingLoads.containsKey(icon)) {
      return _pendingLoads[icon]!.catchError((Object error, StackTrace stackTrace) => throw IconRedundantBadFetchException(icon));
    }
    final Uri url = Uri.parse('https://interstellar-dynasties.space/icons/${Uri.encodeComponent(icon)}.png');
    assert(() {
      debugPrint('fetching icon $icon at $url');
      return true;
    }());
    return _pendingLoads[icon] = _httpClient.get(url).then<IconDescription>((http.Response response) {
      assert(!_cache.containsKey(icon));
      _cache[icon] = null; // in case IconDescription.from throws
      if (response.statusCode != 200) {
        throw NetworkImageLoadException(uri: url, statusCode: response.statusCode);
      }
      return _cache[icon] = IconDescription.from(response);
    }).whenComplete(() {
      _pendingLoads.remove(icon);
    });
  }

  static const double knowledgeIconSize = 64.0;

  // This renders the icon in the form used to represent knowledge.
  static Widget knowledgeIcon(BuildContext context, String icon, String tooltip) {
    // TODO: consider if there's some value to having these be tappable to show
    // a dialog with more information (but what more information; currently all
    // the relevant information is shown in the tooltip anyway).
    const double iconSize = knowledgeIconSize;
    const double iconPadding = 8.0;
    final IconsManager icons = IconsManagerProvider.of(context);
    return Tooltip(
      message: tooltip,
      child: DecoratedBox(
        decoration: ShapeDecoration(
          gradient: const RadialGradient(
            center: Alignment(0.0, 0.6),
            colors: <Color>[
              Color(0xFFFFFFFF),
              Color(0xFFFFFFDD),
            ],
          ),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(12.0)),
            side: BorderSide(),
          ),
          shadows: kElevationToShadow[2],
        ),
        child: Padding(
          padding: const EdgeInsets.all(iconPadding),
          child: IconsManager.icon(context, icon, size: iconSize - iconPadding * 2.0, icons: icons),
        ),
      ),
    );
  }

  // Just the image.
  static Widget icon(BuildContext context, String icon, { required double size, String? tooltip, IconsManager? icons }) {
    icons ??= IconsManagerProvider.of(context);
    Widget result = Image(
      image: IconImageProvider(icon, icons),
      height: size,
      width: size,
      errorBuilder: (BuildContext context, Object error, StackTrace? stackTrace) {
        return Tooltip(
          message: '$error',
          child: Icon(
            Icons.circle,
            color: const Color(0x11000000),
            size: size,
          ),
        );
      },
    );
    if (tooltip != null) {
      result = Tooltip(
        message: tooltip,
        child: result,
      );
    }
    return result;
  }
}

@immutable
class _IconKey {
  const _IconKey(this.name, this.icons, this.dimension);

  final String name;
  final IconsManager icons;
  final int dimension;

  @override
  bool operator ==(Object other) {
    if (other.runtimeType != runtimeType) {
      return false;
    }
    return other is _IconKey
        && other.name == name
        && other.icons == icons
        && other.dimension == dimension;
  }

  @override
  int get hashCode => Object.hash(name, icons, dimension);
}

@immutable
class IconImageProvider extends ImageProvider<_IconKey> {
  const IconImageProvider(this.name, this.icons);

  final String name;
  final IconsManager icons;

  static final double log2 = math.log(2);

  @override
  Future<_IconKey> obtainKey(ImageConfiguration configuration) {
    assert(configuration.size != null);
    assert(configuration.devicePixelRatio != null);
    double target = (configuration.size! * configuration.devicePixelRatio!).longestSide;
    if (target > 32) {
      target = math.pow(2, (math.log(target) / log2).ceil()).toDouble();
    } else {
      target = 32;
    }
    return SynchronousFuture<_IconKey>(_IconKey(name, icons, target.truncate() * 2));
  }

  @override
  ImageStreamCompleter loadImage(_IconKey key, ImageDecoderCallback decode) {
    return MultiFrameImageStreamCompleter(
      codec: _load(key, decode),
      scale: 1.0, // doesn't matter really, we ignore the scale and draw it at a specific size
      debugLabel: name,
    );
  }

  Future<Codec> _load(_IconKey key, ImageDecoderCallback decode) async {
    return decode(
      await ImmutableBuffer.fromUint8List((await icons.fetch(name)).bytes),
      getTargetSize: (int intrinsicWidth, int intrinsicHeight) {
        assert(intrinsicWidth == intrinsicHeight);
        final int size = math.min(key.dimension, intrinsicWidth);
        return TargetImageSize(width: size, height: size);
      },
    );
  }

  @override
  bool operator ==(Object other) {
    if (other.runtimeType != runtimeType) {
      return false;
    }
    return other is IconImageProvider
        && other.name == name
        && other.icons == icons;
  }

  @override
  int get hashCode => Object.hash(name, icons);
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

typedef IconTapCallback = void Function (BuildContext context);

class WorldIcon extends LeafRenderObjectWidget {
  const WorldIcon({
    super.key,
    required this.node,
    required this.icon,
    required this.diameter,
    required this.maxDiameter,
    required this.ghost,
    this.onTap,
  });

  final WorldNode node;
  final String icon;
  final double diameter;
  final double maxDiameter;
  final bool ghost;
  final IconTapCallback? onTap;

  @override
  RenderWorldIcon createRenderObject(BuildContext context) {
    return RenderWorldIcon(
      node: node,
      icon: icon,
      diameter: diameter,
      maxDiameter: maxDiameter,
      ghost: ghost,
      devicePixelRatio: MediaQuery.of(context).devicePixelRatio,
      icons: IconsManagerProvider.of(context),
      shaders: ShaderProvider.of(context),
      spaceTime: SystemNode.of(node).spaceTime,
      onTap: onTap == null ? null : () => onTap!(context),
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderWorldIcon renderObject) {
    renderObject
      ..node = node
      ..icon = icon
      ..diameter = diameter
      ..ghost = ghost
      ..maxDiameter = maxDiameter
      ..devicePixelRatio = MediaQuery.of(context).devicePixelRatio
      ..icons = IconsManagerProvider.of(context)
      ..shaders = ShaderProvider.of(context)
      ..spaceTime = SystemNode.of(node).spaceTime
      ..onTap = onTap == null ? null : () => onTap!(context);
    }
}

class RenderWorldIcon extends RenderWorldNode {
  RenderWorldIcon({
    required super.node,
    required String icon,
    required double diameter,
    required double maxDiameter,
    required bool ghost,
    required double devicePixelRatio,
    required IconsManager icons,
    required ShaderLibrary shaders,
    required SpaceTime spaceTime,
    this.onTap,
  }) : _icon = icon,
       _diameter = diameter,
       _maxDiameter = maxDiameter,
       _ghost = ghost,
       _devicePixelRatio = devicePixelRatio,
       _icons = icons,
       _shaders = shaders,
       _spaceTime = spaceTime;

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

  bool get ghost => _ghost;
  bool _ghost;
  set ghost (bool value) {
    if (value != _ghost) {
      _ghost = value;
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

  ShaderLibrary get shaders => _shaders;
  ShaderLibrary _shaders;
  set shaders (ShaderLibrary value) {
    if (value != _shaders) {
      _shaders = value;
      _shader = null;
      markNeedsPaint();
    }
  }

  SpaceTime get spaceTime => _spaceTime;
  SpaceTime _spaceTime;
  set spaceTime (SpaceTime value) {
    if (value != _spaceTime) {
      _spaceTime = value;
    }
  }

  VoidCallback? onTap;

  ImageStream? _imageStream;
  double? _actualDiameter;
  FragmentShader? _shader;

  @override
  void computeLayout(WorldConstraints constraints) {
    final ImageStream? oldImageStream = _imageStream;
    _actualDiameter = computePaintDiameter(diameter, maxDiameter);
    _shader ??= shaders.ghost;
    _shader!.setFloat(uD, _actualDiameter!);
    _shader!.setFloat(uGhost, ghost ? 1.0 : 0.0);
    _imageStream = IconImageProvider(icon, icons).resolve(ImageConfiguration(
      devicePixelRatio: devicePixelRatio,
      size: Size.square(_actualDiameter!),
    ));
    if (_imageStream!.key != oldImageStream?.key) {
      oldImageStream?.removeListener(_imageChangeListener);
      _imageStream!.addListener(_imageChangeListener); // this can synchronously call _imageChangeHandler below
    }
  }

  ImageInfo? _imageInfo;
  String? _errorMessage;

  late final ImageStreamListener _imageChangeListener = ImageStreamListener(_imageChangeHandler, onError: _imageErrorHandler);
  void _imageChangeHandler(ImageInfo imageInfo, bool synchronousCall) {
    _imageInfo?.dispose();
    _imageInfo = imageInfo;
    _shader!.setFloat(uImageWidth, _imageInfo!.image.width.toDouble());
    _shader!.setFloat(uImageHeight, _imageInfo!.image.height.toDouble());
    _shader!.setImageSampler(uImage, _imageInfo!.image);
    _errorMessage = null;
    markNeedsPaint();
  }
  void _imageErrorHandler(Object exception, StackTrace? stackTrace) {
    _imageInfo = null;
    assert(() {
      _errorMessage = '$exception';
      return true;
    }());
    markNeedsPaint();
    if (exception is! IconRedundantBadFetchException)
      Error.throwWithStackTrace(exception, stackTrace ?? StackTrace.current);
  }

  @override
  void dispose() {
    _imageStream?.removeListener(_imageChangeListener);
    _imageInfo?.dispose();
    _shader?.dispose();
    super.dispose();
  }

  Paint get _errorPaint => Paint() // TODO: cache
    ..color = const Color(0x7FFF0000)
    ..strokeWidth = _actualDiameter! / 10.0
    ..style = PaintingStyle.stroke;

  Paint? _paint;

  @override
  double computePaint(PaintingContext context, Offset offset) {
    if (_imageInfo == null) {
      context.canvas.drawCircle(offset, _actualDiameter! / 2.0, _errorPaint);
      final Offset r = Offset(_actualDiameter! / 2.0, _actualDiameter! / 2.0);
      context.canvas.drawLine(offset - r, offset + r, _errorPaint);
      assert(() {
        if (_actualDiameter! > 100.0) {
          final TextPainter painter = TextPainter(
            text: TextSpan(text: _errorMessage, style: const TextStyle(color: Color(0xFF000000))),
            textAlign: TextAlign.left,
            textDirection: TextDirection.ltr,
          );
          painter.layout(maxWidth: _actualDiameter!);
          painter.paint(context.canvas, offset - Offset(_actualDiameter! / 2.0, _actualDiameter! / 2.0));
          painter.dispose();
        }
        return true;
      }());
    } else {
      final double time = spaceTime.computeTime(<VoidCallback>[markNeedsPaint]);
      _shader!.setFloat(uT, time);
      _shader!.setFloat(uX, offset.dx);
      _shader!.setFloat(uY, offset.dy);
      _shader!.setFloat(uD, _actualDiameter!);
      _paint ??= Paint()
        ..shader = _shader;
      final Rect rect = Rect.fromCircle(center: offset, radius: _actualDiameter! / 2.0);
      context.canvas.drawRect(rect, _paint!);
      // paintImage(
      //   canvas: context.canvas,
      //   rect: rect,
      //   image: _imageInfo!.image,
      //   debugImageLabel: '$icon icon (${_imageInfo!.debugLabel})',
      //   scale: _imageInfo!.scale,
      //   fit: BoxFit.cover,
      //   // filterQuality: ...,
      //   // isAntiAlias: ...,
      // );
    }
    if (debugPaintSizeEnabled) {
      context.canvas.drawCircle(offset, _actualDiameter! / 2.0, Paint()
        ..color= const Color(0x1100CCCC)
      );
    }
    return _actualDiameter!;
  }

  @override
  void reassemble() {
    _imageStream?.removeListener(_imageChangeListener);
    _imageStream = null;
    _imageInfo?.dispose();
    _imageInfo = null;
    _shader?.dispose();
    _shader = null;
    _paint = null;
    super.reassemble();
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, { required Offset position }) {
    return false;
  }

  @override
  WorldTapTarget? routeTap(Offset offset) {
    if ((onTap != null) && isInsideSquare(offset)) {
      return _IconTapTarget(onTap!);
    }
    return null;
  }
}

class _IconTapTarget implements WorldTapTarget {
  _IconTapTarget(this.onTap);

  final VoidCallback onTap;

  @override
  void handleTapDown() {}

  @override
  void handleTapCancel() {}

  @override
  void handleTapUp() {
    onTap();
  }
}

class WorldFields extends MultiChildRenderObjectWidget {
  const WorldFields({
    super.key,
    required this.node,
    required this.icon,
    required this.diameter,
    required this.maxDiameter,
    required super.children,
  });

  final WorldNode node;
  final String icon;
  final double diameter;
  final double maxDiameter;

  @override
  RenderWorldFieldPlacement createRenderObject(BuildContext context) {
    return RenderWorldFieldPlacement(
      node: node,
      icon: icon,
      diameter: diameter,
      maxDiameter: maxDiameter,
      icons: IconsManagerProvider.of(context),
    );
  }

  @override
  void updateRenderObject(BuildContext context, RenderWorldFieldPlacement renderObject) {
    renderObject
      ..node = node
      ..icon = icon
      ..diameter = diameter
      ..maxDiameter = maxDiameter
      ..icons = IconsManagerProvider.of(context);
  }
}

class WorldFieldPlacementParentData extends ContainerBoxParentData<RenderBox> {
  Rect? _region;
  Size? _innerSize;
  Matrix4? _transform;

  final LayerHandle<TransformLayer> _layer = LayerHandle<TransformLayer>();

  @override
  void detach() {
    _layer.layer = null;
    super.detach();
  }
}

class RenderWorldFieldPlacement extends RenderWorldNode
      with ContainerRenderObjectMixin<RenderBox, WorldFieldPlacementParentData>,
           RenderBoxContainerDefaultsMixin<RenderBox, WorldFieldPlacementParentData> {
  RenderWorldFieldPlacement({
    required super.node,
    required String icon,
    required double diameter,
    required double maxDiameter,
    required IconsManager icons,
  }) : _icon = icon,
       _diameter = diameter,
       _maxDiameter = maxDiameter,
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

  IconsManager get icons => _icons;
  IconsManager _icons;
  set icons (IconsManager value) {
    if (value != _icons) {
      _icons = value;
      markNeedsLayout();
    }
  }

  @override
  void setupParentData(RenderObject child) {
    if (child.parentData is! WorldFieldPlacementParentData) {
      child.parentData = WorldFieldPlacementParentData();
    }
  }

  double? _actualDiameter;
  List<IconField>? _fields;
  bool _complained = false;

  @override
  void reassemble() {
    _complained = false;
    super.reassemble();
  }

  @override
  void computeLayout(WorldConstraints constraints) {
    final double actualDiameter = _actualDiameter = computePaintDiameter(diameter, maxDiameter);
    _fields = null;
    RenderBox? child = firstChild;
    if (!icons.isKnownBad(icon)) {
      bool synchronous = true;
      icons.fetch(icon).then((IconDescription desc) {
        if (synchronous) {
          _fields = desc.fields;
        } else if (attached) {
          // let's try again
          markNeedsLayout();
        }
      }).catchError((Object error, StackTrace stack) {
        if (!_complained) {
          _complained = true;
          print('Icon "$icon" failed to load: $error.');
        }
      });
      synchronous = false;
      if (_fields != null) {
        int index = 0;
        while (child != null && index < _fields!.length) {
          final WorldFieldPlacementParentData childParentData = child.parentData! as WorldFieldPlacementParentData;
          final Size innerSize = _fields![index].size;
          final Size outerSize = _fields![index].region.size * actualDiameter;
          final FittedSizes fittedSizes = applyBoxFit(BoxFit.contain, innerSize, outerSize);
          assert(fittedSizes.source == innerSize);
          final double halfWidthDelta = (fittedSizes.destination.width - outerSize.width) / 2.0;
          final double halfHeightDelta = (fittedSizes.destination.height - outerSize.height) / 2.0;
          childParentData._region = Rect.fromLTWH(
            _fields![index].region.left * actualDiameter + halfWidthDelta,
            _fields![index].region.top * actualDiameter + halfHeightDelta,
            fittedSizes.destination.width,
            fittedSizes.destination.height,
          );
          childParentData._innerSize = innerSize;
          child.layout(BoxConstraints.tight(innerSize));
          child = childParentData.nextSibling;
          index += 1;
        }
        if (child != null) {
          if (!_complained) {
            _complained = true;
            print('Icon "$icon" does not have enough fields (found ${_fields?.length} fields, need $childCount).');
          }
        }
      }
    }
    while (child != null) {
      final WorldFieldPlacementParentData childParentData = child.parentData! as WorldFieldPlacementParentData;
      childParentData._region = null;
      child.layout(BoxConstraints.tight(Size.zero));
      child = childParentData.nextSibling;
    }
  }

  @override
  double computePaint(PaintingContext context, Offset offset) {
    RenderBox? child = firstChild;
    final Offset topLeftOffset = offset.translate(-_actualDiameter! / 2.0, -_actualDiameter! / 2.0);
    if (debugPaintSizeEnabled) {
      if (_fields != null) {
        int index = 1;
        for (IconField field in _fields!) {
          final Rect rect = (topLeftOffset + (field.region.topLeft * _actualDiameter!)) & field.region.size * _actualDiameter!;
          context.canvas.drawRect(rect, Paint()..color=const Color(0x30FFFF00));
          if (rect.width > 100) {
            final TextPainter painter = TextPainter(
              text: TextSpan(text: '$index', style: const TextStyle(color: Color(0xFF000000), fontSize: 8.0)),
              textAlign: TextAlign.left,
              textDirection: TextDirection.ltr,
            );
            painter.layout();
            painter.paint(context.canvas, rect.topLeft.translate(2.0, 2.0));
            painter.dispose();
          }
          index += 1;
        }
      }
      context.canvas.drawRect(Rect.fromCircle(center: offset, radius: _actualDiameter! / 2.0), Paint()..color=const Color(0x7FFF00FF)..strokeWidth=2..style=PaintingStyle.stroke);
    }
    while (child != null) {
      final WorldFieldPlacementParentData childParentData = child.parentData! as WorldFieldPlacementParentData;
      if (childParentData._region != null) {
        final Rect rect = childParentData._region!.shift(topLeftOffset);
        final double scale = childParentData._region!.width / childParentData._innerSize!.width;

        if (debugPaintSizeEnabled)
          context.canvas.drawRect(rect, Paint()..color=const Color(0xFFFFFF00)..strokeWidth=2..style=PaintingStyle.stroke);

        childParentData._layer.layer = context.pushTransform(
          needsCompositing,
          Offset.zero,
          childParentData._transform = Matrix4.identity()..translateByDouble(rect.left, rect.top, 0.0, 1.0)..scaleByDouble(scale, scale, scale, 1.0),
          child.paint,
          oldLayer: childParentData._layer.layer,
        );
      }
      child = childParentData.nextSibling;
    }
    return _actualDiameter!;
  }

  @override
  void applyPaintTransform(covariant RenderObject child, Matrix4 transform) {
    assert(child.parent == this);
    final WorldFieldPlacementParentData childParentData = child.parentData! as WorldFieldPlacementParentData;
    if (childParentData._transform != null)
      transform.multiply(childParentData._transform!);
  }

  @override
  WorldTapTarget? routeTap(Offset offset) {
    return null;
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, { required Offset position }) {
    RenderBox? child = lastChild;
    while (child != null) {
      final WorldFieldPlacementParentData childParentData = child.parentData! as WorldFieldPlacementParentData;
      if (result.addWithPaintTransform(
        transform: childParentData._transform,
        position: position,
        hitTest: (BoxHitTestResult result, Offset position) {
          return child!.hitTest(result, position: position);
        },
      )) {
        return true;
      }
      child = childParentData.previousSibling;
    }
    return false;
  }
}
