#ifndef IDA_WATER_MEDIUM_GLSL
#define IDA_WATER_MEDIUM_GLSL
uniform int isEyeInWater;
uniform int worldTime;
uniform ivec2 eyeBrightnessSmooth;
uniform vec3 fogColor;
uniform float nightVision;

// Extinction per block. Red light is absorbed faster than green and blue.
const vec3 WATER_EXTINCTION = vec3(0.20, 0.070, 0.030);
vec3 waterTransmittance(float distance) {
    return exp(-WATER_EXTINCTION * clamp(distance, 0.0, 512.0));
}

vec3 waterScatterColor() {
    vec3 biome = srgbToLinear(max(fogColor, vec3(0.0)));
    float peak = max(biome.r, max(biome.g, biome.b));
    vec3 tint = vec3(0.025, 0.14, 0.20);
    if (peak > 0.0001) tint = mix(tint, biome / peak * 0.20, 0.55);
    vec2 light = clamp(vec2(eyeBrightnessSmooth) / 240.0, vec2(0.0), vec2(1.0));
    float night = clamp((float(worldTime) - 12000.0) / 1000.0, 0.0, 1.0) *
                  (1.0 - clamp((float(worldTime) - 23000.0) / 1000.0, 0.0, 1.0));
    float illumination = 0.025 + light.y * mix(1.0, 0.12, night) + light.x * 0.25;
    illumination = mix(illumination, max(illumination, 0.85), clamp(nightVision, 0.0, 1.0));
    return tint * illumination;
}

vec3 applyUnderwaterMedium(vec3 radiance, float distance) {
    vec3 transmittance = waterTransmittance(distance);
    return radiance * transmittance + waterScatterColor() * (vec3(1.0) - transmittance);
}

// Exact unpolarized dielectric Fresnel, including water-to-air total reflection.
float waterFresnel(float cosine, float eta) {
    float ci = clamp(cosine, 0.0, 1.0);
    float transmittedSinSquared = eta * eta * (1.0 - ci * ci);
    if (transmittedSinSquared >= 1.0) return 1.0;
    float ct = sqrt(max(1.0 - transmittedSinSquared, 0.0));
    float rs = (eta * ci - ct) / max(eta * ci + ct, 0.00001);
    float rp = (ci - eta * ct) / max(ci + eta * ct, 0.00001);
    return clamp(0.5 * (rs * rs + rp * rp), 0.0, 1.0);
}
#endif
