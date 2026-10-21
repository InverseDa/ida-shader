#include "/lib/constant.glsl"
#ifdef FRAGMENT_SHADER
uniform sampler2D colortex0;
uniform sampler2D colortex10;
in vec4 texcoord;
#include "/lib/post/spatial_aa.glsl"
/* RENDERTARGETS: 0,10 */
void main() {
    vec2 uv = texcoord.st;
    ivec2 size = textureSize(colortex10, 0);
    ivec2 pixel = ivec2(gl_FragCoord.xy);
    float reactive = 0.0;
    // Protect both sides of dynamic/transparent silhouettes from history leaks.
    for (int y = -1; y <= 1; ++y)
        for (int x = -1; x <= 1; ++x)
            reactive = max(reactive, texelFetch(colortex10,
                clamp(pixel + ivec2(x, y), ivec2(0), size - 1), 0).r);
    vec3 color = sampleAaColor(uv);
    if (reactive > 0.001) color = resolveSpatialAa(uv, color);
    gl_FragData[0] = vec4(color, 1.0);
    gl_FragData[1] = vec4(reactive);
}
#endif
#ifdef VERTEX_SHADER
out vec4 texcoord;
void main() {
    gl_Position = ftransform();
    texcoord = gl_MultiTexCoord0;
}
#endif
