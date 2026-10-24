#ifndef IDA_LOCAL_SHADOW_CACHE_GLSL
#define IDA_LOCAL_SHADOW_CACHE_GLSL
#include "/lib/lighting/local_grid.glsl"
#if PLACED_LIGHTS == 1
// 64 nearby shadowed sources, rebuilt after collection. More sources retain
// exact voxel tracing rather than disappearing at a global light-count cap.
layout(std430, binding = 3) buffer LocalShadowBuffer {
    uint LocalShadowSlot[262144];
    uint LocalShadowSource[64];
    float LocalShadowDepth[];
};
const int LocalShadowResolution = 96;
vec3 LocalCubeDirection(int Face, vec2 P) {
    if (Face == 0) return vec3(1.0, P.y, -P.x);
    if (Face == 1) return vec3(-1.0, P.y, P.x);
    if (Face == 2) return vec3(P.x, 1.0, -P.y);
    if (Face == 3) return vec3(P.x, -1.0, P.y);
    if (Face == 4) return vec3(P.x, P.y, 1.0);
    return vec3(-P.x, P.y, -1.0);
}
void LocalCubeProject(vec3 D, out int Face, out vec2 P) {
    vec3 A = abs(D);
    if (A.x >= A.y && A.x >= A.z) {
        Face = D.x >= 0.0 ? 0 : 1;
        P = vec2(D.x >= 0.0 ? -D.z : D.z, D.y) / A.x;
    } else if (A.y >= A.z) {
        Face = D.y >= 0.0 ? 2 : 3;
        P = vec2(D.x, D.y >= 0.0 ? -D.z : D.z) / A.y;
    } else {
        Face = D.z >= 0.0 ? 4 : 5;
        P = vec2(D.z >= 0.0 ? D.x : -D.x, D.y) / A.z;
    }
}
uint LocalShadowAddress(uint Slot, int Face, ivec2 Pixel) {
    return ((Slot * 6u + uint(Face)) * uint(LocalShadowResolution) + uint(Pixel.y)) *
           uint(LocalShadowResolution) + uint(Pixel.x);
}
float LocalShadowCacheTap(uint Slot, int Face, ivec2 Pixel, float ReceiverPlane, vec3 Normal) {
    // Reproject edge taps onto adjacent faces; clamping them would leave a seam.
    if (any(lessThan(Pixel, ivec2(0))) || any(greaterThanEqual(Pixel, ivec2(LocalShadowResolution)))) {
        vec3 Direction = LocalCubeDirection(Face, (vec2(Pixel) + 0.5) * (2.0 / float(LocalShadowResolution)) - 1.0);
        vec2 P;
        LocalCubeProject(Direction, Face, P);
        Pixel = clamp(ivec2((P * 0.5 + 0.5) * float(LocalShadowResolution)), ivec2(0), ivec2(LocalShadowResolution - 1));
    }
    float Depth = LocalShadowDepth[LocalShadowAddress(Slot, Face, Pixel)];
    vec3 Ray = LocalCubeDirection(Face, (vec2(Pixel) + 0.5) * (2.0 / float(LocalShadowResolution)) - 1.0);
    // Compare in each tap's receiver plane, not against one radial distance.
    // This avoids large slope bias / detached shadows at grazing angles.
    float Reference = ReceiverPlane / min(dot(Ray, Normal), -0.0001);
    vec3 A = abs(Normal);
    float Bias = 0.06 + 0.35 * (1.0 - max(A.x, max(A.y, A.z)));
    return step(Reference - Bias, Depth);
}
float CachedPlacedLightVisibility(uint Index, vec3 Delta, vec3 ReceiverNormal) {
    uint Slot = LocalShadowSlot[Index] - 1u;
    float Distance = length(Delta);
    if (Distance < 0.1) return 1.0;
    int Face;
    vec2 P;
    LocalCubeProject(-Delta, Face, P);
    vec2 Pixel = (P * 0.5 + 0.5) * float(LocalShadowResolution) - 0.5;
    ivec2 Lo = ivec2(floor(Pixel));
    vec2 F = fract(Pixel);
    float Plane = -dot(Delta, ReceiverNormal);
    float A = LocalShadowCacheTap(Slot, Face, Lo, Plane, ReceiverNormal);
    float B = LocalShadowCacheTap(Slot, Face, Lo + ivec2(1,0), Plane, ReceiverNormal);
    float C = LocalShadowCacheTap(Slot, Face, Lo + ivec2(0,1), Plane, ReceiverNormal);
    float D = LocalShadowCacheTap(Slot, Face, Lo + ivec2(1,1), Plane, ReceiverNormal);
    return mix(mix(A, B, F.x), mix(C, D, F.x), F.y);
}
#endif
#endif
