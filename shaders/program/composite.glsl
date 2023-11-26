#include "/lib/common.glsl"

// =============================================================================
// ============================= Fragment Shader ===============================
// =============================================================================
#ifdef FRAGMENT_SHADER
// ===================== Shader Configuration =====================
const int RG16 = 0;
const int gnormalFormat = RG16;
const int shadowMapResolution = 2048;   // 阴影分辨率 默认 1024
const float	sunPathRotation	= -40.0;    // 太阳偏移角 默认 0
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
uniform sampler2D colortex0;
uniform sampler2D colortex5;
uniform sampler2D noisetex;
uniform sampler2D gnormal;
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
float UnderWaterFadeOut(float d0, float d1, vec4 viewPos, vec3 normal) {
    d0 = screenDepthToLinerDepth(near, far, d0);
    d1 = screenDepthToLinerDepth(near, far, d1);

    float cosine = dot(normalize(viewPos.xyz), normalize(normal));
    cosine = clamp(abs(cosine), 0, 1);

    return clamp(1.0 - (d1 - d0) * cosine * 0.1, 0, 1);
}

float shadowMapping(vec4 worldPos, vec3 normal, float strength) {
    vec4 positionInSunNDC = shadowProjection * shadowModelView * worldPos;
    positionInSunNDC /= positionInSunNDC.w;
    // fish eye distortion
    positionInSunNDC.xy = getFishEyeCoord(positionInSunNDC.xy);
    positionInSunNDC = positionInSunNDC * 0.5 + 0.5; // screen space [0, 1]
    
    float currentDepth = positionInSunNDC.z;
    float dis = length(worldPos.xyz) / far;
    float shadowStrength = strength * 0.6 * (1 - dis) * (1 - 0.6 * nightValue); // 控制昼夜阴影强度

    int radius = 1;
    float shade = pow(radius * 2 + 1, 2);
    for(int x = -radius; x <= radius; x++) {
        for(int y = -radius; y <= radius; y++) {
            vec2 offset = vec2(x, y) / shadowMapResolution;
            float closest = texture2D(shadowtex1, positionInSunNDC.xy + offset).x;
            if (closest + 0.001 <= currentDepth && dis < 0.99) {
                shade -= 1.0;
            }
        }
    }
    shade /= pow(radius * 2 + 1, 2);
    
    return shade * shadowStrength + (1 - shadowStrength);
}


// ========================== Draw Sky ==========================
vec3 drawSky(vec3 color, vec4 viewPos, vec4 worldPos) {
    float dis = length(worldPos.xyz) / far;
    float dis2Sun = 1.0 - dot(normalize(viewPos.xyz), normalize(sunPosition));
    float dis2Moon = 1.0 - dot(normalize(viewPos.xyz), normalize(moonPosition));
    // draw Sun
    vec3 drawSun = vec3(0.f);
    if (dis2Sun < 0.005 && dis > 0.99999) {
        drawSun = sunColor * 2 * (1.f - nightValue);
    }
    // draw Moon
    vec3 drawMoon = vec3(0.f);
    if (dis2Moon < 0.05 && dis > 0.99999) {
        drawMoon = sunColor * 2 * nightValue;
    }
    // fog with sun color mix
    float sunMixFactor = clamp(1.0 - dis2Sun, 0, 1) * (1.f - nightValue);
    vec3 finalColor = mix(skyColor, sunColor, pow(sunMixFactor, 4));
    // fog with moon color mix
    float moonMixFactor = clamp(1.0 - dis2Moon, 0, 1) * nightValue;
    finalColor = mix(finalColor, sunColor, pow(moonMixFactor, 4));

    return mix(color, finalColor, clamp(pow(dis, 3), 0, 1)) + drawSun + drawMoon;
}

// ========================== Draw Water ==========================
#include "/lib/materials/methods/wavingBlock.glsl"
vec3 drawWater(vec3 color, vec4 worldPos, vec4 viewPos, vec3 normal) {
    worldPos.xyz += cameraPosition;
    float wave = GetWave(worldPos);
    vec3 finalColor = skyColor;
    // finalColor *= wave;

    float cosine = dot(normalize(viewPos.xyz), normalize(normal)); 
    cosine = clamp(abs(cosine), 0, 1);
    float factor = pow(1.0 - cosine, 4);
    finalColor = mix(color, finalColor, factor); 

    return finalColor;
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
    vec3 normal = texture2D(gnormal, texcoord.st).rgb * 2 - 1;

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
        // color.rgb = drawWater(color.rgb, worldPos, viewPos, normal);
    }
    gl_FragData[0] = color;
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
        nightValue = 1.f;
    } else if (worldTime > 23000 && worldTime < 24000) {
        // 此时凌晨
        nightValue = (24000 - worldTime) / 1000.f;
    }
}
#endif