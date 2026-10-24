#include "/lib/constant.glsl"
#include "/lib/util/functions.glsl"
#include "/lib/materials/materialData.glsl"
#include "/lib/post/taa.glsl"

// =============================================================================
// Fragment Shader
// =============================================================================
#ifdef FRAGMENT_SHADER

uniform sampler2D texture;
in vec2 Texcoord;
/* RENDERTARGETS: 0,10 */
void main() {
    vec4 Crack = texture2D(texture, Texcoord);
    if (Crack.a <= 0.001) discard;
    // Vanilla's DST_COLOR / SRC_COLOR doubles the source factor. Convert that
    // factor once to linear, then multiply albedo without replacing its G-buffer.
    vec3 Factor = SrgbToLinear(clamp(Crack.rgb * 2.0, vec3(0.0), vec3(1.0)));
    Factor = mix(vec3(1.0), Factor, Crack.a);
    gl_FragData[0] = vec4(Factor, Crack.a);
    gl_FragData[1] = vec4(max(Crack.a, 1.0 / 255.0));
}

#endif // FRAGMENT_SHADER

// =============================================================================
// Vertex Shader
// =============================================================================
#ifdef VERTEX_SHADER

uniform float frameTimeCounter;
uniform sampler2D noisetex;
uniform vec3 cameraPosition;
attribute vec4 mc_Entity;
attribute vec4 mc_midTexCoord;
out vec2 Texcoord;
#include "/lib/materials/methods/foliage.glsl"
void main() {
    vec4 P = gl_Vertex;
    P.xyz += FoliageOffset(P.xyz, mc_Entity.x, gl_MultiTexCoord0.st, mc_midTexCoord.st);
    gl_Position = gl_ProjectionMatrix * gl_ModelViewMatrix * P;
    if (MaterialUsesTaaJitter(GetTerrainMaterialData(mc_Entity.x))) ApplyTaaJitter(gl_Position);
    Texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).st;
}

#endif // VERTEX_SHADER
