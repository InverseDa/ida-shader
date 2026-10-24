#ifndef IDA_COMMON_TONEMAP_GLSL
#define IDA_COMMON_TONEMAP_GLSL

vec3 ACESToneMapping(vec3 Color, float AdaptedLum) {
    const float A = 2.51f;
    const float B = 0.03f;
    const float C = 2.43f;
    const float D = 0.59f;
    const float E = 0.14f;
    Color *= AdaptedLum;
    return (Color * (A * Color + B)) / (Color * (C * Color + D) + E);
}

#endif
