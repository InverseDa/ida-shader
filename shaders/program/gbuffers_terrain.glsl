#include "/lib/constant.glsl"
#include "/lib/util/functions.glsl"
#include "/lib/materials/materialData.glsl"
#include "/lib/materials/pbr.glsl"

// =============================================================================
// ============================= Fragment Shader ===============================
// =============================================================================
#ifdef FRAGMENT_SHADER
const int R32F = 114;
const int colortex4Format = R32F;

uniform sampler2D texture;
uniform sampler2D lightmap;
uniform int fogMode;
uniform float rainStrength;

in vec4 color;
in vec4 texcoord;
in vec4 lmcoord;
in float vertexToCameraDistance;
flat in float materialId;
in vec2 normal;
in vec3 viewPos;

/* DRAWBUFFERS:025 */
void main() {
  // color: the biome color, texture: gray texture color
  // texture * color = RealColor
  vec3 geometryNormal = normalDecode(normal);
  vec4 materialData = getTerrainMaterialData(materialId);
  PbrMaterialSample pbr = samplePbrMaterial(texcoord.st, geometryNormal, viewPos, materialData);
  gl_FragData[0] = texture2D(texture, texcoord.st) * texture2D(lightmap, lmcoord.st) * color;
  gl_FragData[1] = vec4(normalEncode(pbr.normalView), 0.0, 1.0);
  gl_FragData[2] = pbr.materialData;
}
#endif

// =============================================================================
// ============================== Vertex Shader ================================
// =============================================================================
#ifdef VERTEX_SHADER
uniform float frameTimeCounter;
uniform int worldTime;
uniform sampler2D noisetex;
uniform vec3 cameraPosition;

attribute vec4 mc_Entity;
attribute vec4 mc_midTexCoord;

out vec4 color;
out vec4 texcoord;
out vec4 lmcoord;
out float vertexToCameraDistance;
flat out float materialId;
out vec2 normal;
out vec3 viewPos;

void main() {
  color = gl_Color;
  // 0 - texcoord
  // 1 - lightmap texcoord
  texcoord = gl_TextureMatrix[0] * gl_MultiTexCoord0;
  lmcoord = gl_TextureMatrix[1] * gl_MultiTexCoord1;

  vec4 position = gl_Vertex;
  position.xyz += cameraPosition;
  float id = mc_Entity.x;
  materialId = id;
  if ((id == 10091) && mc_midTexCoord.t >= gl_MultiTexCoord0.t) {
    vec3 noise = texture2D(noisetex, position.xz / 256.0).rgb;
    position.x += sin(frameTimeCounter * 1.8 + noise.x * 10) * 0.2;
    position.z += sin(frameTimeCounter * 1.8 + noise.y * 10) * 0.2;
  }
  position.xyz -= cameraPosition;

  // position in camera(steve)
  vec4 positionInView = gl_ModelViewMatrix * position;
  viewPos = positionInView.xyz;
  gl_Position = gl_ProjectionMatrix * positionInView;
  // the length from object vertex to camera center
  vertexToCameraDistance = length(positionInView.xyz);
  normal = normalEncode(gl_NormalMatrix * gl_Normal);
}
#endif
