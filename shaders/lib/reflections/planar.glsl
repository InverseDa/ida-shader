#ifndef IDA_REFLECTIONS_PLANAR_GLSL
#define IDA_REFLECTIONS_PLANAR_GLSL

#include "/lib/common/packing.glsl"
#include "/lib/common/space.glsl"

struct WaterPlaneData {
    vec3 pointWorld;
    vec3 normalWorld;
    vec3 mirroredCameraWorld;
    float levelHeight;
    float planarWeight;
};

struct PlanarIntersectionData {
    vec3 surfacePointWorld;
    vec3 reflectedDirWorld;
    float incidentAlignment;
};

struct PlanarProjectionData {
    vec3 originWorld;
    vec3 directionWorld;
    vec3 lateralAxisWorld;
    float lateralSpread;
    float travelStart;
    float travelEnd;
};

struct PlanarSamplingConfig {
    int stepCount;
    float edgeFadeWeight;
    float distanceFadeMin;
    float distanceFadeMax;
};

struct PlanarSolveResult {
    WaterPlaneData plane;
    PlanarIntersectionData intersection;
    PlanarProjectionData projection;
    PlanarSamplingConfig sampling;
};

struct PlanarReflectionCandidate {
    vec3 color;
    float mask;
    vec2 uv;
};

struct PlanarReprojectedSample {
    vec3 mirroredCandidateWorldPos;
    vec3 sceneWorldPos;
    vec3 sceneNormalWorld;
    vec2 uv;
    float depthError;
    float reprojectionError;
    float rayAlignment;
    float normalAlignment;
    float abovePlaneMask;
    bool valid;
};

float getPlanarViewSpaceDepth(vec3 viewPos) {
    return -viewPos.z;
}

vec3 getPlanarFallbackAxis(vec3 normalWorld) {
    vec3 fallbackAxis = cross(normalWorld, vec3(0.0, 0.0, 1.0));
    if (dot(fallbackAxis, fallbackAxis) < 0.0001) {
        fallbackAxis = cross(normalWorld, vec3(1.0, 0.0, 0.0));
    }
    return normalize(fallbackAxis);
}

vec3 samplePlanarReflectionColor(vec2 uv) {
    vec2 texel = vec2(1.0 / viewWidth, 1.0 / viewHeight);
    vec3 color = texture2D(colortex9, uv).rgb * 0.48;
    color += texture2D(colortex9, uv + vec2(texel.x, 0.0)).rgb * 0.13;
    color += texture2D(colortex9, uv - vec2(texel.x, 0.0)).rgb * 0.13;
    color += texture2D(colortex9, uv + vec2(0.0, texel.y)).rgb * 0.13;
    color += texture2D(colortex9, uv - vec2(0.0, texel.y)).rgb * 0.13;
    return color;
}

vec3 reflectPointAcrossPlane(vec3 point, vec3 planePoint, vec3 planeNormal) {
    float signedDistance = dot(point - planePoint, planeNormal);
    return point - planeNormal * (2.0 * signedDistance);
}

vec3 reflectWorldPointAcrossPlane(vec3 worldPos, WaterPlaneData plane) {
    return reflectPointAcrossPlane(worldPos, plane.pointWorld, plane.normalWorld);
}

float intersectRayPlane(vec3 rayOrigin, vec3 rayDir, vec3 planePoint, vec3 planeNormal) {
    float denom = dot(rayDir, planeNormal);
    if (abs(denom) < 0.0001) {
        return -1.0;
    }

    return dot(planePoint - rayOrigin, planeNormal) / denom;
}

WaterPlaneData buildWaterPlaneData(vec3 worldPos, vec3 worldNormal, float roughness) {
    WaterPlaneData plane;
    plane.pointWorld = vec3(worldPos.x, floor((worldPos.y + cameraPosition.y) * 16.0 + 0.5) / 16.0 - cameraPosition.y, worldPos.z);
    plane.normalWorld = normalize(worldNormal);
    plane.levelHeight = plane.pointWorld.y;
    plane.mirroredCameraWorld = reflectPointAcrossPlane(vec3(0.0), plane.pointWorld, plane.normalWorld);

    float planarNormal = smoothstep(0.90, 0.98, abs(plane.normalWorld.y));
    float planarRoughness = 1.0 - smoothstep(0.08, 0.22, roughness);
    plane.planarWeight = planarNormal * planarRoughness;
    return plane;
}

