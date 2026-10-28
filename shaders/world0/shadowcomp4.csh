#version 430

// ---- Shadowcomp4 ----

uniform vec3 cameraPosition;
#include "/lib/lighting/voxel_gi.glsl"
layout(local_size_x = 64) in;
const ivec3 workGroups = ivec3(24576, 1, 1);

void main()
{
#if VOXEL_GI == 1
    uint Index = gl_GlobalInvocationID.x;
    uint M = VoxelMaterial[Index];
    VoxelBounce[Index] = uvec2(0u);

    if (M == 0u)
    {
        return;
    }

    int Face = int(Index % 6u);
    ivec3 Cell = LocalCell(Index / 6u);
    vec3 N = VoxelFaceNormal(Face);
    vec3 P = VoxelFacePosition(Cell, Face, M) + N * 0.04;
    vec3 Tangent = VoxelFaceNormal(((Face / 2 + 1) % 3) * 2);
    vec3 Bitangent = cross(N, Tangent);
    vec3 Sum = vec3(0.0);

    for (int K = 0; K < VOXEL_GI_SAMPLES; ++K)
    {
        float R2 = (float(K) + 0.5) / float(VOXEL_GI_SAMPLES);
        float Angle = float(K) * 2.39996323;
        vec3 D = Tangent * (sqrt(R2) * cos(Angle)) + Bitangent * (sqrt(R2) * sin(Angle)) + N * sqrt(1.0 - R2);
        vec3 Hit;
        ivec3 B;

        if (!TraceVoxel(P, D, 12.0, Hit, B) || !InsideLocalGrid(B))
        {
            continue;
        }

        // Use the closest opposing face in the occupied cell. Looking up an
        // unrelated far face would transfer light through a one-block wall.
        float Best = 1e6;
        vec3 Light = vec3(0.0);

        for (int F = 0; F < 6; ++F)
        {
            if (dot(VoxelFaceNormal(F), D) >= -0.01)
            {
                continue;
            }

            uint J = LocalIndex(B) * 6u + uint(F);
            uint Material = VoxelMaterial[J];

            if (Material == 0u)
            {
                continue;
            }

            vec3 Q = VoxelFacePosition(B, F, Material);
            float Error = abs(Q[F / 2] - Hit[F / 2]);

            if (Error < Best && Error < 0.3)
            {
                Best = Error;
                Light = UnpackVoxelLight(VoxelRadiance[J]);
            }
        }

        float Fade = 1.0 - smoothstep(8.0, 12.0, length(Hit - P));
        Sum += Light * Fade;
    }

    // Visibility for interpolation is cached too: crossing a wall between
    // neighbouring floor samples must not leak their irradiance at 5K.
    uint Links = 0u;
    int Axis = Face / 2;
    int X = (Axis + 1) % 3;
    int Y = (Axis + 2) % 3;

    for (int K = 0; K < 9; ++K)
    {
        ivec3 B = Cell;
        B[X] += K % 3 - 1;
        B[Y] += K / 3 - 1;

        if (!InsideLocalGrid(B))
        {
            continue;
        }

        uint Material = VoxelMaterial[LocalIndex(B) * 6u + uint(Face)];

        if (Material == 0u)
        {
            continue;
        }

        vec3 Q = VoxelFacePosition(B, Face, Material) + N * 0.04;

        if (abs(Q[Axis] - P[Axis]) > 0.09)
        {
            continue;
        }

        vec3 Delta = Q - P;
        float Distance = length(Delta);
        vec3 Hit;
        ivec3 Block;

        if (K == 4 || !TraceVoxel(P, Delta / max(Distance, 0.001), Distance, Hit, Block))
        {
            Links |= 1u << uint(K);
        }
    }

    uvec2 Packed = PackVoxelLight(Sum / float(VOXEL_GI_SAMPLES));
    Packed.y |= Links << 16u;
    VoxelBounce[Index] = Packed;
#endif
}
