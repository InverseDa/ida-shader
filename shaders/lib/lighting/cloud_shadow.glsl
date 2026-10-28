#ifndef IDA_LIGHTING_CLOUD_SHADOW_GLSL
#define IDA_LIGHTING_CLOUD_SHADOW_GLSL

// ---- Cloud Shadow ----

#include "/lib/settings.glsl"
#include "/lib/lighting/daylight.glsl"

#if CLOUD_SHADOWS == 1
#include "/lib/misc/cloud_density.glsl"

float SurfaceCloudStrength(float LightHeight)
{
    // Limit low-angle projection distances and fade before the light crosses
    // the horizon or Iris switches the active sun/moon shadow direction.
    return CLOUD_SHADOW_STRENGTH * smoothstep(0.04, 0.16, LightHeight) *
           CloudWeatherContrast(rainStrength, NightValue);
}

float SurfaceCloudTransmission(float OpticalDepth, float Strength)
{
    // Soft contrast bound: at most half the directional source is removed at
    // strength 1. No hard clamp seam in dense clouds or long low-angle paths.
    float Opacity = 0.5 * (1.0 - exp(-2.0 * max(OpticalDepth, 0.0)));

    return 1.0 - Opacity * clamp(Strength, 0.0, 1.0);
}

float GetSurfaceCloudVisibility(vec3 RelativeWorld, vec3 LightDirWorld, float SkyVisibility)
{
    float Strength = SurfaceCloudStrength(LightDirWorld.y);

    if (Strength <= 0.0 || SkyVisibility <= 0.0)
    {
        return 1.0;
    }

    vec3 AbsolutePos = RelativeWorld + cameraPosition;
    float Column = CloudColumnLengthAbove(AbsolutePos.y);

    if (Column <= 0.0)
    {
        return 1.0;
    }

    // Integrate the vertical envelope analytically; approximate horizontal variation at the midpoint.
    float SampleHeight = 0.5 * (max(AbsolutePos.y, CloudBottom) + CloudTop);
    float Travel = (SampleHeight - AbsolutePos.y) / max(LightDirWorld.y, 0.04);
    vec2 CloudXZ = AbsolutePos.xz + LightDirWorld.xz * Travel;
    float Coverage = SampleStyledCloudCoverage(vec3(CloudXZ.x, SampleHeight, CloudXZ.y), vec2(0.0), false);
    float OpticalDepth = Coverage * CloudExtinction * Column / max(LightDirWorld.y, 0.04);

    return SurfaceCloudTransmission(OpticalDepth, Strength);
}
#endif

#endif
