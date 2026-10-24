#ifndef IDA_MATERIALS_LIGHTING_SKY_GLSL
#define IDA_MATERIALS_LIGHTING_SKY_GLSL
#include "/lib/lighting/specular_aa.glsl"

float GetSkyDirectionalBlend(vec3 ViewDir, vec3 LightDir) {
    return clamp(1.0 - dot(normalize(ViewDir), normalize(LightDir)), 0.0, 1.0);
}

vec3 GetSunriseTint(float SunHeight) {
    return mix(vec3(1.35, 0.78, 0.30), SunColor, smoothstep(0.18, 0.60, SunHeight));
}

vec3 GetSkyBaseRadiance(vec3 ViewDir) {
    float Dis2Sun = GetSkyDirectionalBlend(ViewDir, sunPosition);
    float Dis2Moon = GetSkyDirectionalBlend(ViewDir, moonPosition);
    // fog with sun color mix
    float SunMixFactor = clamp(1.0 - Dis2Sun, 0, 1) * (1.F - NightValue);
    vec3 FinalColor = mix(SkyColor, SunColor, pow(SunMixFactor, 6));
    // fog with moon color mix
    float MoonMixFactor = clamp(1.0 - Dis2Moon, 0, 1) * NightValue;
    FinalColor = mix(FinalColor, SunColor, pow(MoonMixFactor, 5));

    return FinalColor;
}

vec3 GetFilteredSkyDiskRadiance(vec3 ViewDir, float Variance) {
    vec3 SunDir = normalize(sunPosition);
    vec3 MoonDir = normalize(moonPosition);
    float Dis2Sun = GetSkyDirectionalBlend(ViewDir, SunDir);
    float Dis2Moon = GetSkyDirectionalBlend(ViewDir, MoonDir);

    float SunHeight = clamp(ViewToWorldNormal(SunDir, gbufferModelViewInverse).y * 0.5 + 0.5, 0.0, 1.0);
    float SunriseFade = mix(0.65, 0.95, smoothstep(0.25, 0.70, SunHeight));
    vec3 SunriseTint = GetSunriseTint(SunHeight);
    float SunDisk = FilteredDisk(Dis2Sun, 0.0025, Variance) * SunriseFade * (1.0 - NightValue);
    float SunGlow = pow(clamp(1.0 - Dis2Sun * 7.0, 0.0, 1.0), 4.0) * (1.0 - NightValue);
    SunGlow *= mix(0.12, 0.045, smoothstep(0.25, 0.75, SunHeight));
    float MoonDisk = FilteredDisk(Dis2Moon, 0.0035, Variance) * 0.22 * NightValue;

    return SunriseTint * (SunDisk + SunGlow) + SunColor * MoonDisk;
}

vec3 GetSkyDiskRadiance(vec3 ViewDir) {
    return GetFilteredSkyDiskRadiance(ViewDir, 0.0);
}

vec3 GetMaterialSkyReflection(vec3 ViewDir, float Roughness) {
    // The material roughness already contains the pixel's normal variance.
    float Alpha = Roughness * Roughness;
    return GetSkyBaseRadiance(ViewDir) + GetFilteredSkyDiskRadiance(ViewDir, Alpha * Alpha * SPECULAR_AA);
}

vec3 GetSkyRadiance(vec3 ViewDir) {
    return GetSkyBaseRadiance(ViewDir) + GetSkyDiskRadiance(ViewDir);
}

vec3 DrawSky(vec3 Color, vec3 ViewPos, bool IsSkySurface) {
    float Dis = length(ViewPos) / far;
    vec3 SkyRadiance = GetSkyRadiance(normalize(ViewPos));

    if (IsSkySurface) {
        return SkyRadiance;
    }

    float Atmosphere = smoothstep(0.18, 1.0, Dis);
    return mix(Color, SkyRadiance, clamp(pow(Atmosphere, 2.2) * 0.72, 0, 1));
}

vec3 DrawSky(vec3 Color, vec3 ViewPos) {
    return DrawSky(Color, ViewPos, false);
}

#endif
