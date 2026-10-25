#ifndef IDA_WATER_LIGHTING_GLSL
#define IDA_WATER_LIGHTING_GLSL
#include "/lib/misc/water_surface_cache.glsl"

float WaterDirectionalVisibility(vec3 RelativeWorld) {
#if SHADOW_CSM == 1
    return SunShaftCascadeVisibility(RelativeWorld);
#else
    vec4 Clip = shadowProjection * (shadowModelView * vec4(RelativeWorld,1.0));
    return SunShaftGeometryVisibility(Clip,length(RelativeWorld));
#endif
}
void AddCausticCurvature(vec2 P, vec2 Direction, float Wavelength, float Amplitude, float Speed, float Offset, inout vec3 Curvature) {
    vec2 D=normalize(Direction); float K=6.2831853/Wavelength;
    float Phase=K*dot(D,P)-sqrt(9.81*K)*Speed*frameTimeCounter+Offset;
    Curvature += vec3(D.x*D.x,D.x*D.y,D.y*D.y)*(-Amplitude*K*K*sin(Phase));
}
float WaterCausticPattern(vec2 P, float Depth) {
    // Independent thin-lens wave approximation, bounded near a focus. These
    // caustics do not trace the detailed shading normals or transport photons.
    vec3 C=vec3(0.0);
    AddCausticCurvature(P,vec2(-0.28,0.96),6.2,0.043,1.16,3.10,C);
    AddCausticCurvature(P,vec2(0.97,-0.24),3.1,0.017,1.48,4.40,C);
    AddCausticCurvature(P,vec2(-0.71,0.70),1.9,0.010,1.82,2.30,C);
    C *= min(Depth,8.0)*(1.333-1.0)*WATER_WAVE_STRENGTH;
    float Det=(1.0+C.x)*(1.0+C.z)-C.y*C.y;
    return clamp(1.0/max(abs(Det),0.32)-1.0,0.0,2.0);
}
vec3 ApplyWaterCaustics(vec3 Color, vec3 RelativeWorld, vec3 NormalWorld, float Depth, float Coverage) {
#if WATER_CAUSTICS == 1
    float Day=(1.0-NightValue)*(1.0-smoothstep(0.0,1.0,rainStrength));
    if (Day<=0.0 || Coverage<=0.0 || Depth<=0.04 || Depth>=12.0 || WATER_CAUSTICS_STRENGTH<=0.0) return Color;
    vec3 L=ViewToWorldNormal(normalize(sunPosition),gbufferModelViewInverse);
    float Elevation=smoothstep(0.04,0.20,L.y);
    float Facing=max(dot(NormalWorld,L),0.0);
    if (Elevation*Facing<=0.0) return Color;
    vec3 WaterL=-refract(-L,vec3(0,1,0),1.0/1.333);
    vec2 Surface=(RelativeWorld+cameraPosition).xz+WaterL.xz*(Depth/max(WaterL.y,0.1));
    float Pattern=WaterCausticPattern(Surface,Depth);
    if (Pattern<=0.0) return Color;
    float Visibility=WaterDirectionalVisibility(RelativeWorld+NormalWorld*0.04);
    if (Visibility<=0.0) return Color;
    Visibility*=SunShaftCloudVisibility(cameraPosition+RelativeWorld+vec3(0,Depth,0),L);
    float PixelFootprint=2.0*length(RelativeWorld)/max(abs(gbufferProjection[1][1])*viewHeight*max(abs(dot(normalize(RelativeWorld),NormalWorld)),0.1),1.0);
    float Fade=smoothstep(0.04,0.5,Depth)*(1.0-smoothstep(6.0,12.0,Depth))*(1.0-smoothstep(0.15,0.65,PixelFootprint));
    vec3 Gain=WaterTransmittance(Depth/max(WaterL.y,0.1))*
              (Pattern*Fade*Coverage*Day*Elevation*Facing*Visibility*WATER_CAUSTICS_STRENGTH*DIRECT_LIGHT_STRENGTH*1.8);
    return Color*(vec3(1.0)+Gain);
#else
    return Color;
#endif
}
vec3 RenderUnderwaterLight(vec3 RelativeEnd) {
#if UNDERWATER_LIGHT == 1
    float Day=(1.0-NightValue)*(1.0-smoothstep(0.0,1.0,rainStrength));
    if (Day<=0.0 || UNDERWATER_LIGHT_STRENGTH<=0.0) return vec3(0.0);
    float Distance=length(RelativeEnd), End=min(Distance,32.0);
    if (End<=0.01) return vec3(0.0);
    vec3 Ray=RelativeEnd/max(Distance,0.001);
    vec3 L=ViewToWorldNormal(normalize(sunPosition),gbufferModelViewInverse);
    float Elevation=smoothstep(0.04,0.20,L.y);
    if (Elevation<=0.0) return vec3(0.0);
    vec3 WaterL=-refract(-L,vec3(0,1,0),1.0/1.333);
    float Mu=max(dot(Ray,WaterL),0.0);
    float Phase=0.10+0.70*pow(Mu,6.0);
    vec3 Sum=vec3(0.0);
    // Fixed world-distance strata: terminal surfaces only truncate weights.
    // Twelve shadow comparisons, no full-resolution voxel ray search/history.
    for (int I=0; I<12; ++I) {
        float A=32.0*pow(float(I)/12.0,2.0), B=min(32.0*pow(float(I+1)/12.0,2.0),End);
        if (A>=End) break;
        vec3 P=Ray*A;
        vec2 Water=FindWaterSurface(P);
        if (Water.y<=0.0 || Water.x<0.0) continue;
        float Visibility=WaterDirectionalVisibility(P);
        vec3 Segment=WaterTransmittance(A)-WaterTransmittance(B);
        Sum+=Segment*WaterTransmittance(Water.x/max(WaterL.y,0.1))*Visibility*Water.y;
    }
    // One cloud column per ray; terrain and foliage still queried per stratum.
    float Cloud=SunShaftCloudVisibility(cameraPosition,L);
    return Sum*GetDirectionalLightRadiance(SunColor,0.0)*0.75*
           (Day*Elevation*Phase*Cloud*UNDERWATER_LIGHT_STRENGTH*DIRECT_LIGHT_STRENGTH);
#else
    return vec3(0.0);
#endif
}
#endif
