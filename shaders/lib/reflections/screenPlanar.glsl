#ifndef IDA_REFLECTIONS_SCREEN_PLANAR_GLSL
#define IDA_REFLECTIONS_SCREEN_PLANAR_GLSL

#include "/lib/reflections/water_trace.glsl"
#include "/lib/reflections/voxel.glsl"

ReflectionResult ResolveScreenPlanarReflection(vec3 WorldPos, vec3 WorldNormal, vec3 ReflectDir, float Roughness, float Visibility, float Reflectivity, vec3 FallbackColor, bool IsWater) {
    // Water has an independent hierarchical source/trace. Other materials
    // retain the generic geometry tracer and their existing appearance.
    float Weight = (1.0 - smoothstep(0.25, 0.55, Roughness)) * clamp(Visibility, 0.0, 1.0);
    if (Weight <= 0.0 || Reflectivity <= 0.0) return CreateReflectionResult(FallbackColor, 0.0);
    vec3 SurfaceView = WorldToViewPos(WorldPos, gbufferModelView);
    vec3 NormalView = normalize(mat3(gbufferModelView) * WorldNormal);
    if (dot(NormalView, -SurfaceView) < 0.0) NormalView = -NormalView;
    ReflectionResult Result;
    if(IsWater && WorldNormal.y>0.9)
        Result=TraceWaterReflection(SurfaceView,NormalView,normalize(ReflectDir),min(far,128.0),SSR_TRACE_STEPS,FallbackColor);
    else if(IsWater)
        // Side faces/steep waves also exclude voxel completion. Material
        // identity, rather than a roughness/normal guess, selects this policy.
        Result=TraceScreenReflection(SurfaceView,NormalView,normalize(ReflectDir),min(far,128.0),SSR_TRACE_STEPS,FallbackColor);
    else
        Result=TraceHybridReflection(SurfaceView,NormalView,normalize(ReflectDir),min(far,128.0),SSR_TRACE_STEPS,FallbackColor);
    // Visibility can never amplify away the validated footprint/screen fade.
    Result.Confidence *= Weight;
    return Result;
}

#endif
