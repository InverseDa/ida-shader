#ifndef IDA_WATER_SURFACE_CACHE_GLSL
#define IDA_WATER_SURFACE_CACHE_GLSL
#include "/lib/lighting/local_grid.glsl"
// Highest actual water top in each near-field column, rebuilt every frame.
// Unknown columns do not invent a sea level (raised pools/caves remain valid).
vec2 FindWaterSurface(vec3 RelativeWorld) {
#if WATER_CAUSTICS == 1 || UNDERWATER_LIGHT == 1
    vec3 P = LocalGridPosition(RelativeWorld,cameraPosition);
    ivec2 Cell = ivec2(floor(P.xz));
    if (any(lessThan(Cell,ivec2(0))) || any(greaterThanEqual(Cell,ivec2(64)))) return vec2(0.0);
    uint Packed = LocalWaterSurface[Cell.x+64*Cell.y];
    if (Packed == 0u) return vec2(0.0);
    float Height = uintBitsToFloat(Packed);
    float Edge = min(min(P.x,P.z),min(64.0-P.x,64.0-P.z));
    return vec2(Height-P.y, smoothstep(3.0,8.0,Edge));
#else
    return vec2(0.0);
#endif
}
float WaterShoreWaveMask(vec3 RelativeWorld) {
#if WATER_CAUSTICS == 1 || UNDERWATER_LIGHT == 1
    vec3 P=LocalGridPosition(RelativeWorld,cameraPosition);
    float Edge=min(min(P.x,P.z),min(64.0-P.x,64.0-P.z));
    if (Edge<=1.0) return 1.0;
    float Wet=1.0;
    for (int K=0; K<4; ++K) {
        ivec2 C=ivec2(floor(P.xz+vec2(K%2==0 ? -0.05 : 0.05,K<2 ? -0.05 : 0.05)));
        uint H=LocalWaterSurface[C.x+64*C.y];
        Wet*=H==0u ? 0.0 : 1.0-smoothstep(0.2,0.5,abs(uintBitsToFloat(H)-P.y));
    }
    // Shared corners are pinned at dry banks; distant unknown geometry keeps
    // the global waves. Coverage changes smoothly at the cache boundary.
    return mix(1.0,Wet,smoothstep(1.0,4.0,Edge));
#else
    return 1.0;
#endif
}
#endif
