#ifndef IDA_VOXEL_GI_GLSL
#define IDA_VOXEL_GI_GLSL

// ---- Voxel Gi ----

#include "/lib/lighting/local_grid.glsl"
#if (VOXEL_GI == 1 || VOXEL_REFLECTIONS == 1)
// Six oriented surface records per block. Quarter-block occupancy remains
// authoritative for visibility; radiance is a lower-frequency surface cache.
layout(std430, binding = 4) buffer VoxelMaterialBuffer
{
    uint VoxelMaterial[1572864];
};
layout(std430, binding = 5) buffer VoxelRadianceBuffer
{
    uvec2 VoxelRadiance[1572864];
};
#if VOXEL_GI == 1
layout(std430, binding = 6) buffer VoxelBounceBuffer
{
    uvec2 VoxelBounce[1572864];
};
#endif
vec3 VoxelFaceNormal(int Face)
{
    vec3 N = vec3(0.0);
    N[Face / 2] = (Face % 2 == 0) ? 1.0 : -1.0;

    return N;
}

int VoxelFace(vec3 N)
{
    vec3 A = abs(N);
    int Axis = A.x > A.y ? 0 : 1;

    if (A.z > A[Axis])
    {
        Axis = 2;
    }

    return Axis * 2 + (N[Axis] < 0.0 ? 1 : 0);
}

vec3 VoxelFacePosition(ivec3 Cell, int Face, uint Material)
{
    vec3 P = vec3(Cell) + 0.5;
    P[Face / 2] = float(Cell[Face / 2]) + float(Material >> 24u) / 255.0;

    return P;
}

vec3 VoxelAlbedo(uint M)
{
    return pow(vec3(M & 255u, (M >> 8u) & 255u, (M >> 16u) & 255u) / 255.0, vec3(2.2));
}

uvec2 PackVoxelLight(vec3 L)
{
    L = clamp(L, vec3(0.0), vec3(64.0));

    return uvec2(packHalf2x16(L.xy), packHalf2x16(vec2(L.z, 0.0)));
}

vec3 UnpackVoxelLight(uvec2 L)
{
    return vec3(unpackHalf2x16(L.x), unpackHalf2x16(L.y).x);
}

// Hierarchical, deterministic DDA. A miss contributes zero bounce, never a
// constant ambient floor. Out-of-volume geometry is unknown, not an emitter.
bool TraceVoxel(vec3 Start, vec3 Direction, float Range, out vec3 Hit, out ivec3 Cell)
{
    vec3 Inv = 1.0 / max(abs(Direction), vec3(0.000001));
    float T = 0.0;

    for (int I = 0; I < 160; ++I)
    {
        Hit = Start + Direction * T;
        Cell = ivec3(floor(Hit));

        if (T >= Range || !InsideLocalGrid(Cell))
        {
            return false;
        }

        float Scale = 0.25;

        if (LocalOccluderCoarse[LocalClusterIndex(Cell / 4)] != 0u)
        {
            Scale = 1.0;
            uvec2 Mask = LocalOccluders[LocalIndex(Cell)];

            if (any(notEqual(Mask, uvec2(0u))))
            {
                ivec3 Sub = ivec3(floor(fract(Hit) * 4.0));
                uint Bit = uint(Sub.x + 4 * Sub.y + 16 * Sub.z);
                uint Word = Bit < 32u ? Mask.x : Mask.y;

                if ((Word & (1u << (Bit & 31u))) != 0u)
                {
                    return true;
                }

                Scale = 4.0;
            }
        }

        vec3 Boundary = (floor(Hit * Scale) + step(vec3(0.0), Direction)) / Scale;
        vec3 Dt = abs(Boundary - Hit) * Inv;
        Dt = mix(vec3(1e6), Dt, greaterThanEqual(abs(Direction), vec3(0.000001)));
        T += min(Dt.x, min(Dt.y, Dt.z)) + 0.0001;
    }

    // Exhaustion blocks visibility, but is not a geometric surface hit.
    // Reflection/gather callers must not turn the final empty cell into a wall.
    Cell = ivec3(-1);

    return true;
}

#if VOXEL_GI == 1
vec3 SampleVoxelBounce(vec3 RelativeWorld, vec3 NormalWorld)
{
    vec3 P = LocalGridPosition(RelativeWorld, cameraPosition);
    float Coverage = LocalGridCoverage(P - LocalGridPhase(cameraPosition));

    if (Coverage <= 0.0 || VOXEL_GI_STRENGTH <= 0.0)
    {
        return vec3(0.0);
    }

    int Face = VoxelFace(NormalWorld);
    int Axis = Face / 2;
    int X = (Axis + 1) % 3;
    int Y = (Axis + 2) % 3;
    vec3 N = VoxelFaceNormal(Face);
    ivec3 Centre = ivec3(floor(P - N * 0.04));

    if (!InsideLocalGrid(Centre))
    {
        return vec3(0.0);
    }

    uint Links = VoxelBounce[LocalIndex(Centre) * 6u + uint(Face)].y >> 16u;
    ivec2 Base = ivec2(floor(vec2(P[X], P[Y]) - 0.5));
    vec2 F = fract(vec2(P[X], P[Y]) - 0.5);
    vec3 Sum = vec3(0.0);
    float Weight = 0.0;

    for (int K = 0; K < 4; ++K)
    {
        ivec3 Cell = Centre;
        Cell[X] = Base.x + K % 2;
        Cell[Y] = Base.y + K / 2;

        if (!InsideLocalGrid(Cell))
        {
            continue;
        }

        int Link = (Cell[X] - Centre[X] + 1) + 3 * (Cell[Y] - Centre[Y] + 1);

        if ((Links & (1u << uint(Link))) == 0u)
        {
            continue;
        }

        uint Index = LocalIndex(Cell) * 6u + uint(Face);
        uint M = VoxelMaterial[Index];

        if (M == 0u)
        {
            continue;
        }

        vec3 Q = VoxelFacePosition(Cell, Face, M);

        // Same-facing, coplanar receivers only. Slabs/opposite wall faces may
        // not interpolate light across their depth discontinuity.
        if (abs(Q[Axis] - P[Axis]) > 0.09)
        {
            continue;
        }

        float W = (K % 2 == 0 ? 1.0 - F.x : F.x) * (K < 2 ? 1.0 - F.y : F.y);
        Sum += UnpackVoxelLight(VoxelBounce[Index]) * W;
        Weight += W;
    }

    return Sum / max(Weight, 0.001) * Coverage * VOXEL_GI_STRENGTH;
}
#endif
#endif
#endif
