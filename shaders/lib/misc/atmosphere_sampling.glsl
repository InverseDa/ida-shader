#ifndef IDA_ATMOSPHERE_SAMPLING_GLSL
#define IDA_ATMOSPHERE_SAMPLING_GLSL

// ---- Atmosphere Sampling ----

#include "/lib/post/taa.glsl"

vec2 AtmosphereJitter()
{
    // Offset in the off-screen grid. Remove it during reconstruction; final
    // TAA accumulates the remaining variation in the existing colour history.
    return GetTaaHaltonOffset(frameCounter) - 0.5;
}

vec2 AtmosphereCacheSize()
{
    vec2 Size = max(floor(vec2(viewWidth, viewHeight) * 0.5), vec2(1.0));
#if CLOUD_QUARTER_RES == 1
    // The cloud pass uses the lower-left quarter of the shared half-size
    // attachment. SSR and Bloom later retain its full half-size allocation.
    Size = max(floor(Size * 0.5), vec2(1.0));
#endif
    return Size;
}
#endif
