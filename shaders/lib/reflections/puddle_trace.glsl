#ifndef IDA_PUDDLE_TRACE_GLSL
#define IDA_PUDDLE_TRACE_GLSL

// ---- Puddle Trace ----

#include "/lib/reflections/voxel.glsl"

ReflectionResult TracePuddleReflection(vec3 SurfaceView, vec3 NormalView, vec3 Direction, vec3 Sky)
{
    return TraceHybridReflection(SurfaceView, NormalView, normalize(Direction), 48.0, 24, Sky);
}
#endif
