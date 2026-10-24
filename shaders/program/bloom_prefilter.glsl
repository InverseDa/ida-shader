#include "/lib/constant.glsl"
#include "/lib/post/bloom.glsl"

// =============================================================================
// Fragment Shader
// =============================================================================
#ifdef FRAGMENT_SHADER

uniform sampler2D colortex0;

in vec4 Texcoord;

/* DRAWBUFFERS:6 */
void main() {
    // Compile-time setting: keep the target defined but skip all texture work.
    if (BLOOM_STRENGTH <= 0.0) {
        gl_FragData[0] = vec4(0.0, 0.0, 0.0, 1.0);
        return;
    }
    gl_FragData[0] = vec4(PrefilterBloom(colortex0, Texcoord.st), 1.0);
}

#endif // FRAGMENT_SHADER

// =============================================================================
// Vertex Shader
// =============================================================================
#ifdef VERTEX_SHADER

out vec4 Texcoord;

void main() {
    gl_Position = ftransform();
    Texcoord = gl_MultiTexCoord0;
}

#endif // VERTEX_SHADER
