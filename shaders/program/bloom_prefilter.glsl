#include "/lib/constant.glsl"
#include "/lib/post/bloom.glsl"

// =====================================================================================
// ============================== Fragment Shader ======================================
// =====================================================================================
#ifdef FRAGMENT_SHADER
uniform sampler2D colortex0;
uniform float viewWidth;
uniform float viewHeight;

in vec4 texcoord;

/* DRAWBUFFERS:6 */
void main() {
    vec2 texel = 1.0 / vec2(viewWidth, viewHeight);
    vec2 uv = texcoord.st;

    vec3 bloom = vec3(0.0);
    bloom += sampleBloomTent(colortex0, uv, texel, 1.0) * 0.44;
    bloom += sampleBloomTent(colortex0, uv, texel, 2.6) * 0.28;
    bloom += sampleBloomTent(colortex0, uv, texel, 5.8) * 0.18;
    bloom += sampleBloomTent(colortex0, uv, texel, 12.0) * 0.10;

    gl_FragData[0] = vec4(bloom, 1.0);
}
#endif

// =====================================================================================
// =============================== Vertex Shader =======================================
// =====================================================================================
#ifdef VERTEX_SHADER
out vec4 texcoord;

void main() {
    gl_Position = ftransform();
    texcoord = gl_MultiTexCoord0;
}
#endif
