#include <flutter/runtime_effect.glsl>
#include <../utils.glsl>

uniform float time;
uniform vec2 center;
uniform float diameter;
uniform float visible;
uniform float planetSeed;

out vec4 fragColor;

vec2 origin = vec2(0.0, 0.0);

mat2 rotate2d(float angle) {
  return mat2(cos(angle), -sin(angle), sin(angle), cos(angle));
}

float lines(in vec2 pos, float angle, float b){
  float scale = 10.0;
  pos *= scale;
  pos = rotate2d(angle) * pos;
  return smoothstep(0.0,
    0.5+b*0.5,
    abs((sin(pos.x*3.1415)+b*2.0))*0.5);
}

void main() {
  float radius = diameter / 2.0;
  float atmosphereThicknessRatio = 0.0075;
  float margin = 0.001;

  vec2 pos = FlutterFragCoord().xy - center;
  float r = distance(pos, origin) / radius;
  
  float isPlanet = 1.0 - smoothstep(1.0 - atmosphereThicknessRatio, 1.0, r);
  float isAtmosphere = smoothstep(1.0 - atmosphereThicknessRatio, 1.0, r) * (1.0 - smoothstep(1.0, 1.0 + margin, r));

  vec3 minRange = vec3(origin - diameter, 0.0);
  vec3 maxRange = vec3(origin + diameter, 4294967295.0);

  float noise1 = fractalNoise3(vec3(pos, planetSeed), minRange, maxRange);
  float isMountain = noise1 * noise1;

  // TODO: add high frequency detail when zoomed in

  // TODO: slowly rotate the direction of cloud travel
  float noise3 = fractalNoise3(vec3(pos - diameter * time / 187928123, planetSeed - time * 10), minRange, maxRange);
  float isCloud1 = smoothstep(0.3, 1.0, noise3);
  float noise4 = fractalNoise3(vec3(pos + diameter * time / 129121239, planetSeed + time), minRange, maxRange);
  float isCloud2 = smoothstep(0.5, 1.0, noise4);

  vec4 grass = vec4(0.05, 0.6, 0.1, 1.0);
  vec4 mountains = vec4(0.8, 0.0, 0.8, 1.0);
  vec4 water = vec4(0.0, 0.0, 0.9, 0.95);
  vec4 atmosphere = vec4(0.4, 0.8, 0.9, 1.0);
  vec4 cloud = vec4(1.0, 1.0, 1.0, 0.8);

  fragColor =
              grass * isPlanet
            + mountains * isPlanet * isMountain
            + atmosphere * isAtmosphere
            + cloud * isPlanet * isCloud1 * smoothstep(0.6, 1.0, visible) * (1-smoothstep(5.0, 30.0, visible))
            + cloud * isPlanet * isCloud2 * smoothstep(0.05, 1.0, visible) * (1-smoothstep(5.0, 30.0, visible))
            ;
}
