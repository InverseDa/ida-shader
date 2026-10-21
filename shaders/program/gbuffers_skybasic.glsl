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
in float vertexToCameraDistance;
in vec3 normal;

/* DRAWBUFFERS:025 */
void main() {
  // Vanilla cloud and sky geometry are replaced in composite.
  gl_FragData[0] = vec4(0.0);
  gl_FragData[1] = vec4(normalEncode(safeNormal(normal)), 0.0, 1.0);
  gl_FragData[2] = getSkyMaterialData();
}
#endif

// =============================================================================
// ============================== Vertex Shader ================================
// =============================================================================
#ifdef VERTEX_SHADER
out vec4 color;
out vec4 texcoord;
out float vertexToCameraDistance;
out vec3 normal;

void main() {
  // position in camera(steve)
  vec4 positionInView = gl_ModelViewMatrix * gl_Vertex;
  gl_Position = gl_ProjectionMatrix * positionInView;
  // the length from object vertex to camera center
  vertexToCameraDistance = length(positionInView.xyz);

  color = gl_Color;
  texcoord = gl_TextureMatrix[0] * gl_MultiTexCoord0;
  normal = gl_NormalMatrix * gl_Normal;
}
#endif
