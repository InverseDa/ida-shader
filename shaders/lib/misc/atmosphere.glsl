#ifndef IDA_MISC_ATMOSPHERE_GLSL
#define IDA_MISC_ATMOSPHERE_GLSL

#include "/lib/misc/cloud_density.glsl"
#include "/lib/lighting/daylight.glsl"

float GetCloudShadow(float Height, float LightHeight, float Coverage) {
    // Local-column approximation: reuse this sample's coverage and integrate
    // the vertical profile analytically, instead of another 1-3 noise reads.
    float OpticalDepth = Coverage * CloudExtinction * CloudColumnLengthAbove(Height);
    float Direct = exp(-OpticalDepth / max(LightHeight, 0.16));
    float Scattered = exp(-OpticalDepth * 0.25);
    return Direct * 0.75 + Scattered * 0.25;
}

vec2 CloudRayInterval(vec3 OriginWorld, vec3 RayDir, float MaxDistance) {
    float T0 = 0.0;
    float T1 = min(MaxDistance, CloudMaxDistance);
    if (abs(RayDir.y) < 0.000001) {
        if (OriginWorld.y < CloudBottom || OriginWorld.y > CloudTop) return vec2(0.0);
    } else {
        T0 = (CloudBottom - OriginWorld.y) / RayDir.y;
        T1 = (CloudTop - OriginWorld.y) / RayDir.y;
    }
    float StartDistance = max(min(T0, T1), 0.0);
    float EndDistance = min(max(T0, T1), min(MaxDistance, CloudMaxDistance));
    return vec2(StartDistance, max(StartDistance, EndDistance));
}

float CloudDistanceWeight(float Distance) {
    return 1.0 - smoothstep(CloudFadeStart, CloudMaxDistance, Distance);
}

float CloudSamplePhase(vec2 Pixel) {
    // Spatially distributed strata soften the march's discrete sample planes.
    // Deliberately no frame index: a stationary view must not boil each frame.
    return 0.15 + 0.70 * fract(52.9829189 * fract(dot(Pixel, vec2(0.06711056, 0.00583715))));
}

#if CLOUD_STYLE == 0
#include "/lib/misc/block_clouds.glsl"
#endif

