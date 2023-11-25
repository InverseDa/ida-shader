#include "/lib/common.glsl"

// =====================================================================================
// ============================== Fragment Shader ======================================
// =====================================================================================
#ifdef FRAGMENT_SHADER
    in vec4 color;
    in vec2 normal;
    
    /* DRAWBUFFERS:02 */
    void main() {
        gl_FragData[0] = color;
        gl_FragData[1] = vec4(normal, 0.0, 1.0);
    }
#endif

// =====================================================================================
// ============================== Fragment Shader ======================================
// =====================================================================================
#ifdef VERTEX_SHADER
    out vec4 color;
    out vec2 normal;

    void main() {
        gl_Position = ftransform();
        color = gl_Color;
        vec3 norm = gl_NormalMatrix * gl_Normal;
        normal = normalEncode(norm);
    }
#endif