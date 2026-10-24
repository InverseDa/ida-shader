#ifndef IDA_COLOR_GLSL
#define IDA_COLOR_GLSL
bool isFiniteRadiance(vec3 color) {
    return !(any(isnan(color)) || any(isinf(color)));
}

vec3 sanitizeRadiance(vec3 color) {
    // Reject a bad sample before filtering: clamping NaN is not a portable
    // substitute, and can turn it into the HDR upper bound on some drivers.
    if (!isFiniteRadiance(color)) return vec3(0.0);
    return max(color, vec3(0.0));
}

vec3 srgbToLinear(vec3 c) {
    c = max(c, vec3(0.0));
    return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}
vec3 linearToSrgb(vec3 c) {
    c = max(c, vec3(0.0));
    return mix(c * 12.92, 1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055, step(vec3(0.0031308), c));
}
#endif
