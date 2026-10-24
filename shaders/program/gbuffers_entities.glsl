#include "/lib/constant.glsl"
#include "/lib/util/functions.glsl"
#include "/lib/materials/materialData.glsl"
#if !defined(COLOR_ONLY) && !defined(PARTICLE) && !defined(GBUFFERS_HAND) && !defined(GBUFFERS_HAND_WATER)
#include "/lib/materials/pbr.glsl"
#endif
#if defined(GBUFFERS_HAND_WATER)
#define FORWARD_TRANSLUCENT
#endif
#if defined(FORWARD_TRANSLUCENT) && !defined(GBUFFERS_HAND_WATER)
#include "/lib/lighting/frame.glsl"
#endif

// =============================================================================
// Fragment Shader
// =============================================================================
#ifdef FRAGMENT_SHADER

#include "/lib/misc/water_medium.glsl"
uniform sampler2D texture;
uniform sampler2D lightmap;
in vec4 Color;
in vec4 Texcoord;
in vec4 Lmcoord;
in vec3 Normal;
in vec3 ViewPos;
#if defined(FORWARD_TRANSLUCENT) && !defined(GBUFFERS_HAND_WATER)
#include "/lib/lighting/scene.glsl"
#include "/lib/misc/atmosphere.glsl"
#endif

#if defined(FORWARD_TRANSLUCENT)
/* RENDERTARGETS: 0,10 */
#elif defined(GBUFFERS_HAND)
/* RENDERTARGETS: 0,2,5,1 */
#else
/* RENDERTARGETS: 0,2,5,9 */
#endif
void main() {
    vec4 Base = texture2D(texture, Texcoord.st) * Color;
#if !defined(IDA_MATERIALS_PBR_GLSL) || MATERIAL_MODE == 0
    if (Base.a <= 0.001) discard;
#endif
    vec3 VanillaLight = SrgbToLinear(texture2D(lightmap, Lmcoord.st).rgb);
    vec3 Albedo = SrgbToLinear(Base.rgb);
    vec3 GeometryNormal = SafeNormal(Normal);
#if defined(GBUFFERS_HAND) || defined(GBUFFERS_HAND_WATER)
    vec4 Material = PackMaterialData(0.82, 0.04, 1.0, MaterialIdHand);
#else
    vec4 Material = PackMaterialData(0.82, 0.04, 1.0, MaterialIdDynamic);
#endif
    Material = WithMaterialSkyLight(Material, Lmcoord.t);
// Hands are intentionally Lightmap-only; sampling PBR here has no visible use.
#if !defined(COLOR_ONLY) && !defined(PARTICLE) && !defined(GBUFFERS_HAND) && !defined(GBUFFERS_HAND_WATER)
    PbrMaterialSample Pbr = SamplePbrMaterial(Texcoord.st, GeometryNormal, ViewPos, Material);
    GeometryNormal = Pbr.NormalView;
    Material = Pbr.MaterialData;
#endif
    // Keep normal derivatives valid for alpha-tested edge helper invocations.
#if defined(IDA_MATERIALS_PBR_GLSL) && MATERIAL_MODE == 1
    if (Base.a <= 0.001) discard;
#endif
#if defined(GBUFFERS_HAND) || defined(GBUFFERS_HAND_WATER)
    Albedo *= VanillaLight;
    if (isEyeInWater == 1) Albedo = ApplyUnderwaterMedium(Albedo, length(ViewPos));
#elif defined(FORWARD_TRANSLUCENT)
#if defined(COLOR_ONLY) || defined(PARTICLE)
    Albedo *= VanillaLight;
#else
    vec3 WorldPos = ViewToWorldPos(ViewPos, gbufferModelViewInverse);
    float TransmissionVisibility;
    float Visibility = ShadowMapping(WorldPos, GeometryNormal, 1.0, TransmissionVisibility);
    Albedo = ApplySunDirectLight(Albedo, GeometryNormal, ViewPos, WorldPos, Material, Visibility, TransmissionVisibility, 1.0, VanillaLight);
#endif
    Albedo = ApplyAtmosphere(Albedo, ViewPos, false);
#else
    gl_FragData[3] = vec4(VanillaLight, 1.0);
#endif
    gl_FragData[0] = vec4(Albedo, Base.a);
#if defined(FORWARD_TRANSLUCENT)
    gl_FragData[1] = vec4(max(Base.a, 1.0 / 255.0));
#else
    gl_FragData[1] = vec4(NormalEncode(GeometryNormal), 0.0, 1.0);
    gl_FragData[2] = Material;
#if defined(GBUFFERS_HAND)
    // First-person hand rendering intentionally covers earlier world overlays.
    gl_FragData[3] = vec4(0.0);
#endif
#endif
}

#endif // FRAGMENT_SHADER

// =============================================================================
// Vertex Shader
// =============================================================================
#ifdef VERTEX_SHADER

out vec4 Color;
out vec4 Texcoord;
out vec4 Lmcoord;
out vec3 Normal;
out vec3 ViewPos;

void main() {
    vec4 PositionInView = gl_ModelViewMatrix * gl_Vertex;
    ViewPos = PositionInView.xyz;
    gl_Position = gl_ProjectionMatrix * PositionInView;
#if defined(FORWARD_TRANSLUCENT) && !defined(GBUFFERS_HAND_WATER)
    SetupFrameLighting();
#endif
    Color = gl_Color;
    Texcoord = gl_TextureMatrix[0] * gl_MultiTexCoord0;
    Lmcoord = gl_TextureMatrix[1] * gl_MultiTexCoord1;
    Normal = gl_NormalMatrix * gl_Normal;
}

#endif // VERTEX_SHADER
