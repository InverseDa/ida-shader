#ifndef IDA_LIGHTING_DAYLIGHT_GLSL
#define IDA_LIGHTING_DAYLIGHT_GLSL

float weatherDirectFactor(float rainAmount) {
    return mix(1.0, 0.45, smoothstep(0.0, 1.0, rainAmount));
}

float directionalHeightStrength(float lightHeight, float nightAmount) {
    // Follow the actual world-space light elevation, not a noon-only clock
    // curve. The active sun/moon direction contributes nothing at the horizon.
    float horizon = smoothstep(0.0, 0.08, lightHeight);
    float dayStrength = mix(0.82, 1.32, smoothstep(0.08, 0.80, lightHeight));
    return horizon * mix(dayStrength, 0.82, clamp(nightAmount, 0.0, 1.0));
}

vec3 getDirectionalLightRadiance(vec3 sunLightColor, float nightAmount) {
    // The legacy sky tint table contains sRGB values >1 (2 becomes ~4.95 in
    // linear space). Preserve its hue, but do not use that sky-art gain as
    // surface irradiance. Clear noon and the existing moon radiance are kept.
    vec3 positiveColor = max(sunLightColor, vec3(0.0));
    float peak = max(positiveColor.r, max(positiveColor.g, positiveColor.b));
    vec3 sunRadiance = positiveColor / max(peak, 1.0) * 0.9;
    return mix(sunRadiance, vec3(0.12, 0.16, 0.28), clamp(nightAmount, 0.0, 1.0));
}

float cloudWeatherContrast(float rainAmount, float nightAmount) {
    // Rain already reduces the source. Avoid applying full clear-day cloud
    // contrast again to that weak source, particularly under moonlight.
    return weatherDirectFactor(rainAmount) * mix(1.0, 0.35, smoothstep(0.0, 1.0, nightAmount));
}

float vegetationWeatherWeight(float rainAmount, float nightAmount) {
    return mix(1.0, 0.65, smoothstep(0.0, 1.0, rainAmount)) *
           mix(1.0, 0.35, smoothstep(0.0, 1.0, nightAmount));
}

float surfaceAmbientShadowFloor(float rainAmount, float nightAmount) {
    // Only soften the extra shadow-map modulation of sky fill. SSAO/material
    // AO still occlude it; no new ambient light, Lightmap or emission boost.
    float diffuseWeather = max(smoothstep(0.0, 1.0, rainAmount), smoothstep(0.0, 1.0, nightAmount));
    return mix(0.70, 0.90, diffuseWeather);
}

#endif
