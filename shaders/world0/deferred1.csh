#version 430

// ---- Deferred1 ----

#include "/lib/settings.glsl"
uniform sampler2D colortex4;
uniform int frameCounter;
layout(local_size_x = 8, local_size_y = 8) in;
#if VOXEL_REFLECTIONS == 1
const ivec3 workGroups = ivec3(64, 64, 1);
layout(std430, binding = 7) buffer ReflectionTileBuffer
{
    uint ReflectionTiles[4100];
};
shared uint Occupied;
#else
const ivec3 workGroups = ivec3(1, 1, 1);
#endif
void main()
{
#if VOXEL_REFLECTIONS == 1
    if (gl_LocalInvocationIndex == 0u)
    {
        Occupied = 0u;
    }

    barrier();
    ivec2 Size = textureSize(colortex4, 0);
    ivec2 Tile = ivec2(gl_WorkGroupID.xy);

    // Include a two-pixel halo: mixed jitter, texel footprints and rounding
    // cannot hide a small object along the edge of an otherwise empty tile.
    ivec2 Lo = max(Tile * Size / 64 - 2, ivec2(0));
    ivec2 Hi = min((Tile + 1) * Size / 64 + 3, Size);
    ivec2 Span = Hi - Lo;
    uint Count = uint(Span.x * Span.y);

    for (uint I = gl_LocalInvocationIndex; I < Count; I += 64u)
    {
        ivec2 Pixel = Lo + ivec2(int(I) % Span.x, int(I) / Span.x);

        if (texelFetch(colortex4, Pixel, 0).g < 0.999999)
        {
            atomicOr(Occupied, 1u);
            break;
        }
    }

    barrier();

    if (gl_LocalInvocationIndex == 0u)
    {
        ReflectionTiles[Tile.x + 64 * Tile.y] = Occupied;

        if (Occupied != 0u)
        {
            atomicOr(ReflectionTiles[4099], 1u);
        }

        if (Tile == ivec2(0))
        {
            ReflectionTiles[4096] = uint(frameCounter) + 1u;
            ReflectionTiles[4097] = uint(Size.x);
            ReflectionTiles[4098] = uint(Size.y);
        }
    }
#endif
}
