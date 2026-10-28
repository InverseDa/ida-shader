// ---- Water Leaf Source ----

#include "/lib/settings.glsl"
uniform float viewWidth;
uniform float viewHeight;
uniform mat4 gbufferProjectionInverse;
#include "/lib/reflections/water_hierarchy.glsl"
layout(local_size_x = 8, local_size_y = 8) in;
const ivec3 workGroups = ivec3(128, 128, 1);

void main()
{
    ivec2 Cell = ivec2(gl_GlobalInvocationID.xy);
    ivec2 Size = WaterSourceSize();

    if (any(greaterThanEqual(Cell, Size)))
    {
        return;
    }

    WaterLeafSeeds[Cell.x + Cell.y * 1024] = 0u;
    uvec4 Front = WaterNodes[WaterNodeIndex(Cell, 0)];
    uvec4 Back = WaterBackNode(Cell);
    float Existing = min(WaterNodeIsLeaf(Front) ? uintBitsToFloat(Front.x) : 1e20, WaterNodeIsLeaf(Back) ? uintBitsToFloat(Back.x) : 1e20);
    float Nearby = 1e20;
    ivec2 Group = Cell / 8;

    for (int Y = -1; Y <= 1; ++Y)
    {
        for (int X = -1; X <= 1; ++X)
        {
            ivec2 G = clamp(Group + ivec2(X, Y), ivec2(0), ivec2(127));
            Nearby = min(Nearby, uintBitsToFloat(WaterLeafGroups[G.x + G.y * 128]));
        }
    }

    if (Nearby >= min(24.0, Existing - 0.13))
    {
        return;
    }

    uint Best = 0u;
    float BestDistance = 1e20;

    // Separate seeds avoid source read/write hazards; close gaps only between observed leaf samples.
    for (int Ring = 0; Ring < 4; ++Ring)
    {
        for (int K = 0; K < 8; ++K)
        {
            ivec2 Direction = ivec2(K % 3 - 1, K / 3 - 1);

            if (K == 4)
            {
                Direction = ivec2(1, 1);
            }

            ivec2 Offset = Direction * (1 << Ring);
            ivec2 Tap = Cell + Offset;

            if (any(lessThan(Tap, ivec2(0))) || any(greaterThanEqual(Tap, Size)))
            {
                continue;
            }

            vec2 PixelWorld = 2.0 * vec2(Offset) / vec2(Size) * vec2(gbufferProjectionInverse[0].x, gbufferProjectionInverse[1].y);

            for (int Layer = 0; Layer < 2; ++Layer)
            {
                int Index = Layer == 0 ? WaterNodeIndex(Tap, 0) : 1398016 + Tap.x + Tap.y * 1024;
                uvec4 Node = WaterNodes[Index];

                if (!WaterNodeIsLeaf(Node))
                {
                    continue;
                }

                float Depth = uintBitsToFloat(Node.x);
                float Distance = length(PixelWorld) * Depth;

                // Two 16px texture texels at most; far foliage already integrates
                // within the normal source footprint and needs no expansion.
                if (Depth >= min(24.0, Existing - 0.13) || Distance > 0.125 || Distance >= BestDistance)
                {
                    continue;
                }

                BestDistance = Distance;
                Best = uint(Index) + 1u;
            }
        }
    }

    WaterLeafSeeds[Cell.x + Cell.y * 1024] = Best;
}
