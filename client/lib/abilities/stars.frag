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
  return rand(rand(q.x * 1.1) + rand(q.y - 0.1));
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

float noise2(in vec2 q, in vec2 minRange, in vec2 maxRange, in float cellCount) { // minRange.x <= q.x < maxRange.x; minRange.y <= q.y < maxRange.y
  // normalize q to 0..1
  q -= minRange;
  maxRange -= minRange;
  q /= maxRange;
  
  // divide the grid into cellCount chunks in each direction
  q *= cellCount;
  
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

#define kIterations 7
#define kScaleFactor 2.0
#define kAmplitudeFactor 0.5

float fractalNoise2(in vec2 uv, in vec2 minRange, in vec2 maxRange) {
  float cellCount = 10.0;
  float amplitude = 0.4;
  float total = 0.0;
  float max = 0.0;
  for (int index = 0; index < kIterations; index += 1) {
    total += noise2(uv, minRange, maxRange, cellCount) * amplitude;
    max += amplitude;
    cellCount *= kScaleFactor;
    amplitude *= kAmplitudeFactor;
  }
  return total / max;
}

const vec2 origin = vec2(0.0, 0.0);

void main() {
  float magnitude = 2.0;
  vec3 spectrum = vec3(10.0, 5.0, 1.0);
  spectrum *= vec3(
    mix(0.4, 1.1, fractalNoise1(time / 500.0)),
    mix(0.4, 1.0, fractalNoise1(time / 480.0)),
    mix(0.0, 2.0, fractalNoise1(time / 2000.0))
  );

  vec2 pixelPos = FlutterFragCoord().xy;
  float radius = diameter / 2.0;
  float distanceFromCenter = 2.0 * distance(pixelPos, center) / diameter;
  vec3 starBody = spectrum * clamp(pow(2.0 - distanceFromCenter, magnitude) - 1.0, 0.0, 1.0) * fractalNoise2(pixelPos - center, origin - diameter, origin + diameter);
  vec3 starGlow = spectrum * max(2.0 - distanceFromCenter, 0.0) * 0.03;

  fragColor = vec4(starBody + starGlow, 1.0);
}

