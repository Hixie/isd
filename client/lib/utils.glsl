const float pi = 3.14159265359;

float rand(in float q) {
  return fract(sin(q) * 17475.413); // this number comes from finding a prime then tweaking some IEEE754 bits
}

float rand(in vec2 q) {
  return rand(rand(q.x * 1.1) + rand(q.y - 0.1));
}

float rand(in vec3 q) {
  return rand(rand(q.x * 1.1) + rand(q.y - 0.1) + rand(q.z));
}

float noise1(in float q, in float cellSize) {
  q /= cellSize;
  float p = smoothstep(0.0, 1.0, fract(q));
  q = floor(q);
  float a = rand(q);
  float b = rand(q + 1.0);
  return mix(a, b, p);
}

float fractalNoise1(in float q) { // range should be >= 1.0 (e.g. 0..1, -2..4, but not 0.0..0.1)
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

float noise3(in vec3 q, in vec3 minRange, in vec3 maxRange, in float cellCount) { // minRange < q < maxRange
  // normalize q to 0..1
  q -= minRange;
  maxRange -= minRange;
  q /= maxRange;
  
  // divide the grid into cellCount chunks in each direction
  q *= cellCount;
  
  // find position within chunk
  vec3 p = smoothstep(0.0, 1.0, fract(q));
  
  // find chunk itself
  q = floor(q);

  // find values for the eight corners of the cell
  float a = rand(q + vec3(0.0, 0.0, 0.0));
  float b = rand(q + vec3(1.0, 0.0, 0.0));
  float c = rand(q + vec3(0.0, 1.0, 0.0));
  float d = rand(q + vec3(1.0, 1.0, 0.0));
  float e = rand(q + vec3(0.0, 0.0, 1.0));
  float f = rand(q + vec3(1.0, 0.0, 1.0));
  float g = rand(q + vec3(0.0, 1.0, 1.0));
  float h = rand(q + vec3(1.0, 1.0, 1.0));

  // mix the values
  float ab = mix(a, b, p.x);
  float cd = mix(c, d, p.x);
  float abcd = mix(ab, cd, p.y);
  float ef = mix(e, f, p.x);
  float gh = mix(g, h, p.x);
  float efgh = mix(ef, gh, p.y);
  return mix(abcd, efgh, p.z);
}

const int kIterations = 7;
const float kScaleFactor = 2.0;
const float kAmplitudeFactor = 0.5;

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

float fractalNoise3(in vec3 uv, in vec3 minRange, in vec3 maxRange) {
  float cellCount = 10.0;
  float amplitude = 0.4;
  float total = 0.0;
  float max = 0.0;
  for (int index = 0; index < kIterations; index += 1) {
    total += noise3(uv, minRange, maxRange, cellCount) * amplitude;
    max += amplitude;
    cellCount *= kScaleFactor;
    amplitude *= kAmplitudeFactor;
  }
  return total / max;
}
