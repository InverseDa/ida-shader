#ifndef IDA_SCREEN_TRACE_GLSL
#define IDA_SCREEN_TRACE_GLSL

// ---- Screen Trace ----

#include "/lib/common/packing.glsl"
#include "/lib/post/screen.glsl"
#include "/lib/reflections/confidence.glsl"
#include "/lib/reflections/screen_tiles.glsl"

struct ReflectionRayProbe
{
    vec2 Uv;
    vec2 ProjectedUv;
    vec2 ScreenUv;
    vec3 SceneView;
    vec3 NormalView;
    bool bOnScreen;
    bool bSurface;
};

ReflectionRayProbe ProbeReflectionRay(vec3 RayView)
{
    ReflectionRayProbe Probe;
    Probe.Uv = vec2(-1.0);
    Probe.ProjectedUv = vec2(-1.0);
    Probe.ScreenUv = vec2(-1.0);
    Probe.SceneView = vec3(0.0);
    Probe.NormalView = vec3(0.0);
    Probe.bSurface = false;
    vec4 Snapshot;
    Probe.bOnScreen = ProjectAndSampleOpaque(RayView, Probe.Uv, Snapshot, Probe.ScreenUv);
    Probe.ProjectedUv = Probe.Uv;

    if (!Probe.bOnScreen || Snapshot.b >= 0.999999)
    {
        return Probe;
    }

    // Reconstruct the exact texel whose depth was fetched, including its own
    // jitter convention. A continuous projected UV belongs to a different ray.
    vec2 Size = vec2(textureSize(colortex4, 0));
    Probe.Uv = (floor(Probe.Uv * Size) + 0.5) / Size;
    Probe.SceneView = ReconstructOpaqueViewPos(Probe.Uv, Snapshot);
    Probe.NormalView = NormalDecode(Snapshot.rg);
    Probe.bSurface = true;

    return Probe;
}

float ReflectionHitTolerance(float ViewDepth)
{
    float PixelSize = 2.0 * ViewDepth / (gbufferProjection[1].y * viewHeight);

    return clamp(0.025 + 2.0 * PixelSize, 0.035, 0.35);
}

float ReflectionHitConfidence(vec3 RayView, vec3 SceneView, vec3 SceneNormal, vec3 SurfaceView, vec3 NormalView, vec2 ScreenUv, float Travel, float MaxDistance)
{
    // Validate both surface plane and texel footprint to accept slopes without unrelated layers.
    float Incidence = max(abs(dot(SceneNormal, normalize(SceneView))), 0.5);
    float PixelSize = 2.0 * (-SceneView.z) / (abs(gbufferProjection[1].y) * viewHeight);
    float Tolerance = max(0.035, PixelSize * 2.0 / Incidence);
    float Error = length(SceneView - RayView);
    float Agreement = 1.0 - smoothstep(Tolerance * 0.75, Tolerance, Error);
    float PlaneError = abs(dot(SceneView - RayView, SceneNormal));

    // Scale precision tolerance with perspective depth roundoff, not the ray-march step size.
    float DepthPrecision = 0.00000024 * SceneView.z * SceneView.z / max(near, 0.01);
    float PlaneTolerance = max(0.012 + Error * 0.0015, DepthPrecision);
    Agreement *= 1.0 - smoothstep(PlaneTolerance * 0.5, PlaneTolerance, PlaneError);

    // Geometric validity is not alpha coverage. A tiny residual from an
    // unrelated face must not stop the march with a nearly empty reflection.
    Agreement = step(0.5, Agreement);
    float AbovePlane = smoothstep(0.002, 0.02, dot(SceneView - SurfaceView, NormalView));

    return Agreement * AbovePlane * ReflectionEdgeConfidence(ScreenUv) *
           (1.0 - smoothstep(MaxDistance * (2.0 / 3.0), MaxDistance, Travel));
}

float ReflectionPlaneTravel(vec3 Origin, vec3 Direction, ReflectionRayProbe Probe)
{
    if (!Probe.bSurface)
    {
        return -1.0;
    }

    float Denominator = dot(Direction, Probe.NormalView);

    if (abs(Denominator) < 0.02)
    {
        return -1.0;
    }

    return dot(Probe.SceneView - Origin, Probe.NormalView) / Denominator;
}

// Keep rejected bilinear weight as missing confidence to fade silhouettes without popping.

// ---- Hit Reconstruction ----

