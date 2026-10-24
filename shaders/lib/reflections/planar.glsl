#ifndef IDA_REFLECTIONS_PLANAR_GLSL
#define IDA_REFLECTIONS_PLANAR_GLSL

#include "/lib/common/packing.glsl"
#include "/lib/common/space.glsl"
#include "/lib/reflections/confidence.glsl"

struct WaterPlaneData {
    vec3 PointWorld;
    vec3 NormalWorld;
    vec3 MirroredCameraWorld;
    float LevelHeight;
    float PlanarWeight;
};

struct PlanarIntersectionData {
    vec3 SurfacePointWorld;
    vec3 ReflectedDirWorld;
    float IncidentAlignment;
};

struct PlanarProjectionData {
    vec3 OriginWorld;
    vec3 DirectionWorld;
    vec3 LateralAxisWorld;
    float LateralSpread;
    float TravelStart;
    float TravelEnd;
};

struct PlanarSamplingConfig {
    int StepCount;
    float DistanceFadeMin;
    float DistanceFadeMax;
};

struct PlanarSolveResult {
    WaterPlaneData Plane;
    PlanarIntersectionData Intersection;
    PlanarProjectionData Projection;
    PlanarSamplingConfig Sampling;
};

struct PlanarReflectionCandidate {
    vec2 Uv;
    float Quality;
    float EdgeConfidence;
};

struct PlanarReprojectedSample {
    vec3 MirroredCandidateWorldPos;
    vec3 SceneWorldPos;
    vec3 SceneNormalWorld;
    vec2 Uv;
    float DepthError;
    float ReprojectionError;
    float RayAlignment;
    float NormalAlignment;
    float AbovePlaneMask;
    float EdgeConfidence;
    bool Valid;
};

float GetPlanarViewSpaceDepth(vec3 ViewPos) {
    return -ViewPos.z;
}

vec3 GetPlanarFallbackAxis(vec3 NormalWorld) {
    vec3 FallbackAxis = cross(NormalWorld, vec3(0.0, 0.0, 1.0));
    if (dot(FallbackAxis, FallbackAxis) < 0.0001) {
        FallbackAxis = cross(NormalWorld, vec3(1.0, 0.0, 0.0));
    }
    return normalize(FallbackAxis);
}

vec3 SamplePlanarReflectionColor(vec2 Uv, float Contribution) {
    vec2 Texel = vec2(1.0 / viewWidth, 1.0 / viewHeight);
    vec2 CenterUv = clamp(Uv, Texel * 1.5, vec2(1.0) - Texel * 1.5);
    // Explicit LOD: this helper runs inside divergent candidate branches.
    vec3 Center = textureLod(colortex9, CenterUv, 0.0).rgb;
    float FilterAmount = ReflectionFilterAmount(Contribution);
    if (FilterAmount <= 0.0) return Center;
    vec3 Neighbors = textureLod(colortex9, CenterUv + vec2(Texel.x, 0.0), 0.0).rgb;
    Neighbors += textureLod(colortex9, CenterUv - vec2(Texel.x, 0.0), 0.0).rgb;
    Neighbors += textureLod(colortex9, CenterUv + vec2(0.0, Texel.y), 0.0).rgb;
    Neighbors += textureLod(colortex9, CenterUv - vec2(0.0, Texel.y), 0.0).rgb;
    return mix(Center, Center * 0.48 + Neighbors * 0.13, FilterAmount);
}

vec3 ReflectPointAcrossPlane(vec3 Point, vec3 PlanePoint, vec3 PlaneNormal) {
    float SignedDistance = dot(Point - PlanePoint, PlaneNormal);
    return Point - PlaneNormal * (2.0 * SignedDistance);
}

vec3 ReflectWorldPointAcrossPlane(vec3 WorldPos, WaterPlaneData Plane) {
    return ReflectPointAcrossPlane(WorldPos, Plane.PointWorld, Plane.NormalWorld);
}

float IntersectRayPlane(vec3 RayOrigin, vec3 RayDir, vec3 PlanePoint, vec3 PlaneNormal) {
    float Denom = dot(RayDir, PlaneNormal);
    if (abs(Denom) < 0.0001) {
        return -1.0;
    }

    return dot(PlanePoint - RayOrigin, PlaneNormal) / Denom;
}

