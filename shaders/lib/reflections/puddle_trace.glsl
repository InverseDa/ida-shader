#ifndef IDA_PUDDLE_TRACE_GLSL
#define IDA_PUDDLE_TRACE_GLSL
#include "/lib/reflections/screen_trace.glsl"

ReflectionResult TracePuddleReflection(vec3 SurfaceView, vec3 NormalView, vec3 Direction, vec3 Sky) {
    return TraceScreenReflection(SurfaceView, NormalView, normalize(Direction), 48.0, 24, Sky);
}
#endif
