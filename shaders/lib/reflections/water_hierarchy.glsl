#ifndef IDA_WATER_HIERARCHY_GLSL
#define IDA_WATER_HIERARCHY_GLSL

// ---- Water Hierarchy ----

// The first 4100 words are the generic SSR header; water follows with immutable observed layers.
// Capacity is fixed at 1024 squared, two layers and seven hierarchy levels.
#ifndef IDA_REFLECTION_STORAGE_GLSL
#define IDA_REFLECTION_STORAGE_GLSL
layout(std430, binding = 7) buffer ReflectionTileBuffer
{
    uint ReflectionTiles[4100];
    uvec4 WaterNodes[2446592];
    uint WaterLeafSeeds[1048576];
    uint WaterLeafGroups[16384];
};
#endif
ivec2 WaterSourceSize()
{
    vec2 Full = vec2(viewWidth, viewHeight);

    return max(ivec2(ceil(Full / max(2.0, max(Full.x, Full.y) / 1024.0))), ivec2(1));
}

int WaterNodeIndex(ivec2 Cell, int Level)
{
    int Width = 1024 >> Level;
    int Offset = (1048576 - (1048576 >> (Level * 2))) * 4 / 3;

    return Offset + Cell.x + Cell.y * Width;
}

vec2 WaterDepthRange(ivec2 Cell, int Level)
{
    return uintBitsToFloat(WaterNodes[WaterNodeIndex(Cell, Level)].xy);
}

vec3 WaterSourceColor(ivec2 Cell)
{
    uvec4 Node = WaterNodes[WaterNodeIndex(Cell, 0)];

    return vec3(abs(unpackHalf2x16(Node.z)), unpackHalf2x16(Node.w).x);
}

bool WaterNodeIsLeaf(uvec4 Node)
{
    return (Node.z & 0x80000000u) != 0u;
}

vec3 WaterNodeColor(uvec4 Node)
{
    return vec3(abs(unpackHalf2x16(Node.z)), unpackHalf2x16(Node.w).x);
}

uvec4 WaterLeafNode(ivec2 Cell)
{
    uint Seed = WaterLeafSeeds[Cell.x + Cell.y * 1024];

    return Seed == 0u ? uvec4(floatBitsToUint(1e20), 0u, 0u, 0u) : WaterNodes[Seed - 1u];
}

uvec4 WaterBackNode(ivec2 Cell)
{
    return WaterNodes[1398016 + Cell.x + Cell.y * 1024];
}

vec2 WaterNodeRange(ivec2 Cell, int Level)
{
    vec2 D = WaterDepthRange(Cell, Level);

    if (Level == 0)
    {
        D.y = max(D.y, uintBitsToFloat(WaterBackNode(Cell).y));
        vec2 L = uintBitsToFloat(WaterLeafNode(Cell).xy);

        if (L.y > 0.0)
        {
            D.x = min(D.x, L.x - 0.13);
            D.y = max(D.y, L.y + 0.13);
        }
    }

    return D;
}
#endif
