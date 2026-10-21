#ifndef IDA_LIGHTING_SCENE_GLSL
#define IDA_LIGHTING_SCENE_GLSL
#include "/lib/lighting/shadow.glsl"
#include "/lib/materials/lighting/sky.glsl"
#include "/lib/lighting/surface.glsl"
float getNoonLightFactor() {
    float dayDistance = abs(float(worldTime) - 6000.0) / 6000.0;
    return 1.0 - smoothstep(0.0, 1.0, clamp(dayDistance, 0.0, 1.0));
}

vec3 applySunDirectLight(
    vec3 color,
    vec3 normal,
    vec3 viewPos,
    vec4 materialData,
    float shadow,
    float ssao,
    vec3 vanillaLight
) {
    MaterialLightingProfile profile = getMaterialLightingProfile(materialData);
    vec3 surfaceNormal = normalize(normal);
    vec3 viewDir = normalize(-viewPos);
    vec3 lightDir = normalize(shadowLightPosition);
    float noonLight = getNoonLightFactor();
    float sunlightStrength = mix(0.82, 1.32, noonLight);

    float roughness = adjustMaterialRoughness(materialData, getMaterialRoughness(materialData));
    float metallic = getMaterialMetallic(materialData);
    float materialAo = getMaterialAO(materialData) * ssao;
    vec3 skyReflection = getSkyRadiance(reflect(-viewDir, surfaceNormal));
    vec3 lightRadiance = getDirectionalLightRadiance(sunColor, nightValue) * sunlightStrength;
    SurfaceLightingResult lighting = evaluateSurfaceLighting(
        color,
        surfaceNormal,
        viewDir,
        lightDir,
        lightRadiance,
        skyColor,
        skyReflection,
        roughness,
        metallic,
        materialAo,
        shadow,
        profile
    );

    // Albedo stays unlit until here. Vanilla light is an ambient term only.
    vec3 ambient = color * vanillaLight * materialAo * profile.ambientScale * 0.65;
    vec3 emission = color * profile.emissionStrength;
    return ambient + lighting.direct + lighting.ambient + emission;
}


#endif
