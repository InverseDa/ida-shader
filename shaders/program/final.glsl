#include "/lib/constant.glsl"

// =====================================================================================
// ============================== Fragment Shader ======================================
// =====================================================================================
#ifdef FRAGMENT_SHADER
uniform sampler2D colortex0; // color
uniform sampler2D colortex7; // bloom

in vec4 texcoord;

const float BLOOM_INTENSITY = 0.66;

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

vec3 contrast(vec3 color, float factor) {
    return (color - 0.5) * factor + 0.5;
}

vec3 vibrance(vec3 color, float strength) {
    float maxChannel = max(color.r, max(color.g, color.b));
    float minChannel = min(color.r, min(color.g, color.b));
    float chroma = maxChannel - minChannel;
    float boost = (1.0 - clamp(chroma, 0.0, 1.0)) * strength;
    return saturation(color, 1.0 + boost);
}

void main() {
    vec4 color = texture2D(colortex0, texcoord.st);
    vec3 bloom = texture2D(colortex7, texcoord.st).rgb;
    color.rgb += bloom * BLOOM_INTENSITY;
    color.rgb = ACESToneMapping(color.rgb, 0.92);
    color.rgb = contrast(color.rgb, 1.03);
    color.rgb = vibrance(color.rgb, 0.12);
    color.rgb = saturation(color.rgb, 1.0);
    color.rgb = clamp(color.rgb, 0.0, 1.0);
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
