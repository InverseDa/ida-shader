#include "/lib/materials/translucents/surfaceReflection.glsl"
#include "/lib/materials/translucents/water_waves.glsl"
#include "/lib/materials/translucents/shore_foam.glsl"
#include "/lib/lighting/daylight.glsl"

float GetWaterThickness(vec3 ViewPos, vec3 ViewPosBehind) {
    float WaterDepth = max(length(ViewPosBehind) - length(ViewPos), 0.0);
    return clamp(WaterDepth, 0.0, 512.0);
}

vec3 SampleRefractedSceneColor(vec2 ScreenUv, float SurfaceDepth, vec3 NormalView, float WaterDepth, float WaveSlope) {
    float RefractionStrength = (0.007 + 0.025 * WaveSlope) * (1.0 - exp(-WaterDepth * 0.18));
    vec2 Distortion = NormalView.xy * RefractionStrength;
    vec2 Texel = vec2(1.0 / viewWidth, 1.0 / viewHeight);
    vec2 Uv = OpaqueUvForUnjitteredUv(ScreenUv + Distortion);
    // Do not refract foreground objects across a silhouette.
    if (SampleOpaqueData(Uv).b < SurfaceDepth) Uv = OpaqueUvForUnjitteredUv(ScreenUv);
    vec3 CenterColor = texture2D(colortex9, Uv).rgb;
    float Weight = 1.0;
    for (int I = -1; I <= 1; I += 2) {
        vec2 TapUv = clamp(Uv + vec2(float(I) * Texel.x, 0.0), Texel * 0.5, vec2(1.0) - Texel * 0.5);
        if (SampleOpaqueData(TapUv).b >= SurfaceDepth) {
            CenterColor += texture2D(colortex9, TapUv).rgb * 0.18;
            Weight += 0.18;
        }
    }
    return CenterColor / Weight;
}

vec3 WaterSurfaceScatter(vec3 BiomeColor, vec3 VanillaLight) {
    // Vertex water tint is sRGB; use only a bounded hue contribution. It is
    // not illumination, and the air-side fogColor is not a water-biome color.
    vec3 Biome = SrgbToLinear(clamp(BiomeColor, 0.0, 1.0));
    float Peak = max(Biome.r, max(Biome.g, Biome.b));
    vec3 Tint = mix(vec3(0.025, 0.14, 0.20), Biome / max(Peak, 0.0001) * 0.20, 0.35);
    // Local lightmap already follows weather, night vision and block lights.
    // No unlit cyan floor, second day/night curve or extra direct-light boost.
    return Tint * max(VanillaLight, vec3(0.0)) * LIGHTMAP_STRENGTH;
}

vec3 ApplyWaterVolume(vec3 SceneColor, vec3 ScatterColor, vec3 Transmittance) {
    // Beer-Lambert is per channel. The background is already lit: only the
    // added in-scattering uses local illumination. At zero length this is the
    // unchanged background, with no fixed tint/opacity or extra grazing gain.
    return SceneColor * Transmittance + ScatterColor * (vec3(1.0) - Transmittance);
}

float WaterLayerTransmission(vec3 Transmittance, float Reflectivity) {
    // Alpha blending can preserve prior transparent layers with one scalar.
    // Use the least-transmitted channel so no colored layer bypasses absorption.
    return (1.0 - clamp(Reflectivity, 0.0, 1.0)) *
           min(Transmittance.r, min(Transmittance.g, Transmittance.b));
}

SmoothSurfaceReflectionProfile GetWaterReflectionProfile(float Reflectivity, float Wave, float WaveSlope) {
    return CreateSmoothSurfaceReflectionProfile(mix(0.035, 0.085, WaveSlope), Reflectivity, 1.72, mix(1.95, 1.28, WaveSlope), 0.66, mix(1.08, 1.22, Wave), 0.045, vec3(0.94, 1.02, 0.98), 0.93);
}

float WaterSunLightWeight(float SunHeight, float LightmapY) {
    // Use the existing interpolated sky light level, independent of block light
    // and weather-darkened Lightmap RGB. This is conservative shelter gating,
    // not directional visibility: a side-cast shadow can still have level 15.
    float SkyLevel = clamp(LightmapY * 16.0 - 0.5, 0.0, 15.0);
    float Exposure = smoothstep(14.0, 15.0, SkyLevel);
    // Normalize the shared elevation curve to preserve clear-noon sparkle.
    float Elevation = DirectionalHeightStrength(SunHeight, 0.0) / 1.32;
    return Exposure * Elevation * (1.0 - clamp(NightValue, 0.0, 1.0)) *
           WeatherDirectFactor(rainStrength) * max(DIRECT_LIGHT_STRENGTH, 0.0);
}

