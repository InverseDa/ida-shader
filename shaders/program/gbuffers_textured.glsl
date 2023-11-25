#include "/lib/common.glsl"

// =====================================================================================
// ============================== Fragment Shader ======================================
// =====================================================================================
#ifdef FRAGMENT_SHADER
    uniform sampler2D texture;
    uniform int fogMode;

    varying vec4 color;
    varying vec4 texcoord;
    varying vec2 normal;
    varying float vertexToCameraDistance;

    /* DRAWBUFFERS:02 */
    void main() {
        // color: the biome color, texture: gray texture color
        // texture * color = RealColor
        gl_FragData[0] = texture2D(texture, texcoord.st) * color;
        gl_FragData[1] = vec4(normal, 0.0, 1.0);
        // 9729 - linear fog
        // 2048 - exp fog
        if(fogMode == 9729)
            gl_FragData[0].rgb = mix(gl_Fog.color.rgb, gl_FragData[0].rgb,
                                clamp((gl_Fog.end - vertexToCameraDistance) / (gl_Fog.end - gl_Fog.start), 0.0, 1.0));
        else if(fogMode == 2048) {
            gl_FragData[0].rgb = mix(gl_Fog.color.rgb, gl_FragData[0].rgb, 
                                    clamp(exp(-vertexToCameraDistance * gl_Fog.density), 0.0, 1.0));
        } 
    }
#endif

// =====================================================================================
// ============================== Fragment Shader ======================================
// =====================================================================================
#ifdef VERTEX_SHADER
    varying vec4 color;
    varying vec4 texcoord;
    varying vec2 normal;
    varying float vertexToCameraDistance;

    vec2 normalEncode(vec3 norm) {
        vec2 ret = normalize(norm.xy) * (sqrt(-norm.z * 0.5 + 0.5));
        ret = ret * 0.5 + 0.5;
        return ret;
    }

    void main() {
        // position in camera(steve)
        vec4 positionInView = gl_ModelViewMatrix * gl_Vertex;
        gl_Position = gl_ProjectionMatrix * positionInView;
        // the length from object vertex to camera center
        vertexToCameraDistance = length(positionInView.xyz);

        color = gl_Color;
        texcoord = gl_TextureMatrix[0] * gl_MultiTexCoord0;
        vec3 norm = gl_NormalMatrix * gl_Normal;
        normal = normalEncode(norm);
    }
#endif