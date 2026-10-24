#ifndef IDA_LIGHTING_CLOUD_SHADOW_GLSL
#define IDA_LIGHTING_CLOUD_SHADOW_GLSL
#include "/lib/settings.glsl"
#include "/lib/lighting/daylight.glsl"

#if CLOUD_SHADOWS == 1
#include "/lib/misc/cloud_density.glsl"

float surfaceCloudStrength(float lightHeight) {
    // Limit low-angle projection distances and fade before the light crosses
    // the horizon or Iris switches the active sun/moon shadow direction.
    return CLOUD_SHADOW_STRENGTH * smoothstep(0.04, 0.16, lightHeight) *
           cloudWeatherContrast(rainStrength, nightValue);
}

float surfaceCloudTransmission(float opticalDepth, float strength) {
    // Soft contrast bound: at most half the directional source is removed at
    // strength 1. No hard clamp seam in dense clouds or long low-angle paths.
    float opacity = 0.5 * (1.0 - exp(-2.0 * max(opticalDepth, 0.0)));
    return 1.0 - opacity * clamp(strength, 0.0, 1.0);
}

float getSurfaceCloudVisibility(vec3 relativeWorld, vec3 lightDirWorld, float skyVisibility) {
    float strength = surfaceCloudStrength(lightDirWorld.y);
    if (strength <= 0.0 || skyVisibility <= 0.0) return 1.0;
    vec3 absolutePos = relativeWorld + cameraPosition;
    float column = cloudColumnLengthAbove(absolutePos.y);
    if (column <= 0.0) return 1.0;
    // One midpoint coverage evaluation (at most three existing noise reads).
    // Integrate the vertical envelope analytically, including receivers inside
    // the layer. Horizontal variation along oblique rays is approximated.
    float sampleHeight = 0.5 * (max(absolutePos.y, CLOUD_BOTTOM) + CLOUD_TOP);
    float travel = (sampleHeight - absolutePos.y) / max(lightDirWorld.y, 0.04);
    vec2 cloudXZ = absolutePos.xz + lightDirWorld.xz * travel;
    float coverage = getCloudCoverageAtHeight(vec3(cloudXZ.x, sampleHeight, cloudXZ.y), vec2(0.0));
    float opticalDepth = coverage * CLOUD_EXTINCTION * column / max(lightDirWorld.y, 0.04);
    return surfaceCloudTransmission(opticalDepth, strength);
}
#endif

#endif
