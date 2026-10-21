#include "/lib/constant.glsl"
#include "/lib/util/functions.glsl"
#include "/lib/materials/materialData.glsl"
#include "/lib/post/taa.glsl"
#ifdef FRAGMENT_SHADER
uniform sampler2D texture;
in vec2 texcoord;
/* RENDERTARGETS: 0,10 */
void main() {
    vec4 crack = texture2D(texture, texcoord);
    if (crack.a <= 0.001) discard;
    // Vanilla's DST_COLOR / SRC_COLOR doubles the source factor. Convert that
    // factor once to linear, then multiply albedo without replacing its G-buffer.
    vec3 factor = srgbToLinear(clamp(crack.rgb * 2.0, vec3(0.0), vec3(1.0)));
    factor = mix(vec3(1.0), factor, crack.a);
    gl_FragData[0] = vec4(factor, crack.a);
    gl_FragData[1] = vec4(max(crack.a, 1.0 / 255.0));
}
#endif
#ifdef VERTEX_SHADER
uniform float frameTimeCounter;
uniform sampler2D noisetex;
uniform vec3 cameraPosition;
attribute vec4 mc_Entity;
attribute vec4 mc_midTexCoord;
out vec2 texcoord;
#include "/lib/materials/methods/foliage.glsl"
void main() {
    vec4 p = gl_Vertex;
    p.xyz += foliageOffset(p.xyz, mc_Entity.x, gl_MultiTexCoord0.st, mc_midTexCoord.st);
    gl_Position = gl_ProjectionMatrix * gl_ModelViewMatrix * p;
    if (materialUsesTaaJitter(getTerrainMaterialData(mc_Entity.x))) applyTaaJitter(gl_Position);
    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).st;
}
#endif
