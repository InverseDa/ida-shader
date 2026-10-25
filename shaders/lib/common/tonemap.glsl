#ifndef IDA_COMMON_TONEMAP_GLSL
#define IDA_COMMON_TONEMAP_GLSL

float CompressDisplayHighlight(float Luminance) {
    // Leave midtones intact; approach white gradually instead of clipping
    // bright neutral surfaces. The knee has a continuous first derivative.
    float Excess = max(Luminance - 0.60, 0.0);
    return min(Luminance, 0.60) + Excess / (1.0 + 0.60 * Excess);
}

vec3 ACESToneMapping(vec3 Color, float AdaptedLum) {
    const float A = 2.51f;
    const float B = 0.03f;
    const float C = 2.43f;
    const float D = 0.59f;
    const float E = 0.14f;
    Color *= AdaptedLum;
    vec3 Mapped = (Color * (A * Color + B)) / (Color * (C * Color + D) + E);
    float Luminance = dot(Mapped, vec3(0.2126, 0.7152, 0.0722));
    if (Luminance <= 0.60) return Mapped;
    // Scale all channels together: saturated red/green midtones retain their
    // brightness and hue instead of receiving per-channel highlight cuts.
    return Mapped * (CompressDisplayHighlight(Luminance) / Luminance);
}

#endif
