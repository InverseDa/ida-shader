#ifndef IDA_WATER_TEMPORAL_GLSL
#define IDA_WATER_TEMPORAL_GLSL
// Reuse final TAA history for the fully reconstructed water image. This also
// stabilizes alpha coverage, which isolated reflection-colour clamping misses.
uniform sampler2D colortex1,colortex3,colortex6,colortex13,colortex15,depthtex0;
const float WaterHistoryTag=-65504.0;

bool WaterTemporalSurface(ivec2 Pixel,out vec3 View,out vec3 Normal,out float Travel) {
    View=vec3(0.0);Normal=vec3(0.0,1.0,0.0);Travel=0.0;
#if SSR_HALF_RES == 1 && SSR_TEMPORAL == 1 && WATER_TAA == 1
    if(isEyeInWater!=0) return false;
    vec4 Surface=texelFetch(colortex3,Pixel,0);
    if(Surface.z>=0.0 || Surface.w!=float(frameCounter%64)*4.0+1.0) return false;
    // A particle/glass overlay must not inherit water motion/history. G is
    // untouched by atmospheric attenuation, but multiplied by late alpha.
    if(texelFetch(colortex15,Pixel,0).g<0.999) return false;
    vec2 Uv=(vec2(Pixel)+0.5)/vec2(viewWidth,viewHeight);
    View=ReconstructViewPos(Uv,texelFetch(depthtex0,Pixel,0).r,gbufferProjectionInverse);
    if(-View.z+max(0.04,-Surface.z*0.004)<-Surface.z || View.z>=0.0) return false;
    Normal=vec3(Surface.x,sqrt(max(1.0-dot(Surface.xy,Surface.xy),0.0)),Surface.y);
    // Interpolate distance before reprojection. Nearest sampling changes the
    // motion model abruptly at half-resolution texel / foliage boundaries.
    Travel=texture2D(colortex6,Uv).z;
    if(Travel>128.0) Travel=0.0;
    return true;
#else
    return false;
#endif
}

vec2 WaterPreviousUv(vec2 Uv,vec3 View,vec3 Normal,float Travel,out float Agreement) {
    Agreement=0.0;
    vec3 SurfaceWorld=ViewToWorldPos(View,gbufferModelViewInverse);
    vec3 Offset=cameraPosition-previousCameraPosition;
    vec3 PreviousSurface=WorldToViewPos(SurfaceWorld+Offset,gbufferPreviousModelView);
    // Virtual reflected image lies behind the water along the incident ray.
    // Low-Fresnel water instead follows the transmitted opaque depth.
    float VirtualDepth=-View.z*(1.0+Travel/max(length(View),0.01));
    float Reflectivity=texelFetch(colortex1,ivec2(Uv*vec2(viewWidth,viewHeight)),0).a;
    float Depth=VirtualDepth;
    if(Reflectivity<0.4) {
        vec4 Opaque=FetchOpaqueData(ivec2(Uv*vec2(viewWidth,viewHeight)));
        float BehindDepth=Opaque.b<0.999999 ? -ReconstructViewPos(Uv,Opaque.b,gbufferProjectionInverse).z : -View.z;
        Depth=mix(BehindDepth,VirtualDepth,smoothstep(0.1,0.4,Reflectivity));
    }
    vec3 PreviousVirtual=WorldToViewPos(ViewToWorldPos(View*(Depth/max(-View.z,0.01)),gbufferModelViewInverse)+Offset,gbufferPreviousModelView);
    if(PreviousVirtual.z>=0.0) return vec2(-1.0);
    vec2 PreviousUv=ProjectViewToScreenPos(PreviousVirtual,gbufferPreviousProjection).xy;
    if(!IsScreenUvInRange(PreviousUv)) return vec2(-1.0);
    // Half-history texels store selected full-size water samples, not centers
    // of a fictitious low-resolution plane (also handles odd viewports).
    // The reflection field is planar; changing wave shading normals cannot
    // invalidate the underlying water plane from one frame to the next.
    vec3 PreviousNormal=mat3(gbufferPreviousModelView)*vec3(0,1,0);
    ivec2 HistorySize=textureSize(colortex13,0);
    vec2 P=PreviousUv*vec2(HistorySize)-.5,F=fract(P);
    ivec2 Base=ivec2(floor(P));float Support=0.0;
    for(int K=0;K<4;++K) {
        ivec2 Tap=clamp(Base+ivec2(K%2,K/2),ivec2(0),HistorySize-1);
        vec4 OldSurface=texelFetch(colortex13,Tap,0);
        if(OldSurface.w!=float((frameCounter-1)%64)*4.0+1.0 || OldSurface.z<=0.0) continue;
        vec2 FullSize=vec2(viewWidth,viewHeight);
        vec2 TapUv=(floor((vec2(Tap)+.5)/vec2(HistorySize)*FullSize)+.5)/FullSize+OldSurface.xy;
        vec2 Ndc=TapUv*2.0-1.0;
        vec3 Ray=vec3((Ndc+gbufferPreviousProjection[2].xy)/vec2(gbufferPreviousProjection[0].x,gbufferPreviousProjection[1].y),-1.0);
        // A few centimetres of swell become metres of depth error at grazing
        // angles. Validate the physical height, with the actual WPO bound.
        float Error=abs(dot(Ray*OldSurface.z-PreviousSurface,PreviousNormal));
        float Limit=0.01+0.07*WATER_VERTEX_WAVES*WATER_WAVE_STRENGTH+OldSurface.z*0.0007;
        float W=(K%2==0 ? 1.0-F.x : F.x)*(K<2 ? 1.0-F.y : F.y);
        Agreement+=W*(1.0-smoothstep(Limit*.5,Limit,Error));Support+=W;
    }
    // Full-resolution typed history below still rejects land, glass and hand.
    // A missing half-size centre sample alone must not discard valid edge taps.
    Agreement/=max(Support,0.001);
    vec2 Ratio=vec2(gbufferPreviousProjection[0].x/gbufferProjection[0].x,gbufferPreviousProjection[1].y/gbufferProjection[1].y);
    if(any(greaterThan(abs(Ratio-1.0),vec2(0.02)))) Agreement=0.0;
    return PreviousUv;
}
#endif
