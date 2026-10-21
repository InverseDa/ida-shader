#ifndef IDA_FOLIAGE_GLSL
#define IDA_FOLIAGE_GLSL
vec3 foliageOffset(vec3 relativeWorld, float id, vec2 uv, vec2 midUv) {
    if (id != 10091.0 || uv.y > midUv.y) return vec3(0.0);
    vec3 absolutePos = relativeWorld + cameraPosition;
    vec2 phase = texture2D(noisetex, absolutePos.xz / 256.0).xy * 10.0;
    return vec3(sin(frameTimeCounter * 1.8 + phase.x), 0.0,
                sin(frameTimeCounter * 1.8 + phase.y)) * 0.2;
}
#endif
