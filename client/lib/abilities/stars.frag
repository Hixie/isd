#include <flutter/runtime_effect.glsl>
#include <utils.glsl>

uniform float time;
uniform vec2 center;
uniform float diameter;
uniform float starCategory;

out vec4 fragColor;

const vec2 origin = vec2(0.0, 0.0);
const float period = 50000.0;

void main() {
  float magnitude = 2.0;
  vec4 spectrum = vec4(10.0, 5.0, 1.0, 10.0);
  spectrum *= vec4(
    mix(0.8, 1.1, fractalNoise1(time / 500.0)),
    mix(0.8, 1.0, fractalNoise1(time / 480.0)),
    mix(0.9, 1.0, fractalNoise1(time / 2000.0)),
    1.0
  );

  vec2 pixelPos = FlutterFragCoord().xy;
  vec2 pixelPosFromCenter = pixelPos - center;
  float noise = fractalNoise3(vec3(pixelPosFromCenter, sin(time / period)), vec3(origin - diameter, -1.0), vec3(origin + diameter, 1.0));
  float distanceFromCenter = 2.0 * distance(pixelPos, center) / diameter;
  vec4 starBody = spectrum * clamp(pow(2.0 - distanceFromCenter, magnitude) - 1.0, 0.0, 1.0) * noise;

  vec4 starGlow = spectrum * max(2.0 - distanceFromCenter, 0.0) * 0.03;

  float heatMask = distanceFromCenter > 2.0 || distanceFromCenter < 0.99 ? 0.0 : 1.0;
  heatMask *= max(0.0, log(2) - log(distanceFromCenter * 1.4));
  vec4 heat = vec4(0.9, 0.1, 0.1, 1.0) * smoothstep(0.0, 1.0, 2.0 * heatMask * noise2(vec2(time / 100.0, sin((distanceFromCenter - 1.0) * pi) * noise), vec2(0, 0.0), vec2(1000.0, 1.0), 80.0)) * heatMask;

  fragColor = starBody + starGlow + heat;
}
