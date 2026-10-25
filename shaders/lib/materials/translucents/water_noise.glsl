#ifndef IDA_WATER_NOISE_GLSL
#define IDA_WATER_NOISE_GLSL
#include "/lib/settings.glsl"
float WaterNoiseHash(vec2 Cell) {
    vec3 H=fract(vec3(Cell.xyx)*vec3(0.1031,0.1030,0.0973));
    H+=dot(H,H.yzx+33.33);
    return fract((H.x+H.y)*H.z);
}
// Quintic noise and analytic gradient: no tile, finite-difference fetches or
// screen derivatives. Adjacent vertices and rebased cameras agree.
vec3 WaterNoiseGradient(vec2 P) {
    vec2 I=floor(P), F=fract(P);
    vec2 U=F*F*F*(F*(F*6.0-15.0)+10.0);
    vec2 D=30.0*F*F*(F*(F-2.0)+1.0);
    float A=WaterNoiseHash(I), B=WaterNoiseHash(I+vec2(1,0));
    float C=WaterNoiseHash(I+vec2(0,1)), E=WaterNoiseHash(I+vec2(1,1));
    float Cross=A-B-C+E;
    return vec3(A+(B-A)*U.x+(C-A)*U.y+Cross*U.x*U.y,
                D*vec2(B-A+Cross*U.y,C-A+Cross*U.x))*2.0-vec3(1,0,0);
}
vec3 SampleWaterSwell(vec2 P) {
    mat2 Basis=mat2(0.82,0.57,-0.57,0.82)*0.085;
    vec3 N=WaterNoiseGradient(Basis*P+frameTimeCounter*vec2(-0.055,0.021));
    return vec3(N.x,transpose(Basis)*N.yz);
}
float WaterVertexOffset(vec2 P) {
    // Only a slow vertical swell reaches the block mesh: at most 3.5 cm at
    // default strength. Detailed crest shape lives in pixel normals.
    return SampleWaterSwell(P).x*(0.035*WATER_VERTEX_WAVES*WATER_WAVE_STRENGTH);
}
float WaterVertexWaveMask(vec3 AbsolutePosition, float SkyLight) {
    return smoothstep(0.5,0.85,fract(AbsolutePosition.y))*smoothstep(0.1,0.8,SkyLight);
}
#endif
