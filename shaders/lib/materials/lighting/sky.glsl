#ifndef IDA_MATERIALS_LIGHTING_SKY_GLSL
#define IDA_MATERIALS_LIGHTING_SKY_GLSL

float getSkyDirectionalBlend(vec3 viewDir, vec3 lightDir) {
    return clamp(1.0 - dot(normalize(viewDir), normalize(lightDir)), 0.0, 1.0);
}

vec3 getSunriseTint(float sunHeight) {
    return mix(vec3(1.35, 0.78, 0.30), sunColor, smoothstep(0.18, 0.60, sunHeight));
}

vec3 getSkyBaseRadiance(vec3 viewDir) {
    float dis2Sun = getSkyDirectionalBlend(viewDir, sunPosition);
    float dis2Moon = getSkyDirectionalBlend(viewDir, moonPosition);
    // fog with sun color mix
    float sunMixFactor = clamp(1.0 - dis2Sun, 0, 1) * (1.f - nightValue);
    vec3 finalColor = mix(skyColor, sunColor, pow(sunMixFactor, 6));
    // fog with moon color mix
    float moonMixFactor = clamp(1.0 - dis2Moon, 0, 1) * nightValue;
    finalColor = mix(finalColor, sunColor, pow(moonMixFactor, 5));

    return finalColor;
}

vec3 getSkyDiskRadiance(vec3 viewDir) {
    vec3 sunDir = normalize(sunPosition);
    vec3 moonDir = normalize(moonPosition);
    float dis2Sun = getSkyDirectionalBlend(viewDir, sunDir);
    float dis2Moon = getSkyDirectionalBlend(viewDir, moonDir);

    float sunHeight = clamp(sunDir.y * 0.5 + 0.5, 0.0, 1.0);
    float sunriseFade = mix(0.65, 0.95, smoothstep(0.25, 0.70, sunHeight));
    vec3 sunriseTint = getSunriseTint(sunHeight);
    float sunDisk = smoothstep(0.010, 0.0, dis2Sun) * sunriseFade * (1.0 - nightValue);
    float sunGlow = pow(clamp(1.0 - dis2Sun * 1.35, 0.0, 1.0), 5.0) * (1.0 - nightValue);
    sunGlow *= mix(0.28, 0.10, smoothstep(0.25, 0.75, sunHeight));
    float moonDisk = smoothstep(0.010, 0.0, dis2Moon) * 0.28 * nightValue;

    return sunriseTint * (sunDisk + sunGlow) + sunColor * moonDisk;
}

vec3 getSkyRadiance(vec3 viewDir) {
    return getSkyBaseRadiance(viewDir) + getSkyDiskRadiance(viewDir);
}

vec3 drawSky(vec3 color, vec3 viewPos, bool isSkySurface) {
    float dis = length(viewPos) / far;
    vec3 skyRadiance = getSkyRadiance(normalize(viewPos));

    if (isSkySurface) {
        float cloudMask = smoothstep(0.02, 0.16, max(color.r, max(color.g, color.b)));
        vec3 cloudColor = mix(color * 0.82, min(color * 1.24 + 0.08, vec3(1.0)), cloudMask);
        return mix(skyRadiance, mix(cloudColor, skyRadiance, 0.14), cloudMask);
    }

    float atmosphere = smoothstep(0.18, 1.0, dis);
    return mix(color, skyRadiance, clamp(pow(atmosphere, 2.2) * 0.72, 0, 1));
}

vec3 drawSky(vec3 color, vec3 viewPos) {
    return drawSky(color, viewPos, false);
}

#endif
