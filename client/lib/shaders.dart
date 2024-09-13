import 'dart:async';
import 'dart:ui';

import 'package:flutter/widgets.dart';

const int uT = 0;
const int uX = 1;
const int uY = 2;
const int uD = 3;
const int uStarCategory = 4;

class ShaderLibrary {
  const ShaderLibrary._(
    this._stars,
  );

  final FragmentProgram _stars;
  FragmentShader stars(int starCategory) {
    return _stars.fragmentShader()
      ..setFloat(uStarCategory, starCategory.toDouble());
  }
  
  static Future<ShaderLibrary> initialize() async {
    return ShaderLibrary._(
      await FragmentProgram.fromAsset('lib/abilities/stars.frag'),
    );
  }
}

class ShaderProvider extends InheritedWidget {
  const ShaderProvider({ super.key, required this.shaders, required super.child });

  final ShaderLibrary shaders;

  static ShaderLibrary of(BuildContext context) {
    final ShaderProvider? provider = context.dependOnInheritedWidgetOfExactType<ShaderProvider>();
    assert(provider != null, 'No ShaderProvider found in context');
    return provider!.shaders;
  }

  @override
  bool updateShouldNotify(ShaderProvider oldWidget) => shaders != oldWidget.shaders;
}
