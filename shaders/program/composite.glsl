#include "/lib/constant.glsl"
#include "/lib/util/functions.glsl"

// =============================================================================
// ============================= Fragment Shader ===============================
// =============================================================================
#ifdef FRAGMENT_SHADER
// ===================== Shader Configuration =====================
const int RG16 = 0;
const int gnormalFormat = RG16;
// const int noiseTextureResolution = 256;
// =================== End Shader Configuration ===================

uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferModelViewInverse;
uniform mat4 shadowModelView;
uniform mat4 shadowProjection;
uniform sampler2D depthtex0;
uniform sampler2D depthtex1;
uniform sampler2D shadowtex1;
uniform sampler2D colortex0; // texture
uniform sampler2D colortex2; // normal
uniform sampler2D colortex5; // block flag color
uniform sampler2D noisetex;
uniform vec3 sunPosition;
uniform vec3 moonPosition;
uniform vec3 cameraPosition;
uniform float viewWidth;
uniform float viewHeight;
uniform float far;
uniform float near;
uniform float frameTimeCounter;
uniform int worldTime;

in vec4 texcoord;
in vec3 skyColor;
in vec3 sunColor;
in float nightValue;

// ========================== Draw Shadow ==========================
#include "/lib/materials/lighting/shadowSample.glsl"

// ========================== Draw Sky ==========================
#include "/lib/materials/lighting/sky.glsl"

// ========================== Draw Water ==========================
#include "/lib/materials/translucents/water.glsl"

// ============================== MAIN ==============================
/* DRAWBUFFERS:0 */
void main() {
    // near <= positionInWorld.z
    // depth0 include water and sky
    // depth1 not include water and sky
    float depth0 = texture2D(depthtex0, texcoord.st).x;
    float depth1 = texture2D(depthtex1, texcoord.st).x;

    vec4 color = texture2D(colortex0, texcoord.st);
    vec3 normal = normalDecode(texture2D(colortex2, texcoord.st).rg);

    vec4 viewPos = gbufferProjectionInverse * vec4(texcoord.st * 2.0 - 1.0, depth0 * 2.0 - 1.0, 1.0);
    viewPos /= viewPos.w;
    vec4 worldPos = gbufferModelViewInverse * viewPos;

    vec4 viewPosNotWater = gbufferProjectionInverse * vec4(texcoord.st * 2.0 - 1.0, depth1 * 2.0 - 1.0, 1.0);
    viewPosNotWater /= viewPosNotWater.w;
    vec4 worldPosNotWaterForShadow = gbufferModelViewInverse * viewPosNotWater;

    vec4 blockVector = texture2D(colortex5, texcoord.st);
    bool isWater = (blockVector == WATER_FLAG) ? true : false;
    
    // calculate shadow
    float underWaterShadowFadeOut = UnderWaterFadeOut(depth0, depth1, viewPos, normal); // what it looks like the water shadow (not in water)
    color.rgb *= shadowMapping(worldPosNotWaterForShadow, normal, underWaterShadowFadeOut);
    // draw sky
    color.rgb = drawSky(color.rgb, viewPos, worldPos);
    // draw water
    if (isWater) {
        color.rgb = drawWater(color.rgb, worldPos, viewPos, normal);
    }
    float n = PerlinWaterNoise(texcoord.st);
    gl_FragData[0] = vec4(normal, 1);
    gl_FragData[0] = vec4(color.rgb, 1);
    // gl_FragData[0] = vec4(n, n, n, 1);
}
#endif

// =============================================================================
// ============================== Vertex Shader ================================
// =============================================================================
#ifdef VERTEX_SHADER 
uniform vec3 sunPosition;
uniform vec3 moonPosition;
uniform int worldTime;

out vec4 texcoord;
out vec3 skyColor;
out vec3 sunColor;
out float nightValue;

void main() {
    gl_Position = ftransform();
    texcoord = gl_MultiTexCoord0;

    // 颜色插值
    int hour = worldTime / 1000;
    int next = (hour + 1 < 24) ? hour + 1 : 0;
    float delta = float(worldTime - hour * 1000) / 1000.0;
    skyColor = mix(skyColorArr[hour], skyColorArr[next], delta);
    sunColor = mix(sunColorArr[hour], sunColorArr[next], delta);

    nightValue = 0.f;
    // 昼夜交替插值, 0.f表示白天, 1.f表示黑夜
    if (worldTime > 12000 && worldTime < 13000) {
        // 此时傍晚
        nightValue = 1.0 - (13000 - worldTime) / 1000.f;
    } else if (worldTime >= 13000 && worldTime <= 23000) {
        // 此时夜晚
        nightValue = 1.0;
    } else if (worldTime > 23000 && worldTime < 24000) {
        // 此时凌晨
        nightValue = (24000 - worldTime) / 1000.f;
    }
}
#endif