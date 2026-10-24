#include "/lib/constant.glsl"
#include "/lib/post/bloom.glsl"

// =====================================================================================
// ============================== Fragment Shader ======================================
// =====================================================================================
#ifdef FRAGMENT_SHADER
uniform sampler2D colortex6;

in vec4 texcoord;

/* DRAWBUFFERS:7 */
void main() {
    if (BLOOM_STRENGTH <= 0.0) {
        gl_FragData[0] = vec4(0.0, 0.0, 0.0, 1.0);
        return;
    }
    // Positive normalized weights preserve the prefilter's finite HDR bound.
    gl_FragData[0] = vec4(blurBloom(colortex6, texcoord.st), 1.0);
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
