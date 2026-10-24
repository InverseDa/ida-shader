#ifndef IDA_CLOUD_DENSITY_GLSL
#define IDA_CLOUD_DENSITY_GLSL
#include "/lib/settings.glsl"

// Shared geometry, coverage and wind for visible clouds and surface shadows.
#if CLOUD_STYLE == 0
const float CloudBottom = 192.0;
const float CloudBottomFull = 192.01;
const float CloudTopFull = 215.99;
const float CloudTop = 216.0;
const float CloudExtinction = 0.16;
#else
const float CloudBottom = 168.0;
const float CloudBottomFull = 196.0;
const float CloudTopFull = 248.0;
const float CloudTop = 286.0;
const float CloudExtinction = 0.024;
#endif
const float BlockCloudCellSize = 24.0;
const float CloudMaxDistance = 4096.0;
const float CloudFadeStart = 2048.0;

float SampleAtmosphereNoise(vec2 CellPosition, float CellsPerSample) {
    // World-space noise cells, NOT normalized UV frequencies. The custom PNG
    // is 128x128; query the bound size instead of assuming the 256 constant.
    float Resolved = 1.0 - smoothstep(0.25, 1.25, CellsPerSample);
    if (Resolved <= 0.0) return 0.5;
    vec2 Cell = floor(CellPosition);
    vec2 F = fract(CellPosition);
    vec2 Blend = F * F * (3.0 - 2.0 * F);
    vec2 Size = vec2(textureSize(noisetex, 0));
    vec2 Uv = (mod(Cell, Size) + Blend + 0.5) / Size;
    // One hardware bilinear lookup implements smooth value noise. Explicit
    // LOD is valid in divergent marches; no mip chain / new texture is needed.
    return mix(0.5, textureLod(noisetex, fract(Uv), 0.0).r, Resolved);
}

float CloudCoverageThreshold() {
    return mix(0.46, 0.30, smoothstep(0.0, 1.0, rainStrength));
}

float GetCloudHeightDensity(float Height) {
    float BottomFade = smoothstep(CloudBottom, CloudBottomFull, Height);
    float TopFade = 1.0 - smoothstep(CloudTopFull, CloudTop, Height);
    return BottomFade * TopFade;
}

float SampleCloudBody(vec3 CellPosition, float CellsPerSample) {
    float Resolved = 1.0 - smoothstep(0.25, 1.25, CellsPerSample);
    if (Resolved <= 0.0) return 0.5;
    vec3 Cell = floor(CellPosition);
    vec3 F = fract(CellPosition);
    vec3 Blend = F * F * (3.0 - 2.0 * F);
    vec2 Size = vec2(textureSize(noisetex, 0));
    vec2 Plane = Cell.xz + vec2(37.0, 17.0) * Cell.y;
    vec2 Uv0 = (mod(Plane, Size) + Blend.xz + 0.5) / Size;
    vec2 Uv1 = Uv0 + vec2(37.0, 17.0) / Size;
    float Lower = textureLod(noisetex, fract(Uv0), 0.0).r;
    float Upper = textureLod(noisetex, fract(Uv1), 0.0).r;
    // Interpolated adjacent lattice planes form continuous 3D value noise.
    // Reusing one XZ pattern through the slab would make stacked curtains.
    return mix(0.5, mix(Lower, Upper, Blend.y), Resolved);
}

float GetCloudCoverageAtHeight(vec3 AbsolutePos, vec2 Footprint) {
    vec2 P = AbsolutePos.xz - vec2(2.0, 0.8) * frameTimeCounter;
    float Threshold = CloudCoverageThreshold();
    vec3 BodyPos = vec3(P.x / 96.0, (AbsolutePos.y - CloudBottom) / 48.0, P.y / 96.0);
    float Body = SampleCloudBody(BodyPos, max(Footprint.x / 96.0, Footprint.y / 48.0));
    // The unread broad weather field is bounded by one.
    if (Body * 0.70 + 0.30 <= Threshold) return 0.0;
    float Weather = SampleAtmosphereNoise(P / 384.0 + vec2(17.3, 51.7), Footprint.x / 384.0);
    float Erosion = (1.0 - GetCloudHeightDensity(AbsolutePos.y)) * 0.20;
    float CloudShape = Body * 0.70 + Weather * 0.30 - Erosion;
    return smoothstep(Threshold, 0.72, CloudShape);
}

