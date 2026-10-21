#ifndef IDA_COMMON_PACKING_GLSL
#define IDA_COMMON_PACKING_GLSL
vec3 safeNormal(vec3 n) { return dot(n, n) > 0.000001 ? normalize(n) : vec3(0.0, 0.0, 1.0); }
vec2 signNotZero(vec2 v) { return vec2(v.x >= 0.0 ? 1.0 : -1.0, v.y >= 0.0 ? 1.0 : -1.0); }
vec2 normalEncode(vec3 n) {
    float l = abs(n.x) + abs(n.y) + abs(n.z);
    if (l < 0.000001) return vec2(0.5);
    n /= l;
    vec2 e = n.xy;
    if (n.z < 0.0) e = (1.0 - abs(e.yx)) * signNotZero(e);
    return e * 0.5 + 0.5;
}
vec3 normalDecode(vec2 e) {
    vec2 f = clamp(e, 0.0, 1.0) * 2.0 - 1.0;
    vec3 n = vec3(f, 1.0 - abs(f.x) - abs(f.y));
    if (n.z < 0.0) n.xy = (1.0 - abs(n.yx)) * signNotZero(n.xy);
    return normalize(n);
}
#endif
