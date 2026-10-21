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

float getShadowBias(vec3 viewNormal, float viewDistance) {
    float lightPlaneAngle = abs(dot(normalize(viewNormal), normalize(shadowLightPosition)));
    float slopeBias = (1.0 - lightPlaneAngle) * 0.00055;
    float distanceBias = mix(0.00020, 0.00070, clamp(viewDistance / far, 0.0, 1.0));
    return (slopeBias + distanceBias) * mix(1.0, 0.35, getNoonShadowTightness());
}

float getShadowReceiverFade(vec3 viewNormal) {
    float lightParallel = abs(dot(normalize(viewNormal), normalize(shadowLightPosition)));
    return smoothstep(0.10, 0.28, lightParallel);
}

float sampleShadowVisibility(vec3 shadowScreenPos, float bias, float filterRadius) {
    float visibility = 0.0;
    for (int i = 0; i < SHADOW_PCF_SAMPLES; i++) {
        vec2 offset = getShadowFilterOffset(i) * filterRadius;
        float closestDepth = texture2D(shadowtex1, shadowScreenPos.xy + offset).x;
        visibility += step(shadowScreenPos.z - bias, closestDepth);
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

float shadowMapping(vec3 worldPos, vec3 viewNormal, float strength) {
    vec3 shadowScreenPos = worldToShadowScreenPos(worldPos, shadowModelView, shadowProjection);
    if (shadowScreenPos.z >= 0.999999) {
        return 1.0;
    }
    if (shadowScreenPos.x <= 0.0 || shadowScreenPos.x >= 1.0 ||
        shadowScreenPos.y <= 0.0 || shadowScreenPos.y >= 1.0) {
        return 1.0;
    }

    float viewDistance = length(worldPos);
    float distanceFade = clamp(1.0 - viewDistance / far, 0.0, 1.0);
    float receiverFade = getShadowReceiverFade(viewNormal);
    float shadowStrength = strength * 0.48 * distanceFade * (1.0 - 0.6 * nightValue) * receiverFade;
    if (shadowStrength <= 0.0) {
        return 1.0;
    }

    float bias = getShadowBias(viewNormal, viewDistance);
    float filterRadius = mix(0.58, 0.95, 1.0 - distanceFade) *
                         mix(1.0, 0.62, getNoonShadowTightness()) /
                         float(shadowMapResolution);
    float visibility = sampleShadowVisibility(shadowScreenPos, bias, filterRadius);

    return mix(1.0, visibility, shadowStrength);
}

#endif
