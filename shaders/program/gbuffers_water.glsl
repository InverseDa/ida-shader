#include "/lib/constant.glsl"
#include "/lib/util/functions.glsl"
#include "/lib/materials/materialData.glsl"
#include "/lib/materials/pbr.glsl"
#include "/lib/lighting/frame.glsl"

#ifdef FRAGMENT_SHADER
uniform sampler2D texture;
uniform sampler2D lightmap;
flat in int mat;
in vec4 color;
in vec4 texcoord;
in vec4 lmcoord;
in vec3 normal;
in vec4 viewPos;
#include "/lib/lighting/scene.glsl"
#include "/lib/misc/atmosphere.glsl"
#include "/lib/materials/translucents/water.glsl"
#include "/lib/materials/translucents/composition.glsl"

/* RENDERTARGETS: 0,10 */
void main() {
    vec2 screenUv = gl_FragCoord.xy / vec2(viewWidth, viewHeight);
    vec4 base = texture2D(texture, texcoord.st) * color;
    if (base.a <= 0.001) discard;
    vec4 material = getTranslucentMaterialData(float(mat));
    vec3 surfaceNormal = safeNormal(normal);
    vec3 worldPos = viewToWorldPos(viewPos.xyz, gbufferModelViewInverse);
    vec3 shaded;
    float alpha = base.a;
    if (isWaterEntityId(float(mat))) {
        vec2 opaqueUv = opaqueUvForUnjitteredUv(screenUv);
        vec4 opaque = sampleOpaqueData(opaqueUv);
        vec3 behind = reconstructOpaqueViewPos(opaqueUv, opaque);
        float transmission;
        if (isEyeInWater == 1) {
            shaded = drawUnderwaterSurface(worldPos, viewPos.xyz, surfaceNormal,
                                          screenUv, gl_FragCoord.z, transmission);
        } else {
            shaded = drawWater(vec3(0.1, 0.2, 0.4), worldPos, viewPos.xyz, behind,
                               surfaceNormal, screenUv, gl_FragCoord.z, transmission);
        }
        shaded = applyAtmosphere(shaded, viewPos.xyz, false);
        // The modeled ray includes the opaque background. Factor it out before
        // alpha blending, preserving transparent contributions already drawn.
        vec4 layer = makeRefractiveLayer(shaded, texture2D(colortex11, screenUv).rgb, transmission);
        shaded = layer.rgb;
        alpha = layer.a;
    } else {
        PbrMaterialSample pbr = samplePbrMaterial(texcoord.st, surfaceNormal, viewPos.xyz, material);
        shaded = applySunDirectLight(srgbToLinear(base.rgb), pbr.normalView, viewPos.xyz,
                 pbr.materialData, shadowMapping(worldPos, pbr.normalView, 1.0), 1.0,
                 srgbToLinear(texture2D(lightmap, lmcoord.st).rgb));
        if (isEyeInWater != 1 && isIceEntityId(float(mat)))
            shaded = drawIce(shaded, worldPos, viewPos.xyz, pbr.normalView);
        shaded = applyAtmosphere(shaded, viewPos.xyz, false);
    }
    gl_FragData[0] = vec4(shaded, alpha);
    // Additive R8 mask: later transparent layers cannot erase earlier coverage.
    gl_FragData[1] = vec4(max(alpha, 1.0 / 255.0));
}
#endif

// =============================================================================
// ============================== Vertex Shader ================================
// =============================================================================
#ifdef VERTEX_SHADER
uniform mat4 gbufferProjection;
uniform mat4 gbufferModelView;

in vec4 mc_Entity;

// `flat` used to disable interpolation
flat out int mat;

out vec4 color;
out vec4 texcoord;
out vec4 lmcoord;
out vec3 normal;
out vec4 viewPos;

void main() {
    mat = int(mc_Entity.x);
    viewPos = gbufferModelView * gl_Vertex;
    color = gl_Color;
    normal = gl_NormalMatrix * gl_Normal;
    gl_Position = gbufferProjection * viewPos;
    setupFrameLighting();
    // texture uv
    texcoord = gl_TextureMatrix[0] * gl_MultiTexCoord0;
    lmcoord = gl_TextureMatrix[1] * gl_MultiTexCoord1;
}
#endif
