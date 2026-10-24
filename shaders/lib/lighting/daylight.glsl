#ifndef IDA_LIGHTING_DAYLIGHT_GLSL
#define IDA_LIGHTING_DAYLIGHT_GLSL

float WeatherDirectFactor(float RainAmount) {
    return mix(1.0, 0.45, smoothstep(0.0, 1.0, RainAmount));
}

float DirectionalHeightStrength(float LightHeight, float NightAmount) {
    // Follow the actual world-space light elevation, not a noon-only clock
    // curve. The active sun/moon direction contributes nothing at the horizon.
    float Horizon = smoothstep(0.0, 0.08, LightHeight);
    float DayStrength = mix(0.82, 1.32, smoothstep(0.08, 0.80, LightHeight));
    return Horizon * mix(DayStrength, 0.82, clamp(NightAmount, 0.0, 1.0));
}

vec3 GetDirectionalLightRadiance(vec3 SunLightColor, float NightAmount) {
    // The legacy sky tint table contains sRGB values >1 (2 becomes ~4.95 in
    // linear space). Preserve its hue, but do not use that sky-art gain as
    // irradiance. This shared source also illuminates clouds: keep its released
    // energy budget and apply the surface-only daylight adjustment separately.
    vec3 PositiveColor = max(SunLightColor, vec3(0.0));
    float Peak = max(PositiveColor.r, max(PositiveColor.g, PositiveColor.b));
    vec3 SunRadiance = PositiveColor / max(Peak, 1.0) * 0.9;
    return mix(SunRadiance, vec3(0.12, 0.16, 0.28), clamp(NightAmount, 0.0, 1.0));
}

float SurfaceSunlightGain(float RainAmount, float NightAmount) {
    // More surface contrast in clear daylight without overexposing clouds,
    // changing moonlight, or doubling the existing water sparkle treatment.
    float ClearDay = (1.0 - smoothstep(0.0, 1.0, RainAmount)) *
                     (1.0 - smoothstep(0.0, 1.0, NightAmount));
    return mix(1.0, 1.6, ClearDay);
}

float CloudWeatherContrast(float RainAmount, float NightAmount) {
    // Rain already reduces the source. Avoid applying full clear-day cloud
    // contrast again to that weak source, particularly under moonlight.
    return WeatherDirectFactor(RainAmount) * mix(1.0, 0.35, smoothstep(0.0, 1.0, NightAmount));
}

float VegetationWeatherWeight(float RainAmount, float NightAmount) {
    return mix(1.0, 0.65, smoothstep(0.0, 1.0, RainAmount)) *
           mix(1.0, 0.35, smoothstep(0.0, 1.0, NightAmount));
}

float SurfaceAmbientShadowFloor(float RainAmount, float NightAmount) {
    // Only soften the extra shadow-map modulation of sky fill. SSAO/material
    // AO still occlude it; no new ambient light, Lightmap or emission boost.
    float DiffuseWeather = max(smoothstep(0.0, 1.0, RainAmount), smoothstep(0.0, 1.0, NightAmount));
    return mix(0.85, 0.90, DiffuseWeather);
}

#endif