PlanarIntersectionData buildPlanarIntersectionData(
    WaterPlaneData plane,
    vec3 worldPos,
    vec3 reflectDirWorld
) {
    PlanarIntersectionData intersection;
    vec3 planeSamplePoint = vec3(worldPos.x, plane.levelHeight, worldPos.z);
    vec3 mirroredViewRay = normalize(planeSamplePoint - plane.mirroredCameraWorld);
    float hitDistance = intersectRayPlane(
        plane.mirroredCameraWorld,
        mirroredViewRay,
        plane.pointWorld,
        plane.normalWorld
    );

    intersection.surfacePointWorld =
        (hitDistance > 0.0) ? plane.mirroredCameraWorld + mirroredViewRay * hitDistance : planeSamplePoint;
    intersection.reflectedDirWorld = normalize(mix(mirroredViewRay, reflectDirWorld, 0.65));
    intersection.incidentAlignment = clamp(abs(dot(mirroredViewRay, plane.normalWorld)), 0.0, 1.0);
    return intersection;
}

PlanarProjectionData buildPlanarProjectionData(
    WaterPlaneData plane,
    PlanarIntersectionData intersection,
    float roughness
) {
    PlanarProjectionData projection;
    vec3 flattenedDirection = intersection.reflectedDirWorld -
                             plane.normalWorld * dot(intersection.reflectedDirWorld, plane.normalWorld);
    float flattenedLengthSq = dot(flattenedDirection, flattenedDirection);
    vec3 travelAxisWorld = (flattenedLengthSq > 0.0001)
        ? normalize(flattenedDirection)
        : getPlanarFallbackAxis(plane.normalWorld);

    projection.originWorld = intersection.surfacePointWorld + plane.normalWorld * 0.02;
    projection.directionWorld = intersection.reflectedDirWorld;
    projection.lateralAxisWorld = normalize(cross(plane.normalWorld, travelAxisWorld));
    projection.lateralSpread = mix(0.05, 0.28, roughness) *
                               mix(0.55, 1.0, 1.0 - intersection.incidentAlignment);
    projection.travelStart = mix(2.0, 4.5, plane.planarWeight);
    projection.travelEnd = mix(56.0, 170.0, plane.planarWeight) *
                           mix(0.80, 1.12, intersection.incidentAlignment) *
                           mix(1.0, 0.78, roughness);
    return projection;
}

PlanarSamplingConfig buildPlanarSamplingConfig(WaterPlaneData plane, PlanarIntersectionData intersection) {
    PlanarSamplingConfig sampling;
    sampling.stepCount = 14;
    sampling.edgeFadeWeight = mix(0.92, 1.22, plane.planarWeight);
    sampling.distanceFadeMin = mix(42.0, 70.0, intersection.incidentAlignment);
    sampling.distanceFadeMax = mix(150.0, 230.0, plane.planarWeight);
    return sampling;
}

PlanarSolveResult solvePlanarReflection(
    WaterPlaneData plane,
    vec3 worldPos,
    vec3 reflectDirWorld,
    float roughness
) {
    PlanarSolveResult result;
    result.plane = plane;
    result.intersection = buildPlanarIntersectionData(result.plane, worldPos, reflectDirWorld);
    result.projection = buildPlanarProjectionData(result.plane, result.intersection, roughness);
    result.sampling = buildPlanarSamplingConfig(result.plane, result.intersection);
    return result;
}

PlanarReflectionCandidate createPlanarReflectionCandidate(vec3 color, float mask, vec2 uv) {
    PlanarReflectionCandidate candidate;
    candidate.color = color;
    candidate.mask = mask;
    candidate.uv = uv;
    return candidate;
}

PlanarReprojectedSample createInvalidPlanarReprojectedSample(vec2 uv) {
    PlanarReprojectedSample sample;
    sample.mirroredCandidateWorldPos = vec3(0.0);
    sample.sceneWorldPos = vec3(0.0);
    sample.sceneNormalWorld = vec3(0.0, 1.0, 0.0);
    sample.uv = uv;
    sample.depthError = 999999.0;
    sample.reprojectionError = 999999.0;
    sample.rayAlignment = 0.0;
    sample.normalAlignment = 0.0;
    sample.abovePlaneMask = 0.0;
    sample.valid = false;
    return sample;
}