vec3 WaterSunTint(vec3 LightColor) {
    // Keep the established warm noon tint, without importing the legacy sky
    // table's HDR dawn gain into this extra surface highlight.
    vec3 BoundedSun = GetDirectionalLightRadiance(LightColor, 0.0) / 0.9;
    return mix(vec3(1.0, 0.86, 0.56), BoundedSun, 0.45);
}

vec3 GetWaterSunSparkle(vec3 ViewPos, vec3 SparkleNormalView, float Variance, float WaveSlope, float WaterDepth, float Fresnel, float LightmapY) {
    vec3 LightDir = normalize(sunPosition);
    float SunHeight = ViewToWorldNormal(LightDir, gbufferModelViewInverse).y;
    float LightWeight = WaterSunLightWeight(SunHeight, LightmapY);
    if (LightWeight <= 0.0) return vec3(0.0);
    vec3 ViewDir = normalize(-ViewPos);
    vec3 HalfSum = LightDir + ViewDir;
    vec3 HalfDir = HalfSum * inversesqrt(max(dot(HalfSum, HalfSum), 1e-8));
    vec3 ReflectedView = normalize(reflect(normalize(ViewPos), SparkleNormalView));

    float ReflectionAlignment = clamp(dot(ReflectedView, LightDir), 0.0, 1.0);
    float SunWindow = smoothstep(0.44, 0.925, ReflectionAlignment);
    float BroadSun = FilteredHighlight(ReflectionAlignment, 30.0, 4.0 * Variance);
    float SharpSun = FilteredHighlight(ReflectionAlignment, mix(82.0, 160.0, clamp(WaveSlope, 0.0, 1.0)), 4.0 * Variance);
    float MicroFacet = FilteredHighlight(dot(SparkleNormalView, HalfDir), 90.0, Variance);

    float DepthFade = smoothstep(0.06, 1.45, WaterDepth);
    float SlopeFade = smoothstep(0.06, 0.62, WaveSlope);
    float Grazing = mix(0.55, 1.55, clamp(Fresnel, 0.0, 1.0));
    float Shimmer = mix(0.82, 1.22, SlopeFade);
    float Sparkle = LightWeight * DepthFade * Grazing;
    Sparkle *= BroadSun * 0.78 + SharpSun * 2.15 + MicroFacet * 0.72;
    Sparkle *= SunWindow;
    Sparkle *= Shimmer;

    return WaterSunTint(SunColor) * Sparkle * 18.0;
}

SmoothSurfaceReflectionProfile GetIceReflectionProfile(float Reflectivity) {
    SmoothSurfaceReflectionProfile Profile = CreateSmoothSurfaceReflectionProfile(0.18, Reflectivity, 0.96, 0.72, 0.38, 0.94, 0.05, vec3(1.0), 0.95);
    Profile.HistoryKind = 2.0;
    return Profile;
}

