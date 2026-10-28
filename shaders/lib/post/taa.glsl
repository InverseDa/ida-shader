#ifndef IDA_POST_TAA_GLSL
#define IDA_POST_TAA_GLSL

// ---- Temporal Jitter ----

vec2 GetTaaHaltonOffset(int FrameIndex)
{
    int Index = FrameIndex - (FrameIndex / 8) * 8;

    if (Index == 0)
    {
        return vec2(0.5000, 0.3333);
    }

    if (Index == 1)
    {
        return vec2(0.2500, 0.6667);
    }

    if (Index == 2)
    {
        return vec2(0.7500, 0.1111);
    }

    if (Index == 3)
    {
        return vec2(0.1250, 0.4444);
    }

    if (Index == 4)
    {
        return vec2(0.6250, 0.7778);
    }

    if (Index == 5)
    {
        return vec2(0.3750, 0.2222);
    }

    if (Index == 6)
    {
        return vec2(0.8750, 0.5556);
    }

    return vec2(0.0625, 0.8889);
}

vec2 GetTaaJitterNdc(int FrameIndex, vec2 Resolution)
{
    return 2.0 * (GetTaaHaltonOffset(FrameIndex) - 0.5) / max(Resolution, vec2(1.0));
}

// ---- Vertex Shader ----

#ifdef VERTEX_SHADER

uniform int frameCounter;
uniform float viewWidth;
uniform float viewHeight;

void ApplyTaaJitter(inout vec4 ClipPos)
{
    ClipPos.xy += GetTaaJitterNdc(frameCounter, vec2(viewWidth, viewHeight)) * ClipPos.w;
}
#endif

#endif
