#include "/lib/constant.glsl"
#include "/lib/util/functions.glsl"
#include "/lib/materials/materialData.glsl"
#include "/lib/lighting/frame.glsl"
#ifdef FRAGMENT_SHADER
uniform sampler2D colortex5;
uniform sampler2D colortex1;
uniform sampler2D colortex3;
in vec4 texcoord;
#include "/lib/materials/lighting/sky.glsl"
#include "/lib/misc/atmosphere.glsl"
#include "/lib/materials/translucents/water.glsl"
/* RENDERTARGETS: 0,11 */
void main() {
    vec2 uv = texcoord.st;
    vec4 snapshot = fetchOpaqueData(ivec2(gl_FragCoord.xy));
    vec4 material = texture2D(colortex5, uv);
    vec3 color = texture2D(colortex9, uv).rgb;
    bool isHand = isMaterial(material, MATERIAL_ID_HAND);
    bool isSky = snapshot.b >= 0.999999;
    vec3 viewPos = reconstructOpaqueViewPos(uv, snapshot);
    // Opaque packed/blue ice must be resolved before translucent geometry.
    // The air-side sky-reflection approximation is not valid for submerged ice.
    if (!isSky && isEyeInWater != 1 && isMaterial(material, MATERIAL_ID_ICE)) {
        color = drawIce(color, viewToWorldPos(viewPos, gbufferModelViewInverse),
                        viewPos, normalDecode(snapshot.rg));
    }
    if (!isHand) color = applyAtmosphere(color, viewPos, isSky);
    // Keep the water-composition baseline free of early effects. Their visible
    // contribution then survives as a destination delta through refraction.
    color = max(color, vec3(0.0));
    gl_FragData[1] = vec4(color, 1.0);
    // Early effects carry their own medium attenuation and premultiplied alpha.
    // They must not be relit or fogged using the background surface's depth.
    vec4 effect = texture2D(colortex1, uv);
    float effectDepth = texelFetch(colortex3, ivec2(gl_FragCoord.xy), 0).r;
    // A later opaque draw may have covered an early effect. Conversely a new
    // opaque surface BEHIND an effect must not erase that foreground effect.
    // Account for FP16 view-depth rounding, rather than storing hardware depth
    // in FP16 (which would collapse distant depths towards one).
    if (!isHand && -viewPos.z + max(0.005, effectDepth * 0.001) < effectDepth) effect = vec4(0.0);
    color = color * (1.0 - effect.a) + effect.rgb;
    gl_FragData[0] = vec4(color, 1.0);
}
#endif
#ifdef VERTEX_SHADER
out vec4 texcoord;
void main() {
    gl_Position = ftransform();
    texcoord = gl_MultiTexCoord0;
    setupFrameLighting();
}
#endif
