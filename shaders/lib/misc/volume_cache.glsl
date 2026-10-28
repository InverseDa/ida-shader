#ifndef IDA_VOLUME_CACHE_GLSL
#define IDA_VOLUME_CACHE_GLSL

// A view-ray prefix field, independent of the opaque terminal surface. Each
// entry is accumulated scattering at an integration boundary (scalar in air,
// RGB underwater). Transparent layers truncate it at their own depth.
// This is angular bilinear reconstruction, with no depth-aware edge filtering.
#if VOLUMETRIC_LIGHT_CACHE == 1 && (VOLUMETRIC_LIGHT == 1 || UNDERWATER_LIGHT == 1) && (defined(IDA_VOLUME_CACHE_WRITE) || (defined(OVERWORLD) && defined(FRAGMENT_SHADER)))
#define IDA_VOLUME_CACHE_ACTIVE
#include "/lib/post/taa.glsl"
layout(std430, binding = 8) buffer SunShaftVolumeBuffer {
    uvec4 SunShaftVolumeHeader;
    uint SunShaftVolumeData[];
};

ivec2 SunShaftCacheSize() {
    vec2 Full = max(vec2(viewWidth, viewHeight), vec2(1.0));
    float Scale = max(4.0, max(Full.x, Full.y) / 1024.0);
    return clamp(ivec2(ceil(Full / Scale)), ivec2(1), ivec2(1024));
}
// Water stores RGB at every two integration steps. Half the air grid in each
// dimension exactly fits the SAME allocation (four times as many words/ray).
ivec2 WaterShaftCacheSize() { return max(SunShaftCacheSize() / 2, ivec2(1)); }
const uint WaterShaftCacheTag = 0x80000000u;
vec2 SunShaftCacheJitter() { return GetTaaHaltonOffset(frameCounter) - 0.5; }
vec2 SunShaftCacheUv(ivec2 Pixel, ivec2 Size) {
    vec2 Full = max(vec2(viewWidth, viewHeight), vec2(1.0));
    return clamp((vec2(Pixel) + 0.5 + SunShaftCacheJitter()) / vec2(Size),
                 0.5 / Full, 1.0 - 0.5 / Full);
}
float SunShaftCachePhase(ivec2 Pixel, ivec2 Size) {
    vec2 FullPixel = floor(SunShaftCacheUv(Pixel, Size) * vec2(viewWidth, viewHeight)) + 0.5;
    return 0.35 + 0.30 * fract(52.9829189 * fract(dot(FullPixel, vec2(0.06711056, 0.00583715))));
}
uint SunShaftCacheAddress(ivec2 Pixel, ivec2 Size, int Pair) {
    return uint(Pair * Size.x * Size.y + Pixel.y * Size.x + Pixel.x);
}
float SunShaftCachePrefix(ivec2 Pixel, ivec2 Size, int Boundary) {
    if (Boundary < 0) return 0.0;
    vec2 Values = unpackHalf2x16(SunShaftVolumeData[SunShaftCacheAddress(Pixel, Size, Boundary / 2)]);
    return Boundary % 2 == 0 ? Values.x : Values.y;
}
vec2 SunShaftCacheNeighbours(ivec2 Pixel, ivec2 Size, int Boundary) {
    uint Address = SunShaftCacheAddress(Pixel, Size, Boundary / 2);
    vec2 Values = unpackHalf2x16(SunShaftVolumeData[Address]);
    // Odd boundaries and their predecessor share one packed word. Only an
    // even boundary after zero needs the preceding plane's second prefix.
    if (Boundary % 2 != 0) return Values;
    if (Boundary == 0) return vec2(0.0, Values.x);
    float Before = unpackHalf2x16(SunShaftVolumeData[Address - uint(Size.x * Size.y)]).y;
    return vec2(Before, Values.x);
}
float SunShaftOpticalTransmission(float T, float Density, float NearColumn) {
    float OpticalDistance = mix(T, NearColumn * (1.0 - exp(-T / 10.0)), 0.65);
    return exp(-Density * OpticalDistance);
}
float SunShaftCacheRay(ivec2 Pixel, ivec2 Size, float Stratum, float TransmissionEnd, float Range, float Density, float NearColumn) {
    float Phase = SunShaftCachePhase(Pixel, Size);
    int I = clamp(int(floor(Stratum - Phase)) + 1,
                  0, VOLUMETRIC_LIGHT_SAMPLES - 1);
    float A = max(float(I - 1) + Phase, 0.0) / float(VOLUMETRIC_LIGHT_SAMPLES);
    float B = I + 1 == VOLUMETRIC_LIGHT_SAMPLES ? 1.0 : (float(I) + Phase) / float(VOLUMETRIC_LIGHT_SAMPLES);
    float T0 = Range * A * A, T1 = Range * B * B;
    vec2 Prefix = SunShaftCacheNeighbours(Pixel, Size, I);
    float Transmission0 = SunShaftOpticalTransmission(T0, Density, NearColumn);
    float Transmission1 = SunShaftOpticalTransmission(T1, Density, NearColumn);
    float Weight = clamp((Transmission0 - TransmissionEnd) /
                         max(Transmission0 - Transmission1, 0.0000001), 0.0, 1.0);
    // The visibility in the final stratum is the visibility at its FRONT,
    // exactly as in the direct integrator. Never borrow a later depth sample.
    return mix(Prefix.x, Prefix.y, Weight);
}
float SunShaftCacheIntegral(vec2 Uv, ivec2 Size, float End, float Range, float Density, float NearColumn) {
    vec2 P = Uv * vec2(Size) - 0.5 - SunShaftCacheJitter();
    ivec2 Base = ivec2(floor(P));
    vec2 F = fract(P);
    float Sum = 0.0;
    if (End >= Range) {
        for (int K = 0; K < 4; ++K) {
            ivec2 Pixel = clamp(Base + ivec2(K % 2, K / 2), ivec2(0), Size - 1);
            float Weight = (K % 2 == 0 ? 1.0 - F.x : F.x) * (K < 2 ? 1.0 - F.y : F.y);
            Sum += Weight * SunShaftCachePrefix(Pixel, Size, VOLUMETRIC_LIGHT_SAMPLES - 1);
        }
        return Sum;
    }
    // These are properties of the queried endpoint, shared by all four rays.
    float Stratum = sqrt(max(End / Range, 0.0)) * float(VOLUMETRIC_LIGHT_SAMPLES);
    float TransmissionEnd = SunShaftOpticalTransmission(End, Density, NearColumn);
    for (int K = 0; K < 4; ++K) {
        ivec2 Pixel = clamp(Base + ivec2(K % 2, K / 2), ivec2(0), Size - 1);
        float Weight = (K % 2 == 0 ? 1.0 - F.x : F.x) * (K < 2 ? 1.0 - F.y : F.y);
        Sum += Weight * SunShaftCacheRay(Pixel, Size, Stratum, TransmissionEnd, Range, Density, NearColumn);
    }
    return Sum;
}
#endif
#endif