WaterPlaneData BuildWaterPlaneData(vec3 WorldPos, vec3 WorldNormal, float Roughness) {
    WaterPlaneData Plane;
    Plane.PointWorld = vec3(WorldPos.x, floor((WorldPos.y + cameraPosition.y) * 16.0 + 0.5) / 16.0 - cameraPosition.y, WorldPos.z);
    Plane.NormalWorld = normalize(WorldNormal);
    Plane.LevelHeight = Plane.PointWorld.y;
    Plane.MirroredCameraWorld = ReflectPointAcrossPlane(vec3(0.0), Plane.PointWorld, Plane.NormalWorld);

    float PlanarNormal = smoothstep(0.90, 0.98, abs(Plane.NormalWorld.y));
    float PlanarRoughness = 1.0 - smoothstep(0.08, 0.22, Roughness);
    Plane.PlanarWeight = PlanarNormal * PlanarRoughness;
    return Plane;
}

PlanarIntersectionData BuildPlanarIntersectionData(WaterPlaneData Plane, vec3 WorldPos, vec3 ReflectDirWorld) {
    PlanarIntersectionData Intersection;
    vec3 PlaneSamplePoint = vec3(WorldPos.x, Plane.LevelHeight, WorldPos.z);
    vec3 MirroredViewRay = normalize(PlaneSamplePoint - Plane.MirroredCameraWorld);
    float HitDistance = IntersectRayPlane(Plane.MirroredCameraWorld, MirroredViewRay, Plane.PointWorld, Plane.NormalWorld);

    Intersection.SurfacePointWorld =
        (HitDistance > 0.0) ? Plane.MirroredCameraWorld + MirroredViewRay * HitDistance : PlaneSamplePoint;
    Intersection.ReflectedDirWorld = normalize(mix(MirroredViewRay, ReflectDirWorld, 0.65));
    Intersection.IncidentAlignment = clamp(abs(dot(MirroredViewRay, Plane.NormalWorld)), 0.0, 1.0);
    return Intersection;
}

PlanarProjectionData BuildPlanarProjectionData(WaterPlaneData Plane, PlanarIntersectionData Intersection, float Roughness) {
    PlanarProjectionData Projection;
    vec3 FlattenedDirection = Intersection.ReflectedDirWorld -
                              Plane.NormalWorld * dot(Intersection.ReflectedDirWorld, Plane.NormalWorld);
    float FlattenedLengthSq = dot(FlattenedDirection, FlattenedDirection);
    vec3 TravelAxisWorld = (FlattenedLengthSq > 0.0001)
                               ? normalize(FlattenedDirection)
                               : GetPlanarFallbackAxis(Plane.NormalWorld);

    Projection.OriginWorld = Intersection.SurfacePointWorld + Plane.NormalWorld * 0.02;
    Projection.DirectionWorld = Intersection.ReflectedDirWorld;
    Projection.LateralAxisWorld = normalize(cross(Plane.NormalWorld, TravelAxisWorld));
    Projection.LateralSpread = mix(0.05, 0.28, Roughness) *
                               mix(0.55, 1.0, 1.0 - Intersection.IncidentAlignment);
    Projection.TravelStart = mix(2.0, 4.5, Plane.PlanarWeight);
    Projection.TravelEnd = mix(56.0, 170.0, Plane.PlanarWeight) *
                           mix(0.80, 1.12, Intersection.IncidentAlignment) *
                           mix(1.0, 0.78, Roughness);
    return Projection;
}

PlanarSamplingConfig BuildPlanarSamplingConfig(WaterPlaneData Plane, PlanarIntersectionData Intersection) {
    PlanarSamplingConfig Sampling;
    Sampling.StepCount = 14;
    Sampling.DistanceFadeMin = mix(42.0, 70.0, Intersection.IncidentAlignment);
    Sampling.DistanceFadeMax = mix(150.0, 230.0, Plane.PlanarWeight);
    return Sampling;
}

PlanarSolveResult SolvePlanarReflection(WaterPlaneData Plane, vec3 WorldPos, vec3 ReflectDirWorld, float Roughness) {
    PlanarSolveResult Result;
    Result.Plane = Plane;
    Result.Intersection = BuildPlanarIntersectionData(Result.Plane, WorldPos, ReflectDirWorld);
    Result.Projection = BuildPlanarProjectionData(Result.Plane, Result.Intersection, Roughness);
    Result.Sampling = BuildPlanarSamplingConfig(Result.Plane, Result.Intersection);
    return Result;
}

PlanarReflectionCandidate CreatePlanarReflectionCandidate(vec2 Uv, float Quality, float EdgeConfidence) {
    PlanarReflectionCandidate Candidate;
    Candidate.Uv = Uv;
    Candidate.Quality = Quality;
    Candidate.EdgeConfidence = EdgeConfidence;
    return Candidate;
}

