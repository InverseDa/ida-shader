#ifndef IDA_POST_BLOOM_GLSL
#define IDA_POST_BLOOM_GLSL

const float BLOOM_THRESHOLD = 0.68;
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

vec3 sampleBloomSource(sampler2D sourceBuffer, vec2 uv) {
    return getBloomSource(texture2D(sourceBuffer, clamp(uv, vec2(0.001), vec2(0.999))).rgb);
}

vec3 sampleBloomTent(sampler2D sourceBuffer, vec2 uv, vec2 texel, float radius) {
    vec2 x = vec2(texel.x * radius, 0.0);
    vec2 y = vec2(0.0, texel.y * radius);

    vec3 bloom = sampleBloomSource(sourceBuffer, uv) * 0.25;
    bloom += sampleBloomSource(sourceBuffer, uv + x) * 0.125;
    bloom += sampleBloomSource(sourceBuffer, uv - x) * 0.125;
    bloom += sampleBloomSource(sourceBuffer, uv + y) * 0.125;
    bloom += sampleBloomSource(sourceBuffer, uv - y) * 0.125;
    bloom += sampleBloomSource(sourceBuffer, uv + x + y) * 0.0625;
    bloom += sampleBloomSource(sourceBuffer, uv - x + y) * 0.0625;
    bloom += sampleBloomSource(sourceBuffer, uv + x - y) * 0.0625;
    bloom += sampleBloomSource(sourceBuffer, uv - x - y) * 0.0625;
    return bloom;
}

vec3 sampleBloomBuffer(sampler2D bloomBuffer, vec2 uv) {
    return texture2D(bloomBuffer, clamp(uv, vec2(0.001), vec2(0.999))).rgb;
}

vec3 sampleBloomBlur(sampler2D bloomBuffer, vec2 uv, vec2 texel, float radius) {
    vec2 x = vec2(texel.x * radius, 0.0);
    vec2 y = vec2(0.0, texel.y * radius);
    vec2 d = texel * radius * 0.70710678;

    vec3 bloom = sampleBloomBuffer(bloomBuffer, uv) * 0.20;
    bloom += sampleBloomBuffer(bloomBuffer, uv + x) * 0.10;
    bloom += sampleBloomBuffer(bloomBuffer, uv - x) * 0.10;
    bloom += sampleBloomBuffer(bloomBuffer, uv + y) * 0.10;
    bloom += sampleBloomBuffer(bloomBuffer, uv - y) * 0.10;
    bloom += sampleBloomBuffer(bloomBuffer, uv + d) * 0.10;
    bloom += sampleBloomBuffer(bloomBuffer, uv - d) * 0.10;
    bloom += sampleBloomBuffer(bloomBuffer, uv + vec2(d.x, -d.y)) * 0.10;
    bloom += sampleBloomBuffer(bloomBuffer, uv + vec2(-d.x, d.y)) * 0.10;
    return bloom;
}

#endif
