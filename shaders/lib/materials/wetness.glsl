#ifndef IDA_MATERIALS_WETNESS_GLSL
#define IDA_MATERIALS_WETNESS_GLSL
#include "/lib/settings.glsl"

#if SURFACE_WETNESS == 1
// These block IDs select a rain response. Optional puddles use spare opaque
// material IDs, preserving default lighting and static TAA.
// x: maximum linear-albedo loss, y: wet perceptual roughness before specular AA.
vec2 getWetnessProfile(float blockId) {
    if (blockId == 10096.0) return vec2(0.28, 0.70); // soil / moss: absorbent
    if (blockId == 10097.0) return vec2(0.22, 0.76); // sand / gravel: still granular
    if (blockId == 10098.0) return vec2(0.12, 0.38); // stone / masonry: broad sheen
    if (blockId == 10099.0) return vec2(0.18, 0.50); // wood: intermediate
    return vec2(0.0, 1.0); // opt in known surfaces, not snow, glass or metal blocks
}

#ifdef FRAGMENT_SHADER
#include "/lib/lighting/specular_aa.glsl"
uniform float surfaceWetness;

float rainExposure(float lightmapY, float normalUp) {
    // Raw, interpolated sky LIGHT LEVEL, not lightmap RGB or sunlight shadow.
    // It remains valid at night. Levels <=14 conservatively reject shelter;
    // interpolation towards level 15 softens eaves without quantized bands.
    // This is an approximation, not a vertical precipitation depth map.
    float skyLevel = clamp(lightmapY * 16.0 - 0.5, 0.0, 15.0);
    float skyExposure = smoothstep(14.0, 15.0, skyLevel);
    float sideExposure = mix(0.22, 1.0, smoothstep(0.0, 0.9, normalUp));
    float underside = smoothstep(-0.15, 0.0, normalUp);
    return skyExposure * sideExposure * underside;
}

vec2 wetSurfaceResponse(float dryRoughness, float normalVariance, vec2 profile,
                        float wetAmount, float metallic) {
    float amount = clamp(wetAmount, 0.0, 1.0);
    if (amount <= 0.0 || profile.x <= 0.0 || metallic > 0.5) return vec2(1.0, dryRoughness);
    // Refilter the target with the existing normal footprint. Mixing towards
    // an unfiltered target would undo specular AA on wet fine normal maps.
    // Already smooth LabPBR surfaces must never become rougher in rain.
    // Vanilla has zero normal variance: do not pay for two square roots.
    float filteredTarget = normalVariance > 0.0 ? filterSpecularRoughness(profile.y, normalVariance) : profile.y;
    float target = min(dryRoughness, filteredTarget);
    float colorLoss = profile.x * smoothstep(0.12, 0.65, dryRoughness);
    return vec2(1.0 - colorLoss * amount, mix(dryRoughness, target, amount));
}
#endif
#endif
#endif
