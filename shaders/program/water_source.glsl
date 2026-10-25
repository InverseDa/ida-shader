#include "/lib/settings.glsl"
uniform sampler2D colortex4,colortex5,colortex9;
uniform mat4 gbufferProjectionInverse,gbufferModelViewInverse;
uniform float viewWidth,viewHeight;
uniform int frameCounter;
#include "/lib/reflections/water_hierarchy.glsl"
#include "/lib/post/taa.glsl"
#include "/lib/common/packing.glsl"
#include "/lib/common/opaque_snapshot.glsl"
bool SourceIsLeaf(ivec2 Pixel) { return mod(floor(texelFetch(colortex5,Pixel,0).a*255.0+.5),16.0)==9.0; }
layout(local_size_x=8,local_size_y=8) in;
#if WATER_SOURCE_LEVEL == 0
const ivec3 workGroups=ivec3(128,128,1);
shared uint NearLeaves;
#elif WATER_SOURCE_LEVEL == 1
const ivec3 workGroups=ivec3(64,64,1);
#elif WATER_SOURCE_LEVEL == 2
const ivec3 workGroups=ivec3(32,32,1);
#elif WATER_SOURCE_LEVEL == 3
const ivec3 workGroups=ivec3(16,16,1);
#elif WATER_SOURCE_LEVEL == 4
const ivec3 workGroups=ivec3(8,8,1);
#elif WATER_SOURCE_LEVEL == 5
const ivec3 workGroups=ivec3(4,4,1);
#else
const ivec3 workGroups=ivec3(2,2,1);
#endif
float SourceDepth(float Hardware) {
    vec4 P=gbufferProjectionInverse*vec4(0,0,Hardware*2.0-1.0,1);
    return -P.z/P.w;
}
vec3 SourceView(ivec2 Pixel,vec2 Snapshot,ivec2 Full) {
    vec2 Uv=(vec2(Pixel)+0.5)/vec2(Full);
    if(Snapshot.r<0.0) Uv-=GetTaaJitterNdc(frameCounter,vec2(Full))*0.5;
    vec4 P=gbufferProjectionInverse*vec4(Uv*2.0-1.0,Snapshot.g*2.0-1.0,1.0);
    return P.xyz/P.w;
}
void main() {
    ivec2 Cell=ivec2(gl_GlobalInvocationID.xy),Base=WaterSourceSize();
    int Scale=1<<WATER_SOURCE_LEVEL;
    ivec2 Size=(Base+Scale-1)/Scale;
#if WATER_SOURCE_LEVEL == 0
    if(gl_LocalInvocationIndex==0u) NearLeaves=floatBitsToUint(1e20);
    barrier();
    if(all(lessThan(Cell,Size))) {
#else
    if(any(greaterThanEqual(Cell,Size))) return;
#endif
    vec2 Depth=vec2(1e20,0.0);vec3 Color=vec3(0.0);float Height=0.0;
#if WATER_SOURCE_LEVEL == 0
    ivec2 Full=textureSize(colortex4,0);
    // At 5K each cell already integrates about 5x5 source pixels. Only small
    // viewports need an extra texel to cover terrain-jitter alpha gaps.
    int Halo=Full.x/Base.x<3 ? 1 : 0;
    ivec2 Lo=max(Cell*Full/Base-Halo,ivec2(0)),Hi=min(((Cell+1)*Full+Base-1)/Base+Halo,Full);
    // Conservative spatial coverage is decided ONCE, before rays are traced.
    // Tiny alpha gaps join the nearest observed surface; empty regions stay empty.
    ivec2 Nearest=Lo;
    for(int Y=Lo.y;Y<Hi.y;++Y) for(int X=Lo.x;X<Hi.x;++X) {
        float Z=texelFetch(colortex4,ivec2(X,Y),0).g;
        if(Z<0.999999 && SourceDepth(Z)<Depth.x) { Depth.x=SourceDepth(Z);Nearest=ivec2(X,Y); }
    }
    float Weight=0.0;
    bool Leaf=SourceIsLeaf(Nearest);
    vec2 Anchor=texelFetch(colortex4,Nearest,0).rg;
    vec3 AnchorView=SourceView(Nearest,Anchor,Full);
    vec3 AnchorNormal=NormalDecode(DecodeOpaqueSnapshot(Anchor).rg);
    // A grazing face spans a wide Z range inside one source footprint. Group
    // by its surface plane, not a thin Z slice that deletes the far half.
    float Layer=max(0.08,Depth.x*0.001);
    float BackDepth=1e20;ivec2 BackPixel=Lo;
    for(int Y=Lo.y;Y<Hi.y;++Y) for(int X=Lo.x;X<Hi.x;++X) {
        vec2 Snapshot=texelFetch(colortex4,ivec2(X,Y),0).rg;
        float Z=Snapshot.g;
        if(Z>=0.999999) continue;
        float Linear=SourceDepth(Z);
        vec3 View=SourceView(ivec2(X,Y),Snapshot,Full);
        if(abs(dot(View-AnchorView,AnchorNormal))>Layer) {
            if(Linear<BackDepth) { BackDepth=Linear;BackPixel=ivec2(X,Y); }
            continue;
        }
        Depth.y=max(Depth.y,Linear);
        Height+=(gbufferModelViewInverse*vec4(View,1.0)).y;
        Color+=texelFetch(colortex9,ivec2(X,Y),0).rgb;Weight+=1.0;
    }
    Color/=max(Weight,1.0);
    Height/=max(Weight,1.0);
    vec2 BackRange=vec2(BackDepth,0.0);vec3 BackColor=vec3(0);float BackHeight=0.0,BackWeight=0.0;
    bool BackLeaf=SourceIsLeaf(BackPixel);
    if(BackDepth<1e19) {
        vec2 BackAnchor=texelFetch(colortex4,BackPixel,0).rg;
        vec3 BackView=SourceView(BackPixel,BackAnchor,Full);
        vec3 BackNormal=NormalDecode(DecodeOpaqueSnapshot(BackAnchor).rg);
        for(int Y=Lo.y;Y<Hi.y;++Y) for(int X=Lo.x;X<Hi.x;++X) {
            vec2 Snapshot=texelFetch(colortex4,ivec2(X,Y),0).rg;
            if(Snapshot.g>=0.999999) continue;
            vec3 V=SourceView(ivec2(X,Y),Snapshot,Full);
            if(abs(dot(V-AnchorView,AnchorNormal))<=Layer || abs(dot(V-BackView,BackNormal))>max(0.08,BackDepth*0.001)) continue;
            BackRange.y=max(BackRange.y,-V.z);
            BackColor+=texelFetch(colortex9,ivec2(X,Y),0).rgb;
            BackHeight+=(gbufferModelViewInverse*vec4(V,1)).y;BackWeight+=1.0;
        }
    }
    BackColor/=max(BackWeight,1.0);BackHeight/=max(BackWeight,1.0);
    uint BackFlag=BackWeight>0.0 && BackLeaf ? 0x80000000u : 0u;
    WaterNodes[1398016+Cell.x+Cell.y*1024]=uvec4(floatBitsToUint(BackRange),packHalf2x16(BackColor.rg)|BackFlag,packHalf2x16(vec2(BackColor.b,BackHeight)));
    if(Cell==ivec2(0)) {
        ReflectionTiles[4096]=uint(frameCounter)+1u;
        ReflectionTiles[4097]=uint(viewWidth);ReflectionTiles[4098]=uint(viewHeight);
    }
#else
    ivec2 ChildSize=(Base+(Scale/2)-1)/(Scale/2);
    for(int K=0;K<4;++K) {
        ivec2 Child=Cell*2+ivec2(K%2,K/2);
        if(any(greaterThanEqual(Child,ChildSize))) continue;
        vec2 D=WaterNodeRange(Child,WATER_SOURCE_LEVEL-1);
        Depth.x=min(Depth.x,D.x);Depth.y=max(Depth.y,D.y);
    }
#endif
    WaterNodes[WaterNodeIndex(Cell,WATER_SOURCE_LEVEL)]=uvec4(floatBitsToUint(Depth),packHalf2x16(Color.rg),packHalf2x16(vec2(Color.b,Height)));
#if WATER_SOURCE_LEVEL == 0
    if(Weight>0.0 && Leaf) WaterNodes[WaterNodeIndex(Cell,0)].z|=0x80000000u;
    if(Depth.x<24.0 && Weight>0.0 && Leaf) atomicMin(NearLeaves,floatBitsToUint(Depth.x));
    if(BackDepth<24.0 && BackFlag!=0u) atomicMin(NearLeaves,floatBitsToUint(BackDepth));
    }
    barrier();
    if(gl_LocalInvocationIndex==0u) WaterLeafGroups[gl_WorkGroupID.x+gl_WorkGroupID.y*128u]=NearLeaves;
#endif
}
