#include "/lib/constant.glsl"
#include "/lib/util/functions.glsl"
#include "/lib/materials/materialData.glsl"
#include "/lib/lighting/frame.glsl"

// =============================================================================
// Fragment Shader
// =============================================================================
#ifdef FRAGMENT_SHADER

uniform sampler2D colortex5;
#define IDA_REFLECTION_MATERIAL_SAMPLER
#define IDA_REFLECTION_HISTORY_WRITE
uniform sampler2D colortex1;
uniform sampler2D colortex3;
#if MATERIAL_MODE == 1
uniform sampler2D colortex2;
#endif
in vec4 Texcoord;
#include "/lib/materials/lighting/sky.glsl"
#include "/lib/misc/atmosphere.glsl"
#include "/lib/misc/atmosphere_resolve.glsl"
#include "/lib/materials/translucents/water.glsl"
#include "/lib/materials/puddles.glsl"
#if SSR_TEMPORAL == 1
/* RENDERTARGETS: 0,11,1,3,15 */
#else
/* RENDERTARGETS: 0,11 */
#endif
void main() {
    vec2 Uv = Texcoord.st;
    vec4 Snapshot = FetchOpaqueData(ivec2(gl_FragCoord.xy));
    vec4 Material = FetchMaterialData(colortex5, Uv);
    vec3 Color = texture2D(colortex9, Uv).rgb;
    bool IsHand = IsMaterial(Material, MaterialIdHand);
    bool IsSky = Snapshot.b >= 0.999999;
    vec3 ViewPos = ReconstructOpaqueViewPos(Uv, Snapshot);
    // These derivatives must run before the per-pixel ice branch.
    vec3 SurfaceNormal = NormalDecode(Snapshot.rg);
#if MATERIAL_MODE == 1
    // Ice still reflects with its shading normal; source intersection planes
    // in the immutable snapshot use the separate geometric normal.
    SurfaceNormal = NormalDecode(texelFetch(colortex2, ivec2(gl_FragCoord.xy), 0).rg);
#endif
    float NormalVariance = SpecularNormalVariance(SurfaceNormal);
    float ViewVariance = SpecularNormalVariance(SafeNormal(ViewPos));
#if SURFACE_WETNESS == 1 && PUDDLE_REFLECTIONS == 1
    if (!IsSky && isEyeInWater == 0) {
        Color = DrawPuddleReflection(Color, ViewPos, Material, ViewVariance);
    }
#endif
    // Opaque packed/blue ice must be resolved before translucent geometry.
    // The air-side sky-reflection approximation is not valid for submerged ice.
    if (!IsSky && isEyeInWater != 1 && IsMaterial(Material, MaterialIdIce)) {
        Color = DrawIce(Color, ViewToWorldPos(ViewPos, gbufferModelViewInverse), ViewPos, SurfaceNormal, NormalVariance, ViewVariance);
    }
    if (!IsHand && !IsSky && isEyeInWater == 1) {
        vec3 Relative = ViewToWorldPos(ViewPos,gbufferModelViewInverse);
        vec2 Water = FindWaterSurface(Relative);
        Color = ApplyWaterCaustics(Color,Relative,ViewToWorldNormal(NormalDecode(Snapshot.rg),gbufferModelViewInverse),Water.x,Water.y);
    }
    if (!IsHand) Color = ApplyOpaqueAtmosphere(Color, ViewPos, IsSky, Uv);
    // Keep the water-composition baseline free of early effects. Their visible
    // contribution then survives as a destination delta through refraction.
    Color = max(Color, vec3(0.0));
    gl_FragData[1] = vec4(Color, 1.0);
    // Early effects carry their own medium attenuation and premultiplied alpha.
    // They must not be relit or fogged using the background surface's depth.
    vec4 Effect = texture2D(colortex1, Uv);
    float EffectDepth = texelFetch(colortex3, ivec2(gl_FragCoord.xy), 0).r;
    // A later opaque draw may have covered an early effect. Conversely a new
    // opaque surface BEHIND an effect must not erase that foreground effect.
    // Account for FP16 view-depth rounding, rather than storing hardware depth
    // in FP16 (which would collapse distant depths towards one).
    if (!IsHand && -ViewPos.z + max(0.005, EffectDepth * 0.001) < EffectDepth) Effect = vec4(0.0);
    Color = Color * (1.0 - Effect.a) + Effect.rgb;
    gl_FragData[0] = vec4(Color, 1.0);
#if SSR_TEMPORAL == 1
    // Buffers 1/3 have finished their early-effect color/depth lifetime.
    // Every pixel is overwritten before partial forward reflection draws.
    gl_FragData[2] = ReflectionColorWrite;
    gl_FragData[3] = ReflectionSurfaceWrite;
    gl_FragData[4] = vec4(ReflectionHitWrite.r, 1.0, 0.0, 0.0);
#endif
}

#endif // FRAGMENT_SHADER

// =============================================================================
// Vertex Shader
// =============================================================================
#ifdef VERTEX_SHADER

out vec4 Texcoord;
void main() {
    gl_Position = ftransform();
    Texcoord = gl_MultiTexCoord0;
    SetupFrameLighting();
}

#endif // VERTEX_SHADER
