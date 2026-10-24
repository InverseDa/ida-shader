#include "/lib/constant.glsl"
#include "/lib/settings.glsl"
#ifdef FRAGMENT_SHADER
uniform sampler2D colortex1;
uniform sampler2D colortex3;
uniform sampler2D colortex15;
uniform sampler2D depthtex0;
uniform mat4 gbufferProjectionInverse;
uniform float viewWidth;
uniform float viewHeight;
uniform int frameCounter;
uniform int isEyeInWater;
#include "/lib/common/space.glsl"
#include "/lib/common/color.glsl"
#include "/lib/post/taa.glsl"

/* RENDERTARGETS: 12,13,14 */
void main() {
    vec4 Color = vec4(0.0);
    vec4 Surface = vec4(0.0);
    vec4 Hit = vec4(0.0);
#if SSR_TEMPORAL == 1
    vec2 FullSize = vec2(viewWidth, viewHeight);
    vec2 HistorySize = max(floor(FullSize * 0.5), vec2(1.0));
    ivec2 Pixel = min(ivec2(gl_FragCoord.xy / HistorySize * FullSize), ivec2(FullSize) - 1);
    vec4 Candidate = texelFetch(colortex3, Pixel, 0);
    float Kind = mod(Candidate.w, 4.0);
    float Tag = float(frameCounter - (frameCounter / 64) * 64) * 4.0 + Kind;
    if (isEyeInWater == 0 && Kind >= 1.0 && Kind <= 3.0 && Candidate.w == Tag && Candidate.z > 0.0) {
        // A later depth-writing foreground/hand must not leave water history
        // attached to its pixel. Non-depth-writing particles may overlay it.
        vec2 Uv = (vec2(Pixel) + 0.5) / FullSize;
        if (Kind == 3.0) Uv -= GetTaaJitterNdc(frameCounter, vec2(viewWidth, viewHeight)) * 0.5;
        float VisibleDepth = -ReconstructViewPos(Uv, texelFetch(depthtex0, Pixel, 0).r, gbufferProjectionInverse).z;
        if (VisibleDepth + max(0.04, Candidate.z * 0.004) >= Candidate.z) {
            Color = texelFetch(colortex1, Pixel, 0);
            Hit = texelFetch(colortex15, Pixel, 0);
            if (IsFiniteRadiance(Color.rgb) && !any(isnan(Hit)) && !any(isinf(Hit))) Surface = Candidate;
            else { Color = vec4(0.0); Hit = vec4(0.0); }
        }
    }
#endif
    gl_FragData[0] = Color;
    gl_FragData[1] = Surface;
    gl_FragData[2] = Hit;
}
#endif
#ifdef VERTEX_SHADER
void main() { gl_Position = ftransform(); }
#endif
