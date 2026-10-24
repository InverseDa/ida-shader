#include "/lib/constant.glsl"
#include "/lib/util/functions.glsl"
#include "/lib/post/taa.glsl"
#include "/lib/materials/materialData.glsl"

// =============================================================================
// Fragment Shader
// =============================================================================
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

in vec4 Texcoord;

vec2 GetPreviousFrameUv(vec3 ViewPos, out float PreviousDepth) {
    vec3 CameraRelativeWorld = ViewToWorldPos(ViewPos, gbufferModelViewInverse);
    vec3 PreviousRelativeWorld = CameraRelativeWorld + (cameraPosition - previousCameraPosition);
    vec3 PreviousView = WorldToViewPos(PreviousRelativeWorld, gbufferPreviousModelView);
    PreviousDepth = -PreviousView.z;
    if (PreviousDepth <= 0.0) return vec2(-1.0);
    vec3 PreviousScreen = ProjectViewToScreenPos(PreviousView, gbufferPreviousProjection);
    vec2 PreviousJitter = GetTaaJitterNdc(frameCounter - 1, vec2(viewWidth, viewHeight)) * 0.5;
    return PreviousScreen.xy + PreviousJitter;
}

vec3 ClampHistoryToNeighborhood(ivec2 Pixel, vec3 Center, vec3 HistoryColor) {
    ivec2 Size = textureSize(colortex0, 0);
    vec3 MinimumColor = Center;
    vec3 MaximumColor = Center;

    for (int Y = -1; Y <= 1; Y++) {
        for (int X = -1; X <= 1; X++) {
            if (X == 0 && Y == 0) continue;
            vec3 SampleColor = SanitizeRadiance(texelFetch(colortex0, clamp(Pixel + ivec2(X, Y), ivec2(0), Size - 1), 0).rgb);
            MinimumColor = min(MinimumColor, SampleColor);
            MaximumColor = max(MaximumColor, SampleColor);
        }
    }

    vec3 ColorRange = MaximumColor - MinimumColor;
    return clamp(HistoryColor, MinimumColor - ColorRange * 0.18, MaximumColor + ColorRange * 0.18);
}

/* DRAWBUFFERS:08 */
void main() {
    vec2 Uv = Texcoord.st;
    ivec2 Pixel = ivec2(gl_FragCoord.xy);
    vec3 CurrentColor = SanitizeRadiance(texelFetch(colortex0, Pixel, 0).rgb);
    bool Reactive = HasReactiveCoverage(Pixel);
    vec4 Opaque = vec4(0.0, 0.0, 1.0, 0.0);
    if (!Reactive) Opaque = FetchOpaqueData(Pixel);
    float Depth = Opaque.b;
    // Fuse mask dilation, spatial AA and temporal resolve in one full-screen
    // pass. Reactive pixels never read history or reconstruct opaque depth.
    bool Stable = Opaque.a > 1.5 && !Reactive;
    vec2 Jitter = GetTaaJitterNdc(frameCounter, vec2(viewWidth, viewHeight)) * 0.5;
    vec3 ViewPos = Stable ? ReconstructViewPos(Uv - Jitter, Depth, gbufferProjectionInverse) : vec3(0.0);
    float ViewDepth = -ViewPos.z;
    // Linear FP16 depth has <0.05% relative rounding error, below the 1%
    // history tolerance. Reject out-of-range depth instead of storing infinity.
    bool ValidSurface = Stable && Depth < 0.999999 && ViewDepth > 0.0 && ViewDepth <= 65504.0;
    vec3 ResolvedColor = CurrentColor;
    bool HistoryAccepted = false;
    if (frameCounter > 1 && ValidSurface && length(cameraPosition - previousCameraPosition) < 8.0) {
        float PreviousDepth;
        vec2 PreviousUv = GetPreviousFrameUv(ViewPos, PreviousDepth);
        if (IsScreenUvInRange(PreviousUv)) {
            vec2 HistoryPosition = PreviousUv * vec2(textureSize(colortex8, 0)) - 0.5;
            ivec2 Origin = ivec2(floor(HistoryPosition));
            vec2 Fraction = fract(HistoryPosition);
            vec3 HistoryColor = vec3(0.0);
            float ValidWeight = 0.0;
            for (int Y = 0; Y < 2; ++Y) {
                for (int X = 0; X < 2; ++X) {
                    ivec2 Pixel = clamp(Origin + ivec2(X, Y), ivec2(0), textureSize(colortex8, 0) - 1);
                    vec4 Tap = texelFetch(colortex8, Pixel, 0);
                    float Weight = (X == 0 ? 1.0 - Fraction.x : Fraction.x) *
                                   (Y == 0 ? 1.0 - Fraction.y : Fraction.y);
                    bool SameMedium = isEyeInWater == 1 ? Tap.a < 0.0 : Tap.a > 0.0;
                    if (IsFiniteRadiance(Tap.rgb) && SameMedium && abs(abs(Tap.a) - PreviousDepth) < max(0.05, PreviousDepth * 0.01)) {
                        HistoryColor += Tap.rgb * Weight;
                        ValidWeight += Weight;
                    }
                }
            }
            if (ValidWeight > 0.5) {
                HistoryColor /= ValidWeight;
                // Bound history using the unfiltered current frame. Dynamic
                // pixels use spatial AA independently and never accumulate it.
                HistoryColor = ClampHistoryToNeighborhood(Pixel, CurrentColor, HistoryColor);
                // Jitter is a sampling offset, not camera motion. Measure
                // actual displacement in pixels on each axis (including wide screens).
                vec2 PreviousJitter = GetTaaJitterNdc(frameCounter - 1, vec2(viewWidth, viewHeight)) * 0.5;
                float Motion = length((PreviousUv - Uv + Jitter - PreviousJitter) * vec2(viewWidth, viewHeight));
                float HistoryWeight = mix(0.88, 0.54, clamp(Motion * 0.035, 0.0, 1.0));
                ResolvedColor = mix(CurrentColor, HistoryColor, HistoryWeight * ValidWeight);
                HistoryAccepted = true;
            }
        }
    }

    // Newly revealed static terrain also needs a current-frame resolve while
    // its depth-valid history is unavailable. Reactive pixels remain invalid
    // in history, so this never accumulates moving geometry without vectors.
    if (!HistoryAccepted) ResolvedColor = ResolveSpatialAa(Uv, CurrentColor);
    ResolvedColor = clamp(ResolvedColor, vec3(0.0), vec3(65504.0));
    gl_FragData[0] = vec4(ResolvedColor, 1.0);
    // Zero is invalid. The sign records camera medium, rejecting all history
    // when crossing the water surface without an additional history buffer.
    gl_FragData[1] = vec4(ResolvedColor, ValidSurface ? ViewDepth * (isEyeInWater == 1 ? -1.0 : 1.0) : 0.0);
}

#endif // FRAGMENT_SHADER

// =============================================================================
// Vertex Shader
// =============================================================================
#ifdef VERTEX_SHADER

out vec4 Texcoord;

void main() {
    gl_Position = ftransform();
    Texcoord = gl_MultiTexCoord0;
}

#endif // VERTEX_SHADER
