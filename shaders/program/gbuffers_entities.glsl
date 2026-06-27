#include "/lib/constant.glsl"
#include "/lib/util/functions.glsl"
#include "/lib/materials/materialData.glsl"
#include "/lib/materials/pbr.glsl"

// =============================================================================
// ============================= Fragment Shader ===============================
// =============================================================================
#ifdef FRAGMENT_SHADER

uniform sampler2D texture;
uniform sampler2D lightmap;

in vec4 color;
in vec4 texcoord;
in vec4 lmcoord;
in vec2 normal;
in vec3 viewPos;

void main() {
  vec4 light = texture2D(lightmap, lmcoord.st);
  vec3 geometryNormal = normalDecode(normal);
  PbrMaterialSample pbr = samplePbrMaterial(texcoord.st, geometryNormal, viewPos, getDefaultMaterialData());
  /* DRAWBUFFERS:025 */
  gl_FragData[0] = texture2D(texture, texcoord.st) * light * color;
  gl_FragData[1] = vec4(normalEncode(pbr.normalView), 0.0, 1.0);
  gl_FragData[2] = pbr.materialData;
}
#endif

// =============================================================================
// ============================== Vertex Shader ================================
// =============================================================================
#ifdef VERTEX_SHADER

out vec4 color;
out vec4 texcoord;
out vec4 lmcoord;
out vec2 normal;
out vec3 viewPos;

void main() {
  vec4 positionInView = gl_ModelViewMatrix * gl_Vertex;
  viewPos = positionInView.xyz;
  gl_Position = gl_ProjectionMatrix * positionInView;
  color = gl_Color;
  texcoord = gl_TextureMatrix[0] * gl_MultiTexCoord0;
  lmcoord = gl_TextureMatrix[1] * gl_MultiTexCoord1;
  normal = normalEncode(gl_NormalMatrix * gl_Normal);
}
#endif
