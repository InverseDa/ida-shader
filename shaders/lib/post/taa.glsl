#ifndef IDA_POST_TAA_GLSL
#define IDA_POST_TAA_GLSL

vec2 getTaaHaltonOffset(int frameIndex) {
    int index = frameIndex - (frameIndex / 8) * 8;
    if (index == 0) return vec2(0.5000, 0.3333);
    if (index == 1) return vec2(0.2500, 0.6667);
    if (index == 2) return vec2(0.7500, 0.1111);
    if (index == 3) return vec2(0.1250, 0.4444);
    if (index == 4) return vec2(0.6250, 0.7778);
    if (index == 5) return vec2(0.3750, 0.2222);
    if (index == 6) return vec2(0.8750, 0.5556);
    return vec2(0.0625, 0.8889);
}

vec2 getTaaJitterNdc(int frameIndex, vec2 resolution) {
    return 2.0 * (getTaaHaltonOffset(frameIndex) - 0.5) / max(resolution, vec2(1.0));
}

#ifdef VERTEX_SHADER
uniform int frameCounter;
uniform float viewWidth;
uniform float viewHeight;

void applyTaaJitter(inout vec4 clipPos) {
    clipPos.xy += getTaaJitterNdc(frameCounter, vec2(viewWidth, viewHeight)) * clipPos.w;
}
#endif

#endif
