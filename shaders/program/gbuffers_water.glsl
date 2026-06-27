#include "/lib/constant.glsl"
#include "/lib/util/functions.glsl"
#include "/lib/materials/materialData.glsl"
#include "/lib/materials/pbr.glsl"

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
    float entityId = float(mat);
    vec4 materialData = getTranslucentMaterialData(entityId);
    vec2 packedNormal = normal;
    if (isIceEntityId(entityId)) {
        oColor = texture2D(texture, texcoord.st) * light * color;
        oColor.a = 1.0;
        vec3 geometryNormal = normalDecode(normal);
        PbrMaterialSample pbr = samplePbrMaterial(texcoord.st, geometryNormal, viewPos.xyz, materialData);
        packedNormal = normalEncode(pbr.normalView);
        materialData = pbr.materialData;
    } else if (isWaterEntityId(entityId)) {
        oColor = vec4(vec3(0.1, 0.2, 0.4), 0.5);
    } else {
        oColor = texture2D(texture, texcoord.st) * light * color;
    }
    /* DRAWBUFFERS:025 */
    gl_FragData[0] = oColor;
    gl_FragData[1] = vec4(packedNormal, 0.0, 1.0);
    gl_FragData[2] = materialData;
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
    mat = int(mc_Entity.x);
    viewPos = gbufferModelView * gl_Vertex;
    color = gl_Color;
    normal = normalEncode(gl_NormalMatrix * gl_Normal);
    gl_Position = gbufferProjection * viewPos;
    // texture uv
    texcoord = gl_TextureMatrix[0] * gl_MultiTexCoord0;
    lmcoord = gl_TextureMatrix[1] * gl_MultiTexCoord1;
}
#endif