vec3 DrawWater(vec3 Color, vec3 WorldPos, vec3 ViewPos, vec3 ViewPosBehind, vec3 Normal, vec2 Dpdx, vec2 Dpdy, float ViewVariance, vec2 ScreenUv, float SurfaceDepth, vec2 OpaqueUv, vec4 Opaque, vec2 LightmapUv, vec3 VanillaLight, out float Transmission) {
    vec3 BaseWorldNormal = ViewToWorldNormal(normalize(Normal), gbufferModelViewInverse);
    WaterWaves Waves = SampleWaterWaves(WorldPos, Dpdx, Dpdy);
    float Wave = clamp(0.5 + Waves.Height * 2.65, 0.0, 1.0);
    float WaveSlope = clamp(length(Waves.Slope) * 3.35, 0.0, 1.0);
    float ReflectionSlope = clamp(length(Waves.BroadSlope) * 3.35, 0.0, 1.0);
    vec3 WorldWaveNormal = WaterWaveNormal(BaseWorldNormal, Waves.Slope, 0.88);
    vec3 WorldReflectionNormal = WaterWaveNormal(BaseWorldNormal, Waves.BroadSlope, 0.24);
    vec3 ReflectionNormal = normalize(mix(BaseWorldNormal, WorldReflectionNormal, 0.94));
    vec3 Normal2 = normalize(mat3(gbufferModelView) * ReflectionNormal);
    vec3 SparkleNormal = normalize(mat3(gbufferModelView) * normalize(mix(WorldReflectionNormal, WorldWaveNormal, 0.62)));

    vec3 ReflectDir = reflect(normalize(ViewPos), Normal2);
    float ViewCosine = clamp(abs(dot(normalize(ViewPos), Normal2)), 0.0, 1.0);
    float Fresnel = pow(1.0 - ViewCosine, 2.35);
    float Reflectivity = mix(0.30, 0.96, Fresnel) * mix(1.02, 1.10, Wave);
    float WaterDepth = GetWaterThickness(ViewPos, ViewPosBehind);
    vec3 RefractedScene = SampleRefractedSceneColor(ScreenUv, SurfaceDepth, Normal2, WaterDepth, mix(WaveSlope, ReflectionSlope, 0.25));
    // Scalar transmission preserves already drawn transparent layers during
    // ordinary alpha blending. Spectral absorption remains in the water color.
    vec3 Transmittance = WaterTransmittance(WaterDepth);
    Transmission = WaterLayerTransmission(Transmittance, Reflectivity);
    vec3 AbsorbedBaseColor = ApplyWaterVolume(RefractedScene, WaterSurfaceScatter(Color, VanillaLight), Transmittance);
    SmoothSurfaceReflectionProfile Profile = GetWaterReflectionProfile(Reflectivity, Wave, mix(WaveSlope, ReflectionSlope, 0.2));
    // Keep geometric reflection eligibility independent of AA highlight variance.
    Profile.HighlightVariance = 4.0 * Waves.Variance * 0.051 + ViewVariance;
    vec3 SurfaceColor = ResolveSmoothSurfaceColor(AbsorbedBaseColor, WorldPos, ViewPos, ReflectionNormal, ReflectDir, Profile);
    SurfaceColor += GetWaterSunSparkle(ViewPos, SparkleNormal, Waves.Variance * 0.41 + ViewVariance * 0.25, max(WaveSlope, ReflectionSlope), WaterDepth, Fresnel, LightmapUv.y);
#ifdef IDA_LIGHTING_LOCAL_LIGHT_GLSL
    SurfaceColor += EvaluateLocalLights(vec3(0.0), SparkleNormal, ViewPos, 0.18, 0.0, vec3(0.02), normalize(Normal));
#endif
#if SHORE_FOAM == 1 && defined(IDA_WATER_SURFACE_PASS)
    float Foam = SampleShoreFoam(WorldPos, ViewPos, ViewPosBehind, BaseWorldNormal, OpaqueUv, Opaque, SurfaceDepth, Dpdx, Dpdy, Waves.Height);
    if (Foam > 0.0) {
        vec3 FoamColor = ShoreFoamRadiance(VanillaLight);
        SurfaceColor = mix(SurfaceColor, FoamColor, Foam);
        // Foam replaces reflection/refraction and reduces modeled transmission
        // by its coverage, before the shared atmosphere and layer resolve.
        Transmission *= 1.0 - Foam;
    }
#endif
    return SurfaceColor;
}

vec3 DrawIce(vec3 Color, vec3 WorldPos, vec3 ViewPos, vec3 Normal, float NormalVariance, float ViewVariance) {
    vec3 SmoothNormal = normalize(Normal);
    vec3 ReflectDir = reflect(normalize(ViewPos), SmoothNormal);
    float ViewCosine = clamp(abs(dot(normalize(ViewPos), SmoothNormal)), 0.0, 1.0);
    float Fresnel = pow(1.0 - ViewCosine, 2.4);
    float Reflectivity = mix(0.16, 0.68, Fresnel);
    vec3 WorldNormal = ViewToWorldNormal(SmoothNormal, gbufferModelViewInverse);
    SmoothSurfaceReflectionProfile Profile = GetIceReflectionProfile(Reflectivity);
    Profile.HighlightVariance = 4.0 * NormalVariance + ViewVariance + 0.00104976 * SPECULAR_AA;
    return ResolveSmoothSurfaceColor(Color, WorldPos, ViewPos, WorldNormal, ReflectDir, Profile);
}

