#ifndef IDA_COMMON_PACKING_GLSL
#define IDA_COMMON_PACKING_GLSL
vec3 SafeNormal(vec3 N) {
    return dot(N, N) > 0.000001 ? normalize(N) : vec3(0.0, 0.0, 1.0);
}

vec2 SignNotZero(vec2 V) {
    return vec2(V.x >= 0.0 ? 1.0 : -1.0, V.y >= 0.0 ? 1.0 : -1.0);
}

vec2 NormalEncode(vec3 N) {
    float L = abs(N.x) + abs(N.y) + abs(N.z);
    if (L < 0.000001) return vec2(0.5);
    N /= L;
    vec2 E = N.xy;
    if (N.z < 0.0) E = (1.0 - abs(E.yx)) * SignNotZero(E);
    return E * 0.5 + 0.5;
}

vec3 NormalDecode(vec2 E) {
    vec2 F = clamp(E, 0.0, 1.0) * 2.0 - 1.0;
    vec3 N = vec3(F, 1.0 - abs(F.x) - abs(F.y));
    if (N.z < 0.0) N.xy = (1.0 - abs(N.yx)) * SignNotZero(N.xy);
    return normalize(N);
}
#endif
