#ifndef IDA_WATER_VOLUME_CACHE_GLSL
#define IDA_WATER_VOLUME_CACHE_GLSL
#if defined(IDA_VOLUME_CACHE_ACTIVE) && UNDERWATER_LIGHT == 1
vec3 WaterShaftPrefix(ivec2 Pixel, ivec2 Size, int Boundary) {
    if (Boundary < 0) return vec3(0.0);
    vec2 RG = unpackHalf2x16(SunShaftVolumeData[SunShaftCacheAddress(Pixel, Size, Boundary * 2)]);
    float B = unpackHalf2x16(SunShaftVolumeData[SunShaftCacheAddress(Pixel, Size, Boundary * 2 + 1)]).x;
    return vec3(RG, B);
}
vec3 WaterShaftIntegral(vec2 Uv, ivec2 Size, float End) {
    float Stratum = sqrt(clamp(End / 32.0, 0.0, 1.0)) * float(VOLUMETRIC_LIGHT_SAMPLES);
    int Boundary = min(int(floor(Stratum)), VOLUMETRIC_LIGHT_SAMPLES - 1);
    float A = 32.0 * pow(float(Boundary) / float(VOLUMETRIC_LIGHT_SAMPLES), 2.0);
    float B = 32.0 * pow(float(Boundary + 1) / float(VOLUMETRIC_LIGHT_SAMPLES), 2.0);
    vec3 Ta = WaterTransmittance(A);
    vec3 Weight = clamp((Ta - WaterTransmittance(End)) / max(Ta - WaterTransmittance(B), vec3(0.0000001)), 0.0, 1.0);
    vec2 P = Uv * vec2(Size) - 0.5 - SunShaftCacheJitter();
    ivec2 Base = ivec2(floor(P));
    vec2 F = fract(P);
    vec3 Sum = vec3(0.0);
    for (int K = 0; K < 4; ++K) {
        ivec2 Pixel = clamp(Base + ivec2(K % 2, K / 2), ivec2(0), Size - 1);
        float W = (K % 2 == 0 ? 1.0 - F.x : F.x) * (K < 2 ? 1.0 - F.y : F.y);
        Sum += W * mix(WaterShaftPrefix(Pixel, Size, Boundary - 1), WaterShaftPrefix(Pixel, Size, Boundary), Weight);
    }
    return Sum;
}
#endif
#endif
