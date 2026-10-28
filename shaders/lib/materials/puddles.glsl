#ifndef IDA_MATERIALS_PUDDLES_GLSL
#define IDA_MATERIALS_PUDDLES_GLSL

// ---- Puddles ----

#include "/lib/settings.glsl"

#if SURFACE_WETNESS == 1 && PUDDLE_REFLECTIONS == 1
#include "/lib/materials/wetness.glsl"
#include "/lib/reflections/puddle_trace.glsl"
#include "/lib/materials/lighting/sky.glsl"
#include "/lib/reflections/environment.glsl"

float PuddleRetention(vec4 Material)
{
    if (IsMaterial(Material, MaterialIdPuddleSoil))
    {
        return 0.78;
    }

    if (IsMaterial(Material, MaterialIdPuddleSand))
    {
        return 0.22;
    }

    if (IsMaterial(Material, MaterialIdPuddleStone))
    {
        return 1.0;
    }

    if (IsMaterial(Material, MaterialIdPuddleWood))
    {
        return 0.85;
    }

    return 0.0;
}

float PuddleExposure(float SkyVisibility, float ViewDistance)
{
    // Use geometric skylight metadata for shelter; reject distant ground before noise and SSR.
    float Sky = smoothstep(14.0 / 15.0, 1.0, SkyVisibility);

    return Sky * (1.0 - smoothstep(32.0, 64.0, ViewDistance));
}

vec2 PuddleNoiseUv(vec3 RelativeWorld)
{
    // 128px custom noise: one texel per 3 blocks, repeat every 384 blocks.
    // No time term: puddles grow in place, never swim with camera or wind.
    return (RelativeWorld + cameraPosition).xz / 384.0;
}

float PuddleCoverage(float NoiseValue, float WetAmount)
{
    float Wet = clamp(WetAmount, 0.0, 1.0);
    float Threshold = mix(0.86, 0.46, Wet);
    float Patch = smoothstep(Threshold, Threshold + 0.16, NoiseValue);

    return Patch * smoothstep(0.10, 0.75, Wet);
}

float PuddleReflectivity(float ViewCosine, float Coverage)
{
    // Air/water Fresnel: 2% face-on, increasing at grazing angles. The previous
    // 10% + cubic response turned a missed SSR hit into a broad pale overlay.
    float Grazing = 1.0 - clamp(ViewCosine, 0.0, 1.0);
    float Grazing2 = Grazing * Grazing;

    return clamp(Coverage, 0.0, 1.0) * (0.02 + 0.98 * Grazing2 * Grazing2 * Grazing);
}

vec3 ComposePuddleReflection(vec3 Base, vec3 Sky, vec3 Scene, float Confidence, float Reflectivity)
{
    // Confidence only selects scene versus sky; a lost hit cannot suddenly
    // remove the puddle or change the amount of base color it replaces.
    vec3 Reflected = mix(Sky, Scene, clamp(Confidence, 0.0, 1.0));

    return mix(Base, Reflected, clamp(Reflectivity, 0.0, 1.0));
}

vec3 DrawPuddleReflection(vec3 BaseColor, vec3 ViewPos, vec4 Material, float ViewVariance)
{
    float Retention = PuddleRetention(Material);

    if (Retention <= 0.0 || surfaceWetness <= 0.10 || SURFACE_WETNESS_STRENGTH <= 0.0)
    {
        return BaseColor;
    }

    // Do not reinterpret LabPBR metal pixels or a dry material's F0 as water.
    if (GetMaterialMetallic(Material) > 0.5)
    {
        return BaseColor;
    }

    float Exposure = PuddleExposure(GetMaterialSkyVisibility(Material), length(ViewPos));

    if (Exposure <= 0.0)
    {
        return BaseColor;
    }

    vec3 WorldPos = ViewToWorldPos(ViewPos, gbufferModelViewInverse);
    float WetAmount = surfaceWetness * SURFACE_WETNESS_STRENGTH;
    float NoiseValue = textureLod(noisetex, PuddleNoiseUv(WorldPos), 0.0).r;
    float Coverage = PuddleCoverage(NoiseValue, WetAmount) * Retention * Exposure;

    if (Coverage <= 0.0)
    {
        return BaseColor;
    }

    // A shallow pool has a level air/water interface, independent of the
    // underlying material's fine normal map. No extra normal texture reads.
    vec3 WorldNormal = vec3(0.0, 1.0, 0.0);
    vec3 NormalView = normalize(mat3(gbufferModelView) * WorldNormal);
    vec3 ViewDir = normalize(-ViewPos);
    vec3 ReflectDir = reflect(-ViewDir, NormalView);
    float Reflectivity = PuddleReflectivity(dot(NormalView, ViewDir), Coverage);
    float HighlightVariance = 0.0001 + ViewVariance;

    // Suppress the HDR sky disk during rain and at night, avoiding isolated
    // bright points in the fallback. Scene reflections keep their HDR values.
    vec3 Sky = mix(GetSkyScatteringRadiance(ReflectDir, HighlightVariance), SkyColor, clamp(rainStrength, 0.0, 1.0) * 0.75);
    Sky += GetFilteredSkyDiskRadiance(ReflectDir, HighlightVariance) *
           (1.0 - smoothstep(0.0, 1.0, rainStrength)) * (1.0 - NightValue) * 0.25;
    Sky = SampleReflectionEnvironment(Sky, WorldPos, ReflectDir).rgb;
    ReflectionResult Reflected = CreateReflectionResult(Sky, 0.0);

    // An almost invisible edge gets sky only, fading SSR in continuously.
    float SearchVisibility = smoothstep(0.01, 0.04, Reflectivity);

    if (SearchVisibility > 0.0)
    {
        Reflected = TracePuddleReflection(ViewPos, NormalView, ReflectDir, Sky);
        Reflected.Confidence *= SearchVisibility;
        Reflected = ResolveTemporalReflection(Reflected, ViewPos, WorldNormal, ReflectDir, 3.0);
    }

    return ComposePuddleReflection(BaseColor, Sky, Reflected.Color, Reflected.Confidence, Reflectivity);
}
#endif
#endif
