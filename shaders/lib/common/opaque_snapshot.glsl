#ifndef IDA_OPAQUE_SNAPSHOT_GLSL
#define IDA_OPAQUE_SNAPSHOT_GLSL

// RG32F: R stores two 12-bit octahedral coordinates as an exact integer + 1.
// Its sign carries jitter; zero is the pre-deferred readiness sentinel.
// G preserves the original FP32 hardware depth without quantization.
vec2 EncodeOpaqueSnapshot(vec2 NormalOct, float Depth, bool Jittered) {
    uvec2 Quantized = uvec2(floor(clamp(NormalOct, 0.0, 1.0) * 4095.0 + 0.5));
    uint Bits = (Quantized.x << 12u) | Quantized.y;
    float Payload = float(Bits) + 1.0; // Maximum 2^24, exactly representable.
    return vec2(Jittered ? -Payload : Payload, Depth);
}

vec4 DecodeOpaqueSnapshot(vec2 Encoded) {
    uint Bits = uint(max(abs(Encoded.r) - 1.0, 0.0));
    vec2 NormalOct = vec2(Bits >> 12u, Bits & 4095u) / 4095.0;
    float State = Encoded.r == 0.0 ? 0.0 : (Encoded.r < 0.0 ? 2.0 : 1.0);
    return vec4(NormalOct, Encoded.g, State);
}

// Packed values must never go through interpolating texture sampling.
vec4 FetchOpaqueData(ivec2 Pixel) {
    return DecodeOpaqueSnapshot(texelFetch(colortex4, Pixel, 0).rg);
}

bool OpaqueSnapshotReady() {
    return texelFetch(colortex4, ivec2(0), 0).r != 0.0;
}
#endif
