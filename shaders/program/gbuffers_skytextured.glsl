#include "/lib/constant.glsl"
#include "/lib/util/functions.glsl"
#include "/lib/materials/materialData.glsl"

// =============================================================================
// ============================= Fragment Shader ===============================
// =============================================================================
#ifdef FRAGMENT_SHADER
uniform sampler2D texture;

in vec4 color;
in vec4 texcoord;
in vec2 normal;

/* DRAWBUFFERS:025 */
void main() {
  // color: the biome color, texture: gray texture color
  // texture * color = RealColor
  // 去掉原始太阳和月亮
  gl_FragData[0] = vec4(0.0);
  gl_FragData[1] = vec4(normal, 0.0, 1.0);
  gl_FragData[2] = getSkyMaterialData();
}
#endif

// =============================================================================
// ============================== Vertex Shader ================================
// =============================================================================
#ifdef VERTEX_SHADER
out vec4 color;
out vec4 texcoord;
out vec2 normal;

void main() {
  // position in camera(steve)
  vec4 positionInView = gl_ModelViewMatrix * gl_Vertex;
  gl_Position = gl_ProjectionMatrix * positionInView;

  color = gl_Color;
  texcoord = gl_TextureMatrix[0] * gl_MultiTexCoord0;
  normal = normalEncode(gl_NormalMatrix * gl_Normal);

}
#endif
