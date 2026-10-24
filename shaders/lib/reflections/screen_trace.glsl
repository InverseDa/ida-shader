#ifndef IDA_SCREEN_TRACE_GLSL
#define IDA_SCREEN_TRACE_GLSL
#include "/lib/common/packing.glsl"
#include "/lib/post/screen.glsl"
#include "/lib/reflections/confidence.glsl"

struct ReflectionRayProbe {
    vec2 Uv;
    vec2 ProjectedUv;
    vec2 ScreenUv;
    vec3 SceneView;
    vec3 NormalView;
    bool OnScreen;
    bool Surface;
};

ReflectionRayProbe ProbeReflectionRay(vec3 RayView) {
    ReflectionRayProbe Probe;
    Probe.Uv = vec2(-1.0);
    Probe.ProjectedUv = vec2(-1.0);
    Probe.ScreenUv = vec2(-1.0);
    Probe.SceneView = vec3(0.0);
    Probe.NormalView = vec3(0.0);
    Probe.Surface = false;
    vec4 Snapshot;
    Probe.OnScreen = ProjectAndSampleOpaque(RayView, Probe.Uv, Snapshot, Probe.ScreenUv);
    Probe.ProjectedUv = Probe.Uv;
    if (!Probe.OnScreen || Snapshot.b >= 0.999999) return Probe;
    // Reconstruct the exact texel whose depth was fetched, including its own
    // jitter convention. A continuous projected UV belongs to a different ray.
    vec2 Size = vec2(textureSize(colortex4, 0));
    Probe.Uv = (floor(Probe.Uv * Size) + 0.5) / Size;
    Probe.SceneView = ReconstructOpaqueViewPos(Probe.Uv, Snapshot);
    Probe.NormalView = NormalDecode(Snapshot.rg);
    Probe.Surface = true;
    return Probe;
}

float ReflectionHitTolerance(float ViewDepth) {
    float PixelSize = 2.0 * ViewDepth / (gbufferProjection[1].y * viewHeight);
    return clamp(0.025 + 2.0 * PixelSize, 0.035, 0.35);
}

float ReflectionHitConfidence(vec3 RayView, vec3 SceneView, vec3 SceneNormal, vec3 SurfaceView, vec3 NormalView, vec2 ScreenUv, float Travel, float MaxDistance) {
    // A texel on a grazing surface covers a longer world-space footprint.
    // Test both its plane and its footprint: a sphere around the depth sample
    // rejects valid slopes, while a broad depth slab accepts unrelated layers.
    float Incidence = max(abs(dot(SceneNormal, normalize(SceneView))), 0.5);
    float PixelSize = 2.0 * (-SceneView.z) / (abs(gbufferProjection[1].y) * viewHeight);
    float Tolerance = max(0.035, PixelSize * 2.0 / Incidence);
    float Error = length(SceneView - RayView);
    float Agreement = 1.0 - smoothstep(Tolerance * 0.75, Tolerance, Error);
    float PlaneError = abs(dot(SceneView - RayView, SceneNormal));
    // Packed normal/depth precision, independent of a multi-metre trace step.
    // Perspective depth/reconstruction roundoff grows quadratically with Z.
    // A fixed centimetre threshold creates stippled far walls at 5K even
    // though the source hardware depth is stored without losing any bits.
    float DepthPrecision = 0.00000024 * SceneView.z * SceneView.z / max(near, 0.01);
    float PlaneTolerance = max(0.012 + Error * 0.0015, DepthPrecision);
    Agreement *= 1.0 - smoothstep(PlaneTolerance * 0.5, PlaneTolerance, PlaneError);
    float AbovePlane = smoothstep(0.025, 0.12, dot(SceneView - SurfaceView, NormalView));
    return Agreement * AbovePlane * ReflectionEdgeConfidence(ScreenUv) *
           (1.0 - smoothstep(MaxDistance * (2.0 / 3.0), MaxDistance, Travel));
}

float ReflectionPlaneTravel(vec3 Origin, vec3 Direction, ReflectionRayProbe Probe) {
    if (!Probe.Surface) return -1.0;
    float Denominator = dot(Direction, Probe.NormalView);
    if (abs(Denominator) < 0.02) return -1.0;
    return dot(Probe.SceneView - Origin, Probe.NormalView) / Denominator;
}

