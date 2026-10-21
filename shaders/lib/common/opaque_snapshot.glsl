#ifndef IDA_OPAQUE_SNAPSHOT_GLSL
#define IDA_OPAQUE_SNAPSHOT_GLSL

// RG32F: R stores two 12-bit octahedral coordinates as an exact integer + 1.
// Its sign carries jitter; zero is the pre-deferred readiness sentinel.
// G preserves the original FP32 hardware depth without quantization.
vec2 encodeOpaqueSnapshot(vec2 normalOct, float depth, bool jittered) {
    uvec2 quantized = uvec2(floor(clamp(normalOct, 0.0, 1.0) * 4095.0 + 0.5));
    uint bits = (quantized.x << 12u) | quantized.y;
    float payload = float(bits) + 1.0; // Maximum 2^24, exactly representable.
    return vec2(jittered ? -payload : payload, depth);
}

vec4 decodeOpaqueSnapshot(vec2 encoded) {
    uint bits = uint(max(abs(encoded.r) - 1.0, 0.0));
    vec2 normalOct = vec2(bits >> 12u, bits & 4095u) / 4095.0;
    float state = encoded.r == 0.0 ? 0.0 : (encoded.r < 0.0 ? 2.0 : 1.0);
    return vec4(normalOct, encoded.g, state);
}

// Packed values must never go through interpolating texture sampling.
vec4 fetchOpaqueData(ivec2 pixel) {
    return decodeOpaqueSnapshot(texelFetch(colortex4, pixel, 0).rg);
}
bool opaqueSnapshotReady() {
    return texelFetch(colortex4, ivec2(0), 0).r != 0.0;
}
#endif
