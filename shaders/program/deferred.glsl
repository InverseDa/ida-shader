#include "/lib/constant.glsl"
#include "/lib/util/functions.glsl"
#include "/lib/materials/materialData.glsl"
#include "/lib/lighting/frame.glsl"

// =============================================================================
// Fragment Shader
// =============================================================================
#ifdef FRAGMENT_SHADER

uniform sampler2D depthtex0;
uniform sampler2D colortex0;
uniform sampler2D colortex2;
uniform sampler2D colortex5;
uniform sampler2D colortex10;
in vec4 Texcoord;
#include "/lib/lighting/scene.glsl"
#include "/lib/lighting/ssao.glsl"

// Reading lightmap 9 and writing raw radiance 9 uses Iris's automatic flip.
/* RENDERTARGETS: 4,10,9 */
void main() {
    vec2 Uv = Texcoord.st;
    float Depth = texture2D(depthtex0, Uv).r;
    vec3 Color = texture2D(colortex0, Uv).rgb;
    vec4 NormalData = texelFetch(colortex2, ivec2(gl_FragCoord.xy), 0);
    vec3 Normal = NormalDecode(NormalData.rg);
    vec2 GeometryNormalOct = NormalData.rg;
#if MATERIAL_MODE == 1
    GeometryNormalOct = NormalData.ba;
#endif
    vec4 Material = FetchMaterialData(colortex5, Uv);
    bool IsHand = IsMaterial(Material, MaterialIdHand);
    bool IsSky = Depth >= 0.999999;
    bool Jittered = !IsSky && MaterialUsesTaaJitter(Material);
    vec3 ViewPos = ReconstructSurfaceViewPos(Uv, Depth, Jittered);
    vec3 WorldPos = ViewToWorldPos(ViewPos, gbufferModelViewInverse);
    if (!IsSky && !IsHand && !IsMaterial(Material, MaterialIdUnlit)) {
        float Ao = GetScreenSpaceAmbientOcclusion(ViewPos, Normal, Jittered);
        float TransmissionVisibility;
        vec3 ShadowNormal = Normal;
#if SHADOW_RECEIVER_PLANE == 1
        ShadowNormal = NormalDecode(GeometryNormalOct);
#endif
        float Visibility = ShadowMapping(WorldPos, ShadowNormal, 1.0, TransmissionVisibility);
        Color = ApplySunDirectLight(Color, Normal, ViewPos, WorldPos, Material, Visibility, TransmissionVisibility, Ao, texture2D(colortex9, Uv).rgb, NormalDecode(GeometryNormalOct));
    }
    if (IsSky) Color = GetSkyRadiance(normalize(ViewPos));
    gl_FragData[0] = vec4(EncodeOpaqueSnapshot(GeometryNormalOct, IsHand ? 1.0 : Depth, Jittered), 0.0, 1.0);
    // Keep marks from cracks, glint and other effects drawn before deferred.
    gl_FragData[1] = vec4(max(Jittered ? 0.0 : 1.0, texture2D(colortex10, Uv).r));
    gl_FragData[2] = vec4(Color, 1.0);
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
