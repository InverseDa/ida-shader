#include "/lib/common.glsl"

// =============================================================================
// ============================= Fragment Shader ===============================
// =============================================================================
#ifdef FRAGMENT_SHADER
uniform sampler2D texture;

in vec4 color;
in vec4 texcoord;
in vec3 normal;

/* DRAWBUFFERS:02 */
void main() {
  // color: the biome color, texture: gray texture color
  // texture * color = RealColor
  gl_FragData[0] = texture2D(texture, texcoord.st) * color;
  gl_FragData[1] = vec4(normal * 0.5 + 0.5, 1.0);
}
#endif

// =============================================================================
// ============================== Vertex Shader ================================
// =============================================================================
#ifdef VERTEX_SHADER
out vec4 color;
out vec4 texcoord;
out vec3 normal;

void main() {
  // position in camera(steve)
  vec4 positionInView = gl_ModelViewMatrix * gl_Vertex;
  gl_Position = gl_ProjectionMatrix * positionInView;

  color = gl_Color;
  texcoord = gl_TextureMatrix[0] * gl_MultiTexCoord0;

  normal = normalize(gl_NormalMatrix * gl_Normal);
}
#endif