#ifndef IDA_REFLECTIONS_SCREEN_PLANAR_GLSL
#define IDA_REFLECTIONS_SCREEN_PLANAR_GLSL

#include "/lib/reflections/planar.glsl"

ReflectionResult resolveScreenPlanarReflection(
    vec3 worldPos,
    vec3 worldNormal,
    vec3 reflectDir,
    float roughness,
    float visibility,
    float reflectivity,
    vec3 fallbackColor
) {
    WaterPlaneData plane = buildWaterPlaneData(worldPos, worldNormal, roughness);
    // Vertical/rough surfaces have an exactly zero planar mask. Their sky
    // fallback remains unchanged, without a 26-candidate screen search.
    if (plane.planarWeight <= 0.0) {
        return createReflectionResult(fallbackColor, 0.0);
    }
    vec3 reflectDirWorld = viewToWorldNormal(normalize(reflectDir), gbufferModelViewInverse);
    PlanarSolveResult planarSolve = solvePlanarReflection(
        plane,
        worldPos,
        reflectDirWorld,
        roughness
    );
    return samplePlanarReflectionCandidate(
        planarSolve,
        visibility,
        reflectivity,
        fallbackColor
    );
}

#endif
