#include "/lib/constant.glsl"
#include "/lib/util/functions.glsl"
#include "/lib/materials/materialData.glsl"

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
uniform mat4 gbufferModelView;
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

float getNoonLightFactor() {
    float dayDistance = abs(float(worldTime) - 6000.0) / 6000.0;
    return 1.0 - smoothstep(0.0, 1.0, clamp(dayDistance, 0.0, 1.0));
}

// ========================== Draw Shadow ==========================
#include "/lib/lighting/shadow.glsl"

// ===================== Ambient Occlusion =====================
#include "/lib/lighting/ssao.glsl"

// ========================== Draw Sky ==========================
#include "/lib/materials/lighting/sky.glsl"

// ======================== Surface Light ========================
#include "/lib/lighting/surface.glsl"

// ========================== Draw Water ==========================
#include "/lib/materials/translucents/water.glsl"

vec3 applySunDirectLight(
    vec3 color,
    vec3 normal,
    vec3 viewPos,
    vec4 materialData,
    float shadow,
    float ssao
) {
    MaterialLightingProfile profile = getMaterialLightingProfile(materialData);
    vec3 surfaceNormal = normalize(normal);
    vec3 viewDir = normalize(-viewPos);
    vec3 lightDir = normalize(sunPosition);
    float noL = max(dot(surfaceNormal, lightDir), 0.0);
    float daylight = 1.0 - nightValue;
    float noonLight = getNoonLightFactor();
    float sunExposure = smoothstep(0.02, 0.55, noL) * shadow * daylight;
    float sunlightStrength = mix(0.82, 1.32, noonLight) * daylight;

    float roughness = adjustMaterialRoughness(materialData, getMaterialRoughness(materialData));
    float metallic = getMaterialMetallic(materialData);
    float materialAo = getMaterialAO(materialData) * ssao;
    vec3 skyReflection = getSkyRadiance(reflect(-viewDir, surfaceNormal));
    vec3 lightRadiance = getDirectionalLightRadiance(sunColor, nightValue) * sunlightStrength;
    SurfaceLightingResult lighting = evaluateSurfaceLighting(
        color,
        surfaceNormal,
        viewDir,
        lightDir,
        lightRadiance,
        skyColor,
        skyReflection,
        roughness,
        metallic,
        materialAo,
        shadow,
        profile
    );

    float shadowTone = mix(0.68, 1.0, smoothstep(0.02, 1.0, shadow));
    float aoTone = mix(0.86, 1.0, ssao);
    vec3 baseLight = color * shadowTone * aoTone * mix(0.96, 1.08, noonLight);
    vec3 indirectFloor = color * skyColor * (0.10 + 0.08 * noonLight) * materialAo * profile.ambientScale;
    vec3 pbrLight = lighting.direct * (0.18 + 0.42 * sunExposure) + lighting.ambient * 1.55;
    vec3 emission = color * profile.emissionStrength;
    return baseLight + pbrLight + indirectFloor + emission;
}

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
    vec4 materialData = texture2D(colortex5, texcoord.st);
    if (dot(materialData, materialData) < 0.0001) {
        materialData = getDefaultMaterialData();
    }

    vec3 viewPos = reconstructViewPos(texcoord.st, depth0, gbufferProjectionInverse);
    vec3 worldPos = viewToWorldPos(viewPos, gbufferModelViewInverse);

    vec3 viewPosNotWater = reconstructViewPos(texcoord.st, depth1, gbufferProjectionInverse);
    vec3 worldPosNotWaterForShadow = viewToWorldPos(viewPosNotWater, gbufferModelViewInverse);

    bool isWater = isMaterial(materialData, MATERIAL_ID_WATER);
    bool isIce = isMaterial(materialData, MATERIAL_ID_ICE);
    bool isSky = isMaterial(materialData, MATERIAL_ID_SKY);
    float ssao = (!isSky && !isWater) ? getScreenSpaceAmbientOcclusion(texcoord.st, viewPosNotWater, normal) : 1.0;
    
    // calculate shadow
    float underWaterShadowFadeOut = UnderWaterFadeOut(depth0, depth1, viewPos, normal); // what it looks like the water shadow (not in water)
    float shadow = (!isSky && !isWater) ? shadowMapping(worldPosNotWaterForShadow, normal, underWaterShadowFadeOut) : 1.0;
    if (!isSky && !isWater) {
        color.rgb = applySunDirectLight(color.rgb, normal, viewPosNotWater, materialData, shadow, ssao);
    }
    // draw sky
    color.rgb = drawSky(color.rgb, viewPos, isSky);
    // draw water
    if (isWater) {
        color.rgb = drawWater(color.rgb, worldPos, viewPos, viewPosNotWater, normal);
    } else if (isIce) {
        color.rgb = drawIce(color.rgb, worldPos, viewPos, normal);
    }
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
