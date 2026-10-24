#ifndef IDA_MATERIALS_TRANSLUCENTS_SURFACE_REFLECTION_GLSL
#define IDA_MATERIALS_TRANSLUCENTS_SURFACE_REFLECTION_GLSL

#include "/lib/materials/lighting/sky.glsl"
#include "/lib/reflections/screenPlanar.glsl"

struct SmoothSurfaceReflectionProfile {
    float roughness;
    float highlightVariance;
    float reflectivity;
    float reflectionVisibility;
    float planarVisibility;
    float skyDiskStrength;
    float skyBrightness;
    float sunGlareStrength;
    vec3 reflectionTint;
    float reflectionSaturation;
};

SmoothSurfaceReflectionProfile createSmoothSurfaceReflectionProfile(
    float roughness,
    float reflectivity,
    float reflectionVisibility,
    float planarVisibility,
    float skyDiskStrength,
    float skyBrightness,
    float sunGlareStrength,
    vec3 reflectionTint,
    float reflectionSaturation
) {
    SmoothSurfaceReflectionProfile profile;
    profile.roughness = roughness;
    profile.highlightVariance = 0.0;
    profile.reflectivity = reflectivity;
    profile.reflectionVisibility = reflectionVisibility;
    profile.planarVisibility = planarVisibility;
    profile.skyDiskStrength = skyDiskStrength;
    profile.skyBrightness = skyBrightness;
    profile.sunGlareStrength = sunGlareStrength;
    profile.reflectionTint = reflectionTint;
    profile.reflectionSaturation = reflectionSaturation;
    return profile;
}

vec3 getSmoothSurfaceSkyReflection(vec3 reflectDir, SmoothSurfaceReflectionProfile profile) {
    vec3 viewDir = normalize(reflectDir);
    vec3 skyBase = getSkyBaseRadiance(viewDir);
    vec3 skyDisk = getFilteredSkyDiskRadiance(viewDir, profile.highlightVariance) * profile.skyDiskStrength;
    vec3 radiance = (skyBase + skyDisk) * profile.skyBrightness;
    float luminance = dot(radiance, vec3(0.2126, 0.7152, 0.0722));
    radiance = mix(vec3(luminance), radiance, profile.reflectionSaturation);
    return radiance * profile.reflectionTint;
}

vec3 resolveSmoothSurfaceColor(
    vec3 baseColor,
    vec3 worldPos,
    vec3 viewPos,
    vec3 worldNormal,
    vec3 reflectDir,
    SmoothSurfaceReflectionProfile profile
) {
    vec3 fallbackColor = getSmoothSurfaceSkyReflection(reflectDir, profile);
    ReflectionResult reflection = createReflectionResult(fallbackColor, 0.0);
    float surfaceReflectivity = clamp(profile.reflectivity, 0.0, 1.0);

    if (profile.planarVisibility > 0.0001 && profile.reflectivity > 0.0 &&
        profile.reflectionVisibility > 0.0) {
        reflection = resolveScreenPlanarReflection(
            worldPos,
            worldNormal,
            reflectDir,
            profile.roughness,
            profile.planarVisibility * profile.reflectionVisibility,
            surfaceReflectivity,
            fallbackColor
        );
    }

    vec3 finalColor = fallbackColor;
    float reflectionBlend = reflection.confidence;
    if (reflectionBlend > 0.0) {
        vec3 reflectedColor = reflection.color * profile.reflectionTint;
        float reflectedLuma = dot(reflectedColor, vec3(0.2126, 0.7152, 0.0722));
        reflectedColor = mix(vec3(reflectedLuma), reflectedColor, profile.reflectionSaturation);
        finalColor = mix(finalColor, reflectedColor, reflectionBlend);
    }

    // Hit/miss confidence chooses scene versus sky, never the amount of base
    // color replaced by reflection. Fresnel/transmission keep the same budget.
    finalColor = mix(baseColor, finalColor, surfaceReflectivity);
    finalColor += getFilteredSkyDiskRadiance(normalize(reflectDir), profile.highlightVariance) * profile.sunGlareStrength * profile.reflectionTint;
    return finalColor;
}

#endif