PlanarReprojectedSample CreateInvalidPlanarReprojectedSample(vec2 Uv) {
    PlanarReprojectedSample Sample;
    Sample.MirroredCandidateWorldPos = vec3(0.0);
    Sample.SceneWorldPos = vec3(0.0);
    Sample.SceneNormalWorld = vec3(0.0, 1.0, 0.0);
    Sample.Uv = Uv;
    Sample.DepthError = 999999.0;
    Sample.ReprojectionError = 999999.0;
    Sample.RayAlignment = 0.0;
    Sample.NormalAlignment = 0.0;
    Sample.AbovePlaneMask = 0.0;
    Sample.EdgeConfidence = 0.0;
    Sample.Valid = false;
    return Sample;
}

PlanarReprojectedSample BuildPlanarReprojectedSample(WaterPlaneData Plane, PlanarIntersectionData Intersection, vec3 CandidateWorldPos) {
    PlanarReprojectedSample Sample;
    vec3 CandidateViewPos = WorldToViewPos(CandidateWorldPos, gbufferModelView);
    vec2 Uv;
    vec2 UnjitteredUv;
    vec4 Opaque;
    if (!ProjectAndSampleOpaque(CandidateViewPos, Uv, Opaque, UnjitteredUv)) {
        return CreateInvalidPlanarReprojectedSample(Uv);
    }

    float EdgeConfidence = ReflectionEdgeConfidence(UnjitteredUv);
    if (EdgeConfidence <= 0.0) return CreateInvalidPlanarReprojectedSample(Uv);

    float SceneDepth = Opaque.b;
    if (SceneDepth >= 0.999999) {
        return CreateInvalidPlanarReprojectedSample(Uv);
    }

    vec3 SceneViewPos = ReconstructOpaqueViewPos(Uv, Opaque);
    float DepthError = abs(GetPlanarViewSpaceDepth(CandidateViewPos) - GetPlanarViewSpaceDepth(SceneViewPos));
    // At these limits the original masks are exactly zero. Reject before
    // world transforms, normal decoding, alignment work and HDR color reads.
    if (DepthError >= 9.5) return CreateInvalidPlanarReprojectedSample(Uv);
    vec3 SceneWorldPos = ViewToWorldPos(SceneViewPos, gbufferModelViewInverse);
    float ReprojectionError = length(SceneWorldPos - CandidateWorldPos);
    if (ReprojectionError >= 13.0) return CreateInvalidPlanarReprojectedSample(Uv);
    vec3 ReflectedOffset = SceneWorldPos - Intersection.SurfacePointWorld;
    vec3 ReflectedSampleDir = ReflectedOffset / max(length(ReflectedOffset), 0.0001);

    float SceneHeightAbovePlane = dot(SceneWorldPos - Plane.PointWorld, Plane.NormalWorld);
    float RayAlignment = clamp(dot(ReflectedSampleDir, Intersection.ReflectedDirWorld), 0.0, 1.0);
    if (SceneHeightAbovePlane <= -0.2 || RayAlignment <= 0.62) return CreateInvalidPlanarReprojectedSample(Uv);
    vec3 SceneNormalWorld = ViewToWorldNormal(NormalDecode(Opaque.rg), gbufferModelViewInverse);
    Sample.MirroredCandidateWorldPos = CandidateWorldPos;
    Sample.SceneWorldPos = SceneWorldPos;
    Sample.SceneNormalWorld = SceneNormalWorld;
    Sample.Uv = Uv;
    Sample.DepthError = DepthError;
    Sample.ReprojectionError = ReprojectionError;
    Sample.RayAlignment = RayAlignment;
    Sample.NormalAlignment = clamp(dot(SceneNormalWorld, Plane.NormalWorld), 0.0, 1.0);
    Sample.AbovePlaneMask = smoothstep(-0.2, 1.2, SceneHeightAbovePlane);
    Sample.EdgeConfidence = EdgeConfidence;
    Sample.Valid = true;
    return Sample;
}

PlanarReflectionCandidate EvaluatePlanarReprojectedSample(WaterPlaneData Plane, PlanarIntersectionData Intersection, PlanarSamplingConfig Sampling, PlanarReprojectedSample Sample, float TravelDistance) {
    if (!Sample.Valid) {
        return CreatePlanarReflectionCandidate(Sample.Uv, 0.0, 0.0);
    }

    float ReprojectionMask = 1.0 - smoothstep(1.4, 13.0, Sample.ReprojectionError);
    float DepthMask = 1.0 - smoothstep(0.90, 9.5, Sample.DepthError);
    float DistanceFade = 1.0 - smoothstep(Sampling.DistanceFadeMin, Sampling.DistanceFadeMax, TravelDistance);
    float RayMask = smoothstep(0.62, 0.94, Sample.RayAlignment);
    float NormalMask = mix(1.0, smoothstep(0.08, 0.55, Sample.NormalAlignment), Plane.PlanarWeight * 0.6);
    float GrazingBoost = clamp(mix(0.75, 1.10, Intersection.IncidentAlignment), 0.0, 1.0);
    float StabilityMask = smoothstep(0.18, 0.72, ReprojectionMask * DepthMask);
    float Quality = Plane.PlanarWeight * Sample.AbovePlaneMask * StabilityMask *
                    DepthMask * DistanceFade * RayMask * NormalMask *
                    mix(0.68, 1.04, GrazingBoost);
    return CreatePlanarReflectionCandidate(Sample.Uv, clamp(Quality, 0.0, 1.0), Sample.EdgeConfidence);
}

