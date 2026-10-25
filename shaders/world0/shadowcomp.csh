#version 430
#include "/lib/lighting/local_grid.glsl"
layout(local_size_x = 64) in;
const ivec3 workGroups = ivec3(16, 16, 16);
#if (PLACED_LIGHTS == 1 || (VOXEL_GI == 1 || VOXEL_REFLECTIONS == 1))
shared uint Nearest[8];
#endif
void main() {
#if (PLACED_LIGHTS == 1 || (VOXEL_GI == 1 || VOXEL_REFLECTIONS == 1))
    uint Lane = gl_LocalInvocationID.x;
    if (Lane < 8u) Nearest[Lane] = 0xffffffffu;
    barrier();
    ivec3 Cluster = ivec3(gl_WorkGroupID);
    ivec3 Block = Cluster * 4 + ivec3(Lane & 3u, (Lane >> 2u) & 3u, Lane >> 4u);
    if (any(notEqual(LocalOccluders[LocalIndex(Block)], uvec2(0u))))
        atomicOr(LocalOccluderCoarse[LocalClusterIndex(Cluster)], 1u);
    vec3 Centre = vec3(Cluster * 4) + 2.0;
    // Scan occupancy first: empty neighbourhoods cost no per-source search.
    for (uint K = Lane; K < 729u; K += 64u) {
        ivec3 C = Cluster + ivec3(K % 9u, (K / 9u) % 9u, K / 81u) - 4;
        if (any(lessThan(C, ivec3(0))) || any(greaterThanEqual(C, ivec3(16)))) continue;
        if (LocalCoarse[LocalClusterIndex(C)] == 0u) continue;
        for (uint J = 0u; J < 64u; ++J) {
            ivec3 Cell = C * 4 + ivec3(J & 3u, (J >> 2u) & 3u, J >> 4u);
            uint Index = LocalIndex(Cell), Type = LocalSources[Index];
            if (Type == 0u) continue;
            vec3 Delta = vec3(Cell) + PlacedLightOffset(Type) - Centre;
            float Range = PlacedLightLevel(Type) * 0.85 + 3.465;
            float D2 = dot(Delta, Delta);
            if (D2 >= Range * Range) continue;
            // Lexicographic distance / cell ordering, with no racing append cap.
            uint Key = (uint(D2 * 16.0) << 18u) | Index;
            for (int N = 0; N < 8; ++N) {
                uint Previous = atomicMin(Nearest[N], Key);
                Key = max(Key, Previous);
                if (Key == 0xffffffffu) break;
            }
        }
    }
    barrier();
    if (Lane < 8u) {
        uint Key = Nearest[Lane];
        LocalCandidates[LocalClusterIndex(Cluster) * 8u + Lane] =
            Key == 0xffffffffu ? Key : (Key & 262143u);
    }
#endif
}
