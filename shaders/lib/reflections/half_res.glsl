#ifndef IDA_REFLECTION_HALF_RES_GLSL
#define IDA_REFLECTION_HALF_RES_GLSL
uniform sampler2D colortex6, colortex7;
#include "/lib/reflections/confidence.glsl"
#include "/lib/common/space.glsl"
// Reconstruct the traced radiance itself. Re-intersecting every half-size hit
// with a full-size ray punches holes into solid faces and duplicates the ray
// search on high-frequency wave normals. Only the receiving water geometry is
// an upsampling boundary; reflected cutouts are deliberately area filtered.
ReflectionResult GatherWaterField(vec2 Uv,vec3 View,vec3 Fallback,out float WaterCoverage) {
    ivec2 Size=textureSize(colortex7,0);
    vec2 P=Uv*vec2(Size)-0.5,F=fract(P);
    ivec2 Base=ivec2(floor(P));
    vec3 N=normalize(mat3(gbufferModelView)*vec3(0.0,1.0,0.0)),Sum=vec3(0.0);
    float Support=0.0,Coverage=0.0;
    // Source radiance has already been filtered before traversal. A bilinear
    // reconstruction is sufficient; do not duplicate that work at 5K.
    for(int K=0;K<4;++K) {
        ivec2 Tap=clamp(Base+ivec2(K%2,K/2),ivec2(0),Size-1);
        vec2 FullSize=vec2(viewWidth,viewHeight);
        vec2 TapUv=(floor((vec2(Tap)+0.5)/vec2(Size)*FullSize)+0.5)/FullSize;
        vec4 Water=texelFetch(colortex6,Tap,0);
        Water.w=abs(Water.w);
        if(Water.w<=0.0) continue;
        TapUv+=Water.xy;
        vec2 Ndc=TapUv*2.0-1.0;
        vec3 TapView=vec3((Ndc+gbufferProjection[2].xy)/vec2(gbufferProjection[0].x,gbufferProjection[1].y)*Water.w,-Water.w);
        float PlaneError=abs(dot(TapView-View,N));
        // WPO changes height across the lookup footprint. Compare in world
        // metres; different points on this swell are not different water pools.
        float Limit=max(0.015+0.035*WATER_VERTEX_WAVES*WATER_WAVE_STRENGTH,-View.z*0.001);
        float W=(K%2==0 ? 1.0-F.x : F.x)*(K<2 ? 1.0-F.y : F.y);
        W*=1.0-smoothstep(Limit,Limit*2.0,PlaneError);
        vec4 C=texelFetch(colortex7,Tap,0);
        float A=clamp(abs(C.a),0.0,1.0);
        Support+=W;Coverage+=W*A;Sum+=C.rgb*(W*A);
    }
    WaterCoverage=clamp(Support,0.0,1.0);
    if(Coverage<=0.0001) return CreateReflectionResult(Fallback,0.0);
    ReflectionResult R=CreateReflectionResult(Sum/Coverage,clamp(Coverage/max(Support,0.001),0.0,1.0));
    return R;
}
ReflectionResult TryHalfReflection(vec2 Uv,vec3 View,vec3 NormalWorld,vec3 Fallback) {
    float Coverage;return GatherWaterField(Uv,View,Fallback,Coverage);
}
ReflectionResult ReconstructHalfReflection(vec2 Uv,vec3 View,vec3 NormalWorld,vec3 Fallback) {
    vec3 Up=normalize(mat3(gbufferModelView)*vec3(0,1,0));
    vec3 WaveN=normalize(mat3(gbufferModelView)*NormalWorld);
    float Travel=clamp(texture2D(colortex6,Uv).z,1.0,128.0);
    // Project the virtual image of the wavy ray into the planar reflection
    // field. Distortion is continuous and never changes the traversal itself.
    vec3 Ray=reflect(normalize(View),WaveN);
    // Filter hit distance as well as colour: nearest metadata changes the
    // wave offset abruptly when a half-size texel switches leaf/sky layers.
    vec3 Virtual=View+reflect(Ray,Up)*Travel;
    vec2 Warp=Virtual.z<-0.01 ? ProjectViewToScreenPos(Virtual,gbufferProjection).xy : Uv;
    // Bound the approximation near a grazing horizon/unknown hit distance.
    vec2 Delta=Warp-Uv;float Len=length(Delta);
    Warp=Uv+Delta*min(1.0,0.035/max(Len,0.00001));
    if(Len<0.000001 || !IsScreenUvInRange(Warp)) return TryHalfReflection(Uv,View,NormalWorld,Fallback);
    // Intersect the lookup ray with this water plane. Bilinear receiving-
    // surface coverage fades the warp at banks, instead of a binary center
    // pixel test that pops when waves cross an occluding shoreline.
    vec3 WarpView=ReconstructViewPos(Warp,0.5,gbufferProjectionInverse);
    float Den=dot(WarpView,Up);
    if(abs(Den)<0.00001 || dot(View,Up)/Den<=0.0) return TryHalfReflection(Uv,View,NormalWorld,Fallback);
    WarpView*=dot(View,Up)/Den;
    float Agreement;
    ReflectionResult Distorted=GatherWaterField(Warp,WarpView,Fallback,Agreement);
    // A clamped edge texel is not complete support for an off-screen lookup.
    // Reach the undistorted field continuously BEFORE Warp leaves the screen;
    // otherwise crossing the border switches between two different images.
    vec2 EdgeWidth=max(vec2(0.012),3.0/vec2(textureSize(colortex7,0)));
    vec2 EdgeSupport=smoothstep(vec2(0.0),EdgeWidth,min(Warp,1.0-Warp));
    Agreement*=EdgeSupport.x*EdgeSupport.y;
    if(Agreement<=0.0) return TryHalfReflection(Uv,View,NormalWorld,Fallback);
    if(Agreement>=0.999) return Distorted;
    ReflectionResult Base=TryHalfReflection(Uv,View,NormalWorld,Fallback);
    // Both results include their own fallback coverage; never switch hit/miss.
    float A=Base.Confidence*(1.0-Agreement),B=Distorted.Confidence*Agreement;
    float Coverage=A+B;
    if(Coverage<=0.0001) return Base;
    return CreateReflectionResult((Base.Color*A+Distorted.Color*B)/Coverage,Coverage);
}
#endif
