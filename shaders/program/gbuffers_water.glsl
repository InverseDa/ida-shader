#include "/lib/common.glsl"

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
in vec3 skyColor;
in vec2 normal;
in vec4 viewPos;

void main() {
    // 计算视线和法线夹角余弦值
    float cosine = dot(normalize(viewPos.xyz), normalize(normalDecode(normal)));
    cosine = clamp(abs(cosine), 0, 1);
    float factor = pow(1.0 - cosine, 4); // 透射系数

    vec4 light = texture2D(lightmap, lmcoord.st);
    vec4 oColor = color;
    vec4 oNormal = vec4(normal, 0.0, 0.0);
    vec4 waterFlag = vec4(1.0);
    if (mat != 10092) {
        oColor = texture2D(texture, texcoord.st) * light * color;
    } else {
        // is water
        oColor = vec4(mix(skyColor * 0.3, skyColor, factor), 0.75);

        waterFlag = WATER_FLAG;
    }
    /* DRAWBUFFERS:025 */
    gl_FragData[0] = oColor;
    gl_FragData[1] = oNormal;
    gl_FragData[2] = waterFlag;
}
#endif

// =============================================================================
// ============================== Vertex Shader ================================
// =============================================================================
#ifdef VERTEX_SHADER
attribute vec4 mc_Entity;
uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform vec3 cameraPosition;
uniform int worldTime;
uniform float frameTimeCounter;

// `flat` used to disable interpolation
flat out int mat;

out vec4 color;
out vec4 texcoord;
out vec4 lmcoord;
out vec2 normal;
out vec3 skyColor;
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

    // 颜色过渡插值
    int hour = worldTime / 1000;
    int next = (hour + 1 < 24) ? (hour + 1) : (0);
    float delta = float(worldTime - hour * 1000) / 1000;
    // 天空颜色
    skyColor = mix(skyColorArr[hour], skyColorArr[next], delta);
}
#endif