PlanarReprojectedSample buildPlanarReprojectedSample(
    WaterPlaneData plane,
    PlanarIntersectionData intersection,
    vec3 candidateWorldPos
) {
    PlanarReprojectedSample sample;
    vec3 candidateViewPos = worldToViewPos(candidateWorldPos, gbufferModelView);
    vec2 uv;
    vec4 opaque;
    if (!projectAndSampleOpaque(candidateViewPos, uv, opaque)) {
        return createInvalidPlanarReprojectedSample(uv);
    }

    float sceneDepth = opaque.b;
    if (sceneDepth >= 0.999999) {
        return createInvalidPlanarReprojectedSample(uv);
    }

    vec3 sceneViewPos = reconstructOpaqueViewPos(uv, opaque);
    float depthError = abs(getPlanarViewSpaceDepth(candidateViewPos) - getPlanarViewSpaceDepth(sceneViewPos));
    // At these limits the original masks are exactly zero. Reject before
    // world transforms, normal decoding, alignment work and HDR color reads.
    if (depthError >= 9.5) return createInvalidPlanarReprojectedSample(uv);
    vec3 sceneWorldPos = viewToWorldPos(sceneViewPos, gbufferModelViewInverse);
    float reprojectionError = length(sceneWorldPos - candidateWorldPos);
    if (reprojectionError >= 13.0) return createInvalidPlanarReprojectedSample(uv);
    vec3 reflectedOffset = sceneWorldPos - intersection.surfacePointWorld;
    vec3 reflectedSampleDir = reflectedOffset / max(length(reflectedOffset), 0.0001);

    float sceneHeightAbovePlane = dot(sceneWorldPos - plane.pointWorld, plane.normalWorld);
    float rayAlignment = clamp(dot(reflectedSampleDir, intersection.reflectedDirWorld), 0.0, 1.0);
    if (sceneHeightAbovePlane <= -0.2 || rayAlignment <= 0.62) return createInvalidPlanarReprojectedSample(uv);
    vec3 sceneNormalWorld = viewToWorldNormal(normalDecode(opaque.rg), gbufferModelViewInverse);
    sample.mirroredCandidateWorldPos = candidateWorldPos;
    sample.sceneWorldPos = sceneWorldPos;
    sample.sceneNormalWorld = sceneNormalWorld;
    sample.uv = uv;
    sample.depthError = depthError;
    sample.reprojectionError = reprojectionError;
    sample.rayAlignment = rayAlignment;
    sample.normalAlignment = clamp(dot(sceneNormalWorld, plane.normalWorld), 0.0, 1.0);
    sample.abovePlaneMask = smoothstep(-0.2, 1.2, sceneHeightAbovePlane);
    sample.valid = true;
    return sample;
}

PlanarReflectionCandidate evaluatePlanarReprojectedSample(
    WaterPlaneData plane,
    PlanarIntersectionData intersection,
    PlanarSamplingConfig sampling,
    PlanarReprojectedSample sample,
    float travelDistance,
    vec3 fallbackColor
) {
    if (!sample.valid) {
        return createPlanarReflectionCandidate(fallbackColor, 0.0, sample.uv);
    }

    float reprojectionMask = 1.0 - smoothstep(1.4, 13.0, sample.reprojectionError);
    float depthMask = 1.0 - smoothstep(0.90, 9.5, sample.depthError);
    float distanceFade = 1.0 - smoothstep(sampling.distanceFadeMin, sampling.distanceFadeMax, travelDistance);
    float edgeFade = getScreenEdgeFade(sample.uv) * sampling.edgeFadeWeight;
    float rayMask = smoothstep(0.62, 0.94, sample.rayAlignment);
    float normalMask = mix(1.0, smoothstep(0.08, 0.55, sample.normalAlignment), plane.planarWeight * 0.6);
    float grazingBoost = clamp(mix(0.75, 1.10, intersection.incidentAlignment), 0.0, 1.0);
    float stabilityMask = smoothstep(0.18, 0.72, reprojectionMask * depthMask);
    float mask = plane.planarWeight * sample.abovePlaneMask * stabilityMask *
                 depthMask * distanceFade * edgeFade * rayMask * normalMask *
                 mix(0.68, 1.04, grazingBoost);
    // Only read color after the final score (including the side weight) passes.
    if (mask <= 0.0001) return createPlanarReflectionCandidate(fallbackColor, 0.0, sample.uv);
    return createPlanarReflectionCandidate(fallbackColor, mask, sample.uv);
}

