#ifndef IDA_LIGHTING_SHADOW_GLSL
#define IDA_LIGHTING_SHADOW_GLSL

#include "/lib/common/space.glsl"

const int SHADOW_PCF_SAMPLES = 5;

float getNoonShadowTightness() {
    float dayPhase = clamp(float(worldTime) / 12000.0, 0.0, 1.0);
    float distanceFromNoon = abs(dayPhase - 0.5) * 2.0;
    return 1.0 - smoothstep(0.0, 1.0, distanceFromNoon);
}

vec2 getShadowFilterOffset(int index) {
    if (index == 0) return vec2( 0.0,  0.0);
    if (index == 1) return vec2( 0.70,  0.0);
    if (index == 2) return vec2(-0.70,  0.0);
    if (index == 3) return vec2( 0.0,  0.70);
    return vec2(0.0, -0.70);
}

float getShadowBias(float lightPlaneAngle, float viewDistance, float noonTightness) {
    float slopeBias = (1.0 - lightPlaneAngle) * 0.00055;
    float distanceBias = mix(0.00020, 0.00070, clamp(viewDistance / far, 0.0, 1.0));
    return (slopeBias + distanceBias) * mix(1.0, 0.35, noonTightness);
}

float getShadowReceiverFade(float lightParallel) {
    return smoothstep(0.10, 0.28, lightParallel);
}

float sampleShadowVisibility(vec3 shadowScreenPos, float bias, float filterRadius) {
    float visibility = 0.0;
    for (int i = 0; i < SHADOW_PCF_SAMPLES; i++) {
        vec2 offset = getShadowFilterOffset(i) * filterRadius;
        // Hardware PCF filters comparison results, not raw depths. Keep a
        // stable kernel: no frame-varying rotation/noise or extra atlas reads.
        visibility += shadow2D(shadowtex1, vec3(shadowScreenPos.xy + offset, shadowScreenPos.z - bias)).x;
    }

    return visibility / float(SHADOW_PCF_SAMPLES);
}

float UnderWaterFadeOut(float d0, float d1, vec3 viewPos, vec3 normal) {
    d0 = screenDepthToLinearDepth(near, far, d0);
    d1 = screenDepthToLinearDepth(near, far, d1);

    float cosine = clamp(abs(dot(normalize(viewPos), normalize(normal))), 0.0, 1.0);
    float thickness = max(d1 - d0, 0.0);
    return clamp(1.0 - thickness * mix(0.14, 0.06, cosine), 0.0, 1.0);
}

float shadowMapCoverage(vec3 shadowScreenPos) {
    vec2 edge = min(shadowScreenPos.xy, vec2(1.0) - shadowScreenPos.xy);
    // Include the bilinear footprint, not just the PCF sample centers.
    float guard = 1.5 / float(shadowMapResolution);
    float atlasFade = smoothstep(guard, 0.02, min(edge.x, edge.y));
    float depthFade = smoothstep(0.0, 0.02, shadowScreenPos.z) *
                      (1.0 - smoothstep(0.98, 1.0, shadowScreenPos.z));
    return atlasFade * depthFade;
}

float shadowTransmissionCoverage(vec3 shadowScreenPos, float distanceFade, float receiverFade) {
    return smoothstep(0.0, 0.15, distanceFade) * receiverFade * shadowMapCoverage(shadowScreenPos);
}

float shadowMapping(vec3 worldPos, vec3 viewNormal, float strength, out float transmissionVisibility) {
    transmissionVisibility = 1.0;
    vec3 shadowScreenPos = worldToShadowScreenPos(worldPos, shadowModelView, shadowProjection);
    if (shadowScreenPos.z <= 0.0 || shadowScreenPos.z >= 1.0) {
        return 1.0;
    }
    if (shadowScreenPos.x <= 0.0 || shadowScreenPos.x >= 1.0 ||
        shadowScreenPos.y <= 0.0 || shadowScreenPos.y >= 1.0) {
        return 1.0;
    }

    float viewDistance = length(worldPos);
    float distanceFade = clamp(1.0 - viewDistance / far, 0.0, 1.0);
    float lightParallel = clamp(abs(dot(normalize(viewNormal), normalize(shadowLightPosition))), 0.0, 1.0);
    float receiverFade = getShadowReceiverFade(lightParallel);
    // Direct shading and transmission must both fade before leaving the map.
    float shadowStrength = strength * 0.48 * distanceFade * (1.0 - 0.6 * nightValue) *
                           receiverFade * shadowMapCoverage(shadowScreenPos);
    if (shadowStrength <= 0.0) {
        return 1.0;
    }

    float noonTightness = getNoonShadowTightness();
    float bias = getShadowBias(lightParallel, viewDistance, noonTightness);
    float filterRadius = mix(0.58, 0.95, 1.0 - distanceFade) *
                         mix(1.0, 0.62, noonTightness) /
                         float(shadowMapResolution);
    float visibility = sampleShadowVisibility(shadowScreenPos, bias, filterRadius);
    // Reuse these five PCF taps for vegetation. Preserve the existing artistic
    // shadow tone for normal lighting, but do not lift transmission in shadow.
    // Match every early-out envelope, including the grazing receiver fade, so
    // a tiny change in angle/range cannot suddenly restore full transmission.
    transmissionVisibility = mix(1.0, visibility,
        shadowTransmissionCoverage(shadowScreenPos, distanceFade, receiverFade));

    return mix(1.0, visibility, shadowStrength);
}

float shadowMapping(vec3 worldPos, vec3 viewNormal, float strength) {
    float transmissionVisibility;
    return shadowMapping(worldPos, viewNormal, strength, transmissionVisibility);
}

#endif
