#include <flutter/runtime_effect.glsl>
#include <../utils.glsl>

uniform float time;
uniform vec2 center;
uniform vec2 gridSize; // pixels
uniform vec2 cellCount; // integers

out vec4 fragColor;

void main() {
  vec4 shade = vec4(0.1, 0.0, 0.0, 0.2);
  
  vec2 pixelPos = FlutterFragCoord().xy;
  vec2 topLeft = center - gridSize / 2.0;
  vec2 pixelPosOnGrid = pixelPos - topLeft;

  vec2 cellSize = gridSize / cellCount;
  vec2 pixelPosInCell = mod(pixelPosOnGrid, cellSize);
  vec2 relativePosInCell = pixelPosInCell / cellSize;

  vec2 adjustedPos = max(abs(relativePosInCell - 0.5) - 0.45, 0.0);

  float f = 0.95 + max(adjustedPos.x, adjustedPos.y);

  fragColor = vec4(f, f, f, 1.0);
}
