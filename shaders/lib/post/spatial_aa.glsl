#ifndef IDA_SPATIAL_AA_GLSL
#define IDA_SPATIAL_AA_GLSL

vec3 sampleAaColor(vec2 uv) {
    vec2 halfTexel = 0.5 / vec2(textureSize(colortex0, 0));
    return texture2D(colortex0, clamp(uv, halfTexel, vec2(1.0) - halfTexel)).rgb;
}

float aaLuma(vec3 color) {
    float luma = dot(max(color, vec3(0.0)), vec3(0.299, 0.587, 0.114));
    return luma / (1.0 + luma); // Bounded contrast metric for linear HDR.
}

// Short directional spatial resolve for surfaces without object motion vectors.
// Flat regions return unchanged; the wider result is rejected if it overshoots.
vec3 resolveSpatialAa(vec2 uv, vec3 center) {
    vec2 texel = 1.0 / vec2(textureSize(colortex0, 0));
    float nw = aaLuma(sampleAaColor(uv + vec2(-1.0, -1.0) * texel));
    float ne = aaLuma(sampleAaColor(uv + vec2( 1.0, -1.0) * texel));
    float sw = aaLuma(sampleAaColor(uv + vec2(-1.0,  1.0) * texel));
    float se = aaLuma(sampleAaColor(uv + vec2( 1.0,  1.0) * texel));
    float m = aaLuma(center);
    float lo = min(m, min(min(nw, ne), min(sw, se)));
    float hi = max(m, max(max(nw, ne), max(sw, se)));
    if (hi - lo < max(0.0312, hi * 0.125)) return center;
    vec2 direction = vec2(-((nw + ne) - (sw + se)), (nw + sw) - (ne + se));
    float reduce = max((nw + ne + sw + se) * 0.03125, 0.0078125);
    direction = clamp(direction / (min(abs(direction.x), abs(direction.y)) + reduce),
                      vec2(-4.0), vec2(4.0)) * texel;
    vec3 narrow = 0.5 * (sampleAaColor(uv - direction / 6.0) + sampleAaColor(uv + direction / 6.0));
    vec3 wide = narrow * 0.5 + 0.25 * (sampleAaColor(uv - direction * 0.5) + sampleAaColor(uv + direction * 0.5));
    float wideLuma = aaLuma(wide);
    return wideLuma < lo || wideLuma > hi ? narrow : wide;
}
#endif
