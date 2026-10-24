#ifndef IDA_MATERIALS_TRANSLUCENTS_SURFACE_REFLECTION_GLSL
#define IDA_MATERIALS_TRANSLUCENTS_SURFACE_REFLECTION_GLSL

#include "/lib/materials/lighting/sky.glsl"
#include "/lib/reflections/screenPlanar.glsl"
#include "/lib/reflections/environment.glsl"
#include "/lib/reflections/temporal.glsl"

struct SmoothSurfaceReflectionProfile {
    float Roughness;
    float HighlightVariance;
    float Reflectivity;
    float ReflectionVisibility;
    float PlanarVisibility;
    float SkyDiskStrength;
    float SkyBrightness;
    float SunGlareStrength;
    vec3 ReflectionTint;
    float ReflectionSaturation;
    float HistoryKind;
};

SmoothSurfaceReflectionProfile CreateSmoothSurfaceReflectionProfile(float Roughness, float Reflectivity, float ReflectionVisibility, float PlanarVisibility, float SkyDiskStrength, float SkyBrightness, float SunGlareStrength, vec3 ReflectionTint, float ReflectionSaturation) {
    SmoothSurfaceReflectionProfile Profile;
    Profile.Roughness = Roughness;
    Profile.HighlightVariance = 0.0;
    Profile.Reflectivity = Reflectivity;
    Profile.ReflectionVisibility = ReflectionVisibility;
    Profile.PlanarVisibility = PlanarVisibility;
    Profile.SkyDiskStrength = SkyDiskStrength;
    Profile.SkyBrightness = SkyBrightness;
    Profile.SunGlareStrength = SunGlareStrength;
    Profile.ReflectionTint = ReflectionTint;
    Profile.ReflectionSaturation = ReflectionSaturation;
    Profile.HistoryKind = 1.0;
    return Profile;
}

vec3 GetSmoothSurfaceSkyReflection(vec3 ReflectDir, SmoothSurfaceReflectionProfile Profile) {
    vec3 ViewDir = normalize(ReflectDir);
    vec3 SkyBase = GetSkyScatteringRadiance(ViewDir, Profile.HighlightVariance);
    vec3 SkyDisk = GetFilteredSkyDiskRadiance(ViewDir, Profile.HighlightVariance) * Profile.SkyDiskStrength;
    vec3 Radiance = (SkyBase + SkyDisk) * Profile.SkyBrightness;
    float Luminance = dot(Radiance, vec3(0.2126, 0.7152, 0.0722));
    Radiance = mix(vec3(Luminance), Radiance, Profile.ReflectionSaturation);
    return Radiance * Profile.ReflectionTint;
}

vec4 GetSmoothSurfaceEnvironmentReflection(vec3 ReflectDir, vec3 WorldPos, SmoothSurfaceReflectionProfile Profile) {
    vec3 Sky = GetSkyScatteringRadiance(normalize(ReflectDir), Profile.HighlightVariance) +
               GetFilteredSkyDiskRadiance(normalize(ReflectDir), Profile.HighlightVariance) * Profile.SkyDiskStrength;
    vec4 Environment = SampleReflectionEnvironment(Sky, WorldPos, ReflectDir);
    vec3 FallbackColor = Environment.rgb * Profile.SkyBrightness;
    float FallbackLuma = dot(FallbackColor, vec3(0.2126, 0.7152, 0.0722));
    FallbackColor = mix(vec3(FallbackLuma), FallbackColor, Profile.ReflectionSaturation) * Profile.ReflectionTint;
    return vec4(FallbackColor, Environment.a);
}

vec3 ResolveSmoothSurfaceColor(vec3 BaseColor, vec3 WorldPos, vec3 ViewPos, vec3 WorldNormal, vec3 ReflectDir, SmoothSurfaceReflectionProfile Profile) {
    vec4 Environment = GetSmoothSurfaceEnvironmentReflection(ReflectDir, WorldPos, Profile);
    vec3 FallbackColor = Environment.rgb;
    ReflectionResult Reflection = CreateReflectionResult(FallbackColor, 0.0);
    float SurfaceReflectivity = clamp(Profile.Reflectivity, 0.0, 1.0);

    if (Profile.PlanarVisibility > 0.0001 && Profile.Reflectivity > 0.0 && Profile.ReflectionVisibility > 0.0) {
        Reflection = ResolveScreenPlanarReflection(WorldPos, WorldNormal, ReflectDir, Profile.Roughness, Profile.PlanarVisibility * Profile.ReflectionVisibility, SurfaceReflectivity, FallbackColor);
        Reflection = ResolveTemporalReflection(Reflection, ViewPos, WorldNormal, ReflectDir, Profile.HistoryKind);
    }

    vec3 FinalColor = FallbackColor;
    float ReflectionBlend = Reflection.Confidence;
    if (ReflectionBlend > 0.0) {
        vec3 ReflectedColor = Reflection.Color * Profile.ReflectionTint;
        float ReflectedLuma = dot(ReflectedColor, vec3(0.2126, 0.7152, 0.0722));
        ReflectedColor = mix(vec3(ReflectedLuma), ReflectedColor, Profile.ReflectionSaturation);
        FinalColor = mix(FinalColor, ReflectedColor, ReflectionBlend);
    }

    // Hit/miss confidence chooses scene versus sky, never the amount of base
    // color replaced by reflection. Fresnel/transmission keep the same budget.
    FinalColor = mix(BaseColor, FinalColor, SurfaceReflectivity);
    FinalColor += GetFilteredSkyDiskRadiance(normalize(ReflectDir), Profile.HighlightVariance) * Profile.SunGlareStrength * Profile.ReflectionTint * Environment.a;
    return FinalColor;
}

#endif
