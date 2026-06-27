#include "/lib/constant.glsl"
#include "/lib/util/functions.glsl"
#include "/lib/materials/materialData.glsl"
#include "/lib/materials/pbr.glsl"

// =============================================================================
// ============================= Fragment Shader ===============================
// =============================================================================
#ifdef FRAGMENT_SHADER
uniform sampler2D texture;
uniform int fogMode;

in vec4 color;
in vec4 texcoord;
in float vertexToCameraDistance;
in vec2 normal;
in vec3 viewPos;

/* DRAWBUFFERS:025 */
void main() {
  // color: the biome color, texture: gray texture color
  // texture * color = RealColor
  vec3 geometryNormal = normalDecode(normal);
  PbrMaterialSample pbr = samplePbrMaterial(texcoord.st, geometryNormal, viewPos, getDefaultMaterialData());
  gl_FragData[0] = texture2D(texture, texcoord.st) * color;
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
out float vertexToCameraDistance;
out vec2 normal;
out vec3 viewPos;

void main() {
  // position in camera(steve)
  vec4 positionInView = gl_ModelViewMatrix * gl_Vertex;
  viewPos = positionInView.xyz;
  gl_Position = gl_ProjectionMatrix * positionInView;
  // the length from object vertex to camera center
  vertexToCameraDistance = length(positionInView.xyz);

  color = gl_Color;
  texcoord = gl_TextureMatrix[0] * gl_MultiTexCoord0;
  normal = normalEncode(gl_NormalMatrix * gl_Normal);
}
#endif