vec3 TraceSubmergedReflection(vec3 ViewPos, vec3 Direction, vec3 WaterNormalWorld) {
    vec3 SurfaceWorld = ViewToWorldPos(ViewPos, gbufferModelViewInverse);
    // A missed underwater reflection sees the water volume, not the sky.
    vec3 Fallback = WaterScatterColor();
    for (int I = 0; I < 12; ++I) {
        float Fraction = float(I + 1) / 12.0;
        float Travel = 0.35 + 48.0 * Fraction * Fraction;
        vec3 Candidate = ViewPos + Direction * Travel;
        vec2 Uv;
        vec4 Opaque;
        if (!ProjectAndSampleOpaque(Candidate, Uv, Opaque)) break;
        if (Opaque.b >= 0.999999) continue;
        vec3 Hit = ReconstructOpaqueViewPos(Uv, Opaque);
        float Crossing = Hit.z - Candidate.z;
        if (Crossing < 0.0 || Crossing >= max(0.25, Travel * 0.12)) continue;
        vec3 HitWorld = ViewToWorldPos(Hit, gbufferModelViewInverse);
        if (dot(HitWorld - SurfaceWorld, WaterNormalWorld) > -0.15) {
            return ApplyUnderwaterMedium(texture2D(colortex9, Uv).rgb, length(Hit - ViewPos));
        }
    }
    return Fallback;
}

vec3 DrawUnderwaterSurface(vec3 WorldPos, vec3 ViewPos, vec3 Normal, vec2 Dpdx, vec2 Dpdy, vec2 ScreenUv, float SurfaceDepth, out float Transmission) {
    vec3 Incident = SafeNormal(ViewPos);
    vec3 BaseWorldNormal = ViewToWorldNormal(SafeNormal(Normal), gbufferModelViewInverse);
    // Keep side faces as side faces; only perturb near-horizontal water tops.
    vec3 Outward = BaseWorldNormal.y < 0.0 ? -BaseWorldNormal : BaseWorldNormal;
    WaterWaves Waves = SampleWaterWaves(WorldPos, Dpdx, Dpdy);
    vec3 WaveNormal = WaterWaveNormal(Outward, Waves.Slope, 0.35 * smoothstep(0.70, 0.95, abs(Outward.y)));
    vec3 N = SafeNormal(mat3(gbufferModelView) * WaveNormal);
    if (dot(N, Incident) > 0.0) N = -N;
    vec3 InwardWorld = ViewToWorldNormal(N, gbufferModelViewInverse);
    float Fresnel = WaterFresnel(-dot(Incident, N), 1.333);
    vec3 Reflected = TraceSubmergedReflection(ViewPos, reflect(Incident, N), InwardWorld);
    Transmission = (1.0 - Fresnel) * 0.82;
    if (Fresnel >= 0.99999) return Reflected;

    vec3 Transmitted = refract(Incident, N, 1.333);
    vec3 TransmittedWorld = ViewToWorldNormal(Transmitted, gbufferModelViewInverse);
    vec2 OriginalUv = OpaqueUvForUnjitteredUv(ScreenUv);
    vec4 Original = SampleOpaqueData(OriginalUv);
    vec3 OriginalBehind = ReconstructOpaqueViewPos(OriginalUv, Original);
    float Travel = Original.b >= 0.999999 ? 64.0 : clamp(length(OriginalBehind - ViewPos), 1.0, 64.0);
    vec3 Probe = ViewPos + Transmitted * Travel;
    vec2 Uv = Probe.z < -near ? ProjectOpaqueViewPos(Probe).xy : vec2(-1.0);
    bool Sky = !IsScreenUvInRange(Uv);
    vec3 Radiance = GetSkyRadiance(Transmitted);
    float AirDistance = 900.0;
    if (!Sky) {
        vec4 Opaque = SampleOpaqueData(Uv);
        if (Opaque.b < SurfaceDepth) {
            Uv = OriginalUv;
            Opaque = Original;
        }
        Sky = Opaque.b >= 0.999999;
        vec3 Behind = ReconstructOpaqueViewPos(Uv, Opaque);
        vec3 BehindWorld = ViewToWorldPos(Behind, gbufferModelViewInverse);
        // Never use a submerged foreground object as the air-side refraction.
        if (!Sky && Opaque.b >= SurfaceDepth && dot(BehindWorld - WorldPos, InwardWorld) < 0.0) {
            Radiance = texture2D(colortex9, Uv).rgb;
            AirDistance = length(Behind - ViewPos);
        } else {
            Sky = true;
        }
    }
    Radiance = ApplyAirSegment(Radiance, cameraPosition + WorldPos, TransmittedWorld, AirDistance, Sky);
    // The caller applies the camera-to-water segment exactly once.
    return mix(Radiance, Reflected, Fresnel);
}
