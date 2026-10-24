#ifndef IDA_MATERIALS_LIGHTING_SKY_GLSL
#define IDA_MATERIALS_LIGHTING_SKY_GLSL
#include "/lib/lighting/specular_aa.glsl"

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

vec3 getFilteredSkyDiskRadiance(vec3 viewDir, float variance) {
    vec3 sunDir = normalize(sunPosition);
    vec3 moonDir = normalize(moonPosition);
    float dis2Sun = getSkyDirectionalBlend(viewDir, sunDir);
    float dis2Moon = getSkyDirectionalBlend(viewDir, moonDir);

    float sunHeight = clamp(viewToWorldNormal(sunDir, gbufferModelViewInverse).y * 0.5 + 0.5, 0.0, 1.0);
    float sunriseFade = mix(0.65, 0.95, smoothstep(0.25, 0.70, sunHeight));
    vec3 sunriseTint = getSunriseTint(sunHeight);
    float sunDisk = filteredDisk(dis2Sun, 0.0025, variance) * sunriseFade * (1.0 - nightValue);
    float sunGlow = pow(clamp(1.0 - dis2Sun * 7.0, 0.0, 1.0), 4.0) * (1.0 - nightValue);
    sunGlow *= mix(0.12, 0.045, smoothstep(0.25, 0.75, sunHeight));
    float moonDisk = filteredDisk(dis2Moon, 0.0035, variance) * 0.22 * nightValue;

    return sunriseTint * (sunDisk + sunGlow) + sunColor * moonDisk;
}

vec3 getSkyDiskRadiance(vec3 viewDir) {
    return getFilteredSkyDiskRadiance(viewDir, 0.0);
}

vec3 getMaterialSkyReflection(vec3 viewDir, float roughness) {
    // The material roughness already contains the pixel's normal variance.
    float alpha = roughness * roughness;
    return getSkyBaseRadiance(viewDir) + getFilteredSkyDiskRadiance(viewDir, alpha * alpha * SPECULAR_AA);
}

vec3 getSkyRadiance(vec3 viewDir) {
    return getSkyBaseRadiance(viewDir) + getSkyDiskRadiance(viewDir);
}

vec3 drawSky(vec3 color, vec3 viewPos, bool isSkySurface) {
    float dis = length(viewPos) / far;
    vec3 skyRadiance = getSkyRadiance(normalize(viewPos));

    if (isSkySurface) {
        return skyRadiance;
    }

    float atmosphere = smoothstep(0.18, 1.0, dis);
    return mix(color, skyRadiance, clamp(pow(atmosphere, 2.2) * 0.72, 0, 1));
}

vec3 drawSky(vec3 color, vec3 viewPos) {
    return drawSky(color, viewPos, false);
}

#endif
