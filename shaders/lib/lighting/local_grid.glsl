#ifndef IDA_LOCAL_GRID_GLSL
#define IDA_LOCAL_GRID_GLSL
#include "/lib/settings.glsl"
#if PLACED_LIGHTS == 1 || (VOXEL_GI == 1 || VOXEL_REFLECTIONS == 1) || WATER_CAUSTICS == 1 || UNDERWATER_LIGHT == 1
// Fixed world-space storage: 64^3 block records, 4^3 occupancy bits/block,
// and eight deterministic candidates per 4-block cluster. No 5K-sized target.
layout(std430, binding = 0) buffer LocalSourceBuffer {
    uint LocalSources[262144];
    uvec2 LocalCoarse[4096]; // One bit per source cell in each 4^3 cluster.
};
layout(std430, binding = 1) buffer LocalOccluderBuffer {
    uvec2 LocalOccluders[262144];
    uint LocalOccluderCoarse[4096];
    uint LocalWaterSurface[4096];
};
layout(std430, binding = 2) buffer LocalClusterBuffer {
    uint LocalCandidates[32768];
};
uint LocalIndex(ivec3 P) { return uint(P.x + 64 * (P.y + 64 * P.z)); }
uint LocalClusterIndex(ivec3 P) { return uint(P.x + 16 * (P.y + 16 * P.z)); }
ivec3 LocalCell(uint I) { return ivec3(I & 63u, (I >> 6u) & 63u, I >> 12u); }
// Enumerate only occupied source cells, in the original x/y/z scan order.
uint PopLocalSourceBit(inout uvec2 Mask) {
    if (Mask.x != 0u) {
        uint Bit = uint(findLSB(Mask.x));
        Mask.x &= Mask.x - 1u;
        return Bit;
    }
    uint Bit = uint(findLSB(Mask.y));
    Mask.y &= Mask.y - 1u;
    return Bit + 32u;
}
ivec3 LocalClusterCell(ivec3 Cluster, uint Bit) {
    return Cluster * 4 + ivec3(Bit & 3u, (Bit >> 2u) & 3u, Bit >> 4u);
}
bool InsideLocalGrid(ivec3 P) { return all(greaterThanEqual(P, ivec3(0))) && all(lessThan(P, ivec3(64))); }
vec3 LocalGridPhase(vec3 Camera) {
    return Camera - floor(Camera * 0.25 + 0.5) * 4.0;
}
vec3 LocalGridPosition(vec3 RelativeWorld, vec3 Camera) {
    // Subtract the integer origin before arithmetic, including at large XYZ.
    // Four-block origin alignment keeps cluster partitions fixed in the world
    // while walking; only storage indices change when the volume rebases.
    return RelativeWorld + LocalGridPhase(Camera) + 32.0;
}
float LocalGridCoverage(vec3 GridPosition) {
    vec3 Edge = min(GridPosition, vec3(64.0) - GridPosition);
    // A complete maximum-radius light neighbourhood exists inside this fade.
    return smoothstep(15.0, 19.0, min(Edge.x, min(Edge.y, Edge.z)));
}
float PlacedLightLevel(uint Type) {
    if (Type >= 32u) return 7.0;
    if (Type >= 16u) return 10.0;
    return (Type & 15u) >= 6u ? 15.0 : 14.0;
}
vec3 PlacedLightColor(uint Type) {
    if (Type >= 32u) return vec3(1.0, 0.08, 0.025);
    if (Type >= 16u) return vec3(0.18, 0.65, 1.0);
    return vec3(1.0, 0.67, 0.32);
}
vec3 PlacedLightOffset(uint Type) {
    uint Shape = Type & 15u;
    if (Shape == 1u) return vec3(0.5, 0.68, 0.5);
    if (Shape == 2u) return vec3(0.5, 0.82, 0.73); // facing north
    if (Shape == 3u) return vec3(0.5, 0.82, 0.27); // south
    if (Shape == 4u) return vec3(0.73, 0.82, 0.5); // west
    if (Shape == 5u) return vec3(0.27, 0.82, 0.5); // east
    if (Shape == 6u) return vec3(0.5, 0.3, 0.5);
    if (Shape == 7u) return vec3(0.5, 0.62, 0.5);
    return vec3(0.5);
}
// Fade the weakest retained source before a cluster's eight-source limit.
// The distance bound is independent of enumeration / triangle submission order.
float LocalCandidateLimit(vec3 P, uint Base) {
    uint Last = LocalCandidates[Base + 7u];
    if (Last == 0xffffffffu) return -1.0;
    vec3 LastPosition = vec3(LocalCell(Last)) + PlacedLightOffset(LocalSources[Last]);
    vec3 Centre = floor(P / 4.0) * 4.0 + 2.0;
    return length(LastPosition - Centre);
}
float LocalCandidateWeight(vec3 P, vec3 Light, float Limit) {
    if (Limit < 0.0) return 1.0;
    return 1.0 - smoothstep(max(Limit - 7.0, 0.0), max(Limit, 0.001), length(Light - P));
}
float LocalCandidateWeight(vec3 P, vec3 Light, uint Base) {
    return LocalCandidateWeight(P, Light, LocalCandidateLimit(P, Base));
}
#endif
#endif
