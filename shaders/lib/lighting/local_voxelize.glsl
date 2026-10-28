#ifndef IDA_LOCAL_VOXELIZE_GLSL
#define IDA_LOCAL_VOXELIZE_GLSL

// ---- Local Voxelize ----

#include "/lib/lighting/local_grid.glsl"
#include "/lib/lighting/voxel_gi.glsl"
#if PLACED_LIGHTS == 1 || (VOXEL_GI == 1 || VOXEL_REFLECTIONS == 1) || WATER_CAUSTICS == 1 || UNDERWATER_LIGHT == 1
in vec3 ShadowBlockCentre[];
in vec4 ShadowTint[];
flat in int ShadowBlockId[];
uniform sampler2D texture;

void StoreLocalVoxelBatch(uint Index, uvec2 Mask, uint Material, uint Face)
{
    if (Index == 0xffffffffu)
    {
        return;
    }

    if (Mask.x != 0u)
    {
        atomicOr(LocalOccluders[Index].x, Mask.x);
    }

    if (Mask.y != 0u)
    {
        atomicOr(LocalOccluders[Index].y, Mask.y);
    }
#if (VOXEL_GI == 1 || VOXEL_REFLECTIONS == 1)
    atomicMax(VoxelMaterial[Index * 6u + Face], Material);
#endif
}

