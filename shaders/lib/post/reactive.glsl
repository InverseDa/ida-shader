#ifndef IDA_REACTIVE_GLSL
#define IDA_REACTIVE_GLSL

// ---- Reactive ----

// Only the binary rejection decision is consumed. Checking the center first
// avoids eight more taps over water, sky and interiors of dynamic objects.
bool HasReactiveCoverage(ivec2 Pixel)
{
    if (texelFetch(colortex10, Pixel, 0).r > 0.001)
    {
        return true;
    }

    ivec2 Size = textureSize(colortex10, 0);

    for (int Y = -1; Y <= 1; ++Y)
    {
        for (int X = -1; X <= 1; ++X)
        {
            if (X == 0 && Y == 0)
            {
                continue;
            }

            if (texelFetch(colortex10, clamp(Pixel + ivec2(X, Y), ivec2(0), Size - 1), 0).r > 0.001)
            {
                return true;
            }
        }
    }

    return false;
}
#endif
