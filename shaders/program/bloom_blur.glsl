#include "/lib/constant.glsl"
#include "/lib/post/bloom.glsl"

// =====================================================================================
// ============================== Fragment Shader ======================================
// =====================================================================================
#ifdef FRAGMENT_SHADER
uniform sampler2D colortex6;
uniform float viewWidth;
uniform float viewHeight;

in vec4 texcoord;

/* DRAWBUFFERS:7 */
void main() {
    vec2 texel = 1.0 / vec2(textureSize(colortex6, 0));
    vec2 uv = texcoord.st;

    vec3 bloom = vec3(0.0);
    bloom += sampleBloomBlur(colortex6, uv, texel, 1.25) * 0.38;
    bloom += sampleBloomBlur(colortex6, uv, texel, 3.20) * 0.30;
    bloom += sampleBloomBlur(colortex6, uv, texel, 7.25) * 0.23;
    bloom += sampleBloomBlur(colortex6, uv, texel, 15.5) * 0.09;

    gl_FragData[0] = vec4(clampBloomFireflies(bloom), 1.0);
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
