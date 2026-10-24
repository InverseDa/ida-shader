#ifndef IDA_LIGHTING_SKY_COLOR_GLSL
#define IDA_LIGHTING_SKY_COLOR_GLSL
#include "/lib/common/color.glsl"

vec3 GetFrameSkyColor(vec3 VanillaDisplayColor, float NightAmount) {
    // Retain the v0.1a night palette (the 13000-23000 skyColorArr entries).
    // Blend in display space before linearization, as the released table did.
    // Daytime still uses the engine's biome/weather sky color.
    return SrgbToLinear(mix(VanillaDisplayColor, vec3(0.02, 0.20, 0.27), NightAmount));
}

#endif
