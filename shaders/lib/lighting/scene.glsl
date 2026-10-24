#ifndef IDA_LIGHTING_SCENE_GLSL
#define IDA_LIGHTING_SCENE_GLSL
#include "/lib/settings.glsl"
#include "/lib/lighting/shadow.glsl"
#include "/lib/materials/lighting/sky.glsl"
#include "/lib/lighting/surface.glsl"
#include "/lib/lighting/cloud_shadow.glsl"
#include "/lib/lighting/vegetation.glsl"
vec3 applySunDirectLight(
    vec3 color,
    vec3 normal,
    vec3 viewPos,
    vec3 worldPos,
    vec4 materialData,
    float shadow,
    float transmissionVisibility,
    float ssao,
    vec3 vanillaLight
) {
    MaterialLightingProfile profile = getMaterialLightingProfile(materialData);
    vec3 surfaceNormal = normalize(normal);
    vec3 viewDir = normalize(-viewPos);
    if (profile.transmissionScale > 0.0) surfaceNormal = vegetationFacingNormal(surfaceNormal, viewDir);
    vec3 lightDir = normalize(shadowLightPosition);
    vec3 lightDirWorld = viewToWorldNormal(lightDir, gbufferModelViewInverse);
    float sunlightStrength = directionalHeightStrength(lightDirWorld.y, nightValue);

    float roughness = adjustMaterialRoughness(materialData, getMaterialRoughness(materialData));
    float metallic = getMaterialMetallic(materialData);
    vec3 f0 = getMaterialF0(materialData, color);
    float materialAo = getMaterialAO(materialData) * ssao;
    float skyVisibility = getMaterialSkyVisibility(materialData);
    vec3 skyReflection = getMaterialSkyReflection(reflect(-viewDir, surfaceNormal), roughness);
    vec3 lightRadiance = getDirectionalLightRadiance(sunColor, nightValue) * sunlightStrength * DIRECT_LIGHT_STRENGTH;
    // Rain suppresses the directional source, including the backlit leaf term;
    // Lightmap, emission, sky fill and reflected sky keep their own budgets.
    lightRadiance *= weatherDirectFactor(rainStrength);
#if CLOUD_SHADOWS == 1
    bool needsDirectLight = dot(surfaceNormal, lightDir) > 0.0;
#if VEGETATION_TRANSMISSION == 1
    needsDirectLight = needsDirectLight || profile.transmissionScale > 0.0;
#endif
    if (profile.directScale > 0.0 && needsDirectLight && sunlightStrength > 0.0) {
        lightRadiance *= getSurfaceCloudVisibility(worldPos, lightDirWorld, skyVisibility);
    }
#endif
    SurfaceLightingResult lighting = evaluateSurfaceLighting(
        color,
        surfaceNormal,
        viewDir,
        lightDir,
        lightRadiance,
        skyColor * skyVisibility * SKY_AMBIENT_STRENGTH,
        skyReflection * skyVisibility * SKY_AMBIENT_STRENGTH,
        roughness,
        metallic,
        f0,
        materialAo,
        shadow,
        profile
    );
#if VEGETATION_TRANSMISSION == 1
    if (profile.transmissionScale > 0.0) {
        lighting.direct += evaluateVegetationTransmission(
            color, surfaceNormal, viewDir, lightDir, lightRadiance, f0, metallic,
            profile.transmissionScale, profile.directScale, skyVisibility, transmissionVisibility
        );
    }
#endif

    // Albedo stays unlit until here. Vanilla light is an ambient term only.
    // Lightmap includes block lights and is not suppressed by sky visibility.
    // Isotropic ambient approximation: dielectric diffuse or conductor F0.
    vec3 lightmapResponse = mix(color * (vec3(1.0) - f0), f0, metallic);
    vec3 ambient = lightmapResponse * vanillaLight * materialAo * profile.ambientScale * LIGHTMAP_STRENGTH;
    vec3 emission = color * profile.emissionStrength;
    return ambient + lighting.direct + lighting.ambient + emission;
}


#endif
