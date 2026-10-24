#ifndef IDA_COLOR_GLSL
#define IDA_COLOR_GLSL
bool IsFiniteRadiance(vec3 Color) {
    return !(any(isnan(Color)) || any(isinf(Color)));
}

vec3 SanitizeRadiance(vec3 Color) {
    // Reject a bad sample before filtering: clamping NaN is not a portable
    // substitute, and can turn it into the HDR upper bound on some drivers.
    if (!IsFiniteRadiance(Color)) return vec3(0.0);
    return max(Color, vec3(0.0));
}

vec3 SrgbToLinear(vec3 C) {
    C = max(C, vec3(0.0));
    return mix(C / 12.92, pow((C + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), C));
}

vec3 LinearToSrgb(vec3 C) {
    C = max(C, vec3(0.0));
    return mix(C * 12.92, 1.055 * pow(C, vec3(1.0 / 2.4)) - 0.055, step(vec3(0.0031308), C));
}
#endif
