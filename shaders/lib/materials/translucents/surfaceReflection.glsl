#ifndef IDA_MATERIALS_TRANSLUCENTS_SURFACE_REFLECTION_GLSL
#define IDA_MATERIALS_TRANSLUCENTS_SURFACE_REFLECTION_GLSL

#include "/lib/materials/lighting/sky.glsl"
#include "/lib/reflections/screenPlanar.glsl"

struct SmoothSurfaceReflectionProfile {
    float roughness;
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
    vec3 skyDisk = getSkyDiskRadiance(viewDir) * profile.skyDiskStrength;
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
    ReflectionResult reflection = createReflectionResult(
        fallbackColor,
        0.0,
        0.0,
        0.0
    );

    if (profile.planarVisibility > 0.0001) {
        reflection = resolveScreenPlanarReflection(
            worldPos,
            worldNormal,
            reflectDir,
            profile.roughness,
            profile.planarVisibility,
            fallbackColor
        );
    }

    vec3 finalColor = fallbackColor;
    float reflectionBlend = clamp(
        pow(max(reflection.mask, reflection.confidence), 0.8) * profile.reflectionVisibility,
        0.0,
        1.0
    );
    if (reflectionBlend > 0.0) {
        vec3 reflectedColor = reflection.color * profile.reflectionTint;
        float reflectedLuma = dot(reflectedColor, vec3(0.2126, 0.7152, 0.0722));
        reflectedColor = mix(vec3(reflectedLuma), reflectedColor, profile.reflectionSaturation);
        finalColor = mix(finalColor, reflectedColor, reflectionBlend);
    }

    float surfaceReflectivity = clamp(profile.reflectivity * mix(0.92, 1.08, reflectionBlend), 0.0, 1.0);
    finalColor = mix(baseColor, finalColor, surfaceReflectivity);
    finalColor += getSkyDiskRadiance(normalize(reflectDir)) * profile.sunGlareStrength * profile.reflectionTint;
    return finalColor;
}

#endif
