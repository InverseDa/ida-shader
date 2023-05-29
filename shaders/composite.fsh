#version 130
/* DRAWBUFFERS:0 */

#define SHADOW_MAP_BIAS 0.85

// ===================== Shader Configuration =====================
const int RG16 = 0;
const int gnormalFormat = RG16;
const bool shadowHardwareFiltering = true;
const int shadowMapResolution = 2048;
const int noiseTextureResolution = 256;
// =================== End Shader Configuration ===================

uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferModelViewInverse;
uniform mat4 shadowModelView;
uniform mat4 shadowProjection;
uniform sampler2DShadow shadow;
uniform sampler2D depthtex0;
uniform sampler2D depthtex1;
uniform sampler2D gcolor;
uniform sampler2D gnormal;
uniform sampler2D colortex4; // blockId texture
uniform vec3 sunPosition;
uniform float viewWidth;
uniform float viewHeight;
uniform float far;

varying vec4 texcoord;

vec3 normalDecode(vec2 enc) {
    vec4 nn = vec4(2.0 * enc - 1.0, 1.0, -1.0);
    float l = dot(nn.xyz,-nn.xyw);
    nn.z = l;
    nn.xy *= sqrt(l);
    return nn.xyz * 2.0 + vec3(0.0, 0.0, -1.0);
}

vec4 getWorldPositionShadow(vec3 normal, float depth) {
    vec4 positionInView = gbufferProjectionInverse * vec4(texcoord.x * 2.0 - 1.0, texcoord.y * 2.0 - 1.0, depth * 2.0 - 1.0, 1.0);
    positionInView /= positionInView.w;
    vec4 positionInWorld = gbufferModelViewInverse * (positionInView + vec4(normal * 0.05 * sqrt(abs(positionInView.z)), 0.0));
    return positionInWorld;
}

float shadowMapping(vec4 positionInWorld, float dist, vec3 normal) {
    // dist > 0.9, dont render sky's shadow
    if(dist > 0.9) return 0.0;

    float shade = 0.0;
    // the angle bettween normal and light
    float cosine = dot(normalize(sunPosition), normal);

    if(cosine <= 0.1) 
        shade = 1.0;
    else {
        vec4 positionInSunNDC = shadowProjection * shadowModelView * positionInWorld;
        float distb = sqrt(positionInSunNDC.x * positionInSunNDC.x + positionInSunNDC.y * positionInSunNDC.y);
        float distortFactor = (1.0 - SHADOW_MAP_BIAS) + distb * SHADOW_MAP_BIAS;
        positionInSunNDC.xy /= distortFactor;
        positionInSunNDC /= positionInSunNDC.w;
        positionInSunNDC = positionInSunNDC * 0.5 + 0.5;
        shade = 1.0 - shadow2D(shadow, vec3(positionInSunNDC.st, positionInSunNDC.z - 0.0001)).z;
        if(cosine < 0.2)  // if light parallel normal (nearly)
            shade = max(shade, 1.0 - (cosine - 0.1) * 10.0);
    }
    shade -= clamp((dist - 0.7) * 5.0, 0.0, 1.0); 
    shade = clamp(shade, 0.0, 1.0);
    return shade;
}

void main() {
    vec4 color = texture2D(gcolor, texcoord.st);
    vec3 normal = normalDecode(texture2D(gnormal, texcoord.st).rg);
    // near <= positionInWorld.z
    float depth0 = texture2D(depthtex0, texcoord.st).x;
    float depth1 = texture2D(depthtex1, texcoord.st).x;
    // indicate the block is not cloud and water
    if(depth0 == depth1) {
        vec4 positionInWorld = getWorldPositionShadow(normal, depth0);
        float dist = length(positionInWorld.xyz / far);
        float shade = shadowMapping(positionInWorld, dist, normal);
        color.rgb *= (1.0 - shade * 0.50);
    }
    gl_FragData[0] = color;
}