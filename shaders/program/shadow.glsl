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
out vec4 texcoord;

void main() {
    gl_Position = ftransform();
    gl_Position.xy = getFishEyeCoord(gl_Position.xy);
    texcoord = gl_TextureMatrix[0] * gl_MultiTexCoord0;
}
#endif