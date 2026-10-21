#include "/lib/constant.glsl"
#include "/lib/util/functions.glsl"
#include "/lib/materials/materialData.glsl"
#include "/lib/materials/pbr.glsl"
#include "/lib/post/taa.glsl"

// =============================================================================
// ============================= Fragment Shader ===============================
// =============================================================================
#ifdef FRAGMENT_SHADER


uniform sampler2D texture;
uniform sampler2D lightmap;

in vec4 color;
in vec4 texcoord;
in vec4 lmcoord;
in float vertexToCameraDistance;
flat in float materialId;
in vec3 normal;
in vec3 viewPos;

/* RENDERTARGETS: 0,2,5,9 */
void main() {
  // color: the biome color, texture: gray texture color
  // texture * color = RealColor
  vec3 geometryNormal = safeNormal(normal);
  vec4 materialData = getTerrainMaterialData(materialId);
  PbrMaterialSample pbr = samplePbrMaterial(texcoord.st, geometryNormal, viewPos, materialData);
  vec4 base = texture2D(texture, texcoord.st) * color;
  gl_FragData[0] = vec4(srgbToLinear(base.rgb), base.a);
  gl_FragData[3] = vec4(srgbToLinear(texture2D(lightmap, lmcoord.st).rgb), 1.0);
  gl_FragData[1] = vec4(normalEncode(pbr.normalView), 0.0, 1.0);
  gl_FragData[2] = pbr.materialData;
}
#endif

// =============================================================================
// ============================== Vertex Shader ================================
// =============================================================================
#ifdef VERTEX_SHADER
uniform float frameTimeCounter;
uniform sampler2D noisetex;
uniform vec3 cameraPosition;

attribute vec4 mc_Entity;
attribute vec4 mc_midTexCoord;

out vec4 color;
out vec4 texcoord;
out vec4 lmcoord;
out float vertexToCameraDistance;
flat out float materialId;
out vec3 normal;
out vec3 viewPos;

#include "/lib/materials/methods/foliage.glsl"

void main() {
  color = gl_Color;
  // 0 - texcoord
  // 1 - lightmap texcoord
  texcoord = gl_TextureMatrix[0] * gl_MultiTexCoord0;
  lmcoord = gl_TextureMatrix[1] * gl_MultiTexCoord1;

  vec4 position = gl_Vertex;
  materialId = mc_Entity.x;
  position.xyz += foliageOffset(position.xyz, materialId, gl_MultiTexCoord0.st, mc_midTexCoord.st);

  // position in camera(steve)
  vec4 positionInView = gl_ModelViewMatrix * position;
  viewPos = positionInView.xyz;
  gl_Position = gl_ProjectionMatrix * positionInView;
  if (materialUsesTaaJitter(getTerrainMaterialData(materialId))) applyTaaJitter(gl_Position);
  // the length from object vertex to camera center
  vertexToCameraDistance = length(positionInView.xyz);
  normal = gl_NormalMatrix * gl_Normal;
}
#endif
