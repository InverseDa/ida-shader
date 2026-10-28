#ifndef IDA_MISC_GODRAYS_GLSL
#define IDA_MISC_GODRAYS_GLSL

// Camera-segment single scattering. The existing air fog supplies diffuse
// in-scattering/extinction; this is its directional, shadowed solar component.
// Redistribute a bounded solar scattering budget toward nearby air. Using the
// distant haze density uniformly made 2-8 block canopy shafts invisible after
// tonemapping. This is an artistic near-air profile, not another extinction fog.
// No screen-space sun position, radial blur, extra history or moonlight gain.
#include "/lib/common/space.glsl"
#include "/lib/misc/volume_cache.glsl"
#ifdef IDA_VOLUME_CACHE_WRITE
ivec2 SunShaftWritePixel;
ivec2 SunShaftWriteSize;
#endif
#if SHADOW_CSM == 1
#include "/lib/lighting/cascades.glsl"
float SunShaftCascadeSample(vec3 Position, int Index) {
    vec3 Shadow = CascadeScreenPosition(Position, Index);
    float Coverage = CascadeCoverage(Shadow, Index);
    if (Coverage <= 0.0) return 0.0;
    return Coverage * textureLod(shadowtex1, vec3(Shadow.xy, Shadow.z - 0.000006), 0.0);
}
float SunShaftCascadeVisibility(vec3 Position) {
    float Distance = length(Position);
    float Coverage = CascadeDistanceCoverage(Distance);
    if (Coverage <= 0.0) return 0.0;
    int Index = SelectCascade(Distance);
    float Visibility = SunShaftCascadeSample(Position, Index);
    float Blend = CascadeBlend(Distance, Index);
    if (Blend > 0.0) Visibility = mix(Visibility, SunShaftCascadeSample(Position, Index + 1), Blend);
    return Coverage * Visibility;
}
#endif

float SunShaftCloudVisibility(vec3 Position, vec3 LightDir) {
    float SampleHeight = 0.5 * (CloudBottom + CloudTop);
    float Travel = (SampleHeight - Position.y) / max(LightDir.y, 0.04);
    vec3 CloudPosition = Position + LightDir * Travel;
    float Coverage = SampleStyledCloudCoverage(CloudPosition, vec2(4.0), false);
    float OpticalDepth = Coverage * CloudExtinction * CloudColumnLengthAbove(CloudBottom);
    // Use actual extinction here. Surface cloud shadows deliberately have an
    // artistic darkness cap, which would illuminate beams under dense clouds.
    float Visibility = exp(-OpticalDepth / max(LightDir.y, 0.04));
#if CLOUD_STYLE == 0
    // Filter the projected block boundary, not the visible cloud geometry.
    // A discontinuous cell mask sampled by cached columns produces several
    // false parallel shaft edges. Blend transmission only near cell borders.
    vec2 Cell = fract((CloudPosition.xz - vec2(2.0, 0.8) * frameTimeCounter) / BlockCloudCellSize);
    vec2 Edge = min(Cell, vec2(1.0) - Cell) * BlockCloudCellSize;
    vec2 Weight = 0.5 * (vec2(1.0) - smoothstep(vec2(0.0), vec2(5.0), Edge));
    vec2 Offset = mix(vec2(-BlockCloudCellSize), vec2(BlockCloudCellSize), step(vec2(0.5), Cell));
    float Scale = CloudExtinction * CloudColumnLengthAbove(CloudBottom) / max(LightDir.y, 0.04);
    float X = Visibility;
    float Z = Visibility;
    float XZ = Visibility;
    if (Weight.x > 0.0)
        X = exp(-Scale * SampleBlockCloudCoverage(CloudPosition + vec3(Offset.x, 0.0, 0.0), vec2(4.0)));
    if (Weight.y > 0.0)
        Z = exp(-Scale * SampleBlockCloudCoverage(CloudPosition + vec3(0.0, 0.0, Offset.y), vec2(4.0)));
    if (Weight.x > 0.0 && Weight.y > 0.0)
        XZ = exp(-Scale * SampleBlockCloudCoverage(CloudPosition + vec3(Offset.x, 0.0, Offset.y), vec2(4.0)));
    Visibility = mix(mix(Visibility, X, Weight.x), mix(Z, XZ, Weight.x), Weight.y);
#endif
    return Visibility;
}

