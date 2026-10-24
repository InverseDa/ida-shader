#ifndef IDA_CLOUD_DENSITY_GLSL
#define IDA_CLOUD_DENSITY_GLSL

// Shared geometry, coverage and wind for visible clouds and surface shadows.
const float CLOUD_BOTTOM = 168.0;
const float CLOUD_BOTTOM_FULL = 196.0;
const float CLOUD_TOP_FULL = 248.0;
const float CLOUD_TOP = 286.0;
const float CLOUD_EXTINCTION = 0.024;
const float CLOUD_MAX_DISTANCE = 4096.0;
const float CLOUD_FADE_START = 2048.0;

float sampleAtmosphereNoise(vec2 cellPosition, float cellsPerSample) {
    // World-space noise cells, NOT normalized UV frequencies. The custom PNG
    // is 128x128; query the bound size instead of assuming the 256 constant.
    float resolved = 1.0 - smoothstep(0.25, 1.25, cellsPerSample);
    if (resolved <= 0.0) return 0.5;
    vec2 cell = floor(cellPosition);
    vec2 f = fract(cellPosition);
    vec2 blend = f * f * (3.0 - 2.0 * f);
    vec2 size = vec2(textureSize(noisetex, 0));
    vec2 uv = (mod(cell, size) + blend + 0.5) / size;
    // One hardware bilinear lookup implements smooth value noise. Explicit
    // LOD is valid in divergent marches; no mip chain / new texture is needed.
    return mix(0.5, textureLod(noisetex, fract(uv), 0.0).r, resolved);
}

float cloudCoverageThreshold() {
    return mix(0.46, 0.30, smoothstep(0.0, 1.0, rainStrength));
}

float getCloudHeightDensity(float height) {
    float bottomFade = smoothstep(CLOUD_BOTTOM, CLOUD_BOTTOM_FULL, height);
    float topFade = 1.0 - smoothstep(CLOUD_TOP_FULL, CLOUD_TOP, height);
    return bottomFade * topFade;
}

float sampleCloudBody(vec3 cellPosition, float cellsPerSample) {
    float resolved = 1.0 - smoothstep(0.25, 1.25, cellsPerSample);
    if (resolved <= 0.0) return 0.5;
    vec3 cell = floor(cellPosition);
    vec3 f = fract(cellPosition);
    vec3 blend = f * f * (3.0 - 2.0 * f);
    vec2 size = vec2(textureSize(noisetex, 0));
    vec2 plane = cell.xz + vec2(37.0, 17.0) * cell.y;
    vec2 uv0 = (mod(plane, size) + blend.xz + 0.5) / size;
    vec2 uv1 = uv0 + vec2(37.0, 17.0) / size;
    float lower = textureLod(noisetex, fract(uv0), 0.0).r;
    float upper = textureLod(noisetex, fract(uv1), 0.0).r;
    // Interpolated adjacent lattice planes form continuous 3D value noise.
    // Reusing one XZ pattern through the slab would make stacked curtains.
    return mix(0.5, mix(lower, upper, blend.y), resolved);
}

float getCloudCoverageAtHeight(vec3 absolutePos, vec2 footprint) {
    vec2 p = absolutePos.xz - vec2(2.0, 0.8) * frameTimeCounter;
    float threshold = cloudCoverageThreshold();
    vec3 bodyPos = vec3(p.x / 96.0, (absolutePos.y - CLOUD_BOTTOM) / 48.0, p.y / 96.0);
    float body = sampleCloudBody(bodyPos, max(footprint.x / 96.0, footprint.y / 48.0));
    // The unread broad weather field is bounded by one.
    if (body * 0.70 + 0.30 <= threshold) return 0.0;
    float weather = sampleAtmosphereNoise(p / 384.0 + vec2(17.3, 51.7), footprint.x / 384.0);
    float erosion = (1.0 - getCloudHeightDensity(absolutePos.y)) * 0.20;
    float cloudShape = body * 0.70 + weather * 0.30 - erosion;
    return smoothstep(threshold, 0.72, cloudShape);
}

float getCloudCoverage(vec2 absoluteXZ) {
    // Surface shadows approximate the column with the same mid-layer field.
    return getCloudCoverageAtHeight(vec3(absoluteXZ.x, 227.0, absoluteXZ.y), vec2(0.0));
}

float getCloudLayerDensity(vec3 absolutePos) {
    float heightDensity = getCloudHeightDensity(absolutePos.y);
    if (heightDensity <= 0.0) return 0.0;
    return getCloudCoverageAtHeight(absolutePos, vec2(0.0)) * heightDensity;
}

float cloudRampIntegral(float height, float lower, float upper) {
    float t = clamp((height - lower) / (upper - lower), 0.0, 1.0);
    return max(height - upper, 0.0) + (upper - lower) * t * t * t * (1.0 - 0.5 * t);
}

float cloudColumnLengthAbove(float height) {
    float y = clamp(height, CLOUD_BOTTOM, CLOUD_TOP);
    float fullColumn = CLOUD_TOP - CLOUD_BOTTOM -
                       0.5 * (CLOUD_BOTTOM_FULL - CLOUD_BOTTOM + CLOUD_TOP - CLOUD_TOP_FULL);
    float below = cloudRampIntegral(y, CLOUD_BOTTOM, CLOUD_BOTTOM_FULL) -
                  cloudRampIntegral(y, CLOUD_TOP_FULL, CLOUD_TOP);
    return max(fullColumn - below, 0.0);
}

#endif
