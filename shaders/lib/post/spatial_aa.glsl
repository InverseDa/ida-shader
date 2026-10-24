#ifndef IDA_SPATIAL_AA_GLSL
#define IDA_SPATIAL_AA_GLSL
#include "/lib/settings.glsl"
#include "/lib/common/color.glsl"

vec3 sampleAaColor(vec2 uv) {
    vec2 halfTexel = 0.5 / vec2(textureSize(colortex0, 0));
    return sanitizeRadiance(texture2D(colortex0, clamp(uv, halfTexel, vec2(1.0) - halfTexel)).rgb);
}

float aaLuminance(vec3 color) {
    return dot(color, vec3(0.299, 0.587, 0.114));
}

vec3 aaCompress(vec3 color) {
    color = max(color, vec3(0.0));
    return color / (1.0 + aaLuminance(color));
}

vec3 aaExpand(vec3 color) {
    return color / max(1.0 - aaLuminance(color), 1.0 / 65504.0);
}

float aaLuma(vec3 color) {
    return aaLuminance(aaCompress(color));
}

// Four cardinal reads detect thin lines that the old diagonal-only kernel
// missed. At most four more directional reads; all taps stay in the 3x3 support
// protected by reactive dilation. Filter HDR in a bounded luminance domain so
// a single bright texel does not produce a broad white fringe.
vec3 resolveSpatialAa(vec2 uv, vec3 center) {
    if (DYNAMIC_AA_STRENGTH <= 0.0) return center;
    vec2 texel = 1.0 / vec2(textureSize(colortex0, 0));
    vec3 north = aaCompress(sampleAaColor(uv + vec2(0.0, -1.0) * texel));
    vec3 south = aaCompress(sampleAaColor(uv + vec2(0.0,  1.0) * texel));
    vec3 west = aaCompress(sampleAaColor(uv + vec2(-1.0, 0.0) * texel));
    vec3 east = aaCompress(sampleAaColor(uv + vec2( 1.0, 0.0) * texel));
    vec3 compressedCenter = aaCompress(center);
    float n = aaLuminance(north);
    float s = aaLuminance(south);
    float w = aaLuminance(west);
    float e = aaLuminance(east);
    float m = aaLuminance(compressedCenter);
    float lo = min(m, min(min(n, s), min(w, e)));
    float hi = max(m, max(max(n, s), max(w, e)));
    if (hi - lo < max(0.0312, hi * 0.125)) return center;
    vec2 direction = vec2(-(s - n), e - w);
    float reduce = max((n + s + w + e) * 0.03125, 0.0078125);
    direction = clamp(direction / (min(abs(direction.x), abs(direction.y)) + reduce),
                      vec2(-2.0), vec2(2.0)) * texel;
    vec3 narrow = 0.5 * (aaCompress(sampleAaColor(uv - direction / 6.0)) + aaCompress(sampleAaColor(uv + direction / 6.0)));
    vec3 wide = narrow * 0.5 + 0.25 * (aaCompress(sampleAaColor(uv - direction * 0.5)) + aaCompress(sampleAaColor(uv + direction * 0.5)));
    float wideLuma = aaLuminance(wide);
    vec3 directional = wideLuma < lo || wideLuma > hi ? narrow : wide;
    vec3 meanColor = (north + south + west + east) * 0.25;
    float subpixelContrast = abs(aaLuminance(meanColor) - m) / max(hi - lo, 0.0001);
    float subpixelBlend = min(0.35, 0.5 * subpixelContrast * subpixelContrast);
    vec3 filtered = mix(directional, meanColor, subpixelBlend);
    return aaExpand(mix(compressedCenter, filtered, DYNAMIC_AA_STRENGTH));
}
#endif
