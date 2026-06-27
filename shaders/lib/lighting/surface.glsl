#ifndef IDA_LIGHTING_SURFACE_GLSL
#define IDA_LIGHTING_SURFACE_GLSL

#include "/lib/lighting/brdf.glsl"
#include "/lib/materials/materialLighting.glsl"

struct SurfaceLightingResult {
    vec3 direct;
    vec3 ambient;
};

vec3 getDirectionalLightRadiance(vec3 sunLightColor, float nightValue) {
    return mix(sunLightColor * 0.9, vec3(0.12, 0.16, 0.28), nightValue);
}

float getShadowTone(float shadow) {
    return clamp(1.0 - (1.0 - shadow) * 1.28, 0.0, 1.0);
}

SurfaceLightingResult evaluateSurfaceLighting(
    vec3 albedo,
    vec3 normal,
    vec3 viewDir,
    vec3 lightDir,
    vec3 lightRadiance,
    vec3 skyAmbientColor,
    vec3 skyReflection,
    float roughness,
    float metallic,
    float ao,
    float shadow,
    MaterialLightingProfile profile
) {
    SurfaceLightingResult result;
    vec3 surfaceNormal = normalize(normal);
    float NoV = max(dot(surfaceNormal, viewDir), 0.0);
    vec3 f0 = mix(vec3(0.04), albedo, metallic);
    vec3 ambientFresnel = FresnelSchlickRoughness(NoV, f0, roughness);
    vec3 kS = ambientFresnel;
    vec3 kD = (vec3(1.0) - kS) * (1.0 - metallic);
    vec3 ambientDiffuse = skyAmbientColor * albedo * kD;
    vec3 ambientSpecular = skyReflection * ambientFresnel * mix(0.82, 0.28, roughness);
    vec3 ambientLight = (ambientDiffuse + ambientSpecular) * (0.08 + 0.12 * ao);

    float combinedShadow = getShadowTone(shadow);
    float ambientShadow = mix(0.70, 1.0, smoothstep(0.25, 1.0, combinedShadow));
    float directShadow = mix(combinedShadow, 1.0, profile.shadowLift * 0.18 * ao);
    result.direct = EvaluateDirectionalBRDF(
        albedo,
        surfaceNormal,
        viewDir,
        lightDir,
        lightRadiance,
        roughness,
        metallic
    ) * directShadow * profile.directScale;
    result.ambient = ambientLight * profile.ambientScale * ambientShadow;
    return result;
}

#endif