float SunShaftGeometryVisibility(vec4 ShadowClip, float WorldDistance) {
    vec3 Shadow = ShadowClip.xyz / ShadowClip.w;
    Shadow.xy = GetFishEyeCoord(Shadow.xy);
    Shadow = Shadow * 0.5 + 0.5;
    vec2 Edge = min(Shadow.xy, vec2(1.0) - Shadow.xy);
    float Coverage = smoothstep(1.5 / float(shadowMapResolution), 0.025, min(Edge.x, Edge.y));
    Coverage *= smoothstep(0.0, 0.025, Shadow.z) * (1.0 - smoothstep(0.975, 1.0, Shadow.z));
    Coverage *= 1.0 - smoothstep(0.70 * far, far, WorldDistance);
    // Unknown shadow coverage contributes no beam: never treat outside-map
    // samples as sunlit, especially when viewing a cave from inside it.
    if (Coverage <= 0.0) return 0.0;
    // Explicit level: implicit derivatives inside a divergent ray loop can
    // force costly helper-lane execution. Hardware comparison/PCF is retained.
    return Coverage * textureLod(shadowtex1, vec3(Shadow.xy, Shadow.z - 0.00002), 0.0);
}

vec3 RenderSunShafts(vec3 OriginWorld, vec3 RayDir, float Distance) {
#if VOLUMETRIC_LIGHT == 1
    float Day = 1.0 - smoothstep(0.0, 1.0, NightValue);
    // Only air below the cloud base for this stage. Underwater scattering is
    // handled by its own medium; clouds retain their existing lighting.
    if (Day <= 0.0 || VOLUMETRIC_LIGHT_STRENGTH <= 0.0 || OriginWorld.y >= CloudBottom || Distance <= 0.05) return vec3(0.0);
    vec3 LightDir = ViewToWorldNormal(normalize(sunPosition), gbufferModelViewInverse);
    float Source = Day * smoothstep(0.04, 0.16, LightDir.y) *
                   (1.0 - smoothstep(0.0, 1.0, rainStrength));
    // Fade the ground-air treatment before entering the separate cloud medium,
    // including horizontal views where segment clipping alone cannot fade it.
    Source *= 1.0 - smoothstep(CloudBottom - 24.0, CloudBottom, OriginWorld.y);
    if (Source <= 0.0) return vec3(0.0);
    float Range = min(128.0, far);
    float End = min(Distance, Range);
#ifndef IDA_VOLUME_CACHE_WRITE
    if (RayDir.y > 0.00001) End = min(End, (CloudBottom - OriginWorld.y) / RayDir.y);
#endif
    if (End <= 0.05) return vec3(0.0);

    float Density = 0.00082 * (1.0 + rainStrength * 2.15) *
                    mix(1.24, 0.76, smoothstep(70.0, 130.0, OriginWorld.y));
    // Preserve the original full-column optical depth: only its distribution
    // changes. The short falloff gives branches readable near-field scattering
    // without multiplying the far-sky haze or changing the existing sun halo.
    float NearColumn = Range / (1.0 - exp(-Range / 10.0));
    float Mu = clamp(dot(RayDir, LightDir), -1.0, 1.0);
    // Broad forward lobe, bounded at the solar centre. Warmth follows the
    // released time palette; this does not replace the yellow sky halo.
    float Phase = 0.12 + 0.20 * 0.5775 / pow(1.4225 - 1.30 * Mu, 1.5);
    vec3 Radiance = GetDirectionalLightRadiance(SunColor, 0.0) * vec3(1.0, 0.90, 0.68);
#if defined(IDA_VOLUME_CACHE_ACTIVE) && !defined(IDA_VOLUME_CACHE_WRITE)
    // Effects drawn before deferred10 have no current-frame prefix field and
    // keep the direct path. Camera-relative rays alone may share this cache.
    ivec2 CacheSize = SunShaftCacheSize();
    bool CacheReady = SunShaftVolumeHeader.x == uint(frameCounter) + 1u &&
                      all(equal(SunShaftVolumeHeader.yz, uvec2(CacheSize)));
    if (CacheReady && all(equal(OriginWorld, cameraPosition))) {
        if (SunShaftVolumeHeader.w == 0u) return vec3(0.0);
        vec3 ViewRay = mat3(gbufferModelView) * RayDir;
        vec2 CacheUv = ProjectViewToScreenPos(ViewRay, gbufferProjection).xy;
        if (SunShaftVolumeHeader.w == uint(VOLUMETRIC_LIGHT_SAMPLES) && ViewRay.z < -0.000001 &&
            all(greaterThanEqual(CacheUv, vec2(0.0))) && all(lessThanEqual(CacheUv, vec2(1.0)))) {
            float Integral = SunShaftCacheIntegral(CacheUv, CacheSize, End, Range, Density, NearColumn);
            return Radiance * (Integral * Phase * Source * VOLUMETRIC_LIGHT_STRENGTH * DIRECT_LIGHT_STRENGTH);
        }
    }
#endif
    float Accumulated = 0.0;
    float PreviousTransmission = 1.0;
    // Fixed strata do not stretch when the terminal surface/depth changes.
    // Near samples are denser for branches; a fixed spatial phase avoids
    // frame-varying grain. Visibility is filtered by hardware PCF.
    float PhaseOffset = 0.35 + 0.30 * fract(52.9829189 * fract(dot(IDA_ATMOSPHERE_PIXEL, vec2(0.06711056, 0.00583715))));
    const int CloudStride = VOLUMETRIC_LIGHT_SAMPLES / 8;
    float CloudA = SunShaftCloudVisibility(OriginWorld, LightDir);
    float CloudB = CloudA;
    float CloudStart = 0.0;
    float CloudEnd = 0.0;
    vec3 RelativeOrigin = OriginWorld - cameraPosition;
    // Transform the affine ray once, then apply distortion per sample. This
    // retains every shadow query without two matrix transforms at each step.
    vec4 ShadowOrigin = shadowProjection * (shadowModelView * vec4(RelativeOrigin, 1.0));
    vec4 ShadowDirection = shadowProjection * (shadowModelView * vec4(RayDir, 0.0));
#ifdef IDA_VOLUME_CACHE_WRITE
    float PairFirst = 0.0;
#endif
    for (int I = 0; I < VOLUMETRIC_LIGHT_SAMPLES; ++I) {
        float A = max(float(I - 1) + PhaseOffset, 0.0) / float(VOLUMETRIC_LIGHT_SAMPLES);
        float B = I + 1 == VOLUMETRIC_LIGHT_SAMPLES ? 1.0 :
                  (float(I) + PhaseOffset) / float(VOLUMETRIC_LIGHT_SAMPLES);
        float T0 = Range * A * A;
        if (T0 >= End) break;
        float T1 = min(Range * B * B, End);
        // Causal quadrature: sample at each fixed stratum's front. Shortening
        // the ray only changes its last weight, never moves a shadow query
        // across a leaf edge or samples sunlight behind the terminal wall.
        float T = T0;
        // Cloud shadows vary much more slowly than leaf occlusion. Cache eight
        // intervals instead of re-reading cloud noise at every geometry step.
        if (I % CloudStride == 0) {
            CloudA = CloudB;
            CloudStart = T0;
            float U = (float(I + CloudStride - 1) + PhaseOffset) / float(VOLUMETRIC_LIGHT_SAMPLES);
            CloudEnd = Range * U * U;
            CloudB = SunShaftCloudVisibility(OriginWorld + RayDir * CloudEnd, LightDir);
        }
        float CloudVisibility = mix(CloudA, CloudB, clamp((T - CloudStart) / max(CloudEnd - CloudStart, 0.0001), 0.0, 1.0));
#if SHADOW_CSM == 1
        float Visibility = SunShaftCascadeVisibility(RelativeOrigin + RayDir * T) * CloudVisibility;
#else
        float Visibility = SunShaftGeometryVisibility(ShadowOrigin + ShadowDirection * T,
                                length(RelativeOrigin + RayDir * T)) * CloudVisibility;
#endif
        float OpticalDistance = mix(T1, NearColumn * (1.0 - exp(-T1 / 10.0)), 0.65);
        float Transmission = exp(-Density * OpticalDistance);
        float RangeFade = 1.0 - smoothstep(Range * 0.75, Range, T);
        Accumulated += (PreviousTransmission - Transmission) * Visibility * RangeFade;
        PreviousTransmission = Transmission;
#ifdef IDA_VOLUME_CACHE_WRITE
        // Store the complete ray, independent of any opaque surface depth.
        // Two FP16 prefixes per word; planes are coalesced across neighbouring
        // invocations. All supported sample counts are even (24/32/48).
        if (I % 2 == 0) PairFirst = Accumulated;
        else SunShaftVolumeData[SunShaftCacheAddress(SunShaftWritePixel, SunShaftWriteSize, I / 2)] =
                 packHalf2x16(vec2(PairFirst, Accumulated));
#endif
    }
    return Radiance * (Accumulated * Phase * Source * VOLUMETRIC_LIGHT_STRENGTH * DIRECT_LIGHT_STRENGTH);
#else
    return vec3(0.0);
#endif
}

#endif
