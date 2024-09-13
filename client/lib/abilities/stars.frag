#include <flutter/runtime_effect.glsl>

uniform float time;
uniform vec2 center;
uniform float diameter;
uniform float starCategory;

out vec4 fragColor;

#define pi 3.14159265359

float rand(in float q) {
  return fract(sin(q) * 17475.413); // this number comes from finding a prime then tweaking some IEEE754 bits
}

float rand(in vec2 q) {
  return rand(rand(q.x + 987123.9) + rand(q.y - 128973.2)); // these numbers come from keyboard smashing
}

float noise1(in float q, in float cellSize) {
  q /= cellSize;
  float p = smoothstep(0.0, 1.0, fract(q));
  q = floor(q);
  float a = rand(q);
  float b = rand(q + 1.0);
  return mix(a, b, p);
}

float fractalNoise1(in float q) {
    return noise1(q, 8.0) * 0.1
         + noise1(q, 4.0) * 0.2
         + noise1(q, 2.0) * 0.3
         + noise1(q, 1.0) * 0.4;
}

float noise2(in vec2 q, in vec2 minRange, in vec2 maxRange, in vec2 cellSize) { // minRange.x <= q.x < maxRange.x; minRange.y <= q.y < maxRange.y
  // normalize q to 0..1
  q -= minRange;
  maxRange -= minRange;
  q /= maxRange;
  
  // divide the grid into chunks of size cellSize
  q *= cellSize;
  
  // find position within chunk
  vec2 p = smoothstep(0.0, 1.0, fract(q));
  
  // find chunk itself
  q = floor(q);

  // find values for the four corners of the cell
  float a = rand(q);
  float b = rand(q + vec2(1.0, 0.0));
  float c = rand(q + vec2(0.0, 1.0));
  float d = rand(q + vec2(1.0, 1.0));

  // mix the values
  float ab = mix(a, b, p.x);
  float cd = mix(c, d, p.x);
  return mix(ab, cd, p.y);
}

float fractalNoise2(in vec2 uv, in vec2 minRange, in vec2 maxRange) {
  return noise2(uv, minRange, maxRange, vec2(80.0, 80.0)) * 0.1
       + noise2(uv, minRange, maxRange, vec2(40.0, 40.0)) * 0.2
       + noise2(uv, minRange, maxRange, vec2(20.0, 20.0)) * 0.3
       + noise2(uv, minRange, maxRange, vec2(10.0, 10.0)) * 0.4;
}

const vec2 origin = vec2(0.0, 0.0);

void main() {
  vec2 currentPos = FlutterFragCoord().xy;

  float magnitude = 2.0;
  vec3 spectrum = vec3(10.0, 5.0, 1.0);
  vec3 colorDelta = vec3(
    mix(0.5, 1.05, fractalNoise1(time / 500.0)),
    mix(0.5, 1.05, fractalNoise1(time / 500.0 + 123.0)),
    mix(0.5, 1.05, fractalNoise1(time / 500.0 + 711.0))
  );

  float radius = diameter / 2.0;
  float distanceFromCenter = 2.0 * distance(currentPos, center) / diameter;
  vec3 starBody = spectrum * clamp(pow(2.0 - distanceFromCenter, magnitude) - 1.0, 0.0, 1.0) * fractalNoise2(currentPos - center, origin - diameter, origin + diameter) * colorDelta;
  vec3 starGlow = spectrum * max(2.0 - distanceFromCenter, 0.0) * 0.03 * colorDelta;

  fragColor = vec4(starBody + starGlow, 1.0);
}

