#ifndef IDA_WATER_TRACE_GLSL
#define IDA_WATER_TRACE_GLSL
#include "/lib/reflections/screen_trace.glsl"

vec3 FilterWaterSource(vec2 Uv,float Depth) {
    ivec2 Size=WaterSourceSize();
    vec2 P=Uv*vec2(Size)-0.5,F=fract(P);ivec2 Base=ivec2(floor(P));
    vec3 Color=vec3(0);float Weight=0.0;
    for(int K=0;K<4;++K) {
        ivec2 Cell=clamp(Base+ivec2(K%2,K/2),ivec2(0),Size-1);
        uvec4 Node=WaterNodes[WaterNodeIndex(Cell,0)],Back=WaterBackNode(Cell);
        if(abs(uintBitsToFloat(Back.x)-Depth)<abs(uintBitsToFloat(Node.x)-Depth)) Node=Back;
        vec2 Z=uintBitsToFloat(Node.xy);
        float W=(K%2==0 ? 1.0-F.x : F.x)*(K<2 ? 1.0-F.y : F.y);
        W*=1.0-smoothstep(max(0.1,Depth*0.01),max(0.2,Depth*0.03),abs(Z.x-Depth));
        Color+=WaterNodeColor(Node)*W;Weight+=W;
    }
    if(Weight>0.0001) return Color/Weight;
    ivec2 Cell=clamp(ivec2(Uv*vec2(Size)),ivec2(0),Size-1);
    uvec4 Node=WaterNodes[WaterNodeIndex(Cell,0)],Back=WaterBackNode(Cell);
    if(abs(uintBitsToFloat(Back.x)-Depth)<abs(uintBitsToFloat(Node.x)-Depth)) Node=Back;
    return WaterNodeColor(Node);
}

// Perspective-correct hierarchical DDA over an opaque depth heightfield.
// Keep the FIRST front-depth crossing, including a crossing at a discontinuity.
// A maximum-depth/slab exit test loses that crossing at foliage and banks,
// producing holes that TAA cannot repair. Height below still rejects submerged
// sources; screen/range fades still bound unavailable reflection coverage.
ReflectionResult TraceWaterScreen(vec3 View,vec3 N,vec3 D,float Range,int Steps,vec3 Fallback) {
    ReflectionResult Miss=CreateReflectionResult(Fallback,0.0);
    if(ReflectionTiles[4096]!=uint(frameCounter)+1u ||
       ReflectionTiles[4097]!=uint(viewWidth) || ReflectionTiles[4098]!=uint(viewHeight)) return Miss;
    vec3 Origin=View+N*0.025;
    float End=Range;
    if(D.z>0.0) End=min(End,(-near*1.01-Origin.z)/D.z);
    if(End<=0.06 || Origin.z>=-near) return Miss;
    vec3 A=Origin+D*0.06,B=Origin+D*End;
    vec2 UvA=ProjectViewToScreenPos(A,gbufferProjection).xy;
    vec2 Delta=ProjectViewToScreenPos(B,gbufferProjection).xy-UvA;
    vec2 InvZ=vec2(1.0/-A.z,1.0/-B.z);
    ivec2 Size=WaterSourceSize();
    float WaterHeight=ViewToWorldPos(View,gbufferModelViewInverse).y;
    float T=0.0;int Level=6;
    for(int I=0;I<192;++I) {
        if(I>=Steps*4 || T>=1.0) break;
        vec2 Uv=UvA+Delta*(T+0.0000001);
        if(!IsScreenUvInRange(Uv)) break;
        float Scale=exp2(float(Level));
        ivec2 Cell=ivec2(floor(Uv*vec2(Size)/Scale));
        vec2 Boundary=(vec2(Cell)+step(vec2(0),Delta))*Scale/vec2(Size);
        vec2 Crossing=(Boundary-UvA)/vec2(abs(Delta.x)>1e-8 ? Delta.x : 1e-8,abs(Delta.y)>1e-8 ? Delta.y : 1e-8);
        if(abs(Delta.x)<=1e-8) Crossing.x=2.0;
        if(abs(Delta.y)<=1e-8) Crossing.y=2.0;
        float Exit=min(1.0,min(Crossing.x,Crossing.y));
        Exit=max(Exit,T+0.0000002);
        vec2 Z=WaterNodeRange(Cell,Level);
        float ZA=1.0/mix(InvZ.x,InvZ.y,T),ZB=1.0/mix(InvZ.x,InvZ.y,Exit);
        float Thickness=max(0.06,Z.y*2.0/(abs(gbufferProjection[1].y)*float(Size.y)));
        // Coarse cells only prove the ray is still in front of all surfaces.
        // Being behind their maximum depth is NOT proof of empty space.
        bool Overlap=Z.y>0.0 && max(ZA,ZB)>=Z.x-Thickness;
        if(Overlap && Level>0) { Level-=1;continue; }
        if(Overlap) {
          float BestT=2.0,BestDepth=0.0;vec3 LeafColor=vec3(0);bool LeafHit=false;
          for(int Layer=0;Layer<3;++Layer) {
            uvec4 Node=Layer==0 ? WaterNodes[WaterNodeIndex(Cell,0)] : (Layer==1 ? WaterBackNode(Cell) : WaterLeafNode(Cell));
            Z=uintBitsToFloat(Node.xy);
            Thickness=max(Layer==2 ? 0.13 : 0.06,Z.y*2.0/(abs(gbufferProjection[1].y)*float(Size.y)));
            if(Z.y<=0.0 || max(ZA,ZB)<Z.x-Thickness) continue;
            float Target=clamp(Z.x,min(ZA,ZB),max(ZA,ZB));
            float HitT=abs(InvZ.y-InvZ.x)>1e-9 ? clamp((1.0/Target-InvZ.x)/(InvZ.y-InvZ.x),T,Exit) : T;
            // Water/bottom pixels cannot become an air-side reflection.
            float Height=unpackHalf2x16(Node.w).y;
            if(Height>WaterHeight+0.025 && HitT<BestT) { BestT=HitT;BestDepth=Z.x;LeafHit=Layer==2;LeafColor=WaterNodeColor(Node); }
          }
          if(BestT<2.0) {
                vec2 HitUv=UvA+Delta*BestT;
                vec3 Hit=mix(A*InvZ.x,B*InvZ.y,BestT)/mix(InvZ.x,InvZ.y,BestT);
                float Travel=dot(Hit-Origin,D);
                vec2 Border=min(HitUv,1.0-HitUv);
                float Confidence=smoothstep(0.001,0.025,min(Border.x,Border.y));
                Confidence*=1.0-smoothstep(Range*0.85,Range,Travel);
                ReflectionResult R=CreateReflectionResult(LeafHit ? LeafColor : FilterWaterSource(HitUv,BestDepth),Confidence);
                R.HitDistance=max(Travel,0.06);return R;
            }
        }
        T=Exit+0.0000002;Level=min(Level+1,6);
    }
    return Miss;
}

ReflectionResult TraceWaterReflection(vec3 View,vec3 N,vec3 D,float Range,int Steps,vec3 Fallback) {
    ReflectionResult S=TraceWaterScreen(View,N,D,Range,Steps,Fallback);
    // Water uses the filtered screen field and its existing environment only.
    // Voxel reflection remains a separate path for other reflective materials.
    // Environment fallback has a distant virtual image. Fade the motion hint
    // with the same coverage as radiance instead of snapping to zero on a miss.
    S.HitDistance=mix(min(Range,128.0),S.HitDistance,clamp(S.Confidence,0.0,1.0));
    return S;
}
#endif
