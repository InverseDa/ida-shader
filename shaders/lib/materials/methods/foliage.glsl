#ifndef IDA_FOLIAGE_GLSL
#define IDA_FOLIAGE_GLSL
vec3 FoliageOffset(vec3 RelativeWorld, float Id, vec2 Uv, vec2 MidUv) {
    if (Id != 10091.0 || Uv.y > MidUv.y) return vec3(0.0);
    vec3 AbsolutePos = RelativeWorld + cameraPosition;
    vec2 Phase = texture2D(noisetex, AbsolutePos.xz / 256.0).xy * 10.0;
    return vec3(sin(frameTimeCounter * 1.8 + Phase.x), 0.0, sin(frameTimeCounter * 1.8 + Phase.y)) *
           0.2;
}
#endif