vec4 RenderVolumetricCloudsAtPhase(vec3 OriginWorld, vec3 RayDir, float MaxDistance, bool NeedColor, float Phase) {
    vec2 Interval = CloudRayInterval(OriginWorld, RayDir, MaxDistance);
    float Travel = Interval.y - Interval.x;
    if (Travel <= 0.0) return vec4(0.0);

    vec3 LightDir = vec3(0.0);
    vec3 CloudLight = vec3(0.0);
    vec3 Ambient = vec3(0.0);
    if (NeedColor) {
        LightDir = ViewToWorldNormal(normalize(shadowLightPosition), gbufferModelViewInverse);
        float SunFacing = clamp(dot(RayDir, LightDir), 0.0, 1.0);
        CloudLight = GetDirectionalLightRadiance(SunColor, NightValue) *
                     DirectionalHeightStrength(LightDir.y, NightValue) * WeatherDirectFactor(rainStrength);
        CloudLight *= 0.80 + 0.45 * pow(SunFacing, 4.0);
        float SkyLuma = dot(SkyColor, vec3(0.2126, 0.7152, 0.0722));
        Ambient = mix(vec3(SkyLuma), SkyColor, 0.35) * mix(0.65, 0.40, NightValue) *
                  mix(1.0, 0.75, rainStrength);
    }
    vec3 Accumulated = vec3(0.0);
    float Alpha = 0.0;
    float StepLength = Travel / float(CLOUD_SAMPLES);
    // Filter frequencies unresolved by the march or the screen pixel. Explicit
    // world footprints also work in forward / transmission-only branches.
    float PixelAngle = 2.0 / max(abs(gbufferProjection[1][1]) * viewHeight, 1.0);
    float PreviousColumn = CloudColumnLengthAbove(OriginWorld.y + RayDir.y * Interval.x);

    for (int I = 0; I < CLOUD_SAMPLES; ++I) {
        if (Alpha >= 0.995) break;
        float StepValue = (float(I) + Phase) / float(CLOUD_SAMPLES);
        float T = Interval.x + Travel * StepValue;
        vec3 AbsolutePos = OriginWorld + RayDir * T;
        float NextHeight = OriginWorld.y + RayDir.y * (Interval.x + float(I + 1) * StepLength);
        float NextColumn = CloudColumnLengthAbove(NextHeight);
        float HeightDensity = GetCloudHeightDensity(AbsolutePos.y);
        // Exact vertical-envelope integral over the stratum. Moving the sample
        // within it must not make a thin cloud entry gain/lose optical thickness.
        if (abs(RayDir.y) > 0.000001)
            HeightDensity = clamp(abs(NextColumn - PreviousColumn) / max(StepLength * abs(RayDir.y), 0.000001), 0.0, 1.0);
        PreviousColumn = NextColumn;
        vec2 Footprint = max(StepLength * vec2(length(RayDir.xz), abs(RayDir.y)), vec2(T * PixelAngle));
        float Coverage = SampleStyledCloudCoverage(AbsolutePos, Footprint, true);
        float Density = Coverage * HeightDensity * CloudDistanceWeight(T);
        if (Density > 0.0) {
            float StepAlpha = (1.0 - exp(-Density * CloudExtinction * StepLength)) * (1.0 - Alpha);
            // Emissive overlays only need transmission, not lit cloud color.
            if (NeedColor) {
                // One sample towards the light adds directional self-shadow,
                // instead of shading every cloud as a vertical uniform column.
                vec3 ShadowPosition = AbsolutePos + LightDir * 24.0;
                float ShadowCoverage = GetCloudCoverageAtHeight(ShadowPosition, vec2(8.0));
                float ShadowDensity = ShadowCoverage * GetCloudHeightDensity(ShadowPosition.y);
                float LocalDepth = (Coverage * GetCloudHeightDensity(AbsolutePos.y) + ShadowDensity) * 12.0 * CloudExtinction;
                float LightVisibility = GetCloudShadow(ShadowPosition.y, LightDir.y, ShadowCoverage) *
                                        (0.15 + 0.85 * exp(-LocalDepth));
                float HeightLight = smoothstep(CloudBottom, CloudTop, AbsolutePos.y);
                float Rim = pow(max(dot(RayDir, LightDir), 0.0), 8.0) * pow(1.0 - Coverage, 2.0) * 0.18;
                Accumulated += (Ambient * mix(0.62, 1.0, HeightLight) + CloudLight * (LightVisibility + Rim)) * StepAlpha;
            }
            Alpha += StepAlpha;
        }
    }

    vec3 CloudColor = Accumulated / max(Alpha, 0.0001);
    return vec4(CloudColor, clamp(Alpha, 0.0, 1.0));
}

vec4 RenderVolumetricClouds(vec3 OriginWorld, vec3 RayDir, float MaxDistance, bool NeedColor) {
#if CLOUD_STYLE == 0
    return RenderBlockClouds(OriginWorld, RayDir, MaxDistance, NeedColor);
#else
    return RenderVolumetricCloudsAtPhase(OriginWorld, RayDir, MaxDistance, NeedColor, CloudSamplePhase(IDA_ATMOSPHERE_PIXEL));
#endif
}

float AirFogAmount(float Distance, float OriginHeight, vec3 RayDir, bool IsSkySurface) {
    float RainFog = 1.0 + rainStrength * 2.15;
    float NightFog = mix(1.0, 1.32, NightValue);
    float HeightFog = mix(1.24, 0.76, smoothstep(70.0, 130.0, OriginHeight));
    float FogDensity = 0.00082 * RainFog * NightFog * HeightFog;
    float FogAmount = IsSkySurface ? smoothstep(0.02, 0.26, 1.0 - max(RayDir.y, 0.0)) * 0.028
                                   : 1.0 - exp(-Distance * FogDensity);

    return clamp(FogAmount, 0.0, 0.86);
}

#include "/lib/misc/godrays.glsl"
#include "/lib/misc/water_lighting.glsl"

