#include "/lib/common.glsl"

// =============================================================================
// ============================= Fragment Shader ===============================
// =============================================================================
#ifdef FRAGMENT_SHADER
in vec4 color;
in vec3 normal;

/* DRAWBUFFERS:02 */
void main() {
    gl_FragData[0] = color;
    gl_FragData[1] = vec4(normal * 0.5 + 0.5, 1.0);
}
#endif

// =============================================================================
// ============================== Vertex Shader ================================
// =============================================================================
#ifdef VERTEX_SHADER
out vec4 color;
out vec3 normal;

void main() {
    gl_Position = ftransform();
    color = gl_Color;
    normal = normalize(gl_NormalMatrix * gl_Normal);
}
#endif