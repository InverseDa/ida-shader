#ifndef IDA_REACTIVE_GLSL
#define IDA_REACTIVE_GLSL
// Only the binary rejection decision is consumed. Checking the center first
// avoids eight more taps over water, sky and interiors of dynamic objects.
bool hasReactiveCoverage(ivec2 pixel) {
    if (texelFetch(colortex10, pixel, 0).r > 0.001) return true;
    ivec2 size = textureSize(colortex10, 0);
    for (int y = -1; y <= 1; ++y)
        for (int x = -1; x <= 1; ++x) {
            if (x == 0 && y == 0) continue;
            if (texelFetch(colortex10, clamp(pixel + ivec2(x, y), ivec2(0), size - 1), 0).r > 0.001)
                return true;
        }
    return false;
}
#endif
