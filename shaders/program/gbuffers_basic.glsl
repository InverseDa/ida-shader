#include "/lib/common.glsl"

// =====================================================================================
// ============================== Fragment Shader ======================================
// =====================================================================================
#ifdef FRAGMENT_SHADER
    varying vec4 color;
    varying vec2 normal;
    
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
    varying vec4 color;
    varying vec2 normal;

    vec2 normalEncode(vec3 norm) {
        vec2 ret = normalize(norm.xy) * (sqrt(-norm.z * 0.5 + 0.5));
        ret = ret * 0.5 + 0.5;
        return ret;
    }

    void main() {
        gl_Position = ftransform();
        color = gl_Color;
        vec3 norm = gl_NormalMatrix * gl_Normal;
        normal = normalEncode(norm);
    }
#endif