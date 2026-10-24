#ifndef IDA_LIGHTING_SURFACE_GLSL
#define IDA_LIGHTING_SURFACE_GLSL

#include "/lib/lighting/brdf.glsl"
#include "/lib/materials/materialLighting.glsl"
#include "/lib/lighting/daylight.glsl"

struct SurfaceLightingResult {
    vec3 Direct;
    vec3 Ambient;
};

float GetShadowTone(float Shadow) {
    return clamp(Shadow, 0.0, 1.0);
}

SurfaceLightingResult EvaluateSurfaceLighting(vec3 Albedo, vec3 Normal, vec3 ViewDir, vec3 LightDir, vec3 LightRadiance, vec3 SkyAmbientColor, vec3 SkyReflection, float Roughness, float Metallic, vec3 F0, float Ao, float Shadow, MaterialLightingProfile Profile) {
    SurfaceLightingResult Result;
    vec3 SurfaceNormal = normalize(Normal);
    float NoV = clamp(dot(SurfaceNormal, ViewDir), 0.0, 1.0);
    vec3 AmbientFresnel = FresnelSchlickRoughness(NoV, F0, Roughness);
    vec3 KS = AmbientFresnel;
    vec3 KD = (vec3(1.0) - KS) * (1.0 - Metallic);
    vec3 AmbientDiffuse = SkyAmbientColor * Albedo * KD;
    vec3 AmbientSpecular = SkyReflection * AmbientFresnel * mix(0.82, 0.28, Roughness);
    vec3 AmbientLight = (AmbientDiffuse + AmbientSpecular) * 0.20 * Ao;

    float CombinedShadow = GetShadowTone(Shadow);
    float AmbientShadow = mix(SurfaceAmbientShadowFloor(rainStrength, NightValue), 1.0, smoothstep(0.25, 1.0, CombinedShadow));
    // A fully blocked directional source contributes no direct light.
    // Sky/Lightmap ambient retain detail without leaking sunlight into shade.
    float DirectShadow = CombinedShadow;
    Result.Direct = EvaluateDirectionalBRDF(Albedo, SurfaceNormal, ViewDir, LightDir, LightRadiance, Roughness, Metallic, F0) *
                    DirectShadow * Profile.DirectScale;
    Result.Ambient = AmbientLight * Profile.AmbientScale * AmbientShadow;
    return Result;
}

#endif
