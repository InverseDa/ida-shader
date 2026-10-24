#ifndef IDA_LIGHTING_SURFACE_GLSL
#define IDA_LIGHTING_SURFACE_GLSL

#include "/lib/lighting/brdf.glsl"
#include "/lib/materials/materialLighting.glsl"
#include "/lib/lighting/daylight.glsl"

struct SurfaceLightingResult {
    vec3 direct;
    vec3 ambient;
};

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
    vec3 f0,
    float ao,
    float shadow,
    MaterialLightingProfile profile
) {
    SurfaceLightingResult result;
    vec3 surfaceNormal = normalize(normal);
    float NoV = clamp(dot(surfaceNormal, viewDir), 0.0, 1.0);
    vec3 ambientFresnel = FresnelSchlickRoughness(NoV, f0, roughness);
    vec3 kS = ambientFresnel;
    vec3 kD = (vec3(1.0) - kS) * (1.0 - metallic);
    vec3 ambientDiffuse = skyAmbientColor * albedo * kD;
    vec3 ambientSpecular = skyReflection * ambientFresnel * mix(0.82, 0.28, roughness);
    vec3 ambientLight = (ambientDiffuse + ambientSpecular) * 0.20 * ao;

    float combinedShadow = getShadowTone(shadow);
    float ambientShadow = mix(surfaceAmbientShadowFloor(rainStrength, nightValue), 1.0,
                              smoothstep(0.25, 1.0, combinedShadow));
    float directShadow = mix(combinedShadow, 1.0, profile.shadowLift * 0.18 * ao);
    result.direct = EvaluateDirectionalBRDF(
        albedo,
        surfaceNormal,
        viewDir,
        lightDir,
        lightRadiance,
        roughness,
        metallic,
        f0
    ) * directShadow * profile.directScale;
    result.ambient = ambientLight * profile.ambientScale * ambientShadow;
    return result;
}

#endif
