#include "/lib/constant.glsl"
#include "/lib/util/functions.glsl"
#include "/lib/lighting/frame.glsl"
#ifdef FRAGMENT_SHADER
uniform sampler2D colortex1, colortex3, depthtex0;
#include "/lib/reflections/water_trace.glsl"
/* RENDERTARGETS: 6,7 */
bool VisibleWaterSample(ivec2 Pixel,out vec4 Surface) {
    Surface=texelFetch(colortex3,Pixel,0);
    if(Surface.z>=0.0 || Surface.w!=float(frameCounter%64)*4.0+1.0) return false;
    float Depth=texelFetch(depthtex0,Pixel,0).r*2.0-1.0;
    vec4 V=gbufferProjectionInverse*vec4(0,0,Depth,1);
    return -V.z/V.w+max(.04,-Surface.z*.004)>=-Surface.z;
}
void main() {
    vec4 Data = vec4(0.0), Color = vec4(0.0);
#if SSR_HALF_RES == 1 && SSR_TEMPORAL == 1
    vec2 Size = vec2(viewWidth,viewHeight), HalfSize = max(floor(Size*0.5),vec2(1.0));
    ivec2 Pixel = min(ivec2(gl_FragCoord.xy/HalfSize*Size),ivec2(Size)-1);
    ivec2 Nominal=Pixel;vec4 Surface;
    bool Found=VisibleWaterSample(Pixel,Surface);
    if(!Found && isEyeInWater==0) {
        // A fixed centre sample drops a complete half-size cell when its
        // shoreline crosses land. Select current, depth-visible water within
        // this footprint; never borrow a reflection from another frame.
        ivec2 Cell=ivec2(gl_FragCoord.xy);
        ivec2 Lo=Cell*ivec2(Size)/ivec2(HalfSize);
        ivec2 Hi=min((Cell+1)*ivec2(Size)/ivec2(HalfSize),ivec2(Size));
        // One hardware gather rejects wholly dry cells before individual
        // payload/depth tests. At 5K most of the image may be land or sky.
        bool Large=any(greaterThan(Hi-Lo,ivec2(2)));
        bool Wet=any(lessThan(textureGather(colortex3,(vec2(Lo)+1.0)/Size,2),vec4(0.0)));
        if(Wet || Large) {
        for(int K=0;K<4;++K) {
            if(Found) break;
            ivec2 Tap=ivec2(K%2==0 ? Lo.x : Hi.x-1,K<2 ? Lo.y : Hi.y-1);
            if(all(equal(Tap,Nominal))) continue;
            if(VisibleWaterSample(Tap,Surface)) { Pixel=Tap;Found=true; }
        }
        // Odd viewports occasionally map a cell to three full-size texels.
        // Check its remaining edge centres only in those uncommon cells.
        if(!Found && Large)
            for(int Y=0;Y<3 && !Found;++Y) for(int X=0;X<3 && !Found;++X) {
                ivec2 Tap=Lo+ivec2(X,Y);
                if(any(greaterThanEqual(Tap,Hi))) continue;
                if(VisibleWaterSample(Tap,Surface)) { Pixel=Tap;Found=true; }
            }
        }
    }
    if (Found && isEyeInWater == 0) {
        vec2 Uv = (vec2(Pixel)+0.5)/Size;
        vec3 View = ReconstructViewPos(Uv,texelFetch(depthtex0,Pixel,0).r,gbufferProjectionInverse);
        float Visible = -View.z;
        if (Visible+max(0.04,-Surface.z*0.004) >= -Surface.z) {
            // Stable planar radiance. Wave distortion belongs to the resolve.
            vec3 N = normalize(mat3(gbufferModelView)*vec3(0.0,1.0,0.0));
            if (dot(N,-View) < 0.0) N = -N;
            ReflectionResult R = TraceWaterReflection(View,N,reflect(normalize(View),N),min(far,128.0),SSR_TRACE_STEPS,texelFetch(colortex1,Pixel,0).rgb);
            // Water history is resolved on the final composed image in TAA.
            // Doing another reprojection here costs millions of half-size
            // history reads, and its colour was discarded by screen rebuilds.
            // Keep travel and the selected receiver for reconstruction/history.
            // Water contains screen hits only. Keep travel unsigned for one
            // hardware-bilinear read; receiver depth is always positive.
            Data.z=R.HitDistance;
            Data.xy=vec2(Pixel-Nominal)/Size;
            Data.w=-View.z;
            Color=vec4(R.Color,R.Confidence);
        }
    }
#endif
    gl_FragData[0] = Data; gl_FragData[1] = Color;
}
#endif
#ifdef VERTEX_SHADER
void main() { gl_Position = ftransform(); SetupFrameLighting(); }
#endif
