import 'dart:async';
import 'dart:ui';

import 'package:flutter/widgets.dart';

// common
const int uT = 0;
const int uX = 1; // center
const int uY = 2; // center
const int uD = 3; // diameter

// planets
const int uVisible = 4; // viewport shortest side divider by diameter // TODO: give this to everything
const int uSeed = 5;

// stars
const int uStarCategory = 4;

// grid (does not use uD)
const int uGridWidth = 3; // pixels
const int uGridHeight = 4; // pixels
const int uCellCountWidth = 5; // number of cells
const int uCellCountHeight = 6; // number of cells

// ghost
const int uImageWidth = 4;
const int uImageHeight = 5;
const int uGhost = 6;
const int uImage = 0;

class ShaderLibrary {
  const ShaderLibrary._(
    this._stars,
    this._planet,
    this._grid,
    this._ghost,
  );

  final FragmentProgram _stars;
  FragmentShader stars(int starCategory) {
    return _stars.fragmentShader()
      ..setFloat(uStarCategory, starCategory.toDouble());
  }

  final FragmentProgram _planet;
  FragmentShader get planet {
    return _planet.fragmentShader();
  }

  final FragmentProgram _grid;
  FragmentShader grid({ required int width, required int height }) {
    return _grid.fragmentShader()
      ..setFloat(uCellCountWidth, width.toDouble())
      ..setFloat(uCellCountHeight, height.toDouble());
  }

  final FragmentProgram _ghost;
  FragmentShader get ghost {
    return _ghost.fragmentShader();
  }

  static Future<ShaderLibrary> initialize() async {
    return Future.wait<FragmentProgram>(<Future<FragmentProgram>>[
      FragmentProgram.fromAsset('lib/abilities/stars.frag'),
      FragmentProgram.fromAsset('lib/abilities/planet.frag'),
      FragmentProgram.fromAsset('lib/containers/grid.frag'),
      FragmentProgram.fromAsset('lib/ghost.frag'),
    ]).then((List<FragmentProgram> shaders) {
      return ShaderLibrary._(
        shaders[0],
        shaders[1],
        shaders[2],
        shaders[3],
      );
    });
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
