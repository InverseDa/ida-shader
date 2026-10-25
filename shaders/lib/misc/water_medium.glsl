#ifndef IDA_WATER_MEDIUM_GLSL
#define IDA_WATER_MEDIUM_GLSL
uniform int isEyeInWater;
uniform int worldTime;
uniform ivec2 eyeBrightnessSmooth;
uniform vec3 fogColor;
uniform float nightVision;

// Both surface transmission and scattering follow the interpolated biome tint.
// Keep shallow water clear and avoid imposing blue absorption on green/brown biomes.
vec3 WaterBiomeTint(vec3 BiomeColor) {
    vec3 Biome=sqrt(SrgbToLinear(clamp(BiomeColor,0.0,1.0)));
    float Luma=dot(Biome,vec3(0.2126,0.7152,0.0722));
    return mix(vec3(Luma),Biome,0.70)*0.16;
}
vec3 WaterBiomeExtinction(vec3 BiomeColor) {
    vec3 Biome=SrgbToLinear(clamp(BiomeColor,0.0,1.0));
    float Peak=max(Biome.r,max(Biome.g,Biome.b));
    return vec3(0.035)+0.065*(vec3(1.0)-Biome/max(Peak,0.001));
}
vec3 WaterBiomeTransmittance(float Distance, vec3 BiomeColor) {
    return exp(-WaterBiomeExtinction(BiomeColor)*clamp(Distance,0.0,512.0));
}
vec3 WaterTransmittance(float Distance) {
    // fogColor is an underwater biome color only while the camera is immersed.
    // Air-side callers needing local water color pass vertex tint explicitly.
    vec3 Extinction=vec3(0.065,0.055,0.045);
    if (isEyeInWater==1) Extinction=WaterBiomeExtinction(fogColor);
    return exp(-Extinction*clamp(Distance,0.0,512.0));
}

vec3 WaterScatterColor() {
    vec3 Tint = WaterBiomeTint(fogColor);
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
