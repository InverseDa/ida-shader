#ifndef IDA_WATER_MEDIUM_GLSL
#define IDA_WATER_MEDIUM_GLSL
uniform int isEyeInWater;
uniform int worldTime;
uniform ivec2 eyeBrightnessSmooth;
uniform vec3 fogColor;
uniform float nightVision;

// Extinction per block. Red light is absorbed faster than green and blue.
const vec3 WaterExtinction = vec3(0.20, 0.070, 0.030);
vec3 WaterTransmittance(float Distance) {
    return exp(-WaterExtinction * clamp(Distance, 0.0, 512.0));
}

vec3 WaterScatterColor() {
    vec3 Biome = SrgbToLinear(max(fogColor, vec3(0.0)));
    float Peak = max(Biome.r, max(Biome.g, Biome.b));
    vec3 Tint = vec3(0.025, 0.14, 0.20);
    if (Peak > 0.0001) Tint = mix(Tint, Biome / Peak * 0.20, 0.55);
    vec2 Light = clamp(vec2(eyeBrightnessSmooth) / 240.0, vec2(0.0), vec2(1.0));
    float Night = clamp((float(worldTime) - 12000.0) / 1000.0, 0.0, 1.0) *
                  (1.0 - clamp((float(worldTime) - 23000.0) / 1000.0, 0.0, 1.0));
    float Illumination = 0.025 + Light.y * mix(1.0, 0.12, Night) + Light.x * 0.25;
    Illumination = mix(Illumination, max(Illumination, 0.85), clamp(nightVision, 0.0, 1.0));
    return Tint * Illumination;
}

vec3 ApplyUnderwaterMedium(vec3 Radiance, float Distance) {
    vec3 Transmittance = WaterTransmittance(Distance);
    return Radiance * Transmittance + WaterScatterColor() * (vec3(1.0) - Transmittance);
}

// Exact unpolarized dielectric Fresnel, including water-to-air total reflection.
float WaterFresnel(float Cosine, float Eta) {
    float Ci = clamp(Cosine, 0.0, 1.0);
    float TransmittedSinSquared = Eta * Eta * (1.0 - Ci * Ci);
    if (TransmittedSinSquared >= 1.0) return 1.0;
    float Ct = sqrt(max(1.0 - TransmittedSinSquared, 0.0));
    float Rs = (Eta * Ci - Ct) / max(Eta * Ci + Ct, 0.00001);
    float Rp = (Ci - Eta * Ct) / max(Ci + Eta * Ct, 0.00001);
    return clamp(0.5 * (Rs * Rs + Rp * Rp), 0.0, 1.0);
}
#endif
