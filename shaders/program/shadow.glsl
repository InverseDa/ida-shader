#include "/lib/constant.glsl"
#include "/lib/util/functions.glsl"

// =============================================================================
// ============================= Fragment Shader ===============================
// =============================================================================
#ifdef FRAGMENT_SHADER
uniform sampler2D texture;

in vec4 texcoord;

void main() {
    gl_FragData[0] = texture2D(texture, texcoord.st);
}
#endif

// =============================================================================
// ============================== Vertex Shader ================================
// =============================================================================
#ifdef VERTEX_SHADER
uniform vec3 cameraPosition;
uniform float frameTimeCounter;
uniform sampler2D noisetex;
uniform mat4 shadowModelView;
uniform mat4 shadowModelViewInverse;
attribute vec4 mc_Entity;
attribute vec4 mc_midTexCoord;
#include "/lib/materials/methods/foliage.glsl"
out vec4 texcoord;

void main() {
    vec4 shadowView = gl_ModelViewMatrix * gl_Vertex;
    vec3 relativeWorld = (shadowModelViewInverse * shadowView).xyz;
    relativeWorld += foliageOffset(relativeWorld, mc_Entity.x, gl_MultiTexCoord0.st, mc_midTexCoord.st);
    gl_Position = gl_ProjectionMatrix * shadowModelView * vec4(relativeWorld, 1.0);
    gl_Position.xy = getFishEyeCoord(gl_Position.xy / gl_Position.w) * gl_Position.w;
    texcoord = gl_TextureMatrix[0] * gl_MultiTexCoord0;
}
#endif