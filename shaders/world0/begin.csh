#version 430
#include "/lib/lighting/local_shadow_cache.glsl"
layout(local_size_x = 256) in;
const ivec3 workGroups = ivec3(1024, 1, 1);
void main() {
#if PLACED_LIGHTS == 1
    uint I = gl_GlobalInvocationID.x;
    LocalSources[I] = 0u;
    LocalShadowSlot[I] = 0u;
    if (I < 64u) LocalShadowSource[I] = 0xffffffffu;
    LocalOccluders[I] = uvec2(0u);
    if (I < 4096u) {
        LocalCoarse[I] = 0u;
        LocalOccluderCoarse[I] = 0u;
    }
    if (I < 32768u) LocalCandidates[I] = 0xffffffffu;
#endif
}
