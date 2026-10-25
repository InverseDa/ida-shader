#include "/lib/constant.glsl"
#include "/lib/util/functions.glsl"
#include "/lib/lighting/frame.glsl"
#ifdef FRAGMENT_SHADER
uniform sampler2D colortex0,colortex1,colortex3,colortex15,depthtex0;
#include "/lib/reflections/half_res.glsl"
/* RENDERTARGETS: 0 */
void main() {
    ivec2 Pixel=ivec2(gl_FragCoord.xy); vec2 Uv=gl_FragCoord.xy/vec2(viewWidth,viewHeight);
    vec3 Color=texelFetch(colortex0,Pixel,0).rgb;
    vec4 Payload=texelFetch(colortex1,Pixel,0), Surface=texelFetch(colortex3,Pixel,0), Hit=texelFetch(colortex15,Pixel,0);
#if SSR_HALF_RES == 1 && SSR_TEMPORAL == 1
    if (Surface.z < 0.0 && Surface.w == float(frameCounter%64)*4.0+1.0 && isEyeInWater == 0) {
        vec3 View=ReconstructViewPos(Uv,texelFetch(depthtex0,Pixel,0).r,gbufferProjectionInverse);
        float Visible=-View.z;
        if (Visible+max(0.04,-Surface.z*0.004)>=-Surface.z && Payload.a>0.0) {
            vec3 Normal=vec3(Surface.x,sqrt(max(1.0-dot(Surface.xy,Surface.xy),0.0)),Surface.y);
            ReflectionResult R=ReconstructHalfReflection(Uv,View,Normal,Payload.rgb);
            vec3 Reflected=R.Color*vec3(0.94,1.02,0.98);
            Reflected=mix(vec3(dot(Reflected,vec3(0.2126,0.7152,0.0722))),Reflected,0.93);
            Color += (Reflected-Payload.rgb)*R.Confidence*Payload.a*Hit.r;
        }
    }
#endif
    gl_FragData[0]=vec4(max(Color,vec3(0.0)),1.0);
}
#endif
#ifdef VERTEX_SHADER
void main() { gl_Position=ftransform(); SetupFrameLighting(); }
#endif
