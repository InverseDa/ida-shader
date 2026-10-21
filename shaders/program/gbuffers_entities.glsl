#include "/lib/constant.glsl"
#include "/lib/util/functions.glsl"
#include "/lib/materials/materialData.glsl"
#include "/lib/materials/pbr.glsl"
#if defined(GBUFFERS_HAND_WATER)
#define FORWARD_TRANSLUCENT
#endif
#if defined(FORWARD_TRANSLUCENT) && !defined(GBUFFERS_HAND_WATER)
#include "/lib/lighting/frame.glsl"
#endif

#ifdef FRAGMENT_SHADER
#include "/lib/misc/water_medium.glsl"
uniform sampler2D texture;
uniform sampler2D lightmap;
in vec4 color;
in vec4 texcoord;
in vec4 lmcoord;
in vec3 normal;
in vec3 viewPos;
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
    vec4 base = texture2D(texture, texcoord.st) * color;
    if (base.a <= 0.001) discard;
    vec3 vanillaLight = srgbToLinear(texture2D(lightmap, lmcoord.st).rgb);
    vec3 albedo = srgbToLinear(base.rgb);
    vec3 geometryNormal = safeNormal(normal);
    vec4 material = packMaterialData(0.82, 0.02, 1.0,
#if defined(GBUFFERS_HAND) || defined(GBUFFERS_HAND_WATER)
        MATERIAL_ID_HAND
#else
        MATERIAL_ID_DYNAMIC
#endif
    );
#if !defined(COLOR_ONLY) && !defined(PARTICLE)
    PbrMaterialSample pbr = samplePbrMaterial(texcoord.st, geometryNormal, viewPos, material);
    geometryNormal = pbr.normalView;
    material = pbr.materialData;
#endif
#if defined(GBUFFERS_HAND) || defined(GBUFFERS_HAND_WATER)
    albedo *= vanillaLight;
    if (isEyeInWater == 1) albedo = applyUnderwaterMedium(albedo, length(viewPos));
#elif defined(FORWARD_TRANSLUCENT)
#if defined(COLOR_ONLY) || defined(PARTICLE)
    albedo *= vanillaLight;
#else
    vec3 worldPos = viewToWorldPos(viewPos, gbufferModelViewInverse);
    albedo = applySunDirectLight(albedo, geometryNormal, viewPos, material,
             shadowMapping(worldPos, geometryNormal, 1.0), 1.0, vanillaLight);
#endif
    albedo = applyAtmosphere(albedo, viewPos, false);
#else
    gl_FragData[3] = vec4(vanillaLight, 1.0);
#endif
    gl_FragData[0] = vec4(albedo, base.a);
#if defined(FORWARD_TRANSLUCENT)
    gl_FragData[1] = vec4(max(base.a, 1.0 / 255.0));
#else
    gl_FragData[1] = vec4(normalEncode(geometryNormal), 0.0, 1.0);
    gl_FragData[2] = material;
#if defined(GBUFFERS_HAND)
    // First-person hand rendering intentionally covers earlier world overlays.
    gl_FragData[3] = vec4(0.0);
#endif
#endif
}
#endif

// =============================================================================
// ============================== Vertex Shader ================================
// =============================================================================
#ifdef VERTEX_SHADER

out vec4 color;
out vec4 texcoord;
out vec4 lmcoord;
out vec3 normal;
out vec3 viewPos;

void main() {
  vec4 positionInView = gl_ModelViewMatrix * gl_Vertex;
  viewPos = positionInView.xyz;
  gl_Position = gl_ProjectionMatrix * positionInView;
#if defined(FORWARD_TRANSLUCENT) && !defined(GBUFFERS_HAND_WATER)
  setupFrameLighting();
#endif
  color = gl_Color;
  texcoord = gl_TextureMatrix[0] * gl_MultiTexCoord0;
  lmcoord = gl_TextureMatrix[1] * gl_MultiTexCoord1;
  normal = gl_NormalMatrix * gl_Normal;
}
#endif
