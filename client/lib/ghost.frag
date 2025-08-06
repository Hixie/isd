#include <flutter/runtime_effect.glsl>
#include <utils.glsl>

uniform float time;
uniform vec2 center;
uniform float diameter;
uniform vec2 imageSize;
uniform float ghost;
uniform sampler2D image;

out vec4 fragColor;

void main() {
  vec2 pixelPos = FlutterFragCoord().xy;
  vec2 topLeft = center - diameter / 2.0;
  vec2 normalizedPosition = (pixelPos - topLeft) / diameter;
  float posNoise = (fractalNoise1(time / 100000.0 + normalizedPosition.y * 50.0) - 0.5) * ghost;
  vec2 sourcePosition = normalizedPosition + vec2(posNoise, 0.0) / 80.0;
  vec2 delta = 0.5 / imageSize;
  vec4 a = texture(image, sourcePosition - vec2(-delta.x, -delta.y));
  vec4 d = texture(image, sourcePosition - vec2( delta.x, -delta.y));
  vec4 b = texture(image, sourcePosition - vec2(-delta.x,  delta.y));
  vec4 c = texture(image, sourcePosition - vec2( delta.x,  delta.y));
  fragColor = (a + b + c + d) / 4.0;
  float rNoise = mix(1.0, fractalNoise3(vec3(normalizedPosition, sin(time / 999000.0)), vec3(0.0, 0.0, -1.0), vec3(1.0, 1.0, 1.0)) / 10.0, ghost);
  float gNoise = mix(1.0, fractalNoise3(vec3(normalizedPosition, sin(time / 980000.0)), vec3(0.0, 0.0, -1.0), vec3(1.0, 1.0, 1.0)) / 2.0 + 0.5, ghost);
  float bNoise = mix(1.0, fractalNoise3(vec3(normalizedPosition, sin(time / 1230000.0)), vec3(0.0, 0.0, -1.0), vec3(1.0, 1.0, 1.0)) / 2.0 + 0.5, ghost);
  fragColor = vec4(fragColor.r * rNoise, fragColor.g * gNoise, fragColor.b * bNoise, fragColor.a);
  float colorNoise = noise3(vec3(normalizedPosition, sin(time / 50000000.0)), vec3(0.0, 0.0, -1.0), vec3(1.0, 1.0, 1.0), imageSize.x / 2.0) / 2.0 + 0.1;
  fragColor = fragColor + fragColor.a * colorNoise * ghost;
}