float GetCloudCoverage(vec2 AbsoluteXZ) {
    // Surface shadows approximate the column with the same mid-layer field.
    return GetCloudCoverageAtHeight(vec3(AbsoluteXZ.x, 227.0, AbsoluteXZ.y), vec2(0.0));
}

float GetCloudLayerDensity(vec3 AbsolutePos) {
    float HeightDensity = GetCloudHeightDensity(AbsolutePos.y);
    if (HeightDensity <= 0.0) return 0.0;
    return GetCloudCoverageAtHeight(AbsolutePos, vec2(0.0)) * HeightDensity;
}

// Evaluate the advected cell, not a screen-space pixelation of a smooth cloud.
// Footprint is used only by approximate shadows/reflections, not by the DDA.
float SampleBlockCloudCoverage(vec3 AbsolutePos, vec2 Footprint) {
    vec2 P = AbsolutePos.xz - vec2(2.0, 0.8) * frameTimeCounter;
    vec2 CellCenter = (floor(P / BlockCloudCellSize) + 0.5) * BlockCloudCellSize;
    float Body = SampleAtmosphereNoise(CellCenter / 96.0, Footprint.x / 96.0);
    float Weather = SampleAtmosphereNoise(CellCenter / 384.0 + vec2(17.3, 51.7), Footprint.x / 384.0);
    float Threshold = mix(0.51, 0.38, smoothstep(0.0, 1.0, rainStrength));
    float Shape = Body * 0.7 + Weather * 0.3;
    // A narrow transition lets weather change density before a cell becomes
    // opaque, while keeping its boundary a real, world-space block face.
    return smoothstep(Threshold, Threshold + 0.045, Shape);
}

float SampleStyledCloudCoverage(vec3 AbsolutePos, vec2 Footprint, bool Detail) {
#if CLOUD_STYLE == 0
    float Coverage = SampleBlockCloudCoverage(AbsolutePos, Footprint);
    if (!Detail || Coverage <= 0.0) return Coverage;
    vec2 P = AbsolutePos.xz - vec2(2.0, 0.8) * frameTimeCounter;
    float Texture = SampleCloudBody(vec3(P.x / 56.0, AbsolutePos.y / 24.0, P.y / 56.0),
                                   max(Footprint.x / 56.0, Footprint.y / 24.0));
    return Coverage * (0.78 + 0.22 * Texture);
#else
    float Coverage = GetCloudCoverageAtHeight(AbsolutePos, Footprint);
    // Shadow/reflection columns retain the broad mass at their lower cost.
    if (!Detail || Coverage <= 0.01 || Coverage >= 0.99) return Coverage;
    vec2 P = AbsolutePos.xz - vec2(2.0, 0.8) * frameTimeCounter;
    float Erosion = SampleCloudBody(vec3(P.x / 22.0, (AbsolutePos.y - CloudBottom) / 18.0, P.y / 22.0),
                                   max(Footprint.x / 22.0, Footprint.y / 18.0));
    return Coverage * smoothstep(0.06, 0.38, Coverage + Erosion * 0.30);
#endif
}

float CloudRampIntegral(float Height, float Lower, float Upper) {
    float T = clamp((Height - Lower) / (Upper - Lower), 0.0, 1.0);
    return max(Height - Upper, 0.0) + (Upper - Lower) * T * T * T * (1.0 - 0.5 * T);
}

float CloudColumnLengthAbove(float Height) {
    float Y = clamp(Height, CloudBottom, CloudTop);
    float FullColumn = CloudTop - CloudBottom -
                       0.5 * (CloudBottomFull - CloudBottom + CloudTop - CloudTopFull);
    float Below = CloudRampIntegral(Y, CloudBottom, CloudBottomFull) -
                  CloudRampIntegral(Y, CloudTopFull, CloudTop);
    return max(FullColumn - Below, 0.0);
}

#endif
