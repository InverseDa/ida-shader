#ifndef IDA_LIGHTING_SHADOW_GLSL
#define IDA_LIGHTING_SHADOW_GLSL

#include "/lib/common/space.glsl"
#if SHADOW_CSM == 1
#include "/lib/lighting/cascades.glsl"
#endif

const int ShadowPcfSamples = 5;

float GetNoonShadowTightness() {
    float DayPhase = clamp(float(worldTime) / 12000.0, 0.0, 1.0);
    float DistanceFromNoon = abs(DayPhase - 0.5) * 2.0;
    return 1.0 - smoothstep(0.0, 1.0, DistanceFromNoon);
}

vec2 GetShadowFilterOffset(int Index) {
    if (Index == 0) return vec2(0.0, 0.0);
    if (Index == 1) return vec2(0.70, 0.0);
    if (Index == 2) return vec2(-0.70, 0.0);
    if (Index == 3) return vec2(0.0, 0.70);
    return vec2(0.0, -0.70);
}

float GetShadowBias(float LightPlaneAngle, float ViewDistance, float NoonTightness) {
    float SlopeBias = (1.0 - LightPlaneAngle) * 0.00055;
    float DistanceBias = mix(0.00020, 0.00070, clamp(ViewDistance / far, 0.0, 1.0));
    return (SlopeBias + DistanceBias) * mix(1.0, 0.35, NoonTightness);
}

float GetShadowReceiverFade(float LightParallel) {
    return smoothstep(0.015, 0.08, LightParallel);
}

// Analytic receiver-plane gradient in distorted shadow UV. Avoid screen
// derivatives: deferred silhouettes, cutouts and forward alpha discards need
// not form a continuous quad. Only the geometric normal defines this plane.
vec2 GetShadowReceiverGradient(vec2 P, vec3 ViewNormal) {
    vec3 WorldNormal = normalize(mat3(gbufferModelViewInverse) * ViewNormal);
    vec3 ShadowNormal = mat3(shadowModelView) * WorldNormal;
    vec3 Plane = normalize(ShadowNormal / vec3(shadowProjection[0][0], shadowProjection[1][1], shadowProjection[2][2]));
    float Z = (Plane.z < 0.0 ? -1.0 : 1.0) * max(abs(Plane.z), 0.02);
    vec2 Slope = -Plane.xy / Z;
    float R = length(P);
    float Distortion = 0.15 + 0.85 * R;
    // Inverse Jacobian of P / (0.15 + 0.85 * |P|). The depth and UV factors
    // of 0.5 cancel. Correct both the radial and tangential pixel footprint.
    vec2 Gradient = Distortion * (Slope + (0.85 / 0.15) * P * dot(P, Slope) / max(R, 0.000001));
    return clamp(Gradient, vec2(-8.0), vec2(8.0));
}

float SampleShadowVisibility(vec3 ShadowScreenPos, float Bias, float FilterRadius, vec2 ReceiverGradient) {
    float Visibility = 0.0;
    for (int I = 0; I < ShadowPcfSamples; I++) {
        vec2 Offset = GetShadowFilterOffset(I) * FilterRadius;
        // Hardware PCF filters comparison results, not raw depths. Keep a
        // stable kernel: no frame-varying rotation/noise or extra atlas reads.
        float ReceiverDepth = ShadowScreenPos.z + dot(ReceiverGradient, Offset);
        Visibility += shadow2D(shadowtex1, vec3(ShadowScreenPos.xy + Offset, ReceiverDepth - Bias)).x;
    }

    return Visibility / float(ShadowPcfSamples);
}

float UnderWaterFadeOut(float D0, float D1, vec3 ViewPos, vec3 Normal) {
    D0 = ScreenDepthToLinearDepth(near, far, D0);
    D1 = ScreenDepthToLinearDepth(near, far, D1);

    float Cosine = clamp(abs(dot(normalize(ViewPos), normalize(Normal))), 0.0, 1.0);
    float Thickness = max(D1 - D0, 0.0);
    return clamp(1.0 - Thickness * mix(0.14, 0.06, Cosine), 0.0, 1.0);
}

float ShadowMapCoverage(vec3 ShadowScreenPos) {
    vec2 Edge = min(ShadowScreenPos.xy, vec2(1.0) - ShadowScreenPos.xy);
    // Include the bilinear footprint, not just the PCF sample centers.
    float Guard = 1.5 / float(shadowMapResolution);
    float AtlasFade = smoothstep(Guard, 0.02, min(Edge.x, Edge.y));
    float DepthFade = smoothstep(0.0, 0.02, ShadowScreenPos.z) *
                      (1.0 - smoothstep(0.98, 1.0, ShadowScreenPos.z));
    return AtlasFade * DepthFade;
}

float ShadowTransmissionCoverage(vec3 ShadowScreenPos, float DistanceFade, float ReceiverFade) {
    return smoothstep(0.0, 0.15, DistanceFade) * ReceiverFade * ShadowMapCoverage(ShadowScreenPos);
}

