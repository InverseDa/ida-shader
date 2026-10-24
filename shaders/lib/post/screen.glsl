#ifndef IDA_SCREEN_GLSL
#define IDA_SCREEN_GLSL
#include "/lib/post/taa.glsl"
#include "/lib/common/opaque_snapshot.glsl"
uniform int frameCounter;
vec2 CurrentJitterUv() {
    return GetTaaJitterNdc(frameCounter, vec2(viewWidth, viewHeight)) * 0.5;
}

vec3 ReconstructSceneViewPos(vec2 Uv, float Depth) {
    return ReconstructViewPos(Uv - CurrentJitterUv(), Depth, gbufferProjectionInverse);
}

vec3 ReconstructSurfaceViewPos(vec2 Uv, float Depth, bool Jittered) {
    return ReconstructViewPos(Uv - (Jittered ? CurrentJitterUv() : vec2(0.0)), Depth, gbufferProjectionInverse);
}

vec3 ReconstructOpaqueViewPos(vec2 Uv, vec4 Snapshot) {
    return ReconstructSurfaceViewPos(Uv, Snapshot.b, Snapshot.a > 1.5);
}

vec4 SampleOpaqueData(vec2 Uv) {
    ivec2 Size = textureSize(colortex4, 0);
    return FetchOpaqueData(clamp(ivec2(Uv * vec2(Size)), ivec2(0), Size - 1));
}
// Reflection probes need both the projected UV and snapshot. Reuse the first
// fetch when jitter does not cross a texel boundary; keep the second otherwise.
bool ProjectAndSampleOpaque(vec3 P, out vec2 Uv, out vec4 Opaque, out vec2 UnjitteredUv) {
    Uv = vec2(-1.0);
    UnjitteredUv = Uv;
    Opaque = vec4(0.0, 0.0, 1.0, 0.0);
    if (P.z >= -near) return false;
    Uv = ProjectViewToScreenPos(P, gbufferProjection).xy;
    UnjitteredUv = Uv;
    vec2 Jitter = CurrentJitterUv();
    // Preserve probes just outside the image that jitter can move inside.
    if (any(lessThanEqual(Uv, -abs(Jitter))) || any(greaterThanEqual(Uv, vec2(1.0) + abs(Jitter)))) return false;
    ivec2 Size = textureSize(colortex4, 0);
    ivec2 Pixel = clamp(ivec2(Uv * vec2(Size)), ivec2(0), Size - 1);
    Opaque = FetchOpaqueData(Pixel);
    if (Opaque.a > 1.5) Uv += Jitter;
    if (!IsScreenUvInRange(Uv)) return false;
    ivec2 ShiftedPixel = clamp(ivec2(Uv * vec2(Size)), ivec2(0), Size - 1);
    if (any(notEqual(Pixel, ShiftedPixel))) Opaque = FetchOpaqueData(ShiftedPixel);
    return true;
}

bool ProjectAndSampleOpaque(vec3 P, out vec2 Uv, out vec4 Opaque) {
    vec2 UnjitteredUv;
    return ProjectAndSampleOpaque(P, Uv, Opaque, UnjitteredUv);
}

vec2 OpaqueUvForUnjitteredUv(vec2 Uv) {
    vec2 HalfTexel = 0.5 / vec2(textureSize(colortex4, 0));
    vec2 Offset = SampleOpaqueData(Uv).a > 1.5 ? CurrentJitterUv() : vec2(0.0);
    return clamp(Uv + Offset, HalfTexel, vec2(1.0) - HalfTexel);
}

vec3 ProjectSceneViewPos(vec3 P) {
    vec3 S = ProjectViewToScreenPos(P, gbufferProjection);
    S.xy += CurrentJitterUv();
    return S;
}

vec3 ProjectOpaqueViewPos(vec3 P) {
    vec3 S = ProjectViewToScreenPos(P, gbufferProjection);
    // Dynamic geometry and static terrain share the snapshot. Select the
    // projection convention from the destination pixel, then read it again.
    if (SampleOpaqueData(S.xy).a > 1.5) S.xy += CurrentJitterUv();
    return S;
}
#endif
