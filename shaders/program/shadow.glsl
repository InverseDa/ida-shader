#include "/lib/constant.glsl"
#include "/lib/util/functions.glsl"

// =============================================================================
// Fragment Shader
// =============================================================================
#ifdef FRAGMENT_SHADER

uniform sampler2D texture;

in vec4 Texcoord;

void main() {
    gl_FragData[0] = texture2D(texture, Texcoord.st);
}

#endif // FRAGMENT_SHADER

// =============================================================================
// Vertex Shader
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
out vec4 Texcoord;

void main() {
    vec4 ShadowView = gl_ModelViewMatrix * gl_Vertex;
    vec3 RelativeWorld = (shadowModelViewInverse * ShadowView).xyz;
    RelativeWorld += FoliageOffset(RelativeWorld, mc_Entity.x, gl_MultiTexCoord0.st, mc_midTexCoord.st);
    gl_Position = gl_ProjectionMatrix * shadowModelView * vec4(RelativeWorld, 1.0);
    gl_Position.xy = GetFishEyeCoord(gl_Position.xy / gl_Position.w) * gl_Position.w;
    Texcoord = gl_TextureMatrix[0] * gl_MultiTexCoord0;
}

#endif // VERTEX_SHADER
