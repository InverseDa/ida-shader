#include "/lib/common.glsl"

// =====================================================================================
// ============================== Fragment Shader ======================================
// =====================================================================================
#ifdef FRAGMENT_SHADER
    uniform sampler2D colortex0;    //color
    uniform sampler2D colortex1;    //depth
    uniform sampler2D colortex2;    //normal
    uniform sampler2D colortex4;    //blockId
    uniform sampler2D depthtex0;    //depth0
    uniform sampler2D depthtex1;    //depth1
    
    in vec4 texcoord;
    
    vec3 ACESToneMapping(vec3 color, float adapted_lum) {
    	const float A = 2.51f;
    	const float B = 0.03f;
    	const float C = 2.43f;
    	const float D = 0.59f;
    	const float E = 0.14f;
    	color *= adapted_lum;
    	return (color * (A * color + B)) / (color * (C * color + D) + E);
    }
    
    vec3 saturation(vec3 color, float factor) {
        float brightness = dot(color, vec3(0.2125, 0.7154, 0.0721));
        return mix(vec3(brightness), color, factor);
    }
    
    void main() {
        vec4 color = texture2D(colortex0, texcoord.st);
        color.rgb = ACESToneMapping(color.rgb, 1.0);
        color.rgb = saturation(color.rgb, 1.45);
        gl_FragData[0] = color;
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