// A depth-aware bilinear footprint fades geometry silhouettes by coverage.
// Keep rejected tap weight as missing confidence: renormalizing it to one would
// turn the last surviving leaf/edge texel into a full-strength popping reflection.
ReflectionResult FilterReflectionHit(vec3 RayView, vec3 SurfaceView, vec3 NormalView, ReflectionRayProbe Hit, float Travel, float MaxDistance, vec3 Sky) {
    vec2 Size = vec2(textureSize(colortex4, 0));
    vec2 BasePixel = floor(Hit.ProjectedUv * Size - 0.5);
    vec3 Sum = vec3(0.0);
    float Support = 0.0;
    vec3 ColorMinimum = vec3(65504.0);
    vec3 ColorMaximum = vec3(0.0);
    for (int I = 0; I < 4; ++I) {
        vec2 Offset = vec2(float(I % 2), float(I >= 2));
        vec2 Pixel = BasePixel + Offset;
        if (Pixel.x < 0.0 || Pixel.y < 0.0 || Pixel.x >= Size.x || Pixel.y >= Size.y) continue;
        vec2 Uv = (Pixel + 0.5) / Size;
        vec4 Snapshot = FetchOpaqueData(ivec2(Pixel));
        if (Snapshot.b >= 0.999999) continue;
        vec2 ProjectedUv = Hit.ScreenUv;
        if (Snapshot.a > 1.5) ProjectedUv += CurrentJitterUv();
        vec2 Coverage = max(vec2(0.0), vec2(1.0) - abs((ProjectedUv - Uv) * Size));
        float Weight = Coverage.x * Coverage.y;
        vec3 SceneView = ReconstructOpaqueViewPos(Uv, Snapshot);
        vec3 SceneNormal = NormalDecode(Snapshot.rg);
        Weight *= ReflectionHitConfidence(RayView, SceneView, SceneNormal, SurfaceView, NormalView, Hit.ScreenUv, Travel, MaxDistance);
        if (Weight <= 0.0) continue;
        vec3 TapColor = texelFetch(colortex9, ivec2(Pixel), 0).rgb;
        Sum += TapColor * Weight;
        ColorMinimum = min(ColorMinimum, TapColor);
        ColorMaximum = max(ColorMaximum, TapColor);
        Support += Weight;
    }
    if (Support <= 0.0) return CreateReflectionResult(Sky, 0.0);
    ReflectionResult Result = CreateReflectionResult(Sum / Support, clamp(Support, 0.0, 1.0));
    Result.HitDistance = Travel;
    Result.ColorMinimum = ColorMinimum;
    Result.ColorMaximum = ColorMaximum;
    return Result;
}

