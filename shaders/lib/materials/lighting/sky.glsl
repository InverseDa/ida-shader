#ifndef IDA_MATERIALS_LIGHTING_SKY_GLSL
#define IDA_MATERIALS_LIGHTING_SKY_GLSL

// ---- Sky ----

#include "/lib/lighting/specular_aa.glsl"

float GetSkyDirectionalBlend(vec3 ViewDir, vec3 LightDir)
{
    return clamp(1.0 - dot(normalize(ViewDir), normalize(LightDir)), 0.0, 1.0);
}

vec3 GetSunriseTint(float SunElevation)
{
    // v0.1a keeps the time-table solar tint, including its HDR warmth at
    // /time set day. An elevation-only fade to white erased that yellow glow.
    float SunHeight = clamp(SunElevation * 0.5 + 0.5, 0.0, 1.0);

    return mix(vec3(1.35, 0.78, 0.30), SunColor, smoothstep(0.18, 0.60, SunHeight));
}

vec3 GetSkyBaseRadiance(vec3 ViewDir)
{
    vec3 Direction = normalize(ViewDir);
    vec3 WorldDirection = ViewToWorldNormal(Direction, gbufferModelViewInverse);
    vec3 SunDirection = normalize(sunPosition);
    float SunElevation = ViewToWorldNormal(SunDirection, gbufferModelViewInverse).y;
    float Horizon = 1.0 - smoothstep(0.0, 0.50, max(WorldDirection.y, 0.0));
    float SkyLuma = dot(SkyColor, vec3(0.2126, 0.7152, 0.0722));

    // Derived from the same vanilla sky: fogColor becomes a water/lava color
    // when immersed and must not recolor the reflected air-side sky.
    vec3 HorizonColor = SkyColor * 0.75 + vec3(SkyLuma) * 0.55;
    vec3 Base = mix(SkyColor, HorizonColor, Horizon * 0.65);
    float Twilight = (1.0 - smoothstep(0.02, 0.22, abs(SunElevation))) *
                     smoothstep(-0.12, 0.02, SunElevation) * (1.0 - rainStrength);
    float FacingSun = pow(max(dot(Direction, SunDirection), 0.0), 4.0);
    Base = mix(Base, vec3(0.62, 0.20, 0.065), Twilight * Horizon * FacingSun * 0.55);

    // Keep the engine sky palette linear for fog and reflections; expose and tone-map only at output.
    // Night restores the cyan/moon gradient as the daytime horizon fades.
    Base = mix(Base, SkyColor, NightValue);
    float MoonMixFactor = clamp(dot(Direction, normalize(moonPosition)), 0.0, 1.0) * NightValue;

    return mix(Base, SunColor, pow(MoonMixFactor, 5.0));
}

vec3 GetSkyScatteringRadiance(vec3 ViewDir, float Variance)
{
    vec3 Direction = normalize(ViewDir);
    vec3 SunDir = normalize(sunPosition);
    float SunElevation = ViewToWorldNormal(SunDir, gbufferModelViewInverse).y;
    float WeatherVisibility = mix(1.0, 0.08, smoothstep(0.0, 1.0, rainStrength));
    float SunVisibility = smoothstep(-0.08, 0.02, SunElevation);

    // Keep the broad solar gradient in visible/reflected sky; rough reflections still filter peaks.
    float SunHalo = FilteredHighlight(dot(Direction, SunDir), 6.0, Variance);
    SunHalo *= pow(1.0 - NightValue, 6.0) * SunVisibility * WeatherVisibility;
    vec3 Radiance = GetSkyBaseRadiance(Direction);
    Radiance = mix(Radiance, SunColor, SunHalo);

    // Daytime haze excludes this solar halo. At night the base already carries
    // the released moon gradient; clouds attenuate the sky in ApplyAirSegment.
    return Radiance;
}

vec3 GetFilteredSkyDiskRadiance(vec3 ViewDir, float Variance)
{
    vec3 SunDir = normalize(sunPosition);
    vec3 MoonDir = normalize(moonPosition);
    float Dis2Sun = GetSkyDirectionalBlend(ViewDir, SunDir);
    float Dis2Moon = GetSkyDirectionalBlend(ViewDir, MoonDir);

    float SunElevation = ViewToWorldNormal(SunDir, gbufferModelViewInverse).y;
    float SunHeight = clamp(SunElevation * 0.5 + 0.5, 0.0, 1.0);
    float SunriseFade = mix(0.65, 0.95, smoothstep(0.25, 0.70, SunHeight));
    vec3 SunriseTint = GetSunriseTint(SunElevation);
    float SunDisk = FilteredDisk(Dis2Sun, 0.0025, Variance) * SunriseFade *
                    smoothstep(-0.08, 0.02, SunElevation) * (1.0 - NightValue);
    float SunGlow = pow(clamp(1.0 - Dis2Sun * 7.0, 0.0, 1.0), 4.0) * (1.0 - NightValue);
    SunGlow *= mix(0.12, 0.045, smoothstep(0.25, 0.75, SunHeight)) * smoothstep(-0.08, 0.02, SunElevation);
    float MoonDisk = FilteredDisk(Dis2Moon, 0.0035, Variance) * 0.22 * NightValue;

    float WeatherVisibility = mix(1.0, 0.08, smoothstep(0.0, 1.0, rainStrength));

    return SunriseTint * (SunDisk + SunGlow) * WeatherVisibility + SunColor * MoonDisk;
}

vec3 GetSkyDiskRadiance(vec3 ViewDir)
{
    return GetFilteredSkyDiskRadiance(ViewDir, 0.0);
}

vec3 GetMaterialSkyReflection(vec3 ViewDir, float Roughness)
{
    // The material roughness already contains the pixel's normal variance.
    float Alpha = Roughness * Roughness;
    float Variance = Alpha * Alpha * SPECULAR_AA;

    return GetSkyScatteringRadiance(ViewDir, Variance) + GetFilteredSkyDiskRadiance(ViewDir, Variance);
}

vec3 GetSkyRadiance(vec3 ViewDir)
{
    return GetSkyScatteringRadiance(ViewDir, 0.0) + GetSkyDiskRadiance(ViewDir);
}

vec3 DrawSky(vec3 Color, vec3 ViewPos, bool bIsSkySurface)
{
    float Dis = length(ViewPos) / far;
    vec3 SkyRadiance = GetSkyRadiance(normalize(ViewPos));

    if (bIsSkySurface)
    {
        return SkyRadiance;
    }

    float Atmosphere = smoothstep(0.18, 1.0, Dis);

    return mix(Color, SkyRadiance, clamp(pow(Atmosphere, 2.2) * 0.72, 0, 1));
}

vec3 DrawSky(vec3 Color, vec3 ViewPos)
{
    return DrawSky(Color, ViewPos, false);
}

#endif
