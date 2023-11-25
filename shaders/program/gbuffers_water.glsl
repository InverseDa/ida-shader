#include "/lib/common.glsl"

// =====================================================================================
// ============================== Fragment Shader ======================================
// =====================================================================================
#ifdef FRAGMENT_SHADER
    uniform sampler2D texture;
    uniform sampler2D lightmap;
    uniform int fogMode;

    varying vec4 color;
    varying vec4 texcoord;
    varying vec4 lmcoord;
    varying vec3 skyColor;
    varying vec2 normal;
    varying float blockID;

    /* DRAWBUFFERS:02 */
    void main() {
        vec4 light = texture2D(lightmap, lmcoord.st);
        vec4 oColor = color;
        if (blockID != 10092.0) {
            oColor = texture2D(texture, texcoord.st) * light * color;
        } else {
            oColor = vec4(vec3(0.05, 0.2, 0.3), 0.5) * light;
        }
        gl_FragData[0] = oColor;
        gl_FragData[1] = vec4(normal, 0.0, 1.0);
    }
#endif

// =====================================================================================
// ============================== Fragment Shader ======================================
// =====================================================================================
#ifdef VERTEX_SHADER
    attribute vec4 mc_Entity;
    uniform mat4 gbufferProjection;
    uniform mat4 gbufferProjectionInverse;
    uniform mat4 gbufferModelView;
    uniform mat4 gbufferModelViewInverse;

    uniform vec3 cameraPosition;

    uniform int worldTime;
    uniform float frameTimeCounter;

    varying vec4 color;
    varying vec4 texcoord;
    varying vec4 lmcoord;
    varying vec2 normal;
    varying float blockID;

    vec4 bump() {
        vec4 pos = gl_Vertex;
        pos.xyz += cameraPosition;
        pos.y += 0.10 * (sin(pos.x + frameTimeCounter) + cos(pos.z + frameTimeCounter));
        pos.xyz -= cameraPosition;
        return gbufferModelView * pos;
    }

    vec2 normalEncode(vec3 norm) {
        vec2 ret = normalize(norm.xy) * (sqrt(-norm.z * 0.5 + 0.5));
        ret = ret * 0.5 + 0.5;
        return ret;
    }

    // mc_Entity.x == 79.0  ice;
    // mc_Entity.x == 90.0  netherPortal;
    // mc_Entity.x == 95.0  stainedGlass;
    // mc_Entity.x == 160.0 stainedGlassPlane;

    void main() {
        vec4 positionInView;
        // 对水计算
        blockID = int(mc_Entity.x);
        positionInView = (blockID == 10092.0) ? gbufferModelView * gl_Vertex : gbufferModelView * gl_Vertex;
        color = gl_Color;
        normal = normalEncode(gl_NormalMatrix * gl_Normal);
        gl_Position = gbufferProjection * positionInView;
        // texture uv
        texcoord = gl_TextureMatrix[0] * gl_MultiTexCoord0;
        lmcoord = gl_TextureMatrix[1] * gl_MultiTexCoord1;
    }
#endif