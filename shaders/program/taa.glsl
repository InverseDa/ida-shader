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
#include "/lib/post/water_temporal.glsl"

in vec4 Texcoord;
// Exactly representable FP16, distinct from the existing water tag -65504.
const float SkyHistoryTag = -65472.0;

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
    vec3 WaterView,WaterNormal;float WaterTravel;
    bool Water=Reactive && WaterTemporalSurface(Pixel,WaterView,WaterNormal,WaterTravel);
    vec4 Opaque = vec4(0.0, 0.0, 1.0, 0.0);
    if (!Reactive) Opaque = FetchOpaqueData(Pixel);
    float Depth = Opaque.b;
    // Fuse mask dilation, spatial AA and temporal resolve in one full-screen
    // pass. Dynamic overlays reject history; verified water has its own
    // reflection-aware reprojection and history type below.
    bool Stable = Opaque.a > 1.5 && !Reactive;
    bool Sky = false;
#if ATMOSPHERE_HALF_RES == 1 || (VOLUMETRIC_LIGHT == 1 && VOLUMETRIC_LIGHT_CACHE == 1)
    Sky = !Reactive && Depth >= 0.999999 && isEyeInWater == 0;
#endif
    vec2 Jitter = GetTaaJitterNdc(frameCounter, vec2(viewWidth, viewHeight)) * 0.5;
    vec3 ViewPos = Stable ? ReconstructViewPos(Uv - Jitter, Depth, gbufferProjectionInverse) : vec3(0.0);
    float ViewDepth = -ViewPos.z;
    // Linear FP16 depth has <0.05% relative rounding error, below the 1%
    // history tolerance. Reject out-of-range depth instead of storing infinity.
    bool ValidSurface = Stable && Depth < 0.999999 && ViewDepth > 0.0 && ViewDepth <= 65504.0;
    vec3 ResolvedColor = CurrentColor;
    bool HistoryAccepted = false;
    if (Sky && frameCounter > 1 && length(cameraPosition - previousCameraPosition) < 8.0) {
        // Sky geometry is unjittered. Reproject a direction, not distant terrain.
        vec3 Direction = normalize(ReconstructViewPos(Uv, 1.0, gbufferProjectionInverse));
        vec3 WorldDirection = mat3(gbufferModelViewInverse) * Direction;
        vec3 PreviousDirection = mat3(gbufferPreviousModelView) * WorldDirection;
        if (PreviousDirection.z < 0.0) {
            vec2 PreviousUv = ProjectViewToScreenPos(PreviousDirection, gbufferPreviousProjection).xy;
            if (IsScreenUvInRange(PreviousUv)) {
                vec4 History = texture2D(colortex8, PreviousUv);
                // Mixed silhouettes, overlays and changed media reset history.
                if (History.a == SkyHistoryTag && IsFiniteRadiance(History.rgb)) {
                    float SkyMotion = length((PreviousUv - Uv) * vec2(viewWidth, viewHeight));
                    float Weight = mix(0.88, 0.45, clamp(SkyMotion * 0.06, 0.0, 1.0));
                    // Translation causes cloud parallax, unlike infinite sky.
                    Weight *= 1.0 - 0.75 * clamp(length(cameraPosition - previousCameraPosition) * 2.0, 0.0, 1.0);
                    ResolvedColor = mix(CurrentColor, ClampHistoryToNeighborhood(Pixel, CurrentColor, History.rgb), Weight);
                    HistoryAccepted = true;
                }
            }
        }
    }
    if(Water && frameCounter>1 && length(cameraPosition-previousCameraPosition)<8.0) {
        float Agreement;
        vec2 PreviousUv=WaterPreviousUv(Uv,WaterView,WaterNormal,WaterTravel,Agreement);
        if(Agreement>0.5 && IsScreenUvInRange(PreviousUv)) {
            ivec2 Size=textureSize(colortex8,0);vec2 P=PreviousUv*vec2(Size)-0.5,F=fract(P);ivec2 Base=ivec2(floor(P));
            vec3 History=vec3(0.0);float Support=0.0;
            // A bilinear tap has exactly this tag only when its entire
            // footprint is water. Mixed shore/hand footprints validate taps
            // separately; their opaque colours must never bleed into water.
            vec4 Bilinear=texture2D(colortex8,PreviousUv);
            if(Bilinear.a==WaterHistoryTag && IsFiniteRadiance(Bilinear.rgb)) {
                History=Bilinear.rgb;Support=1.0;
            } else for(int K=0;K<4;++K) {
                ivec2 Tap=clamp(Base+ivec2(K%2,K/2),ivec2(0),Size-1);
                vec4 Old=texelFetch(colortex8,Tap,0);
                if(Old.a!=WaterHistoryTag || !IsFiniteRadiance(Old.rgb)) continue;
                float W=(K%2==0 ? 1.0-F.x : F.x)*(K<2 ? 1.0-F.y : F.y);
                History+=Old.rgb*W;Support+=W;
            }
            if(Support>0.5) {
                History=ClampHistoryToNeighborhood(Pixel,CurrentColor,History/Support);
                float Motion=length((PreviousUv-Uv)*vec2(viewWidth,viewHeight));
                float Weight=mix(0.78,0.45,clamp(Motion*0.06,0.0,1.0))*Agreement*Support;
                ResolvedColor=mix(CurrentColor,History,Weight);HistoryAccepted=true;
            }
        }
    }
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
                    bool SameMedium = isEyeInWater == 1 ? Tap.a < 0.0 && Tap.a!=WaterHistoryTag && Tap.a!=SkyHistoryTag : Tap.a > 0.0;
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
    // its depth-valid history is unavailable. Other reactive surfaces remain
    // invalid in history; only explicitly verified water uses the new path.
    if (!HistoryAccepted) ResolvedColor = ResolveSpatialAa(Uv, CurrentColor);
    ResolvedColor = clamp(ResolvedColor, vec3(0.0), vec3(65504.0));
    gl_FragData[0] = vec4(ResolvedColor, 1.0);
    // Zero is invalid; -65504 marks water, -65472 marks sky. Other signs
    // record opaque camera medium, keeping these history types separate.
    gl_FragData[1] = vec4(ResolvedColor, Sky ? SkyHistoryTag : (Water ? WaterHistoryTag : (ValidSurface ? ViewDepth * (isEyeInWater == 1 ? -1.0 : 1.0) : 0.0)));
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