#if SHADOW_CSM == 1
float SampleCascadeSurface(vec3 WorldPos, vec3 ViewNormal, int Index) {
    vec3 Position = CascadeScreenPosition(WorldPos, Index);
    float Coverage = CascadeCoverage(Position, Index);
    if (Coverage <= 0.0) return 1.0;
    vec3 N = mat3(shadowModelView) * (mat3(gbufferModelViewInverse) * normalize(ViewNormal));
    float Z = (N.z < 0.0 ? -1.0 : 1.0) * max(abs(N.z), 0.02);
    vec2 Gradient = clamp(-2.0 * CascadeRadius(Index) * shadowProjection[2][2] * N.xy / Z,
                          vec2(-32.0), vec2(32.0));
    float Bias = 0.000006 + dot(abs(Gradient), vec2(1.0)) / float(shadowMapResolution);
    float Visibility = SampleShadowVisibility(Position, Bias, 0.85 / float(shadowMapResolution), Gradient);
    return mix(1.0, Visibility, Coverage);
}

float CascadeShadowMapping(vec3 WorldPos, vec3 ViewNormal, float Strength, out float TransmissionVisibility) {
    float Distance = length(WorldPos);
    float DistanceFade = CascadeDistanceCoverage(Distance);
    float ReceiverFade = GetShadowReceiverFade(abs(dot(normalize(ViewNormal), normalize(shadowLightPosition))));
    TransmissionVisibility = 1.0;
    if (DistanceFade * ReceiverFade <= 0.0) return 1.0;
    int Index = SelectCascade(Distance);
    float Visibility = SampleCascadeSurface(WorldPos, ViewNormal, Index);
    float Blend = CascadeBlend(Distance, Index);
    if (Blend > 0.0) Visibility = mix(Visibility, SampleCascadeSurface(WorldPos, ViewNormal, Index + 1), Blend);
    TransmissionVisibility = mix(1.0, Visibility, smoothstep(0.0, 0.15, DistanceFade) * ReceiverFade);
    return mix(1.0, Visibility, clamp(Strength, 0.0, 1.0) * DistanceFade * ReceiverFade);
}
#endif

float ShadowMapping(vec3 WorldPos, vec3 ViewNormal, float Strength, out float TransmissionVisibility) {
#if SHADOW_CSM == 1
    return CascadeShadowMapping(WorldPos, ViewNormal, Strength, TransmissionVisibility);
#else
    TransmissionVisibility = 1.0;
    vec4 ShadowClip = shadowProjection * (shadowModelView * vec4(WorldPos, 1.0));
    vec3 ShadowNdc = ShadowClip.xyz / ShadowClip.w;
    vec3 ShadowScreenPos = vec3(GetFishEyeCoord(ShadowNdc.xy), ShadowNdc.z) * 0.5 + 0.5;
    if (ShadowScreenPos.z <= 0.0 || ShadowScreenPos.z >= 1.0) {
        return 1.0;
    }
    if (ShadowScreenPos.x <= 0.0 || ShadowScreenPos.x >= 1.0 || ShadowScreenPos.y <= 0.0 || ShadowScreenPos.y >= 1.0) {
        return 1.0;
    }

    float ViewDistance = length(WorldPos);
    // Preserve near/midrange contrast; fade only near the coverage boundary.
    float DistanceFade = 1.0 - smoothstep(0.70, 1.0, ViewDistance / far);
    float LightParallel = clamp(abs(dot(normalize(ViewNormal), normalize(shadowLightPosition))), 0.0, 1.0);
    float ReceiverFade = GetShadowReceiverFade(LightParallel);
    // Direct shading and transmission must both fade before leaving the map.
    float ShadowStrength = clamp(Strength, 0.0, 1.0) * DistanceFade *
                           ReceiverFade * ShadowMapCoverage(ShadowScreenPos);
    if (ShadowStrength <= 0.0) {
        return 1.0;
    }

    float NoonTightness = GetNoonShadowTightness();
    float Bias = GetShadowBias(LightParallel, ViewDistance, NoonTightness);
    float FilterRadius = mix(0.58, 0.95, 1.0 - DistanceFade) *
                         mix(1.0, 0.62, NoonTightness) /
                         float(shadowMapResolution);
    vec2 ReceiverGradient = vec2(0.0);
#if SHADOW_RECEIVER_PLANE == 1
    ReceiverGradient = GetShadowReceiverGradient(ShadowNdc.xy, ViewNormal);
    // PCF compares four texels against a single reference. A contributing
    // centre can be almost a full texel away at fractional UV coordinates.
    // Keep a fixed precision guard instead of a distance/time-driven gap.
    Bias = 0.00002 + dot(abs(ReceiverGradient), vec2(1.0)) / float(shadowMapResolution);
    FilterRadius = mix(0.70, 0.95, 1.0 - DistanceFade) / float(shadowMapResolution);
#endif
    float Visibility = SampleShadowVisibility(ShadowScreenPos, Bias, FilterRadius, ReceiverGradient);
    // Reuse these five PCF taps for vegetation and surface visibility.
    // Match every early-out envelope, including the grazing receiver fade, so
    // a tiny change in angle/range cannot suddenly restore full transmission.
    TransmissionVisibility = mix(1.0, Visibility, ShadowTransmissionCoverage(ShadowScreenPos, DistanceFade, ReceiverFade));

    return mix(1.0, Visibility, ShadowStrength);
#endif
}

float ShadowMapping(vec3 WorldPos, vec3 ViewNormal, float Strength) {
    float TransmissionVisibility;
    return ShadowMapping(WorldPos, ViewNormal, Strength, TransmissionVisibility);
}

#endif
