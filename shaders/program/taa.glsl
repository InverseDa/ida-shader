#include "/lib/constant.glsl"
#include "/lib/util/functions.glsl"
#include "/lib/post/taa.glsl"
#include "/lib/materials/materialData.glsl"

// =====================================================================================
// ============================== Fragment Shader ======================================
// =====================================================================================
#ifdef FRAGMENT_SHADER
uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferPreviousProjection;
uniform mat4 gbufferPreviousModelView;
uniform sampler2D colortex0;
uniform sampler2D colortex8;
uniform sampler2D colortex4;
uniform sampler2D colortex10;
uniform vec3 cameraPosition;
uniform vec3 previousCameraPosition;
uniform float viewWidth;
uniform float viewHeight;
uniform int frameCounter;
uniform int isEyeInWater;
#include "/lib/common/opaque_snapshot.glsl"
#include "/lib/post/spatial_aa.glsl"
#include "/lib/post/reactive.glsl"

in vec4 texcoord;

vec2 getPreviousFrameUv(vec3 viewPos, out float previousDepth) {
    vec3 cameraRelativeWorld = viewToWorldPos(viewPos, gbufferModelViewInverse);
    vec3 previousRelativeWorld = cameraRelativeWorld + (cameraPosition - previousCameraPosition);
    vec3 previousView = worldToViewPos(previousRelativeWorld, gbufferPreviousModelView);
    previousDepth = -previousView.z;
    if (previousDepth <= 0.0) return vec2(-1.0);
    vec3 previousScreen = projectViewToScreenPos(previousView, gbufferPreviousProjection);
    vec2 previousJitter = getTaaJitterNdc(frameCounter - 1, vec2(viewWidth, viewHeight)) * 0.5;
    return previousScreen.xy + previousJitter;
}

vec3 clampHistoryToNeighborhood(ivec2 pixel, vec3 center, vec3 historyColor) {
    ivec2 size = textureSize(colortex0, 0);
    vec3 minimumColor = center;
    vec3 maximumColor = center;

    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            if (x == 0 && y == 0) continue;
            vec3 sampleColor = texelFetch(colortex0, clamp(pixel + ivec2(x, y), ivec2(0), size - 1), 0).rgb;
            minimumColor = min(minimumColor, sampleColor);
            maximumColor = max(maximumColor, sampleColor);
        }
    }

    vec3 colorRange = maximumColor - minimumColor;
    return clamp(historyColor, minimumColor - colorRange * 0.18, maximumColor + colorRange * 0.18);
}

/* DRAWBUFFERS:08 */
void main() {
    vec2 uv = texcoord.st;
    ivec2 pixel = ivec2(gl_FragCoord.xy);
    vec3 currentColor = texelFetch(colortex0, pixel, 0).rgb;
    bool reactive = hasReactiveCoverage(pixel);
    vec4 opaque = vec4(0.0, 0.0, 1.0, 0.0);
    if (!reactive) opaque = fetchOpaqueData(pixel);
    float depth = opaque.b;
    // Fuse mask dilation, spatial AA and temporal resolve in one full-screen
    // pass. Reactive pixels never read history or reconstruct opaque depth.
    bool stable = opaque.a > 1.5 && !reactive;
    vec2 jitter = getTaaJitterNdc(frameCounter, vec2(viewWidth, viewHeight)) * 0.5;
    vec3 viewPos = stable ? reconstructViewPos(uv - jitter, depth, gbufferProjectionInverse) : vec3(0.0);
    float viewDepth = -viewPos.z;
    // Linear FP16 depth has <0.05% relative rounding error, below the 1%
    // history tolerance. Reject out-of-range depth instead of storing infinity.
    bool validSurface = stable && depth < 0.999999 && viewDepth > 0.0 && viewDepth <= 65504.0;
    vec3 resolvedColor = reactive ? resolveSpatialAa(uv, currentColor) : currentColor;
    if (frameCounter > 1 && validSurface && length(cameraPosition - previousCameraPosition) < 8.0) {
        float previousDepth;
        vec2 previousUv = getPreviousFrameUv(viewPos, previousDepth);
        if (isScreenUvInRange(previousUv)) {
            vec2 historyPosition = previousUv * vec2(textureSize(colortex8, 0)) - 0.5;
            ivec2 origin = ivec2(floor(historyPosition));
            vec2 fraction = fract(historyPosition);
            vec3 historyColor = vec3(0.0);
            float validWeight = 0.0;
            for (int y = 0; y < 2; ++y) {
                for (int x = 0; x < 2; ++x) {
                    ivec2 pixel = clamp(origin + ivec2(x, y), ivec2(0), textureSize(colortex8, 0) - 1);
                    vec4 tap = texelFetch(colortex8, pixel, 0);
                    float weight = (x == 0 ? 1.0 - fraction.x : fraction.x) *
                                   (y == 0 ? 1.0 - fraction.y : fraction.y);
                    bool sameMedium = isEyeInWater == 1 ? tap.a < 0.0 : tap.a > 0.0;
                    if (sameMedium && abs(abs(tap.a) - previousDepth) < max(0.05, previousDepth * 0.01)) {
                        historyColor += tap.rgb * weight;
                        validWeight += weight;
                    }
                }
            }
            if (validWeight > 0.5) {
                historyColor /= validWeight;
                // Bound history using the unfiltered current frame. Dynamic
                // pixels use spatial AA independently and never accumulate it.
                historyColor = clampHistoryToNeighborhood(pixel, currentColor, historyColor);
                float motion = length(previousUv - uv) * max(viewWidth, viewHeight);
                float historyWeight = mix(0.88, 0.54, clamp(motion * 0.035, 0.0, 1.0));
                resolvedColor = mix(currentColor, historyColor, historyWeight);
            }
        }
    }

    resolvedColor = clamp(resolvedColor, vec3(0.0), vec3(65504.0));
    gl_FragData[0] = vec4(resolvedColor, 1.0);
    // Zero is invalid. The sign records camera medium, rejecting all history
    // when crossing the water surface without an additional history buffer.
    gl_FragData[1] = vec4(resolvedColor, validSurface ? viewDepth * (isEyeInWater == 1 ? -1.0 : 1.0) : 0.0);
}
#endif

// =====================================================================================
// =============================== Vertex Shader =======================================
// =====================================================================================
#ifdef VERTEX_SHADER
out vec4 texcoord;

void main() {
    gl_Position = ftransform();
    texcoord = gl_MultiTexCoord0;
}
#endif
