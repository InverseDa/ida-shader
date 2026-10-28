#ifndef IDA_POST_BLOOM_GLSL
#define IDA_POST_BLOOM_GLSL

// ---- Bloom ----

#include "/lib/settings.glsl"
const float BloomKnee = 0.58;
const float BloomPrefilterClamp = 32.0;

vec3 ClampBloomFireflies(vec3 Color)
{
    return min(max(Color, vec3(0.0)), vec3(BloomPrefilterClamp));
}

vec3 GetBloomSource(vec3 Color)
{
    Color = ClampBloomFireflies(Color);
    float Brightness = dot(Color, vec3(0.2126, 0.7152, 0.0722));
    float Knee = BLOOM_THRESHOLD * BloomKnee + 0.0001;
    float Soft = Brightness - BLOOM_THRESHOLD + Knee;
    Soft = clamp(Soft, 0.0, 2.0 * Knee);
    Soft = Soft * Soft / (4.0 * Knee);
    float Contribution = max(Soft, Brightness - BLOOM_THRESHOLD);
    Contribution /= max(Brightness, 0.0001);

    return Color * clamp(Contribution, 0.0, 1.0);
}

// Threshold HDR texels before bilinear filtering to preserve moving-source energy.
// Use actual texture bounds, including odd render sizes.
vec3 SampleBloomSource(sampler2D SourceBuffer, vec2 Pixel, ivec2 SourceSize)
{
    ivec2 Base = ivec2(floor(Pixel));
    vec2 Fraction = fract(Pixel);
    ivec2 Last = SourceSize - ivec2(1);
    vec3 A = GetBloomSource(texelFetch(SourceBuffer, clamp(Base, ivec2(0), Last), 0).rgb);
    vec3 B = GetBloomSource(texelFetch(SourceBuffer, clamp(Base + ivec2(1, 0), ivec2(0), Last), 0).rgb);
    vec3 C = GetBloomSource(texelFetch(SourceBuffer, clamp(Base + ivec2(0, 1), ivec2(0), Last), 0).rgb);
    vec3 D = GetBloomSource(texelFetch(SourceBuffer, clamp(Base + ivec2(1, 1), ivec2(0), Last), 0).rgb);

    return mix(mix(A, B, Fraction.x), mix(C, D, Fraction.x), Fraction.y);
}

// Eleven-tap Gaussian (sigma 1.8) fuses X filtering and 2x reduction: 44 source reads.
vec3 PrefilterBloom(sampler2D SourceBuffer, vec2 Uv)
{
    ivec2 SourceSize = textureSize(SourceBuffer, 0);
    vec2 Pixel = Uv * vec2(SourceSize) - 0.5;
    vec3 Bloom = SampleBloomSource(SourceBuffer, Pixel, SourceSize) * 0.222071781;
    Bloom += (SampleBloomSource(SourceBuffer, Pixel + vec2(2.0, 0.0), SourceSize) + SampleBloomSource(SourceBuffer, Pixel - vec2(2.0, 0.0), SourceSize)) * 0.190314826;
    Bloom += (SampleBloomSource(SourceBuffer, Pixel + vec2(4.0, 0.0), SourceSize) + SampleBloomSource(SourceBuffer, Pixel - vec2(4.0, 0.0), SourceSize)) * 0.119787186;
    Bloom += (SampleBloomSource(SourceBuffer, Pixel + vec2(6.0, 0.0), SourceSize) + SampleBloomSource(SourceBuffer, Pixel - vec2(6.0, 0.0), SourceSize)) * 0.055374089;
    Bloom += (SampleBloomSource(SourceBuffer, Pixel + vec2(8.0, 0.0), SourceSize) + SampleBloomSource(SourceBuffer, Pixel - vec2(8.0, 0.0), SourceSize)) * 0.018800150;
    Bloom += (SampleBloomSource(SourceBuffer, Pixel + vec2(10.0, 0.0), SourceSize) + SampleBloomSource(SourceBuffer, Pixel - vec2(10.0, 0.0), SourceSize)) * 0.004687859;

    return Bloom;
}

vec3 SampleBloomBuffer(sampler2D BloomBuffer, vec2 Uv, vec2 Texel)
{
    return texture2D(BloomBuffer, clamp(Uv, 0.5 * Texel, vec2(1.0) - 0.5 * Texel)).rgb;
}

// Pair adjacent Y taps with hardware bilinear filtering: six reads for the same Gaussian.
vec3 BlurBloom(sampler2D BloomBuffer, vec2 Uv)
{
    vec2 Texel = 1.0 / vec2(textureSize(BloomBuffer, 0));
    vec2 NearOffset = vec2(0.0, Texel.y * 0.631539318);
    vec2 MidOffset = vec2(0.0, Texel.y * 2.316132028);
    vec2 FarOffset = vec2(0.0, Texel.y * 4.199585199);
    vec3 Bloom = (SampleBloomBuffer(BloomBuffer, Uv + NearOffset, Texel) + SampleBloomBuffer(BloomBuffer, Uv - NearOffset, Texel)) * 0.301350716;
    Bloom += (SampleBloomBuffer(BloomBuffer, Uv + MidOffset, Texel) + SampleBloomBuffer(BloomBuffer, Uv - MidOffset, Texel)) * 0.175161275;
    Bloom += (SampleBloomBuffer(BloomBuffer, Uv + FarOffset, Texel) + SampleBloomBuffer(BloomBuffer, Uv - FarOffset, Texel)) * 0.023488009;

    return Bloom;
}

#endif
