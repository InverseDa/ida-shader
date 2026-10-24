#ifndef IDA_LIGHTING_VEGETATION_GLSL
#define IDA_LIGHTING_VEGETATION_GLSL
#include "/lib/settings.glsl"
#include "/lib/lighting/brdf.glsl"
#include "/lib/lighting/daylight.glsl"

vec3 vegetationFacingNormal(vec3 normal, vec3 viewDir) {
    // Thin cutout faces may be drawn from either side. Use the visible side,
    // independently of mesh winding, for reflection and transmission together.
    return dot(normal, viewDir) < 0.0 ? -normal : normal;
}

#if VEGETATION_TRANSMISSION == 1
float vegetationTransmissionStrength(float transmissionScale, float directScale) {
    // Bound the peak relative to this material's unshadowed diffuse budget,
    // independent of albedo/exposure and even at the highest UI setting.
    float strength = min(transmissionScale * VEGETATION_TRANSMISSION_STRENGTH, 0.60 * directScale);
    return max(strength, 0.0) * vegetationWeatherWeight(rainStrength, nightValue);
}

float vegetationTransmissionLobe(vec3 normal, vec3 viewDir, vec3 lightDir) {
    float backLight = max(-dot(normal, lightDir), 0.0);
    float forwardLight = max(dot(-viewDir, lightDir), 0.0);
    float forwardLobe = forwardLight * forwardLight;
    return backLight * (0.35 + 0.65 * forwardLobe * forwardLobe);
}

vec3 evaluateVegetationTransmission(
    vec3 albedo, vec3 normal, vec3 viewDir, vec3 lightDir, vec3 lightRadiance,
    vec3 f0, float metallic, float transmissionScale, float directScale, float skyVisibility, float lightVisibility
) {
    // Local thin-surface approximation: no thickness map, shadow bypass or
    // extra texture reads. Reuse unlifted PCF visibility so blockers still win.
    float visibility = clamp(skyVisibility, 0.0, 1.0) * clamp(lightVisibility, 0.0, 1.0);
    float lobe = vegetationTransmissionLobe(normal, viewDir, lightDir);
    float strength = vegetationTransmissionStrength(transmissionScale, directScale);
    vec3 transmittedAlbedo = albedo * (vec3(1.0) - f0) * (1.0 - metallic);
    return transmittedAlbedo * lightRadiance *
           (lobe * strength * visibility / PI);
}
#endif

#endif
