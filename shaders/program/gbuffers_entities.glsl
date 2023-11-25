#include "/lib/common.glsl"

// =====================================================================================
// ============================== Fragment Shader ======================================
// =====================================================================================
#ifdef FRAGMENT_SHADER

uniform sampler2D texture;
uniform sampler2D lightmap;

in vec4 color;
in vec4 texcoord;
in vec4 lmcoord;
in vec2 normal;

void main() {
    vec4 light = texture2D(lightmap, lmcoord.st);
    gl_FragData[0] = texture2D(texture, texcoord.st) * light * color;
}
#endif

// =====================================================================================
// =============================== Vertex Shader =======================================
// =====================================================================================
#ifdef VERTEX_SHADER

out vec4 color;
out vec4 texcoord;
out vec4 lmcoord;
out vec2 normal;

void main() {
    gl_Position = ftransform();
    color = gl_Color;
    normal = normalEncode(gl_NormalMatrix * gl_Normal);
    texcoord = gl_TextureMatrix[0] * gl_MultiTexCoord0;
    lmcoord = gl_TextureMatrix[1] * gl_MultiTexCoord1;
}
#endif