#include <flutter/runtime_effect.glsl>
#include <utils.glsl>

uniform float time;
uniform vec2 center;
uniform float diameter;
uniform vec2 imageSize;
uniform float ghost;
uniform sampler2D image;

out vec4 fragColor;

float hump1(float x) { // domain: -1..1; range: 0..1
  if (x < -1)
    return 0;
  if (x > 1)
    return 0;
  return cos(x * pi) / 2 + 0.5;
}

float hump2(float x) { // domain: -1..1; range: 0..1
  float sigma = 0.4;
  return exp(-(x*x) / sigma);
}

vec2 interference(float y, float waveCenter, float waveWidth, float displacementAmplitude, float waveCount) {
  // float waveCenter = fract(-time / 1000000.0);
  // float waveWidth = 0.1;
  // float displacementAmplitude = 0.08;
  // float waveCount = 6;
  return vec2(cos(y * (waveCount / waveWidth) * pi) * displacementAmplitude * (hump1((y - waveCenter) / (waveWidth / 2.0))), 0.0);
}

void main() {
  vec2 pixelPos = FlutterFragCoord().xy;
  vec2 topLeft = center - diameter / 2.0;
  vec2 source = (pixelPos - topLeft) / diameter;
  float posNoise = (fractalNoise1(time / 100000.0 + source.y * 50.0) - 0.5) * ghost;
  vec2 sourcePosition = source + vec2(posNoise, 0.0) / 80.0
         + interference(source.y, fract(-time / 2000000.0), 0.1, 0.05, 6) * ghost
         + interference(source.y, fract(-time / 3239123.0), 0.12, 0.03, 8) * ghost;
  vec2 delta = 0.5 / imageSize;
  vec4 a = texture(image, sourcePosition - vec2(-delta.x, -delta.y));
  vec4 b = texture(image, sourcePosition - vec2( delta.x, -delta.y));
  vec4 c = texture(image, sourcePosition - vec2(-delta.x,  delta.y));
  vec4 d = texture(image, sourcePosition - vec2( delta.x,  delta.y));
  fragColor = (a + b + c + d) / 4.0;
  
  float rNoise = mix(1.0, fractalNoise3(vec3(source, sin(time / 999000.0)), vec3(0.0, 0.0, -1.0), vec3(1.0, 1.0, 1.0)) / 10.0, ghost);
  float gNoise = mix(1.0, fractalNoise3(vec3(source, sin(time / 980000.0)), vec3(0.0, 0.0, -1.0), vec3(1.0, 1.0, 1.0)) / 2.0 + 0.5, ghost);
  float bNoise = mix(1.0, fractalNoise3(vec3(source, sin(time / 1230000.0)), vec3(0.0, 0.0, -1.0), vec3(1.0, 1.0, 1.0)) / 2.0 + 0.5, ghost);
  fragColor = vec4(fragColor.r * rNoise, fragColor.g * gNoise, fragColor.b * bNoise, fragColor.a);
  
  float colorNoise = noise3(vec3(source, sin(time / 50000000.0)), vec3(0.0, 0.0, -1.0), vec3(1.0, 1.0, 1.0), imageSize.x / 2.0) / 2.0 + 0.1;
  fragColor = fragColor + fragColor.a * colorNoise * ghost;
  
  fragColor = fragColor * (1 - ghost * sin(source.y * diameter * 2));
}
