#include "/lib/constant.glsl"
#include "/lib/util/functions.glsl"
#include "/lib/materials/materialData.glsl"

// =============================================================================
// ============================= Fragment Shader ===============================
// =============================================================================
#ifdef FRAGMENT_SHADER
in vec4 color;
in vec2 normal;

/* DRAWBUFFERS:025 */
void main() {
    gl_FragData[0] = color;
    gl_FragData[1] = vec4(normal, 0.0, 1.0);
    gl_FragData[2] = getDefaultMaterialData();
}
#endif

// =============================================================================
// ============================== Vertex Shader ================================
// =============================================================================
#ifdef VERTEX_SHADER
out vec4 color;
out vec2 normal;

void main() {
    gl_Position = ftransform();
    color = gl_Color;
    normal = normalEncode(gl_NormalMatrix * gl_Normal);
}
#endif
