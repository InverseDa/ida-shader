#include "/lib/constant.glsl"
#include "/lib/common/color.glsl"
#include "/lib/settings.glsl"

// =============================================================================
// Fragment Shader
// =============================================================================
#ifdef FRAGMENT_SHADER

uniform sampler2D colortex0; // color after TAA
uniform sampler2D colortex7; // bloom

in vec4 Texcoord;

vec3 ACESToneMapping(vec3 Color, float AdaptedLum) {
    const float A = 2.51f;
    const float B = 0.03f;
    const float C = 2.43f;
    const float D = 0.59f;
    const float E = 0.14f;
    Color *= AdaptedLum;
    return (Color * (A * Color + B)) / (Color * (C * Color + D) + E);
}

vec3 Saturation(vec3 Color, float Factor) {
    float Brightness = dot(Color, vec3(0.2125, 0.7154, 0.0721));
    return mix(vec3(Brightness), Color, Factor);
}

vec3 Contrast(vec3 Color, float Factor) {
    return (Color - 0.5) * Factor + 0.5;
}

vec3 Vibrance(vec3 Color, float Strength) {
    float MaxChannel = max(Color.r, max(Color.g, Color.b));
    float MinChannel = min(Color.r, min(Color.g, Color.b));
    float Chroma = MaxChannel - MinChannel;
    float Boost = (1.0 - clamp(Chroma, 0.0, 1.0)) * Strength;
    return Saturation(Color, 1.0 + Boost);
}

void main() {
    vec4 Color = texture2D(colortex0, Texcoord.st);
    if (BLOOM_STRENGTH > 0.0) {
        vec3 Bloom = texture2D(colortex7, Texcoord.st).rgb;
        Color.rgb += Bloom * BLOOM_STRENGTH;
    }
    Color.rgb = ACESToneMapping(Color.rgb, EXPOSURE);
    Color.rgb = LinearToSrgb(Color.rgb);
    Color.rgb = Contrast(Color.rgb, COLOR_CONTRAST);
    Color.rgb = Vibrance(Color.rgb, COLOR_VIBRANCE);
    Color.rgb = Saturation(Color.rgb, COLOR_SATURATION);
    Color.rgb = clamp(Color.rgb, 0.0, 1.0);
    gl_FragData[0] = Color;
}

#endif // FRAGMENT_SHADER

// =============================================================================
// Vertex Shader
// =============================================================================
#ifdef VERTEX_SHADER

out vec4 Texcoord;

void main() {
    gl_Position = ftransform();
    Texcoord = gl_MultiTexCoord0;
}

#endif // VERTEX_SHADER
