#ifndef IDA_LIGHTING_SKY_COLOR_GLSL
#define IDA_LIGHTING_SKY_COLOR_GLSL

// ---- Sky Color ----

#include "/lib/common/color.glsl"

vec3 GetFrameSkyColor(vec3 VanillaDisplayColor, float NightAmount)
{
    // Blend the night palette in display space before linearization; daytime uses the engine sky.
    return SrgbToLinear(mix(VanillaDisplayColor, vec3(0.02, 0.20, 0.27), NightAmount));
}

#endif
