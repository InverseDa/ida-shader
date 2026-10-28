#ifndef IDA_SPATIAL_AA_GLSL
#define IDA_SPATIAL_AA_GLSL

// ---- Spatial Aa ----

#include "/lib/settings.glsl"
#include "/lib/common/color.glsl"

vec3 SampleAaColor(vec2 Uv)
{
    vec2 HalfTexel = 0.5 / vec2(textureSize(colortex0, 0));

    return SanitizeRadiance(texture2D(colortex0, clamp(Uv, HalfTexel, vec2(1.0) - HalfTexel)).rgb);
}

float AaLuminance(vec3 Color)
{
    return dot(Color, vec3(0.299, 0.587, 0.114));
}

vec3 AaCompress(vec3 Color)
{
    Color = max(Color, vec3(0.0));

    return Color / (1.0 + AaLuminance(Color));
}

vec3 AaExpand(vec3 Color)
{
    return Color / max(1.0 - AaLuminance(Color), 1.0 / 65504.0);
}

float AaLuma(vec3 Color)
{
    return AaLuminance(AaCompress(Color));
}

// Use four cardinal and up to four directional reads within the dilated 3x3 support.
// Bound HDR luminance before filtering to avoid bright fringes.
vec3 ResolveSpatialAa(vec2 Uv, vec3 Center)
{
    if (DYNAMIC_AA_STRENGTH <= 0.0)
    {
        return Center;
    }

    vec2 Texel = 1.0 / vec2(textureSize(colortex0, 0));
    vec3 North = AaCompress(SampleAaColor(Uv + vec2(0.0, -1.0) * Texel));
    vec3 South = AaCompress(SampleAaColor(Uv + vec2(0.0, 1.0) * Texel));
    vec3 West = AaCompress(SampleAaColor(Uv + vec2(-1.0, 0.0) * Texel));
    vec3 East = AaCompress(SampleAaColor(Uv + vec2(1.0, 0.0) * Texel));
    vec3 CompressedCenter = AaCompress(Center);
    float N = AaLuminance(North);
    float S = AaLuminance(South);
    float W = AaLuminance(West);
    float E = AaLuminance(East);
    float M = AaLuminance(CompressedCenter);
    float Lo = min(M, min(min(N, S), min(W, E)));
    float Hi = max(M, max(max(N, S), max(W, E)));

    if (Hi - Lo < max(0.0312, Hi * 0.125))
    {
        return Center;
    }

    vec2 Direction = vec2(-(S - N), E - W);
    float Reduce = max((N + S + W + E) * 0.03125, 0.0078125);
    Direction = clamp(Direction / (min(abs(Direction.x), abs(Direction.y)) + Reduce), vec2(-2.0), vec2(2.0)) *
                Texel;
    vec3 Narrow = 0.5 * (AaCompress(SampleAaColor(Uv - Direction / 6.0)) + AaCompress(SampleAaColor(Uv + Direction / 6.0)));
    vec3 Wide = Narrow * 0.5 + 0.25 * (AaCompress(SampleAaColor(Uv - Direction * 0.5)) + AaCompress(SampleAaColor(Uv + Direction * 0.5)));
    float WideLuma = AaLuminance(Wide);
    vec3 Directional = WideLuma < Lo || WideLuma > Hi ? Narrow : Wide;
    vec3 MeanColor = (North + South + West + East) * 0.25;
    float SubpixelContrast = abs(AaLuminance(MeanColor) - M) / max(Hi - Lo, 0.0001);
    float SubpixelBlend = min(0.35, 0.5 * SubpixelContrast * SubpixelContrast);
    vec3 Filtered = mix(Directional, MeanColor, SubpixelBlend);

    return AaExpand(mix(CompressedCenter, Filtered, DYNAMIC_AA_STRENGTH));
}
#endif
