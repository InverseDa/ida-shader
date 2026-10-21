#ifndef IDA_SCREEN_GLSL
#define IDA_SCREEN_GLSL
#include "/lib/post/taa.glsl"
uniform int frameCounter;
vec2 currentJitterUv() { return getTaaJitterNdc(frameCounter, vec2(viewWidth, viewHeight)) * 0.5; }
vec3 reconstructSceneViewPos(vec2 uv, float depth) {
    return reconstructViewPos(uv - currentJitterUv(), depth, gbufferProjectionInverse);
}
vec3 reconstructSurfaceViewPos(vec2 uv, float depth, bool jittered) {
    return reconstructViewPos(uv - (jittered ? currentJitterUv() : vec2(0.0)),
                              depth, gbufferProjectionInverse);
}
vec3 reconstructOpaqueViewPos(vec2 uv, vec4 snapshot) {
    return reconstructSurfaceViewPos(uv, snapshot.b, snapshot.a > 1.5);
}
vec4 sampleOpaqueData(vec2 uv) {
    ivec2 size = textureSize(colortex4, 0);
    return texelFetch(colortex4, clamp(ivec2(uv * vec2(size)), ivec2(0), size - 1), 0);
}
// Reflection probes need both the projected UV and snapshot. Reuse the first
// fetch when jitter does not cross a texel boundary; keep the second otherwise.
bool projectAndSampleOpaque(vec3 p, out vec2 uv, out vec4 opaque) {
    uv = vec2(-1.0);
    opaque = vec4(0.0, 0.0, 1.0, 0.0);
    if (p.z >= -near) return false;
    uv = projectViewToScreenPos(p, gbufferProjection).xy;
    vec2 jitter = currentJitterUv();
    // Preserve probes just outside the image that jitter can move inside.
    if (any(lessThanEqual(uv, -abs(jitter))) ||
        any(greaterThanEqual(uv, vec2(1.0) + abs(jitter)))) return false;
    ivec2 size = textureSize(colortex4, 0);
    ivec2 pixel = clamp(ivec2(uv * vec2(size)), ivec2(0), size - 1);
    opaque = texelFetch(colortex4, pixel, 0);
    if (opaque.a > 1.5) uv += jitter;
    if (!isScreenUvInRange(uv)) return false;
    ivec2 shiftedPixel = clamp(ivec2(uv * vec2(size)), ivec2(0), size - 1);
    if (any(notEqual(pixel, shiftedPixel))) opaque = texelFetch(colortex4, shiftedPixel, 0);
    return true;
}
vec2 opaqueUvForUnjitteredUv(vec2 uv) {
    vec2 halfTexel = 0.5 / vec2(textureSize(colortex4, 0));
    vec2 offset = sampleOpaqueData(uv).a > 1.5 ? currentJitterUv() : vec2(0.0);
    return clamp(uv + offset, halfTexel, vec2(1.0) - halfTexel);
}
vec3 projectSceneViewPos(vec3 p) {
    vec3 s = projectViewToScreenPos(p, gbufferProjection);
    s.xy += currentJitterUv();
    return s;
}
vec3 projectOpaqueViewPos(vec3 p) {
    vec3 s = projectViewToScreenPos(p, gbufferProjection);
    // Dynamic geometry and static terrain share the snapshot. Select the
    // projection convention from the destination pixel, then read it again.
    if (sampleOpaqueData(s.xy).a > 1.5) s.xy += currentJitterUv();
    return s;
}
#endif
