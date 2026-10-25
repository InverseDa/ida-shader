#ifndef IDA_REFLECTION_PLANE_CACHE_GLSL
#define IDA_REFLECTION_PLANE_CACHE_GLSL
// A numeric 24-bit integer stays finite and exact in RGBA32F. Keep plane
// distance in its own FP32 channel: half precision breaks distant leaf planes.
float PackReflectionPlaneNormal(vec3 N) {
    vec2 Q=floor(NormalEncode(N)*4095.0+0.5);
    return Q.x+4096.0*Q.y;
}
vec4 UnpackReflectionPlane(vec4 Data) {
    vec2 Q=vec2(mod(Data.x,4096.0),floor(Data.x/4096.0));
    return vec4(Q/4095.0,Data.y,abs(Data.z));
}
#endif