ReflectionResult FilterReflectionHit(vec3 RayView, vec3 SurfaceView, vec3 NormalView, ReflectionRayProbe Hit, float Travel, float MaxDistance, vec3 Sky)
{
    vec2 Size = vec2(textureSize(colortex4, 0));
    vec2 BasePixel = floor(Hit.ProjectedUv * Size - 0.5);
    vec3 Sum = vec3(0.0);
    float Support = 0.0;
    vec3 ColorMinimum = vec3(65504.0);
    vec3 ColorMaximum = vec3(0.0);
    vec4 BestPlane = vec4(0.0);
    float BestWeight = 0.0;

    for (int I = 0; I < 4; ++I)
    {
        vec2 Offset = vec2(float(I % 2), float(I >= 2));
        vec2 Pixel = BasePixel + Offset;

        if (Pixel.x < 0.0 || Pixel.y < 0.0 || Pixel.x >= Size.x || Pixel.y >= Size.y)
        {
            continue;
        }

        vec2 Uv = (Pixel + 0.5) / Size;
        vec4 Snapshot = FetchOpaqueData(ivec2(Pixel));

        if (Snapshot.b >= 0.999999)
        {
            continue;
        }

        vec2 ProjectedUv = Hit.ScreenUv;

        if (Snapshot.a > 1.5)
        {
            ProjectedUv += CurrentJitterUv();
        }

        vec2 Coverage = max(vec2(0.0), vec2(1.0) - abs((ProjectedUv - Uv) * Size));
        float Weight = Coverage.x * Coverage.y;
        vec3 SceneView = ReconstructOpaqueViewPos(Uv, Snapshot);
        vec3 SceneNormal = NormalDecode(Snapshot.rg);
        Weight *= ReflectionHitConfidence(RayView, SceneView, SceneNormal, SurfaceView, NormalView, Hit.ScreenUv, Travel, MaxDistance);

        if (Weight <= 0.0)
        {
            continue;
        }

        if (Weight > BestWeight)
        {
            BestPlane = vec4(SceneNormal, dot(SceneNormal, SceneView));
            BestWeight = Weight;
        }

        vec3 TapColor = texelFetch(colortex9, ivec2(Pixel), 0).rgb;
        Sum += TapColor * Weight;
        ColorMinimum = min(ColorMinimum, TapColor);
        ColorMaximum = max(ColorMaximum, TapColor);
        Support += Weight;
    }

    if (Support <= 0.0)
    {
        return CreateReflectionResult(Sky, 0.0);
    }

    ReflectionResult Result = CreateReflectionResult(Sum / Support, clamp(Support, 0.0, 1.0));
    Result.HitDistance = Travel;
    Result.ColorMinimum = ColorMinimum;
    Result.ColorMaximum = ColorMaximum;
    Result.Plane = BestPlane;

    return Result;
}

// ---- Screen Ray March ----