ReflectionResult TraceScreenReflection(vec3 SurfaceView, vec3 NormalView, vec3 Direction, float MaxDistance, int Steps, vec3 Sky) {
    ReflectionResult Miss = CreateReflectionResult(Sky, 0.0);
    vec3 Origin = SurfaceView + NormalView * 0.015;
    float PreviousTravel = 0.06;
    float Stride = 0.25;
    ReflectionRayProbe Previous = ProbeReflectionRay(Origin + Direction * PreviousTravel);
    if (!Previous.OnScreen) return Miss;
    // A cutout canopy is not a continuous depth function. Bisection can lock
    // onto an alpha-hole boundary and discard a perfectly visible leaf. Use
    // the sampled surface plane as a hint, then verify the proposed hit against
    // the original snapshot. A normal map cannot create fictitious geometry.
    int Probes = 1;
    float LastChecked = -1.0;
    float PendingTravel = 1e6;
    vec3 PendingNormal = vec3(0.0);
    // Grow through empty space and shorten the next step near visible depth.
    // Travel is independent of the number of candidate checks already spent.
    // One budget still bounds all projection probes and bilinear validation.
    // No frame-varying offsets: a static surface has a static search pattern.
    for (int I = 0; I < 48; ++I) {
        if (I >= Steps || Probes >= Steps + 1) return Miss;
        float Travel = min(PreviousTravel + Stride, MaxDistance);
        ReflectionRayProbe Probe = ProbeReflectionRay(Origin + Direction * Travel);
        Probes += 1;
        // Even when this coarse endpoint leaves the viewport, a surface seen
        // at the previous endpoint can intersect the ray before the edge.
        float A = ReflectionPlaneTravel(Origin, Direction, Previous);
        float B = ReflectionPlaneTravel(Origin, Direction, Probe);
        // A leaf plane can be observed before its intersection distance, then
        // disappear into alpha holes in the next depth sample. Retain its
        // nearest future hint until the march reaches it; do not lose it just
        // because the current pixel sees the wall behind the canopy.
        if (A > Travel && A < MaxDistance && A < PendingTravel) {
            PendingTravel = A;
            PendingNormal = Previous.NormalView;
        }
        if (B > Travel && B < MaxDistance && B < PendingTravel) {
            PendingTravel = B;
            PendingNormal = Probe.NormalView;
        }
        float C = PendingTravel;
        // Allow one interval of look-back when a coarse probe landed in a
        // cutout hole. Every accepted color still belongs to the actual ray.
        float Lower = max(0.06, PreviousTravel - (Travel - PreviousTravel));
        if (A < Lower || A > Travel) A = 1e6;
        if (B < Lower || B > Travel) B = 1e6;
        if (C < Lower || C > Travel) C = 1e6;
        if (PendingTravel <= Travel) PendingTravel = 1e6;
        float First = min(min(A, B), C);
        float Second = max(min(A, B), min(max(A, B), C));
        float Third = max(max(A, B), C);
        for (int J = 0; J < 3; ++J) {
            float Candidate = First;
            if (J == 1) Candidate = Second;
            if (J == 2) Candidate = Third;
            if (Candidate < MaxDistance && abs(Candidate - LastChecked) > 0.02 && Probes < Steps + 1) {
                vec3 CandidateNormal = Previous.NormalView;
                if (Candidate == B) CandidateNormal = Probe.NormalView;
                if (Candidate == C) CandidateNormal = PendingNormal;
                LastChecked = Candidate;
                Probes += 1;
                vec3 RayView = Origin + Direction * Candidate;
                ReflectionRayProbe Hit = ProbeReflectionRay(RayView);
                if (Hit.OnScreen) {
                    // Refit a coarse hint's quantized plane against local depth.
                    // A different face at the center must not pull the hit off
                    // its original plane; its neighbours may cover that plane.
                    for (int K = 0; K < 2; ++K) {
                        if (!Hit.Surface || Probes + 3 > Steps + 1) break;
                        if (dot(CandidateNormal, Hit.NormalView) < 0.995) break;
                        float Corrected = ReflectionPlaneTravel(Origin, Direction, Hit);
                        float Correction = abs(Corrected - Candidate);
                        if (Corrected < 0.06 || Corrected >= MaxDistance ||
                            Correction > max(0.12, Candidate * 0.002) ||
                            Correction < max(0.001, Candidate * 0.00001)) break;
                        Candidate = Corrected;
                        RayView = Origin + Direction * Candidate;
                        Hit = ProbeReflectionRay(RayView);
                        Probes += 1;
                    }
                    if (!Hit.OnScreen) continue;
                    if (Probes + 2 > Steps + 1) return Miss;
                    Probes += 2;
                    ReflectionResult Filtered = FilterReflectionHit(RayView, SurfaceView, NormalView, Hit, Candidate, MaxDistance, Sky);
                    if (Filtered.Confidence > 0.0) return Filtered;
                }
                // A hole or unrelated foreground surface invalidates this
                // hint, not the entire ray. Later hits must pass the same test.
            }
        }
        if (!Probe.OnScreen || Travel >= MaxDistance) return Miss;
        Stride = min(Stride * 1.7, MaxDistance * 0.125);
        if (Probe.Surface) {
            // The depth separation estimates distance to the next crossing.
            // Keep a floor to progress past cutout/foreground discontinuities.
            float Separation = length(Probe.SceneView - (Origin + Direction * Travel));
            Stride = min(Stride, max(0.25, Separation * 0.75));
        } else {
            // Sky texels are also holes between leaves. Bound their projected
            // span so exponential growth cannot jump across an entire canopy.
            float AngularSlope = length(vec2(gbufferProjection[0].x, gbufferProjection[1].y) *
                                        (Direction.xy * Origin.z - Origin.xy * Direction.z));
            float RayDepth = -(Origin.z + Direction.z * Travel);
            Stride = min(Stride, max(0.25, 0.02 * RayDepth * RayDepth / max(AngularSlope, 0.0001)));
        }
        PreviousTravel = Travel;
        Previous = Probe;
    }
    return Miss;
}
#endif
