#ifndef IDA_REFLECTIONS_SCREEN_PLANAR_GLSL
#define IDA_REFLECTIONS_SCREEN_PLANAR_GLSL

#include "/lib/reflections/screen_trace.glsl"

ReflectionResult ResolveScreenPlanarReflection(vec3 WorldPos, vec3 WorldNormal, vec3 ReflectDir, float Roughness, float Visibility, float Reflectivity, vec3 FallbackColor) {
    // Kept as the material entry point; this now traces the actual reflected
    // ray, without a snapped water plane or averaging unrelated candidates.
    float Weight = (1.0 - smoothstep(0.25, 0.55, Roughness)) * clamp(Visibility, 0.0, 1.0);
    if (Weight <= 0.0 || Reflectivity <= 0.0) return CreateReflectionResult(FallbackColor, 0.0);
    vec3 SurfaceView = WorldToViewPos(WorldPos, gbufferModelView);
    vec3 NormalView = normalize(mat3(gbufferModelView) * WorldNormal);
    if (dot(NormalView, -SurfaceView) < 0.0) NormalView = -NormalView;
    ReflectionResult Result = TraceScreenReflection(SurfaceView, NormalView, normalize(ReflectDir), min(far, 128.0), SSR_TRACE_STEPS, FallbackColor);
    // Visibility can never amplify away the validated footprint/screen fade.
    Result.Confidence *= Weight;
    return Result;
}

#endif
