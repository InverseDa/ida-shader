#include "/lib/constant.glsl"
#include "/lib/util/functions.glsl"
#include "/lib/lighting/frame.glsl"
#include "/lib/common/render_stage.glsl"
#include "/lib/post/taa.glsl"

// ---- Fragment Shader ----

#ifdef FRAGMENT_SHADER

uniform sampler2D texture;
uniform sampler2D lightmap;
in vec4 Color;
in vec2 Texcoord;
in vec2 Lmcoord;
in vec3 ViewPos;
#include "/lib/materials/lighting/sky.glsl"
#include "/lib/misc/atmosphere.glsl"

// colortex1 is WRITE-ONLY in gbuffers; Iris aliases its sampler to the atlas.
#if SSR_HALF_RES == 1 && SSR_TEMPORAL == 1
/* RENDERTARGETS: 0,1,10,3,15 */
#else
/* RENDERTARGETS: 0,1,10,3 */
#endif
void main()
{
#ifdef EFFECT_UNTEXTURED
    vec4 Base = Color;
#else
    vec4 Base = texture2D(texture, Texcoord) * Color;
#endif
    if (Base.a <= 0.001)
    {
        discard;
    }

    vec3 Radiance = SrgbToLinear(Base.rgb);
#ifdef EFFECT_LIT
    Radiance *= SrgbToLinear(texture2D(lightmap, Lmcoord).rgb);
#endif
#ifdef EFFECT_GLINT
    // Vanilla glint uses SRC_COLOR + ONE; preserve its squared source term.
    Radiance = SrgbToLinear(Base.rgb * Base.rgb);
#endif
    bool bHand = IsHandStage();
    float Coverage = clamp(Base.a, 0.0, 1.0);
    vec4 Layer;
#if defined(EFFECT_GLINT) || defined(EFFECT_EYES)
    vec3 Transmission = bHand ? (isEyeInWater == 1 ? WaterTransmittance(length(ViewPos)) : vec3(1.0))
                              : CameraMediumTransmittance(ViewPos);
    Layer = vec4(Radiance * Transmission * Coverage, 0.0); // Additive, no background fog.
#else
    if (!bHand)
    {
        Radiance = ApplyAtmosphere(Radiance, ViewPos, false);
    }
    else if (isEyeInWater == 1)
    {
        Radiance = ApplyUnderwaterMedium(Radiance, length(ViewPos));
    }

    Layer = vec4(Radiance * Coverage, Coverage);
#endif
    // Unlike renderStage, this marker distinguishes pre/post deferred entity
    // draws as well as hand and modded effects. It is reset at every frame.
    bool bAfterDeferred = OpaqueSnapshotReady();

    gl_FragData[0] = bAfterDeferred ? Layer : vec4(0.0);

    gl_FragData[1] = bAfterDeferred ? vec4(0.0) : Layer;

    gl_FragData[2] = vec4(max(Coverage, 1.0 / 255.0));

    // FP16 view depth preserves early-effect depth; alpha zero preserves late reflection metadata.
    gl_FragData[3] = vec4(clamp(-ViewPos.z, 0.0, 65504.0), 0.0, 0.0, bAfterDeferred ? 0.0 : 1.0);
#if SSR_HALF_RES == 1 && SSR_TEMPORAL == 1
    gl_FragData[4] = vec4(0.0, 0.0, 0.0, bAfterDeferred ? Layer.a : 0.0);
#endif
}

#endif // FRAGMENT_SHADER

// ---- Vertex Shader ----

#ifdef VERTEX_SHADER

out vec4 Color;
out vec2 Texcoord;
out vec2 Lmcoord;
out vec3 ViewPos;

void main()
{
    vec4 P = gl_ModelViewMatrix * gl_Vertex;
    ViewPos = P.xyz;
    gl_Position = gl_ProjectionMatrix * P;

    // Block selection lines must stay on the jittered terrain they outline.
    if (IsOutlineStage())
    {
        ApplyTaaJitter(gl_Position);
    }

    Color = gl_Color;
    Texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).st;
    Lmcoord = (gl_TextureMatrix[1] * gl_MultiTexCoord1).st;
    SetupFrameLighting();
}

#endif // VERTEX_SHADER
