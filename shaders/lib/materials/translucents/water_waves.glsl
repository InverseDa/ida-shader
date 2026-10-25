#ifndef IDA_WATER_WAVES_GLSL
#define IDA_WATER_WAVES_GLSL
#include "/lib/materials/translucents/water_noise.glsl"
struct WaterWaves {
    float Height;
    vec2 Slope;
    vec2 BroadSlope;
    float Variance;
};
float WaterWaveVisibility(float CyclesPerPixel) {
    return 1.0-smoothstep(0.125,0.5,CyclesPerPixel);
}
vec3 WaterNoiseBand(vec2 P, mat2 Basis, vec2 Drift, vec3 Warp, float Time) {
    vec2 Bend=vec2(0.38,-0.27);
    vec3 N=WaterNoiseGradient(Basis*P+Drift*Time+Bend*Warp.x);
    // Chain rule includes the moving domain warp. Smoothly compress troughs
    // and sharpen crests without a repeating handful of sine directions.
    vec2 Gradient=transpose(Basis)*N.yz+Warp.yz*dot(N.yz,Bend);
    return vec3(N.x+0.30*(N.x*N.x-0.333333),Gradient*(1.0+0.60*N.x));
}
void AddWaterNoiseBand(vec2 P, vec2 Dpdx, vec2 Dpdy, mat2 Basis, vec2 Drift,
                       vec3 Warp, float Amplitude, inout vec3 Sum, inout float Variance) {
    float Frequency=max(length(Basis*Dpdx),length(Basis*Dpdy));
    Frequency+=0.47*max(abs(dot(Warp.yz,Dpdx)),abs(dot(Warp.yz,Dpdy)));
    float Visibility=WaterWaveVisibility(Frequency);
    float Energy=Amplitude*Amplitude*dot(Basis[0],Basis[0])*2.0;
    Variance+=Energy*(1.0-Visibility*Visibility);
    Variance+=Energy*0.15*pow(min(Frequency*6.2831853,1.0),2.0);
    if (Visibility>0.0) Sum+=WaterNoiseBand(P,Basis,Drift,Warp,frameTimeCounter)*(Amplitude*Visibility);
}
WaterWaves SampleWaterWaves(vec3 RelativeWorld, vec2 Dpdx, vec2 Dpdy) {
    vec2 P=(RelativeWorld+cameraPosition).xz;
    vec3 Warp=SampleWaterSwell(P);
    float BroadVisibility=WaterWaveVisibility(max(length(Dpdx),length(Dpdy))*0.085);
    vec3 Sum=Warp*(0.12*BroadVisibility);
    float Variance=0.00021*(1.0-BroadVisibility*BroadVisibility);
    AddWaterNoiseBand(P,Dpdx,Dpdy,mat2(0.217,0.124,-0.124,0.217),vec2(-0.105,0.041),Warp,0.09,Sum,Variance);
    vec2 Broad=Sum.yz;
    AddWaterNoiseBand(P,Dpdx,Dpdy,mat2(0.48,-0.47,0.47,0.48),vec2(0.079,0.145),Warp,0.032,Sum,Variance);
    // Medium detail enters reflection rays; fine ripples affect highlights and
    // refraction only, avoiding noisy high-frequency SSR queries.
    Broad=mix(Broad,Sum.yz,0.45);
    AddWaterNoiseBand(P,Dpdx,Dpdy,mat2(-0.77,1.51,-1.51,-0.77),vec2(-0.24,-0.18),Warp,0.009,Sum,Variance);
    return WaterWaves(Sum.x*WATER_WAVE_STRENGTH,Sum.yz*WATER_WAVE_STRENGTH,
                      Broad*WATER_WAVE_STRENGTH,min(Variance,0.09)*SPECULAR_AA*WATER_WAVE_STRENGTH*WATER_WAVE_STRENGTH);
}
vec3 WaterWaveNormal(vec3 BaseNormal, vec2 Slope, float Strength) {
    vec3 WaveNormal=normalize(vec3(-Slope.x,1.0,-Slope.y));
    return normalize(mix(BaseNormal,WaveNormal,Strength));
}
#endif