vec3 ApplyAirHaze(vec3 Color, vec3 OriginWorld, vec3 RayDir, float Distance, bool IsSkySurface) {
    vec3 AirColor = GetSkyBaseRadiance(normalize(mat3(gbufferModelView) * RayDir));
    // Aerial haze integrates scattered light, rather than the saturated sky
    // pixel (or solar disk) behind a surface. Preserve luminance but soften
    // chroma so mid-distance foliage keeps its green in directional shade.
    float AirLuma = dot(AirColor, vec3(0.2126, 0.7152, 0.0722));
    AirColor = mix(vec3(AirLuma), AirColor, 0.35);
    // v0.1a night haze used the same colored sky/moon radiance as reflections.
    AirColor = mix(AirColor, GetSkyRadiance(normalize(mat3(gbufferModelView) * RayDir)), NightValue);
    AirColor = mix(AirColor, vec3(0.52, 0.58, 0.62), rainStrength * 0.42);
    return mix(Color, AirColor, AirFogAmount(Distance, OriginWorld.y, RayDir, IsSkySurface));
}

// Premultiplied scattering plus cloud opacity; independent of surface colour.
vec4 AirScattering(vec3 OriginWorld, vec3 RayDir, float MaxDistance) {
    vec3 SunShafts = isEyeInWater == 1 ? vec3(0.0) : RenderSunShafts(OriginWorld, RayDir, MaxDistance);
    // Most geometry is below the cloud slab. Do not enter the ray marcher
    // when the entire camera-to-surface segment is below or above it.
    float EndHeight = OriginWorld.y + RayDir.y * MaxDistance;
    if (max(OriginWorld.y, EndHeight) < CloudBottom || min(OriginWorld.y, EndHeight) > CloudTop) return vec4(SunShafts, 0.0);
    vec4 Clouds = RenderVolumetricClouds(OriginWorld, RayDir, MaxDistance, true);
    // Shafts integrate only foreground air up to the cloud base: clouds behind
    // that segment must not erase it. The underwater/additive paths skip it.
    return vec4(Clouds.rgb * Clouds.a + SunShafts, Clouds.a);
}

vec3 ApplyAirSegment(vec3 Color, vec3 OriginWorld, vec3 RayDir, float Distance, bool IsSkySurface) {
    vec3 Fogged = ApplyAirHaze(Color, OriginWorld, RayDir, Distance, IsSkySurface);
    vec4 Scattering = AirScattering(OriginWorld, RayDir, IsSkySurface ? CloudMaxDistance : max(Distance, 0.0));
    return Fogged * (1.0 - Scattering.a) + Scattering.rgb;
}

vec3 ApplyAtmosphere(vec3 Color, vec3 ViewPos, bool IsSkySurface) {
    if (isEyeInWater == 1) return ApplyUnderwaterMedium(Color, length(ViewPos)) +
                                RenderUnderwaterLight(ViewToWorldPos(ViewPos,gbufferModelViewInverse));
    vec3 RayDir = SafeNormal(ViewToWorldNormal(SafeNormal(ViewPos), gbufferModelViewInverse));
    return ApplyAirSegment(Color, cameraPosition, RayDir, length(ViewPos), IsSkySurface);
}

// Additive light is attenuated; adding in-scattering would paint fog over the
// background a second time. Used by eyes, glint and other additive overlays.
vec3 CameraMediumTransmittance(vec3 ViewPos) {
    if (isEyeInWater == 1) return WaterTransmittance(length(ViewPos));
    vec3 RayDir = SafeNormal(ViewToWorldNormal(SafeNormal(ViewPos), gbufferModelViewInverse));
    float Transmission = 1.0 - AirFogAmount(length(ViewPos), cameraPosition.y, RayDir, false);
    float EndHeight = cameraPosition.y + RayDir.y * length(ViewPos);
    if (max(cameraPosition.y, EndHeight) >= CloudBottom && min(cameraPosition.y, EndHeight) <= CloudTop)
        Transmission *= 1.0 - RenderVolumetricClouds(cameraPosition, RayDir, length(ViewPos), false).a;
    return vec3(Transmission);
}

#endif
