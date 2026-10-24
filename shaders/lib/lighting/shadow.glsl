#ifndef IDA_LIGHTING_SHADOW_GLSL
#define IDA_LIGHTING_SHADOW_GLSL

#include "/lib/common/space.glsl"

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
    return smoothstep(0.10, 0.28, LightParallel);
}

float SampleShadowVisibility(vec3 ShadowScreenPos, float Bias, float FilterRadius) {
    float Visibility = 0.0;
    for (int I = 0; I < ShadowPcfSamples; I++) {
        vec2 Offset = GetShadowFilterOffset(I) * FilterRadius;
        // Hardware PCF filters comparison results, not raw depths. Keep a
        // stable kernel: no frame-varying rotation/noise or extra atlas reads.
        Visibility += shadow2D(shadowtex1, vec3(ShadowScreenPos.xy + Offset, ShadowScreenPos.z - Bias)).x;
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

float ShadowMapping(vec3 WorldPos, vec3 ViewNormal, float Strength, out float TransmissionVisibility) {
    TransmissionVisibility = 1.0;
    vec3 ShadowScreenPos = WorldToShadowScreenPos(WorldPos, shadowModelView, shadowProjection);
    if (ShadowScreenPos.z <= 0.0 || ShadowScreenPos.z >= 1.0) {
        return 1.0;
    }
    if (ShadowScreenPos.x <= 0.0 || ShadowScreenPos.x >= 1.0 || ShadowScreenPos.y <= 0.0 || ShadowScreenPos.y >= 1.0) {
        return 1.0;
    }

    float ViewDistance = length(WorldPos);
    float DistanceFade = clamp(1.0 - ViewDistance / far, 0.0, 1.0);
    float LightParallel = clamp(abs(dot(normalize(ViewNormal), normalize(shadowLightPosition))), 0.0, 1.0);
    float ReceiverFade = GetShadowReceiverFade(LightParallel);
    // Direct shading and transmission must both fade before leaving the map.
    float ShadowStrength = Strength * 0.48 * DistanceFade * (1.0 - 0.6 * NightValue) *
                           ReceiverFade * ShadowMapCoverage(ShadowScreenPos);
    if (ShadowStrength <= 0.0) {
        return 1.0;
    }

    float NoonTightness = GetNoonShadowTightness();
    float Bias = GetShadowBias(LightParallel, ViewDistance, NoonTightness);
    float FilterRadius = mix(0.58, 0.95, 1.0 - DistanceFade) *
                         mix(1.0, 0.62, NoonTightness) /
                         float(shadowMapResolution);
    float Visibility = SampleShadowVisibility(ShadowScreenPos, Bias, FilterRadius);
    // Reuse these five PCF taps for vegetation. Preserve the existing artistic
    // shadow tone for normal lighting, but do not lift transmission in shadow.
    // Match every early-out envelope, including the grazing receiver fade, so
    // a tiny change in angle/range cannot suddenly restore full transmission.
    TransmissionVisibility = mix(1.0, Visibility, ShadowTransmissionCoverage(ShadowScreenPos, DistanceFade, ReceiverFade));

    return mix(1.0, Visibility, ShadowStrength);
}

float ShadowMapping(vec3 WorldPos, vec3 ViewNormal, float Strength) {
    float TransmissionVisibility;
    return ShadowMapping(WorldPos, ViewNormal, Strength, TransmissionVisibility);
}

#endif
