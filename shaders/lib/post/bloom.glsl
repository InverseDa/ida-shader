#ifndef IDA_POST_BLOOM_GLSL
#define IDA_POST_BLOOM_GLSL

#include "/lib/settings.glsl"
const float BLOOM_KNEE = 0.58;
const float BLOOM_PREFILTER_CLAMP = 32.0;

vec3 clampBloomFireflies(vec3 color) {
    return min(max(color, vec3(0.0)), vec3(BLOOM_PREFILTER_CLAMP));
}

vec3 getBloomSource(vec3 color) {
    color = clampBloomFireflies(color);
    float brightness = dot(color, vec3(0.2126, 0.7152, 0.0722));
    float knee = BLOOM_THRESHOLD * BLOOM_KNEE + 0.0001;
    float soft = brightness - BLOOM_THRESHOLD + knee;
    soft = clamp(soft, 0.0, 2.0 * knee);
    soft = soft * soft / (4.0 * knee);
    float contribution = max(soft, brightness - BLOOM_THRESHOLD);
    contribution /= max(brightness, 0.0001);
    return color * clamp(contribution, 0.0, 1.0);
}

// Threshold/clamp individual HDR texels BEFORE interpolation. Otherwise a tiny
// bright source changes energy as it crosses the half-resolution sampling grid.
// Manual bilinear filtering also works at odd render sizes. Bounds follow the
// actual texture, rather than dropping a fixed 0.1% border at high resolutions.
vec3 sampleBloomSource(sampler2D sourceBuffer, vec2 pixel, ivec2 sourceSize) {
    ivec2 base = ivec2(floor(pixel));
    vec2 fraction = fract(pixel);
    ivec2 last = sourceSize - ivec2(1);
    vec3 a = getBloomSource(texelFetch(sourceBuffer, clamp(base, ivec2(0), last), 0).rgb);
    vec3 b = getBloomSource(texelFetch(sourceBuffer, clamp(base + ivec2(1, 0), ivec2(0), last), 0).rgb);
    vec3 c = getBloomSource(texelFetch(sourceBuffer, clamp(base + ivec2(0, 1), ivec2(0), last), 0).rgb);
    vec3 d = getBloomSource(texelFetch(sourceBuffer, clamp(base + ivec2(1, 1), ivec2(0), last), 0).rgb);
    return mix(mix(a, b, fraction.x), mix(c, d, fraction.x), fraction.y);
}

// Normalized eleven-tap Gaussian, sigma=1.8 half-resolution pixels. Keep almost
// three sigma of support so the finite kernel's edge does not form a square.
// Fuse horizontal filtering and 2x downsampling; the second pass filters Y.
// Eleven groups of four source texels = 44 fetches, no intermediate target.
vec3 prefilterBloom(sampler2D sourceBuffer, vec2 uv) {
    ivec2 sourceSize = textureSize(sourceBuffer, 0);
    vec2 pixel = uv * vec2(sourceSize) - 0.5;
    vec3 bloom = sampleBloomSource(sourceBuffer, pixel, sourceSize) * 0.222071781;
    bloom += (sampleBloomSource(sourceBuffer, pixel + vec2(2.0, 0.0), sourceSize)
            + sampleBloomSource(sourceBuffer, pixel - vec2(2.0, 0.0), sourceSize)) * 0.190314826;
    bloom += (sampleBloomSource(sourceBuffer, pixel + vec2(4.0, 0.0), sourceSize)
            + sampleBloomSource(sourceBuffer, pixel - vec2(4.0, 0.0), sourceSize)) * 0.119787186;
    bloom += (sampleBloomSource(sourceBuffer, pixel + vec2(6.0, 0.0), sourceSize)
            + sampleBloomSource(sourceBuffer, pixel - vec2(6.0, 0.0), sourceSize)) * 0.055374089;
    bloom += (sampleBloomSource(sourceBuffer, pixel + vec2(8.0, 0.0), sourceSize)
            + sampleBloomSource(sourceBuffer, pixel - vec2(8.0, 0.0), sourceSize)) * 0.018800150;
    bloom += (sampleBloomSource(sourceBuffer, pixel + vec2(10.0, 0.0), sourceSize)
            + sampleBloomSource(sourceBuffer, pixel - vec2(10.0, 0.0), sourceSize)) * 0.004687859;
    return bloom;
}

vec3 sampleBloomBuffer(sampler2D bloomBuffer, vec2 uv, vec2 texel) {
    return texture2D(bloomBuffer, clamp(uv, 0.5 * texel, vec2(1.0) - 0.5 * texel)).rgb;
}

// The same Gaussian along Y. Pair adjacent taps with hardware bilinear filtering
// (half of 0,1), (2,3), (4,5), mirrored about zero: six reads instead of four
// sparse nine-read rings. Iris 1.8.8 filters non-integer render targets linearly.
vec3 blurBloom(sampler2D bloomBuffer, vec2 uv) {
    vec2 texel = 1.0 / vec2(textureSize(bloomBuffer, 0));
    vec2 nearOffset = vec2(0.0, texel.y * 0.631539318);
    vec2 midOffset = vec2(0.0, texel.y * 2.316132028);
    vec2 farOffset = vec2(0.0, texel.y * 4.199585199);
    vec3 bloom = (sampleBloomBuffer(bloomBuffer, uv + nearOffset, texel)
               + sampleBloomBuffer(bloomBuffer, uv - nearOffset, texel)) * 0.301350716;
    bloom += (sampleBloomBuffer(bloomBuffer, uv + midOffset, texel)
            + sampleBloomBuffer(bloomBuffer, uv - midOffset, texel)) * 0.175161275;
    bloom += (sampleBloomBuffer(bloomBuffer, uv + farOffset, texel)
            + sampleBloomBuffer(bloomBuffer, uv - farOffset, texel)) * 0.023488009;
    return bloom;
}

#endif
