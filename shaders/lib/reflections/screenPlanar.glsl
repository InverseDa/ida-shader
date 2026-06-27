#ifndef IDA_REFLECTIONS_SCREEN_PLANAR_GLSL
#define IDA_REFLECTIONS_SCREEN_PLANAR_GLSL

#include "/lib/reflections/planar.glsl"

struct ReflectionResult {
    vec3 color;
    float mask;
    float planarWeight;
    float confidence;
};

ReflectionResult createReflectionResult(
    vec3 color,
    float mask,
    float planarWeight,
    float confidence
) {
    ReflectionResult result;
    result.color = color;
    result.mask = mask;
    result.planarWeight = planarWeight;
    result.confidence = confidence;
    return result;
}

ReflectionResult tracePlanarReflection(
    vec3 worldPos,
    vec3 worldNormal,
    vec3 reflectDir,
    float roughness,
    vec3 fallbackColor
) {
    vec3 reflectDirWorld = viewToWorldNormal(normalize(reflectDir), gbufferModelViewInverse);
    PlanarSolveResult planarSolve = solvePlanarReflection(
        worldPos,
        worldNormal,
        reflectDirWorld,
        roughness
    );
    PlanarReflectionCandidate candidate = samplePlanarReflectionCandidate(
        planarSolve,
        fallbackColor
    );

    return createReflectionResult(
        candidate.color,
        candidate.mask,
        planarSolve.plane.planarWeight,
        candidate.mask
    );
}

ReflectionResult resolveScreenPlanarReflection(
    vec3 worldPos,
    vec3 worldNormal,
    vec3 reflectDir,
    float roughness,
    float planarVisibility,
    vec3 fallbackColor
) {
    ReflectionResult planarResult = tracePlanarReflection(
        worldPos,
        worldNormal,
        normalize(reflectDir),
        roughness,
        fallbackColor
    );

    planarResult.mask *= planarVisibility;
    planarResult.confidence *= planarVisibility;
    float planarConfidence = planarResult.mask * mix(0.82, 1.18, planarResult.planarWeight);

    if (planarConfidence > 0.0) {
        return createReflectionResult(
            planarResult.color,
            planarResult.mask,
            planarResult.planarWeight,
            planarConfidence
        );
    }

    return createReflectionResult(
        planarResult.color,
        planarResult.mask,
        planarResult.planarWeight,
        planarResult.confidence
    );
}

#endif