void CollectLocalGeometry()
{
    int Id = ShadowBlockId[0];

    if (Id > 10100 && Id < 10140)
    {
        ivec3 Cell = ivec3(floor(LocalGridPosition(ShadowBlockCentre[0], cameraPosition)));

        if (InsideLocalGrid(Cell))
        {
            uint Previous = atomicMax(LocalSources[LocalIndex(Cell)], uint(Id - 10100));

            if (Previous == 0u)
            {
                ivec3 Sub = Cell & 3;
                uint Bit = uint(Sub.x + 4 * Sub.y + 16 * Sub.z);
                uint Cluster = LocalClusterIndex(Cell / 4);

                if (Bit < 32u)
                {
                    atomicOr(LocalCoarse[Cluster].x, 1u << Bit);
                }
                else
                {
                    atomicOr(LocalCoarse[Cluster].y, 1u << (Bit - 32u));
                }
            }
        }

        // Small luminous models must not shadow their own centre.
        // Full luminous cubes can be crossed only at the ray's final source cell.
        if ((Id - 10100) % 16 != 8)
        {
            return;
        }
    }
#if WATER_CAUSTICS == 1 || UNDERWATER_LIGHT == 1
    if (Id == 10092)
    {
        vec3 A = LocalGridPosition(ShadowWorld[0], cameraPosition);
        vec3 B = LocalGridPosition(ShadowWorld[1], cameraPosition);
        vec3 C = LocalGridPosition(ShadowWorld[2], cameraPosition);
        vec3 N = cross(B - A, C - A);

        // Water tops only, before discarding water from solid occupancy.
        if (N.y > 0.0001 && abs(N.y) > length(N.xz))
        {
            ivec2 Lo = max(ivec2(floor(min(A.xz, min(B.xz, C.xz)))), ivec2(0));
            ivec2 Hi = min(ivec2(floor(max(A.xz, max(B.xz, C.xz)))), ivec2(63));

            for (int Z = Lo.y; Z <= Hi.y; ++Z)
            {
                for (int X = Lo.x; X <= Hi.x; ++X)
                {
                    vec2 P = vec2(X, Z) + 0.5;
                    vec2 U = B.xz - A.xz;
                    vec2 V = C.xz - A.xz;
                    vec2 D = P - A.xz;
                    float Det = U.x * V.y - U.y * V.x;
                    vec2 W = vec2(D.x * V.y - D.y * V.x, U.x * D.y - U.y * D.x) / Det;

                    if (min(W.x, W.y) < -0.001 || W.x + W.y > 1.001)
                    {
                        continue;
                    }

                    float Height = A.y + W.x * (B.y - A.y) + W.y * (C.y - A.y);

                    if (Height > 0.0 && Height < 64.0)
                    {
                        atomicMax(LocalWaterSurface[X + 64 * Z], floatBitsToUint(Height));
                    }
                }
            }
        }

        return;
    }
#endif
    if (Id == 10092 || Id == 10093 || Id == 10190)
    {
        return; // water / glass / ice
    }
#if LOCAL_LIGHT_SHADOWS == 1 || (VOXEL_GI == 1 || VOXEL_REFLECTIONS == 1)
    vec3 A = LocalGridPosition(ShadowWorld[0], cameraPosition) * 4.0;
    vec3 B = LocalGridPosition(ShadowWorld[1], cameraPosition) * 4.0;
    vec3 C = LocalGridPosition(ShadowWorld[2], cameraPosition) * 4.0;

    // Quantize collection coordinates to 1/4096 block before ownership tests to avoid camera drift.
    A = round(A * 1024.0) / 1024.0;
    B = round(B * 1024.0) / 1024.0;
    C = round(C * 1024.0) / 1024.0;

    if (any(lessThan(max(A, max(B, C)), vec3(0.0))) ||
        any(greaterThan(min(A, min(B, C)), vec3(256.0))))
    {
        return;
    }

    vec3 N = cross(B - A, C - A);
    float Area = length(N);

    if (Area < 0.00001)
    {
        return;
    }

    N /= Area;

    // Move a surface slightly inside its solid. This keeps receivers outside
    // their own occupied voxel; normals come from geometry, never normal maps.
    A -= N * 0.03;
    B -= N * 0.03;
    C -= N * 0.03;
    vec3 AbsN = abs(N);
    int Z = AbsN.x > AbsN.y ? 0 : 1;

    if (AbsN.z > AbsN[Z])
    {
        Z = 2;
    }

    int X = (Z + 1) % 3;
    int Y = (Z + 2) % 3;
    vec2 U = vec2(B[X] - A[X], B[Y] - A[Y]);
    vec2 V = vec2(C[X] - A[X], C[Y] - A[Y]);
    float Det = U.x * V.y - U.y * V.x;
    vec2 Db = vec2(V.y, -V.x) / Det;
    vec2 Dc = vec2(-U.y, U.x) / Det;
    vec3 Pad = vec3(abs(Db.x + Dc.x) + abs(Db.y + Dc.y),
                    abs(Db.x) + abs(Db.y), abs(Dc.x) + abs(Dc.y)) *
               0.5;
    ivec2 Lo = max(ivec2(floor(min(vec2(A[X], A[Y]), min(vec2(B[X], B[Y]), vec2(C[X], C[Y]))))), ivec2(0));

    // Exclude the zero-area boundary cell to avoid overwriting neighbouring material and plane data.
    ivec2 Hi = min(ivec2(ceil(max(vec2(A[X], A[Y]), max(vec2(B[X], B[Y]), vec2(C[X], C[Y]))))) - 1, ivec2(255));

    if (min(A[Z], min(B[Z], C[Z])) > 256.0 || max(A[Z], max(B[Z], C[Z])) < 0.0)
    {
        return;
    }

    uint Face = 0u;
#if (VOXEL_GI == 1 || VOXEL_REFLECTIONS == 1)
    Face = uint(VoxelFace(N));
#endif
    // Merge quarter-block samples with local OR/MAX before SSBO writes.
    // Flush on full block-index changes so sloped triangles retain their subvoxel masks.
    for (int By = Lo.y / 4; By <= Hi.y / 4; ++By)
    {
        for (int Bx = Lo.x / 4; Bx <= Hi.x / 4; ++Bx)
        {
            uint Pending = 0xffffffffu;
            uint Material = 0u;
            uvec2 Mask = uvec2(0u);
            ivec2 First = max(Lo, ivec2(Bx, By) * 4);
            ivec2 Last = min(Hi, ivec2(Bx, By) * 4 + 3);

            for (int Yp = First.y; Yp <= Last.y; ++Yp)
            {
                for (int Xp = First.x; Xp <= Last.x; ++Xp)
                {
                    vec2 P = vec2(Xp, Yp) + 0.5;
                    vec2 Delta = P - vec2(A[X], A[Y]);
                    float Wb = dot(Db, Delta);
                    float Wc = dot(Dc, Delta);
                    vec3 W = vec3(1.0 - Wb - Wc, Wb, Wc);

                    if (any(lessThan(W, -Pad)))
                    {
                        continue;
                    }

                    // Cutout leaves and fences keep holes at the voxel sampling scale.
                    vec3 Tw = max(W, vec3(0.0));
                    Tw /= dot(Tw, vec3(1.0));
                    vec2 Uv = ShadowTexcoord[0].st * Tw.x + ShadowTexcoord[1].st * Tw.y + ShadowTexcoord[2].st * Tw.z;
                    vec4 Texel = textureLod(texture, Uv, 0.0);

                    if (Texel.a < 0.2)
                    {
                        continue;
                    }

                    float Depth = A[Z] + Wb * (B[Z] - A[Z]) + Wc * (C[Z] - A[Z]);
                    ivec3 Cell;
                    Cell[X] = Xp;
                    Cell[Y] = Yp;
                    Cell[Z] = int(floor(Depth));

                    if (any(lessThan(Cell, ivec3(0))) || any(greaterThanEqual(Cell, ivec3(256))))
                    {
                        continue;
                    }

                    uint Index = LocalIndex(Cell / 4);

                    if (Index != Pending)
                    {
                        StoreLocalVoxelBatch(Pending, Mask, Material, Face);
                        Pending = Index;
                        Mask = uvec2(0u);
                        Material = 0u;
                    }

                    ivec3 Sub = Cell & 3;
                    uint Bit = uint(Sub.x + 4 * Sub.y + 16 * Sub.z);

                    if (Bit < 32u)
                    {
                        Mask.x |= 1u << Bit;
                    }
                    else
                    {
                        Mask.y |= 1u << (Bit - 32u);
                    }
#if (VOXEL_GI == 1 || VOXEL_REFLECTIONS == 1)
                    vec3 Tint = ShadowTint[0].rgb * Tw.x + ShadowTint[1].rgb * Tw.y + ShadowTint[2].rgb * Tw.z;
                    uvec3 Rgb = uvec3(clamp(Texel.rgb * Tint, 0.0, 1.0) * 255.0 + 0.5);
                    float Plane = Depth * 0.25 + N[Z] * 0.0075 - float(Cell[Z] / 4);
                    uint Packed = Rgb.x | (Rgb.y << 8u) | (Rgb.z << 16u) | (uint(clamp(Plane, 0.0, 1.0) * 255.0 + 0.5) << 24u);
                    Material = max(Material, max(Packed, 1u));
#endif
                }
            }

            StoreLocalVoxelBatch(Pending, Mask, Material, Face);
        }
    }
#endif
}
#endif
#endif
