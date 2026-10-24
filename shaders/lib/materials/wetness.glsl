#ifndef IDA_MATERIALS_WETNESS_GLSL
#define IDA_MATERIALS_WETNESS_GLSL
#include "/lib/settings.glsl"

#if SURFACE_WETNESS == 1
// These block IDs select a rain response. Optional puddles use spare opaque
// material IDs, preserving default lighting and static TAA.
// x: maximum linear-albedo loss, y: wet perceptual roughness before specular AA.
vec2 GetWetnessProfile(float BlockId) {
    if (BlockId == 10096.0) return vec2(0.28, 0.70); // soil / moss: absorbent
    if (BlockId == 10097.0) return vec2(0.22, 0.76); // sand / gravel: still granular
    if (BlockId == 10098.0) return vec2(0.12, 0.38); // stone / masonry: broad sheen
    if (BlockId == 10099.0) return vec2(0.18, 0.50); // wood: intermediate
    return vec2(0.0, 1.0);                           // opt in known surfaces, not snow, glass or metal blocks
}

// =============================================================================
// Fragment Shader
// =============================================================================
#ifdef FRAGMENT_SHADER

#include "/lib/lighting/specular_aa.glsl"
uniform float surfaceWetness;

float RainExposure(float LightmapY, float NormalUp) {
    // Raw, interpolated sky LIGHT LEVEL, not lightmap RGB or sunlight shadow.
    // It remains valid at night. Levels <=14 conservatively reject shelter;
    // interpolation towards level 15 softens eaves without quantized bands.
    // This is an approximation, not a vertical precipitation depth map.
    float SkyLevel = clamp(LightmapY * 16.0 - 0.5, 0.0, 15.0);
    float SkyExposure = smoothstep(14.0, 15.0, SkyLevel);
    float SideExposure = mix(0.22, 1.0, smoothstep(0.0, 0.9, NormalUp));
    float Underside = smoothstep(-0.15, 0.0, NormalUp);
    return SkyExposure * SideExposure * Underside;
}

vec2 WetSurfaceResponse(float DryRoughness, float NormalVariance, vec2 Profile, float WetAmount, float Metallic) {
    float Amount = clamp(WetAmount, 0.0, 1.0);
    if (Amount <= 0.0 || Profile.x <= 0.0 || Metallic > 0.5) return vec2(1.0, DryRoughness);
    // Refilter the target with the existing normal footprint. Mixing towards
    // an unfiltered target would undo specular AA on wet fine normal maps.
    // Already smooth LabPBR surfaces must never become rougher in rain.
    // Vanilla has zero normal variance: do not pay for two square roots.
    float FilteredTarget = NormalVariance > 0.0 ? FilterSpecularRoughness(Profile.y, NormalVariance) : Profile.y;
    float Target = min(DryRoughness, FilteredTarget);
    float ColorLoss = Profile.x * smoothstep(0.12, 0.65, DryRoughness);
    return vec2(1.0 - ColorLoss * Amount, mix(DryRoughness, Target, Amount));
}
#endif
#endif
#endif
