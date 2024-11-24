import 'dart:async';
import 'dart:ui';

import 'package:flutter/widgets.dart';

// common
const int uT = 0;
const int uX = 1; // center
const int uY = 2; // center

// stars
const int uD = 3; // diameter
const int uStarCategory = 4;

// grid
const int uGridWidth = 3; // pixels
const int uGridHeight = 4; // pixels
const int uCellCountWidth = 5; // number of cells
const int uCellCountHeight = 6; // number of cells

class ShaderLibrary {
  const ShaderLibrary._(
    this._stars,
    this._grid,
  );

  final FragmentProgram _stars;
  FragmentShader stars(int starCategory) {
    return _stars.fragmentShader()
      ..setFloat(uStarCategory, starCategory.toDouble());
  }

  final FragmentProgram _grid;
  FragmentShader grid({ required int width, required int height }) {
    return _grid.fragmentShader()
      ..setFloat(uCellCountWidth, width.toDouble())
      ..setFloat(uCellCountHeight, height.toDouble());
  }
  
  static Future<ShaderLibrary> initialize() async {
    // TODO: load this in parallel (using Future.wait)
    return ShaderLibrary._(
      await FragmentProgram.fromAsset('lib/abilities/stars.frag'),
      await FragmentProgram.fromAsset('lib/containers/grid.frag'),
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
