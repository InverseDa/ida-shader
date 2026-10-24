#ifndef IDA_PUDDLE_TRACE_GLSL
#define IDA_PUDDLE_TRACE_GLSL
#include "/lib/common/packing.glsl"
#include "/lib/post/screen.glsl"
#include "/lib/reflections/confidence.glsl"

struct PuddleRayProbe {
    vec2 Uv;
    vec2 ScreenUv;
    vec3 SceneView;
    vec3 NormalView;
    bool OnScreen;
    bool Surface;
};

PuddleRayProbe ProbePuddleRay(vec3 RayView) {
    PuddleRayProbe Probe;
    Probe.Uv = vec2(-1.0);
    Probe.ScreenUv = vec2(-1.0);
    Probe.SceneView = vec3(0.0);
    Probe.NormalView = vec3(0.0);
    Probe.Surface = false;
    vec4 Snapshot;
    Probe.OnScreen = ProjectAndSampleOpaque(RayView, Probe.Uv, Snapshot, Probe.ScreenUv);
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

float PuddleTraceDistance(float Fraction) {
    // Denser near the pool, deterministic in world distance (no frame noise).
    return 0.06 + 47.94 * Fraction * Fraction;
}

float PuddleHitTolerance(float ViewDepth) {
    float PixelSize = 2.0 * ViewDepth / (gbufferProjection[1].y * viewHeight);
    return clamp(0.025 + 2.0 * PixelSize, 0.035, 0.18);
}

float PuddleHitConfidence(vec3 RayView, vec3 SceneView, vec3 SurfaceView, vec3 NormalView, vec2 ScreenUv, float Travel) {
    // A depth crossing at a silhouette is NOT necessarily a ray intersection.
    // Bound the full 3D error to a few pixels, never several world blocks.
    float Tolerance = PuddleHitTolerance(-SceneView.z);
    float Error = length(SceneView - RayView);
    float Agreement = 1.0 - smoothstep(Tolerance * 0.4, Tolerance, Error);
    float AbovePlane = smoothstep(0.025, 0.12, dot(SceneView - SurfaceView, NormalView));
    return Agreement * AbovePlane * ReflectionEdgeConfidence(ScreenUv) *
           (1.0 - smoothstep(32.0, 48.0, Travel));
}

float PuddlePlaneTravel(vec3 Origin, vec3 Direction, PuddleRayProbe Probe) {
    if (!Probe.Surface) return -1.0;
    float Denominator = dot(Direction, Probe.NormalView);
    if (abs(Denominator) < 0.02) return -1.0;
    return dot(Probe.SceneView - Origin, Probe.NormalView) / Denominator;
}

ReflectionResult TracePuddleReflection(vec3 SurfaceView, vec3 NormalView, vec3 Direction, vec3 Sky) {
    ReflectionResult Miss = CreateReflectionResult(Sky, 0.0);
    vec3 Origin = SurfaceView + NormalView * 0.015;
    float PreviousTravel = PuddleTraceDistance(0.0);
    PuddleRayProbe Previous = ProbePuddleRay(Origin + Direction * PreviousTravel);
    if (!Previous.OnScreen) return Miss;
    // A cutout canopy is not a continuous depth function. Bisection can lock
    // onto an alpha-hole boundary and discard a perfectly visible leaf. Use
    // the sampled surface plane as a hint, then verify the proposed hit against
    // the original snapshot. A normal map cannot create fictitious geometry.
    int Probes = 1;
    float LastChecked = -1.0;
    float PendingTravel = 1e6;
    // Share a 25-probe budget between denser marching and verification. Solid
    // faces usually need just one verification; cutouts may use several, but
    // cannot multiply the old maximum of 50 packed-snapshot reads.
    for (int I = 0; I < 24; ++I) {
        if (Probes >= 25) return Miss;
        float Travel = PuddleTraceDistance(float(I + 1) / 24.0);
        PuddleRayProbe Probe = ProbePuddleRay(Origin + Direction * Travel);
        Probes += 1;
        if (!Probe.OnScreen) return Miss;
        float A = PuddlePlaneTravel(Origin, Direction, Previous);
        float B = PuddlePlaneTravel(Origin, Direction, Probe);
        // A leaf plane can be observed before its intersection distance, then
        // disappear into alpha holes in the next depth sample. Retain its
        // nearest future hint until the march reaches it; do not lose it just
        // because the current pixel sees the wall behind the canopy.
        if (A > Travel && A < 48.0) PendingTravel = min(PendingTravel, A);
        if (B > Travel && B < 48.0) PendingTravel = min(PendingTravel, B);
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
            if (Candidate < 48.0 && abs(Candidate - LastChecked) > 0.02 && Probes < 25) {
                LastChecked = Candidate;
                Probes += 1;
                vec3 RayView = Origin + Direction * Candidate;
                PuddleRayProbe Hit = ProbePuddleRay(RayView);
                if (Hit.OnScreen && Hit.Surface) {
                    float Confidence = PuddleHitConfidence(RayView, Hit.SceneView, SurfaceView, NormalView, Hit.ScreenUv, Candidate);
                    if (Confidence > 0.0) {
                        vec3 Color = textureLod(colortex9, Hit.Uv, 0.0).rgb;
                        return CreateReflectionResult(Color, Confidence);
                    }
                }
                // A hole or unrelated foreground surface invalidates this
                // hint, not the entire ray. Later hits must pass the same test.
            }
        }
        PreviousTravel = Travel;
        Previous = Probe;
    }
    return Miss;
}
#endif
