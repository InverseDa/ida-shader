#include "/lib/common.glsl"

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
in vec2 normal;

/* DRAWBUFFERS:024 */
void main() {
  // color: the biome color, texture: gray texture color
  // texture * color = RealColor
  gl_FragData[0] =
      texture2D(texture, texcoord.st) * texture2D(lightmap, lmcoord.st) * color;
  gl_FragData[1] = vec4(normal, 0.0, 1.0);
  // 9729 - linear fog
  // 2048 - exp fog
  if (fogMode == 9729) {
    gl_FragData[0].rgb = mix(gl_Fog.color.rgb, gl_FragData[0].rgb,
                             clamp((gl_Fog.end - vertexToCameraDistance) /
                                       (gl_Fog.end - gl_Fog.start),
                                   0.0, 1.0));
  } else if (fogMode == 2048) {
    gl_FragData[0].rgb =
        mix(gl_Fog.color.rgb, gl_FragData[0].rgb,
            clamp(exp(-vertexToCameraDistance * gl_Fog.density), 0.0, 1.0));
  }
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
out vec2 normal;

void main() {
  color = gl_Color;
  // 0 - texcoord
  // 1 - lightmap texcoord
  texcoord = gl_TextureMatrix[0] * gl_MultiTexCoord0;
  lmcoord = gl_TextureMatrix[1] * gl_MultiTexCoord1;

  vec3 norm = gl_NormalMatrix * gl_Normal;
  normal = normalEncode(norm);

  vec4 position = gl_Vertex;
  position.xyz += cameraPosition;
  float id = mc_Entity.x;
  if ((id == 10091) && mc_midTexCoord.t >= gl_MultiTexCoord0.t) {
    vec3 noise = texture2D(noisetex, position.xz / 256.0).rgb;
    position.x += sin(frameTimeCounter * 1.8 + noise.x * 10) * 0.2;
    position.z += sin(frameTimeCounter * 1.8 + noise.y * 10) * 0.2;
  }
  position.xyz -= cameraPosition;

  // position in camera(steve)
  vec4 positionInView = gl_ModelViewMatrix * position;
  gl_Position = gl_ProjectionMatrix * positionInView;
  // the length from object vertex to camera center
  vertexToCameraDistance = length(positionInView.xyz);
}
#endif