#include "/lib/constant.glsl"
#include "/lib/util/functions.glsl"
#include "/lib/lighting/frame.glsl"
#include "/lib/common/render_stage.glsl"
#include "/lib/post/taa.glsl"

#ifdef FRAGMENT_SHADER
uniform sampler2D texture;
uniform sampler2D lightmap;
in vec4 color;
in vec2 texcoord;
in vec2 lmcoord;
in vec3 viewPos;
#include "/lib/materials/lighting/sky.glsl"
#include "/lib/misc/atmosphere.glsl"

// colortex1 is WRITE-ONLY in gbuffers; Iris aliases its sampler to the atlas.
/* RENDERTARGETS: 0,1,10,3 */
void main() {
#ifdef EFFECT_UNTEXTURED
    vec4 base = color;
#else
    vec4 base = texture2D(texture, texcoord) * color;
#endif
    if (base.a <= 0.001) discard;
    vec3 radiance = srgbToLinear(base.rgb);
#ifdef EFFECT_LIT
    radiance *= srgbToLinear(texture2D(lightmap, lmcoord).rgb);
#endif
#ifdef EFFECT_GLINT
    // Vanilla glint uses SRC_COLOR + ONE; preserve its squared source term.
    radiance = srgbToLinear(base.rgb * base.rgb);
#endif
    bool hand = isHandStage();
    float coverage = clamp(base.a, 0.0, 1.0);
    vec4 layer;
#if defined(EFFECT_GLINT) || defined(EFFECT_EYES)
    vec3 transmission = hand ? (isEyeInWater == 1 ? waterTransmittance(length(viewPos)) : vec3(1.0))
                             : cameraMediumTransmittance(viewPos);
    layer = vec4(radiance * transmission * coverage, 0.0); // Additive, no background fog.
#else
    if (!hand) radiance = applyAtmosphere(radiance, viewPos, false);
    else if (isEyeInWater == 1) radiance = applyUnderwaterMedium(radiance, length(viewPos));
    layer = vec4(radiance * coverage, coverage);
#endif
    // Unlike renderStage, this marker distinguishes pre/post deferred entity
    // draws as well as hand and modded effects. It is reset at every frame.
    bool afterDeferred = opaqueSnapshotReady();
    gl_FragData[0] = afterDeferred ? layer : vec4(0.0);
    gl_FragData[1] = afterDeferred ? vec4(0.0) : layer;
    gl_FragData[2] = vec4(max(coverage, 1.0 / 255.0));
    // FP16 view depth keeps useful precision without allocating another buffer.
    gl_FragData[3] = vec4(clamp(-viewPos.z, 0.0, 65504.0));
}
#endif

#ifdef VERTEX_SHADER
out vec4 color;
out vec2 texcoord;
out vec2 lmcoord;
out vec3 viewPos;
void main() {
    vec4 p = gl_ModelViewMatrix * gl_Vertex;
    viewPos = p.xyz;
    gl_Position = gl_ProjectionMatrix * p;
    // Block selection lines must stay on the jittered terrain they outline.
    if (isOutlineStage()) applyTaaJitter(gl_Position);
    color = gl_Color;
    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).st;
    lmcoord = (gl_TextureMatrix[1] * gl_MultiTexCoord1).st;
    setupFrameLighting();
}
#endif
