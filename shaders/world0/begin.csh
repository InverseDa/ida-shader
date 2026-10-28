#version 430

// ---- Begin ----

#include "/lib/lighting/local_shadow_cache.glsl"
uniform vec3 cameraPosition;
#include "/lib/lighting/voxel_gi.glsl"
#if VOXEL_REFLECTIONS == 1
layout(std430, binding = 7) buffer ReflectionTileBuffer
{
    uint ReflectionTiles[4100];
};
#endif
layout(local_size_x = 256) in;
const ivec3 workGroups = ivec3(1024, 1, 1);

void main()
{
#if PLACED_LIGHTS == 1 || (VOXEL_GI == 1 || VOXEL_REFLECTIONS == 1) || WATER_CAUSTICS == 1 || UNDERWATER_LIGHT == 1
    uint I = gl_GlobalInvocationID.x;
#if VOXEL_REFLECTIONS == 1
    if (I == 0u)
    {
        ReflectionTiles[4096] = 0u;
        ReflectionTiles[4099] = 0u;
    }
#endif
    LocalSources[I] = 0u;
#if PLACED_LIGHTS == 1
    LocalShadowSlot[I] = 0u;

    if (I < 64u)
    {
        LocalShadowSource[I] = 0xffffffffu;
    }
#endif
    LocalOccluders[I] = uvec2(0u);

    if (I < 4096u)
    {
        LocalWaterSurface[I] = 0u;
        LocalCoarse[I] = uvec2(0u);
        LocalOccluderCoarse[I] = 0u;
    }

    if (I < 32768u)
    {
        LocalCandidates[I] = 0xffffffffu;
    }
#if (VOXEL_GI == 1 || VOXEL_REFLECTIONS == 1)
    for (uint F = 0u; F < 6u; ++F)
    {
        VoxelMaterial[I * 6u + F] = 0u;
    }
#endif
#endif
}
