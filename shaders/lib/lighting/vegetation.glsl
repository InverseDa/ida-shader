#ifndef IDA_LIGHTING_VEGETATION_GLSL
#define IDA_LIGHTING_VEGETATION_GLSL

// ---- Vegetation ----

#include "/lib/settings.glsl"
#include "/lib/lighting/brdf.glsl"
#include "/lib/lighting/daylight.glsl"

vec3 VegetationFacingNormal(vec3 Normal, vec3 ViewDir)
{
    // Thin cutout faces may be drawn from either side. Use the visible side,
    // independently of mesh winding, for reflection and transmission together.
    return dot(Normal, ViewDir) < 0.0 ? -Normal : Normal;
}

#if VEGETATION_TRANSMISSION == 1
float VegetationTransmissionStrength(float TransmissionScale, float DirectScale)
{
    // Bound the peak relative to this material's unshadowed diffuse budget,
    // independent of albedo/exposure and even at the highest UI setting.
    float Strength = min(TransmissionScale * VEGETATION_TRANSMISSION_STRENGTH, 0.60 * DirectScale);

    return max(Strength, 0.0) * VegetationWeatherWeight(rainStrength, NightValue);
}

float VegetationTransmissionLobe(vec3 Normal, vec3 ViewDir, vec3 LightDir)
{
    float BackLight = max(-dot(Normal, LightDir), 0.0);
    float ForwardLight = max(dot(-ViewDir, LightDir), 0.0);
    float ForwardLobe = ForwardLight * ForwardLight;

    return BackLight * (0.35 + 0.65 * ForwardLobe * ForwardLobe);
}

vec3 EvaluateVegetationTransmission(vec3 Albedo, vec3 Normal, vec3 ViewDir, vec3 LightDir, vec3 LightRadiance, vec3 F0, float Metallic, float TransmissionScale, float DirectScale, float SkyVisibility, float LightVisibility)
{
    // Local thin-surface approximation: no thickness map, shadow bypass or
    // extra texture reads. Reuse unlifted PCF visibility so blockers still win.
    float Visibility = clamp(SkyVisibility, 0.0, 1.0) * clamp(LightVisibility, 0.0, 1.0);
    float Lobe = VegetationTransmissionLobe(Normal, ViewDir, LightDir);
    float Strength = VegetationTransmissionStrength(TransmissionScale, DirectScale);
    vec3 TransmittedAlbedo = Albedo * (vec3(1.0) - F0) * (1.0 - Metallic);

    return TransmittedAlbedo * LightRadiance *
           (Lobe * Strength * Visibility / PI);
}
#endif

#endif