ReflectionResult TraceScreenReflection(vec3 SurfaceView, vec3 NormalView, vec3 Direction, float MaxDistance, int Steps, vec3 Sky, float StopDistance)
{
    ReflectionResult Miss = CreateReflectionResult(Sky, 0.0);
    float TraceLimit = min(MaxDistance, StopDistance);
    vec3 Origin = SurfaceView + NormalView * 0.015;
    float PreviousTravel = 0.06;
    float Stride = 0.25;
#if VOXEL_REFLECTIONS == 1
    bool bTilesReady = ReflectionTilesReady();

    if (bTilesReady && ReflectionTiles[4099] == 0u)
    {
        return Miss;
    }

    if (bTilesReady)
    {
        PreviousTravel = SkipEmptyReflectionTiles(Origin, Direction, PreviousTravel, TraceLimit);
    }

    if (PreviousTravel >= TraceLimit)
    {
        return Miss;
    }
#endif
    ReflectionRayProbe Previous = ProbeReflectionRay(Origin + Direction * PreviousTravel);

    if (!Previous.bOnScreen)
    {
        return Miss;
    }

    // Use sampled geometry planes as hints, then validate against the original snapshot.
    // Bisection across alpha holes can discard a visible leaf.
    int Probes = 1;
    float LastChecked = -1.0;
    float PendingTravel = 1e6;
    vec3 PendingNormal = vec3(0.0);

    // Adapt travel to visible depth under one probe budget; static rays use a fixed search pattern.
    for (int I = 0; I < 48; ++I)
    {
        if (I >= Steps || Probes >= Steps + 1)
        {
            return Miss;
        }

        float Travel = min(PreviousTravel + Stride, TraceLimit);
        ReflectionRayProbe Probe = ProbeReflectionRay(Origin + Direction * Travel);
        Probes += 1;

        // Even when this coarse endpoint leaves the viewport, a surface seen
        // at the previous endpoint can intersect the ray before the edge.
        float A = ReflectionPlaneTravel(Origin, Direction, Previous);
        float B = ReflectionPlaneTravel(Origin, Direction, Probe);

        // Retain leaf-plane geometry through alpha holes; neighbouring rays must validate their own colors.
        if (A > 0.06 && A < TraceLimit && (Miss.HitDistance <= 0.0 || A < Miss.HitDistance) &&
            dot(Origin + Direction * A - SurfaceView, NormalView) > 0.025)
        {
            Miss.HitDistance = A;
            Miss.Plane = vec4(Previous.NormalView, dot(Previous.NormalView, Previous.SceneView));
        }

        if (B > 0.06 && B < TraceLimit && (Miss.HitDistance <= 0.0 || B < Miss.HitDistance) &&
            dot(Origin + Direction * B - SurfaceView, NormalView) > 0.025)
        {
            Miss.HitDistance = B;
            Miss.Plane = vec4(Probe.NormalView, dot(Probe.NormalView, Probe.SceneView));
        }

        // Retain the nearest future leaf-plane hint across alpha holes until the ray reaches it.
        if (A > Travel && A < TraceLimit && A < PendingTravel)
        {
            PendingTravel = A;
            PendingNormal = Previous.NormalView;
        }

        if (B > Travel && B < TraceLimit && B < PendingTravel)
        {
            PendingTravel = B;
            PendingNormal = Probe.NormalView;
        }

        float C = PendingTravel;

        // Allow one interval of look-back when a coarse probe landed in a
        // cutout hole. Every accepted color still belongs to the actual ray.
        float Lower = max(0.06, PreviousTravel - (Travel - PreviousTravel));

        if (A < Lower || A > Travel)
        {
            A = 1e6;
        }

        if (B < Lower || B > Travel)
        {
            B = 1e6;
        }

        if (C < Lower || C > Travel)
        {
            C = 1e6;
        }

        if (PendingTravel <= Travel)
        {
            PendingTravel = 1e6;
        }

        float First = min(min(A, B), C);
        float Second = max(min(A, B), min(max(A, B), C));
        float Third = max(max(A, B), C);

        for (int J = 0; J < 3; ++J)
        {
            float Candidate = First;

            if (J == 1)
            {
                Candidate = Second;
            }

            if (J == 2)
            {
                Candidate = Third;
            }

            if (Candidate < TraceLimit && abs(Candidate - LastChecked) > 0.02 && Probes < Steps + 1)
            {
                vec3 CandidateNormal = Previous.NormalView;

                if (Candidate == B)
                {
                    CandidateNormal = Probe.NormalView;
                }

                if (Candidate == C)
                {
                    CandidateNormal = PendingNormal;
                }

                LastChecked = Candidate;
                Probes += 1;
                vec3 RayView = Origin + Direction * Candidate;
                ReflectionRayProbe Hit = ProbeReflectionRay(RayView);

                if (Hit.bOnScreen)
                {
                    // Refit against matching neighbouring depth; a different centre face must not move the plane.
                    for (int K = 0; K < 2; ++K)
                    {
                        if (!Hit.bSurface || Probes + 3 > Steps + 1)
                        {
                            break;
                        }

                        if (dot(CandidateNormal, Hit.NormalView) < 0.995)
                        {
                            break;
                        }

                        float Corrected = ReflectionPlaneTravel(Origin, Direction, Hit);
                        float Correction = abs(Corrected - Candidate);

                        if (Corrected < 0.06 || Corrected >= TraceLimit ||
                            Correction > max(0.12, Candidate * 0.002) ||
                            Correction < max(0.001, Candidate * 0.00001))
                        {
                            break;
                        }

                        Candidate = Corrected;
                        RayView = Origin + Direction * Candidate;
                        Hit = ProbeReflectionRay(RayView);
                        Probes += 1;
                    }

                    if (!Hit.bOnScreen)
                    {
                        continue;
                    }

                    if (Probes + 2 > Steps + 1)
                    {
                        return Miss;
                    }

                    Probes += 2;
                    ReflectionResult Filtered = FilterReflectionHit(RayView, SurfaceView, NormalView, Hit, Candidate, MaxDistance, Sky);

                    if (Filtered.Confidence > 0.0)
                    {
                        return Filtered;
                    }
                }

                // A hole or unrelated foreground surface invalidates this
                // hint, not the entire ray. Later hits must pass the same test.
            }
        }

        if (!Probe.bOnScreen || Travel >= TraceLimit)
        {
            return Miss;
        }

        Stride = min(Stride * 1.7, MaxDistance * 0.125);

        if (Probe.bSurface)
        {
            // The depth separation estimates distance to the next crossing.
            // Keep a floor to progress past cutout/foreground discontinuities.
            float Separation = length(Probe.SceneView - (Origin + Direction * Travel));
            Stride = min(Stride, max(0.25, Separation * 0.75));
        }
        else
        {
            // Sky texels are also holes between leaves. Bound their projected
            // span so exponential growth cannot jump across an entire canopy.
            float AngularSlope = length(vec2(gbufferProjection[0].x, gbufferProjection[1].y) *
                                        (Direction.xy * Origin.z - Origin.xy * Direction.z));
            float RayDepth = -(Origin.z + Direction.z * Travel);
            Stride = min(Stride, max(0.25, 0.02 * RayDepth * RayDepth / max(AngularSlope, 0.0001)));
#if VOXEL_REFLECTIONS == 1
            if (bTilesReady)
            {
                Stride = max(Stride, SkipEmptyReflectionTiles(Origin, Direction, Travel, TraceLimit) - Travel);
            }
#endif
        }

        PreviousTravel = Travel;
        Previous = Probe;
    }

    return Miss;
}

ReflectionResult TraceScreenReflection(vec3 SurfaceView, vec3 NormalView, vec3 Direction, float MaxDistance, int Steps, vec3 Sky)
{
    return TraceScreenReflection(SurfaceView, NormalView, Direction, MaxDistance, Steps, Sky, MaxDistance);
}
#endif