PlanarReflectionCandidate SamplePlanarReflectionAtPosition(PlanarSolveResult SolveResult, vec3 CandidateWorldPos, float TravelDistance) {
    PlanarReprojectedSample Sample = BuildPlanarReprojectedSample(SolveResult.Plane, SolveResult.Intersection, CandidateWorldPos);
    return EvaluatePlanarReprojectedSample(SolveResult.Plane, SolveResult.Intersection, SolveResult.Sampling, Sample, TravelDistance);
}

void AccumulatePlanarReflectionCandidate(PlanarReflectionCandidate Candidate, float SideWeight, float Visibility, float Reflectivity, inout vec3 AccumulatedColor, inout float AccumulatedWeight, inout float AccumulatedConfidence) {
    float Score = Candidate.Quality * Candidate.EdgeConfidence * SideWeight;
    float SampleWeight = ReflectionCandidateWeight(Score);
    if (SampleWeight <= 0.0) return;
    float Confidence = ReflectionCandidateConfidence(Candidate.Quality, Candidate.EdgeConfidence, Visibility);
    vec3 Color = SamplePlanarReflectionColor(Candidate.Uv, Confidence * Reflectivity);
    AccumulatedColor += Color * SampleWeight;
    AccumulatedWeight += SampleWeight;
    AccumulatedConfidence += Confidence * SampleWeight;
}

ReflectionResult SamplePlanarReflectionCandidate(PlanarSolveResult SolveResult, float Visibility, float Reflectivity, vec3 FallbackColor) {
    vec3 AccumulatedColor = vec3(0.0);
    float AccumulatedWeight = 0.0;
    float AccumulatedConfidence = 0.0;

    for (int I = 0; I < SolveResult.Sampling.StepCount; I++) {
        float T = (float(I) + 0.5) / float(SolveResult.Sampling.StepCount);
        float TravelDistance = mix(SolveResult.Projection.TravelStart, SolveResult.Projection.TravelEnd, T);
        vec3 CandidateWorldPos = SolveResult.Projection.OriginWorld +
                                 SolveResult.Projection.DirectionWorld * TravelDistance;
        PlanarReflectionCandidate Candidate = SamplePlanarReflectionAtPosition(SolveResult, CandidateWorldPos, TravelDistance);
        AccumulatePlanarReflectionCandidate(Candidate, 1.0, Visibility, Reflectivity, AccumulatedColor, AccumulatedWeight, AccumulatedConfidence);

        if (I > 0 && I < SolveResult.Sampling.StepCount - 1) {
            float SideSign = (mod(float(I), 2.0) < 0.5) ? -1.0 : 1.0;
            float LateralAmount = SolveResult.Projection.LateralSpread * mix(0.22, 0.58, T);
            vec3 SideCandidateWorldPos = CandidateWorldPos +
                                         SolveResult.Projection.LateralAxisWorld * LateralAmount * SideSign;
            PlanarReflectionCandidate SideCandidate = SamplePlanarReflectionAtPosition(SolveResult, SideCandidateWorldPos, TravelDistance);
            AccumulatePlanarReflectionCandidate(SideCandidate, 0.58, Visibility, Reflectivity, AccumulatedColor, AccumulatedWeight, AccumulatedConfidence);
        }
    }

    if (AccumulatedWeight <= 0.0) return CreateReflectionResult(FallbackColor, 0.0);
    vec3 ResolvedColor = AccumulatedColor / max(AccumulatedWeight, 1e-8);
    float Confidence = ReflectionResolveConfidence(AccumulatedConfidence, AccumulatedWeight);
    return CreateReflectionResult(ResolvedColor, Confidence);
}

PlanarSolveResult SolvePlanarWaterReflection(vec3 WorldPos, vec3 WorldNormal, vec3 ReflectDirWorld, float Roughness) {
    return SolvePlanarReflection(BuildWaterPlaneData(WorldPos, WorldNormal, Roughness), WorldPos, ReflectDirWorld, Roughness);
}

#endif
