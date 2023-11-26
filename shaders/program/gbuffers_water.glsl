#include "/lib/constant.glsl"
#include "/lib/util/functions.glsl"

// =============================================================================
// ============================= Fragment Shader ===============================
// =============================================================================
#ifdef FRAGMENT_SHADER

uniform sampler2D texture;
uniform sampler2D lightmap;
uniform int fogMode;

flat in int mat;

in vec4 color;
in vec4 texcoord;
in vec4 lmcoord;
in vec2 normal;
in vec4 viewPos;

void main() {
    vec4 light = texture2D(lightmap, lmcoord.st);
    vec4 oColor = color;
    vec4 waterFlag = vec4(1.0);
    if (mat != 10092) {
        oColor = texture2D(texture, texcoord.st) * light * color;
    } else {
        // is water
        oColor = vec4(vec3(0.1, 0.2, 0.4), 0.5);
        waterFlag = WATER_FLAG;
    }
    /* DRAWBUFFERS:025 */
    gl_FragData[0] = oColor;
    gl_FragData[1] = vec4(normal, 0.0, 1.0);
    gl_FragData[2] = waterFlag;
}
#endif

// =============================================================================
// ============================== Vertex Shader ================================
// =============================================================================
#ifdef VERTEX_SHADER
uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform vec3 cameraPosition;
uniform int worldTime;
uniform float frameTimeCounter;

in vec4 mc_Entity;

// `flat` used to disable interpolation
flat out int mat;

out vec4 color;
out vec4 texcoord;
out vec4 lmcoord;
out vec2 normal;
out vec4 viewPos;

// mc_Entity.x == 79.0  ice;
// mc_Entity.x == 90.0  netherPortal;
// mc_Entity.x == 95.0  stainedGlass;
// mc_Entity.x == 160.0 stainedGlassPlane;

// #ifdef WATER_WAVING
#include "/lib/materials/methods/wavingBlock.glsl"
// #endif

void main() {
    // 对水计算
    mat = int(mc_Entity.x);
    viewPos = (mat == 10092) ? gbufferModelView * gl_Vertex
                             : gbufferModelView * gl_Vertex;
    color = gl_Color;
    normal = normalEncode(gl_NormalMatrix * gl_Normal);
    gl_Position = gbufferProjection * viewPos;
    // texture uv
    texcoord = gl_TextureMatrix[0] * gl_MultiTexCoord0;
    lmcoord = gl_TextureMatrix[1] * gl_MultiTexCoord1;
}
#endif