float scorePlanarReflectionCandidate(
    PlanarReflectionCandidate candidate,
    PlanarSamplingConfig sampling
) {
    float edgeFade = getScreenEdgeFade(candidate.uv) * sampling.edgeFadeWeight;
    return candidate.mask * edgeFade;
}

PlanarReflectionCandidate samplePlanarReflectionAtPosition(
    PlanarSolveResult solveResult,
    vec3 candidateWorldPos,
    float travelDistance,
    vec3 fallbackColor
) {
    PlanarReprojectedSample sample = buildPlanarReprojectedSample(
        solveResult.plane,
        solveResult.intersection,
        candidateWorldPos
    );
    return evaluatePlanarReprojectedSample(
        solveResult.plane,
        solveResult.intersection,
        solveResult.sampling,
        sample,
        travelDistance,
        fallbackColor
    );
}

PlanarReflectionCandidate samplePlanarReflectionCandidate(
    PlanarSolveResult solveResult,
    vec3 fallbackColor
) {
    PlanarReflectionCandidate bestCandidate = createPlanarReflectionCandidate(fallbackColor, 0.0, vec2(0.0));
    float bestScore = 0.0;
    vec3 accumulatedColor = vec3(0.0);
    float accumulatedWeight = 0.0;
    float accumulatedMask = 0.0;

    for (int i = 0; i < solveResult.sampling.stepCount; i++) {
        float t = (float(i) + 0.5) / float(solveResult.sampling.stepCount);
        float travelDistance = mix(solveResult.projection.travelStart, solveResult.projection.travelEnd, t);
        vec3 candidateWorldPos = solveResult.projection.originWorld +
                                 solveResult.projection.directionWorld * travelDistance;
        PlanarReflectionCandidate candidate = samplePlanarReflectionAtPosition(
            solveResult,
            candidateWorldPos,
            travelDistance,
            fallbackColor
        );
        float score = scorePlanarReflectionCandidate(candidate, solveResult.sampling);
        if (score > 0.0001) {
            candidate.color = samplePlanarReflectionColor(candidate.uv);
            float sampleWeight = score * score;
            accumulatedColor += candidate.color * sampleWeight;
            accumulatedWeight += sampleWeight;
            accumulatedMask += candidate.mask * sampleWeight;
        }
        if (score > bestScore) {
            bestCandidate = candidate;
            bestScore = score;
        }

        if (i > 0 && i < solveResult.sampling.stepCount - 1) {
            float sideSign = (mod(float(i), 2.0) < 0.5) ? -1.0 : 1.0;
            float lateralAmount = solveResult.projection.lateralSpread * mix(0.22, 0.58, t);
            vec3 sideCandidateWorldPos = candidateWorldPos +
                                         solveResult.projection.lateralAxisWorld * lateralAmount * sideSign;
            PlanarReflectionCandidate sideCandidate = samplePlanarReflectionAtPosition(
                solveResult,
                sideCandidateWorldPos,
                travelDistance,
                fallbackColor
            );
            float sideScore = scorePlanarReflectionCandidate(sideCandidate, solveResult.sampling) * 0.58;
            if (sideScore > 0.0001) {
                sideCandidate.color = samplePlanarReflectionColor(sideCandidate.uv);
                float sideWeight = sideScore * sideScore;
                accumulatedColor += sideCandidate.color * sideWeight;
                accumulatedWeight += sideWeight;
                accumulatedMask += sideCandidate.mask * sideWeight;
            }
            if (sideScore > bestScore) {
                bestCandidate = sideCandidate;
                bestScore = sideScore;
            }
        }
    }

    if (accumulatedWeight > 0.0001) {
        vec3 resolvedColor = accumulatedColor / accumulatedWeight;
        float resolvedMask = clamp(accumulatedMask / accumulatedWeight, 0.0, 1.0);

        return createPlanarReflectionCandidate(resolvedColor, resolvedMask, bestCandidate.uv);
    }

    // A very small nonzero best score can still reach this fallback. Preserve
    // its original color even when it was too small for weighted accumulation.
    if (bestScore > 0.0 && bestScore <= 0.0001) {
        bestCandidate.color = samplePlanarReflectionColor(bestCandidate.uv);
    }
    return bestCandidate;
}

PlanarSolveResult solvePlanarWaterReflection(
    vec3 worldPos,
    vec3 worldNormal,
    vec3 reflectDirWorld,
    float roughness
) {
    return solvePlanarReflection(buildWaterPlaneData(worldPos, worldNormal, roughness),
                                worldPos, reflectDirWorld, roughness);
}

#endif
