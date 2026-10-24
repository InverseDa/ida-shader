#ifndef IDA_REFLECTIONS_SCREEN_PLANAR_GLSL
#define IDA_REFLECTIONS_SCREEN_PLANAR_GLSL

#include "/lib/reflections/planar.glsl"

ReflectionResult ResolveScreenPlanarReflection(vec3 WorldPos, vec3 WorldNormal, vec3 ReflectDir, float Roughness, float Visibility, float Reflectivity, vec3 FallbackColor) {
    WaterPlaneData Plane = BuildWaterPlaneData(WorldPos, WorldNormal, Roughness);
    // Vertical/rough surfaces have an exactly zero planar mask. Their sky
    // fallback remains unchanged, without a 26-candidate screen search.
    if (Plane.PlanarWeight <= 0.0) {
        return CreateReflectionResult(FallbackColor, 0.0);
    }
    vec3 ReflectDirWorld = ViewToWorldNormal(normalize(ReflectDir), gbufferModelViewInverse);
    PlanarSolveResult PlanarSolve = SolvePlanarReflection(Plane, WorldPos, ReflectDirWorld, Roughness);
    return SamplePlanarReflectionCandidate(PlanarSolve, Visibility, Reflectivity, FallbackColor);
}

#endif
